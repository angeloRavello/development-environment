#Requires -Version 7.0
# Installs Zig via mise. Runs under pwsh7 on both Windows and Linux. No
# config files to deploy for this tool - just the mise install.
$ErrorActionPreference = "Stop"
. "$PSScriptRoot/../bootstrap/common.ps1"

Invoke-ExternalCommand -Exe "mise" -Arguments @("use", "--global", "zig") -Label "mise use --global zig"
