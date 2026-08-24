#Requires -Version 7.0
# Installs mise (https://mise.jdx.dev) as a portable binary under
# ~/.local/bin - no admin/sudo. Runs under pwsh7 on both Windows and Linux.
$ErrorActionPreference = "Stop"
. "$PSScriptRoot/../bootstrap/common.ps1"

$homeDir = if ($IsWindows) { $env:USERPROFILE } else { $HOME }
$binDir = "$homeDir/.local/bin"
$miseBinName = if ($IsWindows) { "mise.exe" } else { "mise" }
$exe = "$binDir/$miseBinName"

Write-Host "==> [mise] Target executable: $exe"

if (Test-Path $exe) {
  Write-Host "==> [mise] Already installed at $exe - skipping download"
} elseif ($IsWindows) {
  Write-Host "==> [mise] Not found - downloading portable zip for Windows"
  New-Item -ItemType Directory -Force -Path $binDir | Out-Null
  $url = Get-LatestGithubAsset -Repo "jdx/mise" -Pattern '^mise-v[\d.]+-windows-x64\.zip$'
  $tmp = Join-Path $env:TEMP ("mise_" + [guid]::NewGuid().ToString())
  Install-PortableZip -Url $url -DestDir $tmp
  # The zip nests the binary as mise/bin/mise.exe - find it rather than
  # assuming the exact layout.
  $found = Get-ChildItem -Path $tmp -Recurse -Filter "mise.exe" | Select-Object -First 1
  if (-not $found) { throw "mise.exe not found after extracting mise zip (searched $tmp)" }
  Write-Host "==> [mise] Found extracted binary at $($found.FullName)"
  Copy-Item $found.FullName $exe -Force
  Remove-Item $tmp -Recurse -Force
} else {
  # Linux: use mise's own official installer script rather than
  # hand-rolling a tarball download. This is the one place in the repo that
  # intentionally shells out to bash instead of doing the work in pwsh -
  # it's the vendor-documented install method, not custom logic worth
  # reimplementing.
  Write-Host "==> [mise] Not found - running the official installer (curl https://mise.run | sh)"
  & bash -c "curl -fsSL --max-time 300 https://mise.run | sh"
  if ($LASTEXITCODE -ne 0) {
    throw "mise's official installer exited with code $LASTEXITCODE"
  }
}

if (-not (Test-Path $exe)) {
  throw "mise did not end up at the expected path $exe after installation"
}

Add-UserPath $binDir
Add-UserPath "$homeDir/.local/share/mise/shims"

Write-Host "==> [mise] Verifying installation"
& $exe --version
