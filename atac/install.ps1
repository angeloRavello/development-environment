#Requires -Version 7.0
# Installs ATAC (https://github.com/Julien-cpsn/ATAC), a terminal UI HTTP
# client, via mise. Runs under pwsh7 on both Windows and Linux. No config
# files to deploy for this tool - just the mise install.
#
# ATAC has no first-party mise registry entry (verified against
# github.com/jdx/mise/registry.toml), but it ships prebuilt GitHub release
# binaries for both OSes, so mise's generic "github:" backend installs it
# directly from Julien-cpsn/ATAC's releases - no manual portable-zip
# download/extract needed here, unlike git/wezterm (which aren't on GitHub
# Releases in a shape mise's backend can auto-detect).
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot ".." "bootstrap" "common.ps1")

Invoke-ExternalCommand -Exe "mise" -Arguments @("use", "--global", "github:Julien-cpsn/ATAC") -Label "mise use --global github:Julien-cpsn/ATAC"
