#Requires -Version 7.0
# Installs Eclipse Temurin JDK 8, 11, 17, 21 and 25 side-by-side via mise.
# Runs under pwsh7 on both Windows and Linux. 25 is set as the global
# default (what `java`/`javac` resolve to with no extra config); the other
# four stay installed on disk so any project can pin to them via its own
# mise.toml without re-downloading. Safe to re-run: `mise install` is a
# no-op for a version that's already present.
#
# Temurin specifically (not the generic "openjdk-N" mise resolves by
# default) - Adoptium keeps Temurin build artifacts available long-term
# for every LTS release, unlike some other distributions whose older
# builds get pulled once a newer one ships. Confirmed all five versions
# below resolve via `mise latest java@temurin-<N>` before writing this.
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot ".." "bootstrap" "common.ps1")

$versions = @("temurin-8", "temurin-11", "temurin-17", "temurin-21", "temurin-25")
$default = "temurin-25"

Write-Log -Tag "java" -Message "Versions to ensure installed: $($versions -join ', ')"
Write-Log -Tag "java" -Message "Global default will be: $default"

foreach ($v in $versions) {
  Invoke-ExternalCommand -Exe "mise" -Arguments @("install", "java@$v") -Label "mise install java@$v"
}

Invoke-ExternalCommand -Exe "mise" -Arguments @("use", "--global", "java@$default") -Label "mise use --global java@$default"

Write-Log -Tag "java" -Message "Verifying default version"
& mise exec "java@$default" -- java -version
