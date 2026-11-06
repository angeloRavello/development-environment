#Requires -Version 7.0
# Installs lazygit via mise. Runs under pwsh7 on both Windows and Linux. No
# config files to deploy for this tool - just the mise install. LazyVim's
# <leader>gg opens it, so it must be on PATH before Neovim is used.
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot ".." "bootstrap" "common.ps1")

Invoke-ExternalCommand -Exe "mise" -Arguments @("use", "--global", "lazygit") -Label "mise use --global lazygit"
