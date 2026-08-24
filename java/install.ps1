#Requires -Version 7.0
# Installs OpenJDK 8, 11, 21 and 25 side-by-side via mise. Runs under pwsh7
# on both Windows and Linux. 25 is set as the global default (what
# `java`/`javac` resolve to with no extra config); the other three stay
# installed on disk so any project can pin to them via its own mise.toml
# without re-downloading. Safe to re-run: `mise install` is a no-op for a
# version that's already present.
$ErrorActionPreference = "Stop"
. "$PSScriptRoot/../bootstrap/common.ps1"

$versions = @("openjdk-8", "openjdk-11", "openjdk-21", "openjdk-25")
$default = "openjdk-25"

Write-Host "==> [java] Versions to ensure installed: $($versions -join ', ')"
Write-Host "==> [java] Global default will be: $default"

foreach ($v in $versions) {
  Invoke-ExternalCommand -Exe "mise" -Arguments @("install", "java@$v") -Label "mise install java@$v"
}

Invoke-ExternalCommand -Exe "mise" -Arguments @("use", "--global", "java@$default") -Label "mise use --global java@$default"

Write-Host "==> [java] Verifying default version"
& mise exec "java@$default" -- java -version
