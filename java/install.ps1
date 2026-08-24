#Requires -Version 7.0
# Installs OpenJDK 8, 11, 21 and 25 side-by-side via mise. Runs under pwsh7
# on both Windows and Linux. 25 is set as the global default (what
# `java`/`javac` resolve to with no extra config); the other three stay
# installed on disk so any project can pin to them via its own mise.toml
# without re-downloading. Safe to re-run: `mise install` is a no-op for a
# version that's already present.
$ErrorActionPreference = "Stop"

$versions = @("openjdk-8", "openjdk-11", "openjdk-21", "openjdk-25")
$default = "openjdk-25"

Write-Host "==> [java] Versions to ensure installed: $($versions -join ', ')"
Write-Host "==> [java] Global default will be: $default"

foreach ($v in $versions) {
  Write-Host "==> [java] mise install java@$v"
  & mise install "java@$v"
  if ($LASTEXITCODE -ne 0) { throw "mise install java@$v exited with code $LASTEXITCODE" }
}

Write-Host "==> [java] mise use --global java@$default"
& mise use --global "java@$default"
if ($LASTEXITCODE -ne 0) { throw "mise use --global java@$default exited with code $LASTEXITCODE" }

Write-Host "==> [java] Verifying default version"
& mise exec "java@$default" -- java -version
