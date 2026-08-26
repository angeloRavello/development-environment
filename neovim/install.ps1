#Requires -Version 7.0
# Installs the neovim binary (via mise), clones (or updates) LazyVim into
# ~/.config/nvim, then deploys this repo's own overrides on top. Runs
# under pwsh7 on both Windows and Linux.
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot ".." "bootstrap" "common.ps1")

Invoke-ExternalCommand -Exe "mise" -Arguments @("use", "--global", "neovim") -Label "mise use --global neovim"

$homeDir = $null
if ($IsWindows) { $homeDir = $env:USERPROFILE }
if ($IsLinux) { $homeDir = $HOME }
$xdgConfigHome = $env:XDG_CONFIG_HOME ?? (Join-Path $homeDir ".config")
$nvimConfig = Join-Path $xdgConfigHome "nvim"

Write-Log -Tag "neovim" -Message "Config target: $nvimConfig"

# Keeps .git (unlike earlier versions of this repo, which deleted it right
# after cloning) specifically so this branch can tell "already cloned" from
# "needs cloning" AND so a re-run can `git pull` to stay current instead of
# only ever cloning once and never updating again.
if (Test-Path (Join-Path $nvimConfig ".git")) {
  Write-Log -Tag "neovim" -Message "LazyVim starter already present - updating via git pull"
  Invoke-ExternalCommand -Exe "git" -Arguments @("-C", $nvimConfig, "pull", "--ff-only") -Label "git pull LazyVim/starter"
} else {
  if (Test-Path $nvimConfig) {
    Write-Log -Tag "neovim" -Level "WARN" -Message "$nvimConfig exists without git metadata (from an older version of this repo, which deleted .git after cloning) - removing and re-cloning fresh so future runs can auto-update"
    Remove-Item $nvimConfig -Recurse -Force
  } else {
    Write-Log -Tag "neovim" -Message "Cloning LazyVim starter into $nvimConfig"
  }
  Invoke-ExternalCommand -Exe "git" -Arguments @("clone", "https://github.com/LazyVim/starter", $nvimConfig) -Label "git clone LazyVim/starter"
}

$paths = Get-BootstrapPaths
Sync-DotLink -Source (Join-Path $PSScriptRoot "config" "lua" "config") -Target (Join-Path $nvimConfig "lua" "config") -BackupDir $paths.BackupDir
Sync-DotLink -Source (Join-Path $PSScriptRoot "config" "lua" "plugins") -Target (Join-Path $nvimConfig "lua" "plugins") -BackupDir $paths.BackupDir
