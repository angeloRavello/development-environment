#Requires -Version 5.1
<#
  PREREQUISITE step for Windows. Runs under the stock Windows PowerShell 5.1
  that ships with every Windows 11 install - nothing else is guaranteed to
  exist yet on a brand new machine.

  Its ONLY job is to get PowerShell 7 (pwsh) installed, then hand off to
  bootstrap.ps1, which from that point on assumes pwsh7 and is the single
  script (shared with Linux) that does everything else: mise, rotz,
  installing/linking every dot.

  This script is intentionally self-contained (it does NOT dot-source
  common.ps1) because common.ps1 is written for pwsh7 - it uses the
  $IsWindows/$IsLinux automatic variables, which do not exist under Windows
  PowerShell 5.1 and would silently break the OS branching in every helper
  function. Duplicating this one small "download+extract pwsh7" block here
  is the one deliberate piece of duplication in this repo; everything past
  this point lives in exactly one place.
#>

$ErrorActionPreference = "Stop"

Write-Host "==> [prereq] Running under Windows PowerShell $($PSVersionTable.PSVersion) (this is expected - pwsh7 is not installed yet)"

$RepoRoot = (Resolve-Path "$PSScriptRoot\..").Path
Write-Host "==> [prereq] Dotfiles repo: $RepoRoot"

# --- Step 1: is pwsh7 already available anywhere on PATH? -------------
$existing = Get-Command pwsh -ErrorAction SilentlyContinue
$destDir = Join-Path $env:USERPROFILE ".local\opt\pwsh7"
$pwshExe = Join-Path $destDir "pwsh.exe"

if ($existing) {
  Write-Host "==> [prereq] pwsh already on PATH at $($existing.Source) - skipping download"
  $pwshExe = $existing.Source
} elseif (Test-Path $pwshExe) {
  Write-Host "==> [prereq] pwsh7 already installed at $pwshExe - skipping download"
} else {
  Write-Host "==> [prereq] pwsh7 not found - downloading PowerShell 7 (portable, no admin)"

  # --- Step 2: resolve the latest release asset URL -------------------
  $repo = "PowerShell/PowerShell"
  $pattern = '^PowerShell-[\d.]+-win-x64\.zip$'
  Write-Host "==> [prereq] Querying GitHub API for latest release of $repo"
  try {
    $release = Invoke-RestMethod -UseBasicParsing -TimeoutSec 30 -Uri "https://api.github.com/repos/$repo/releases/latest" -Headers @{ "User-Agent" = "rotz-dotfiles-bootstrap" }
  } catch {
    throw "[prereq] Timed out or failed reaching GitHub API for $repo after 30s (offline? behind a proxy/firewall?): $($_.Exception.Message)"
  }
  $asset = $release.assets | Where-Object { $_.name -match $pattern } | Select-Object -First 1
  if (-not $asset) {
    throw "[prereq] No release asset matching '$pattern' found in latest release of $repo"
  }
  $url = $asset.browser_download_url
  Write-Host "==> [prereq] Resolved download URL: $url"

  # --- Step 3: download the zip (guarded with a timeout) ---------------
  $tmpZip = Join-Path $env:TEMP ("pwsh7_" + [guid]::NewGuid().ToString() + ".zip")
  Write-Host "==> [prereq] Downloading to $tmpZip (timeout 300s)"
  try {
    Invoke-WebRequest -UseBasicParsing -TimeoutSec 300 -Uri $url -OutFile $tmpZip
  } catch {
    throw "[prereq] Timed out or failed downloading $url after 300s (offline? behind a proxy/firewall?): $($_.Exception.Message)"
  }
  Write-Host "==> [prereq] Download complete ($((Get-Item $tmpZip).Length) bytes) - extracting to $destDir"

  # --- Step 4: extract ---------------------------------------------------
  New-Item -ItemType Directory -Force -Path $destDir | Out-Null
  Expand-Archive -Path $tmpZip -DestinationPath $destDir -Force
  Remove-Item $tmpZip -Force

  if (-not (Test-Path $pwshExe)) {
    throw "[prereq] pwsh.exe not found at $pwshExe after extracting - archive layout may have changed"
  }
  Write-Host "==> [prereq] pwsh7 extracted successfully to $pwshExe"
}

# --- Step 5: put pwsh7 on PATH (user scope, persisted + current session) ---
Write-Host "==> [prereq] Adding $destDir to user PATH"
$current = [Environment]::GetEnvironmentVariable("Path", "User")
$parts = @()
if ($current) { $parts = $current -split ";" }
if (-not ($parts -contains $destDir)) {
  $new = if ($current) { "$current;$destDir" } else { $destDir }
  [Environment]::SetEnvironmentVariable("Path", $new, "User")
}
if (($env:Path -split ";") -notcontains $destDir) {
  $env:Path = "$env:Path;$destDir"
}

# --- Step 6: allow local (unsigned) scripts to run for CurrentUser ---------
# No admin needed - CurrentUser scope only. RemoteSigned still blocks
# unsigned scripts *downloaded* from the internet (their Zone.Identifier
# marks them), but allows the ones in this repo to run without needing
# -ExecutionPolicy Bypass on every single `pwsh -File ...` invocation from
# dot.yaml.
$currentPolicy = Get-ExecutionPolicy -Scope CurrentUser
Write-Host "==> [prereq] Current CurrentUser execution policy: $currentPolicy"
if ($currentPolicy -ne "RemoteSigned" -and $currentPolicy -ne "Unrestricted" -and $currentPolicy -ne "Bypass") {
  Write-Host "==> [prereq] Setting CurrentUser execution policy to RemoteSigned"
  Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
}

Write-Host "==> [prereq] pwsh7 executable: $pwshExe"
& $pwshExe -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' | ForEach-Object { Write-Host "==> [prereq] pwsh7 version: $_" }

# --- Step 7: hand off to the unified bootstrap script, running under pwsh7 -
$mainScript = Join-Path $RepoRoot "bootstrap\bootstrap.ps1"
Write-Host "==> [prereq] Handing off to $mainScript (now running under pwsh7)"
& $pwshExe -NoProfile -File $mainScript
exit $LASTEXITCODE
