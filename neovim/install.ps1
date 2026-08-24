#Requires -Version 7.0
# Installs the neovim binary (via mise) and bootstraps LazyVim into
# ~/.config/nvim the first time. Runs under pwsh7 on both Windows and
# Linux. Safe to re-run: it never touches an existing nvim config.
$ErrorActionPreference = "Stop"

Write-Host "==> [neovim] mise use --global neovim"
& mise use --global neovim
if ($LASTEXITCODE -ne 0) { throw "mise use --global neovim exited with code $LASTEXITCODE" }

$homeDir = if ($IsWindows) { $env:USERPROFILE } else { $HOME }
$xdgConfigHome = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { "$homeDir/.config" }
$nvimConfig = "$xdgConfigHome/nvim"

Write-Host "==> [neovim] Config target: $nvimConfig"

if (Test-Path "$nvimConfig/lua/config/lazy.lua") {
  Write-Host "==> [neovim] LazyVim starter already present - skipping clone"
} else {
  Write-Host "==> [neovim] Cloning LazyVim starter into $nvimConfig"
  & git clone --depth 1 https://github.com/LazyVim/starter $nvimConfig
  if ($LASTEXITCODE -ne 0) { throw "git clone of LazyVim starter exited with code $LASTEXITCODE" }
  Remove-Item "$nvimConfig/.git" -Recurse -Force -ErrorAction SilentlyContinue
}
