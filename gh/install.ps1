#Requires -Version 7.0
# Installs the GitHub CLI (gh) via mise. Runs under pwsh7 on both Windows
# and Linux. No config files to deploy for this tool - just the mise
# install.
#
# gh has no first-party mise registry entry (verified against
# github.com/jdx/mise/registry/*.toml - no gh.toml/github-cli.toml), but
# cli/cli's releases ship prebuilt per-OS/arch archives (gh_<ver>_windows_amd64.zip,
# gh_<ver>_linux_amd64.tar.gz, ...), so mise's generic "github:" backend
# installs it directly - same approach as atac/install.ps1.
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot ".." "bootstrap" "common.ps1")

Invoke-ExternalCommand -Exe "mise" -Arguments @("use", "--global", "github:cli/cli") -Label "mise use --global github:cli/cli"
