#Requires -Version 7.0
# Installs the neovim binary (via mise) and bootstraps LazyVim into
# ~/.config/nvim the first time. Runs under pwsh7 on both Windows and
# Linux. Safe to re-run: it never touches an existing nvim config.
$ErrorActionPreference = "Stop"
. "$PSScriptRoot/../bootstrap/common.ps1"

Invoke-ExternalCommand -Exe "mise" -Arguments @("use", "--global", "neovim") -Label "mise use --global neovim"

$homeDir = if ($IsWindows) { $env:USERPROFILE } else { $HOME }
$xdgConfigHome = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { "$homeDir/.config" }
$nvimConfig = "$xdgConfigHome/nvim"

Write-Host "==> [neovim] Config target: $nvimConfig"

if (Test-Path "$nvimConfig/lua/config/lazy.lua") {
  Write-Host "==> [neovim] LazyVim starter already present - skipping clone"
} else {
  Invoke-ExternalCommand -Exe "git" -Arguments @("clone", "--depth", "1", "https://github.com/LazyVim/starter", $nvimConfig) -Label "git clone LazyVim/starter"
  Remove-Item "$nvimConfig/.git" -Recurse -Force -ErrorAction SilentlyContinue
}
