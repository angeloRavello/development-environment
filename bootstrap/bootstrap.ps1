#Requires -Version 7.0
<#
  Unified bootstrap script - runs under pwsh7 on BOTH Windows and Linux.

  Do not run this directly on a brand new machine: use bootstrap/prereq.ps1
  (Windows) or bootstrap/prereq.sh (Linux) first. Those install pwsh7 if it
  isn't already present (nothing else is guaranteed to exist on a fresh
  machine) and then hand off to this script.

  What it does, in order:
    1. Sets $env:DOTFILES (persisted) and, on Windows only, the XDG_* env
       vars so tools like neovim/yazi/wezterm resolve config from
       ~/.config/<tool> the same way they do by default on Linux.
    2. Installs mise (portable, user-scoped).
    3. Installs rotz via mise's generic GitHub backend.
    4. Backs up any pre-existing real file/folder at a spot a dot.yaml is
       about to symlink over (e.g. an existing ~/.gitconfig from before
       this repo was ever used here) into bootstrap/paths.env's BACKUP_DIR,
       timestamped - so `rotz link` never silently clobbers something you
       already had.
    5. Runs `rotz install --continue-on-error` (executes every dot's install
       command, which are now all pwsh7 scripts too) then `rotz link`
       (symlinks every dot's config files).

  Every stage below prints what it's doing and the key values involved
  (paths, URLs, versions) so that if this hangs or fails, the last line
  printed tells you exactly which stage to look at - no more guessing.
#>

$ErrorActionPreference = "Stop"

if ($PSVersionTable.PSVersion.Major -lt 7) {
  throw "bootstrap.ps1 requires pwsh7, but is running under PowerShell $($PSVersionTable.PSVersion). Run bootstrap/prereq.ps1 (Windows) or bootstrap/prereq.sh (Linux) instead - they install pwsh7 and relaunch this script correctly."
}

. "$PSScriptRoot/common.ps1"

$RepoRoot = (Resolve-Path "$PSScriptRoot/..").Path
$HomeDir = if ($IsWindows) { $env:USERPROFILE } else { $HOME }

Write-Host "==> [bootstrap] Dotfiles repo: $RepoRoot"
Write-Host "==> [bootstrap] pwsh version: $($PSVersionTable.PSVersion)  IsWindows=$IsWindows  IsLinux=$IsLinux  Home=$HomeDir"

# --- Stage 1/5: DOTFILES + XDG env vars -------------------------------------
Write-Host "==> [bootstrap] Stage 1/5: environment variables"
try {
  Set-UserEnvVar -Name "DOTFILES" -Value $RepoRoot
  if ($IsWindows) {
    Set-UserEnvVar -Name "XDG_CONFIG_HOME" -Value (Join-Path $env:USERPROFILE ".config")
    Set-UserEnvVar -Name "XDG_DATA_HOME"   -Value (Join-Path $env:USERPROFILE ".local\share")
    Set-UserEnvVar -Name "XDG_CACHE_HOME"  -Value (Join-Path $env:USERPROFILE ".cache")
    Set-UserEnvVar -Name "XDG_STATE_HOME"  -Value (Join-Path $env:USERPROFILE ".local\state")
  } else {
    Write-Host "    [bootstrap] Linux: leaving XDG_* vars alone (tools default to ~/.config etc. on their own)"
  }
} catch {
  Write-Host "!!! [bootstrap] Stage 1/5 (environment variables) FAILED: $($_.Exception.Message)"
  throw
}

# --- Stage 2/5: mise ----------------------------------------------------------
# Note: mise/install.ps1 runs in-process (via `&` on the .ps1 file, not a
# new OS process) - it's this repo's own script, not a third-party program,
# so its Write-Host lines are already tagged [mise]/[common] and don't need
# the >>>/<<< boundary treatment. It internally uses Invoke-ExternalCommand
# itself wherever it calls a real external program.
Write-Host "==> [bootstrap] Stage 2/5: installing mise"
try {
  & "$RepoRoot/mise/install.ps1"
} catch {
  Write-Host "!!! [bootstrap] Stage 2/5 (mise) FAILED: $($_.Exception.Message)"
  throw
}

# mise/install.ps1 no longer installs to a fixed path (it extracts into
# <InstallDir>/mise on Windows - see bootstrap/paths.env - and adds that
# folder to PATH itself via Add-UserPath), so resolve it dynamically off
# PATH instead of hardcoding a second guess here that could drift out of
# sync with wherever mise/install.ps1 actually put it.
$miseCmd = Get-Command mise -ErrorAction SilentlyContinue
if (-not $miseCmd) {
  throw "mise did not install correctly - 'mise' not found on PATH after mise/install.ps1 ran"
}
$miseExe = $miseCmd.Source
Write-Host "==> [bootstrap] mise executable: $miseExe"

# --- Stage 3/5: rotz (via mise's generic GitHub backend, no registry entry needed) ---
Write-Host "==> [bootstrap] Stage 3/5: installing rotz"
try {
  Invoke-ExternalCommand -Exe $miseExe -Arguments @("use", "--global", "github:volllly/rotz") -Label "mise use --global github:volllly/rotz (installing rotz)"
} catch {
  Write-Host "!!! [bootstrap] Stage 3/5 (rotz) FAILED: $($_.Exception.Message)"
  throw
}

$shims = "$HomeDir/.local/share/mise/shims"
Add-UserPath $shims
$rotzBinName = if ($IsWindows) { "rotz.exe" } else { "rotz" }
$rotz = "$shims/$rotzBinName"
Write-Host "==> [bootstrap] rotz executable: $rotz"

if (-not (Test-Path $rotz)) {
  throw "rotz did not install correctly, expected $rotz"
}

# --- Stage 4/5: back up any pre-existing dotfiles before they get symlinked over ---
# If you already had a real ~/.gitconfig, ~/.config/nvim, etc. before ever
# running this repo, `rotz link` is about to replace it with a symlink.
# This moves whatever's really there into BACKUP_DIR (bootstrap/paths.env)
# first - it's a no-op on a machine that's already fully linked, since
# anything already a symlink is skipped.
Write-Host "==> [bootstrap] Stage 4/5: backing up pre-existing dotfiles"
try {
  $paths = Get-BootstrapPaths
  Backup-ExistingLinkTargets -RepoRoot $RepoRoot -BackupDir $paths.BackupDir
} catch {
  Write-Host "!!! [bootstrap] Stage 4/5 (backup) FAILED: $($_.Exception.Message)"
  throw
}

# --- Stage 5/5: rotz install + link -------------------------------------------
# This is where a hang is most likely: rotz shells out to every dot's own
# install command (mise installing toolchains, git cloning, apt-get, ...),
# any of which can stall on a slow/stuck network connection with no timeout
# of its own. The >>>/<<< boundary at least makes clear when rotz itself
# started and whether it's still alive vs. truly stuck.
Write-Host "==> [bootstrap] Stage 5/5: rotz install (running each dot's install command, continuing past individual failures)"
try {
  Invoke-ExternalCommand -Exe $rotz -Arguments @("--dotfiles", $RepoRoot, "install", "--continue-on-error") -Label "rotz install"
} catch {
  Write-Host "!!! [bootstrap] Stage 5/5 (rotz install) FAILED: $($_.Exception.Message)"
  throw
}

Write-Host "==> [bootstrap] Stage 5/5: rotz link (symlinking config files)"
try {
  Invoke-ExternalCommand -Exe $rotz -Arguments @("--dotfiles", $RepoRoot, "link") -Label "rotz link"
} catch {
  Write-Host "!!! [bootstrap] Stage 5/5 (rotz link) FAILED: $($_.Exception.Message)"
  throw
}

Write-Host ""
Write-Host "==> [bootstrap] Done. Open a NEW terminal so the updated PATH/env vars take effect."
