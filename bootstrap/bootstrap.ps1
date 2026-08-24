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
    4. Runs `rotz install --continue-on-error` (executes every dot's install
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

# --- Stage 1/4: DOTFILES + XDG env vars -------------------------------------
Write-Host "==> [bootstrap] Stage 1/4: environment variables"
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
  Write-Host "!!! [bootstrap] Stage 1/4 (environment variables) FAILED: $($_.Exception.Message)"
  throw
}

# --- Stage 2/4: mise ----------------------------------------------------------
Write-Host "==> [bootstrap] Stage 2/4: installing mise"
try {
  & "$RepoRoot/mise/install.ps1"
} catch {
  Write-Host "!!! [bootstrap] Stage 2/4 (mise) FAILED: $($_.Exception.Message)"
  throw
}

$miseBinName = if ($IsWindows) { "mise.exe" } else { "mise" }
$miseExe = "$HomeDir/.local/bin/$miseBinName"
Write-Host "==> [bootstrap] mise executable: $miseExe"
if (-not (Test-Path $miseExe)) {
  throw "mise did not install correctly, expected $miseExe"
}

# --- Stage 3/4: rotz (via mise's generic GitHub backend, no registry entry needed) ---
Write-Host "==> [bootstrap] Stage 3/4: installing rotz"
try {
  & $miseExe use --global "github:volllly/rotz" | Out-Host
} catch {
  Write-Host "!!! [bootstrap] Stage 3/4 (rotz) FAILED: $($_.Exception.Message)"
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

# --- Stage 4/4: rotz install + link -------------------------------------------
Write-Host "==> [bootstrap] Stage 4/4: rotz install (running each dot's install command, continuing past individual failures)"
try {
  & $rotz --dotfiles $RepoRoot install --continue-on-error
} catch {
  Write-Host "!!! [bootstrap] Stage 4/4 (rotz install) FAILED: $($_.Exception.Message)"
  throw
}

Write-Host "==> [bootstrap] Stage 4/4: rotz link (symlinking config files)"
try {
  & $rotz --dotfiles $RepoRoot link
} catch {
  Write-Host "!!! [bootstrap] Stage 4/4 (rotz link) FAILED: $($_.Exception.Message)"
  throw
}

Write-Host ""
Write-Host "==> [bootstrap] Done. Open a NEW terminal so the updated PATH/env vars take effect."
