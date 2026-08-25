#Requires -Version 5.1
<#
  PREREQUISITE step for Windows. Runs under the stock Windows PowerShell 5.1
  that ships with every Windows 11 install - nothing else is guaranteed to
  exist yet on a brand new machine.

  Its ONLY job is to get PowerShell 7 (pwsh) installed, then hand off to
  bootstrap.ps1, which from that point on assumes pwsh7 and is the single
  script (shared with Linux) that installs every tool, in a fixed order,
  with no external orchestration tool involved.

  This script is intentionally self-contained (it does NOT dot-source
  common.ps1) because common.ps1 is written for pwsh7 - it uses the
  $IsWindows/$IsLinux automatic variables, which do not exist under Windows
  PowerShell 5.1 and would silently break the OS branching in every helper
  function. Duplicating this one small "download+extract pwsh7" block (and
  a matching small Write-Log) here is the one deliberate piece of
  duplication in this repo; everything past this point lives in exactly
  one place.
#>

$ErrorActionPreference = "Stop"

# Same "[yyyy-MM-dd HH:mm:ss.fff] [LEVEL] [tag] message" format every other
# script in this repo uses (bootstrap/common.ps1's Write-Log) - duplicated
# here in its own tiny form since this script can't dot-source common.ps1
# (see the header comment above for why).
function Write-Log {
  param(
    [Parameter(Mandatory)][string]$Message,
    [ValidateSet("INFO", "WARN", "ERROR")][string]$Level = "INFO"
  )
  $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
  Write-Host "[$timestamp] [$($Level.PadRight(5))] [prereq] $Message"
}

Write-Log "Running under Windows PowerShell $($PSVersionTable.PSVersion) (this is expected - pwsh7 is not installed yet)"

$RepoRoot = (Resolve-Path "$PSScriptRoot\..").Path
Write-Log "Dotfiles repo: $RepoRoot"

# --- Step 0: read bootstrap/paths.env (same file bootstrap.ps1 reads later
# via Get-BootstrapPaths - parsed by hand here since common.ps1's helper is
# pwsh7-only and pwsh7 doesn't exist yet at this point) --------------------
#
# Each key can be an absolute Windows path (e.g. "D:\tools\download"), a
# "_WINDOWS"-suffixed override (e.g. DOWNLOADS_DIR_WINDOWS=...), or a
# relative fragment joined with %USERPROFILE% - see bootstrap/paths.env
# for the full explanation. A value that looks like a Linux absolute path
# (starts with "/") is a configuration mistake on Windows, so this fails
# fast with a clear message instead of silently mangling it.
function Resolve-ConfiguredPathWindows {
  param([string]$Value, [string]$HomeDir, [string]$KeyName)
  if (($Value -match '^[A-Za-z]:[\\/]') -or ($Value -match '^\\\\')) { return $Value }
  if ($Value -match '^/') {
    throw "$KeyName is set to '$Value', which looks like a Linux absolute path, but this is Windows. Set ${KeyName}_WINDOWS in bootstrap/paths.env to a Windows path instead."
  }
  return Join-Path $HomeDir $Value
}

$configPath = Join-Path $RepoRoot "bootstrap\paths.env"
if (-not (Test-Path $configPath)) { throw "Missing config file: $configPath" }
$rawConfig = @{}
Get-Content $configPath | ForEach-Object {
  if ($_ -match '^\s*#' -or $_ -match '^\s*$') { return }
  if ($_ -match '^([A-Z_]+)=(.*)$') { $rawConfig[$matches[1]] = $matches[2].Trim() }
}
foreach ($key in @("DOWNLOADS_DIR", "INSTALL_DIR")) {
  if (-not $rawConfig.ContainsKey($key)) { throw "$configPath is missing required key $key" }
}
$downloadsRaw = if ($rawConfig.ContainsKey("DOWNLOADS_DIR_WINDOWS")) { $rawConfig["DOWNLOADS_DIR_WINDOWS"] } else { $rawConfig["DOWNLOADS_DIR"] }
$installRaw = if ($rawConfig.ContainsKey("INSTALL_DIR_WINDOWS")) { $rawConfig["INSTALL_DIR_WINDOWS"] } else { $rawConfig["INSTALL_DIR"] }
$downloadsDir = Resolve-ConfiguredPathWindows -Value $downloadsRaw -HomeDir $env:USERPROFILE -KeyName "DOWNLOADS_DIR"
$installDir = Resolve-ConfiguredPathWindows -Value $installRaw -HomeDir $env:USERPROFILE -KeyName "INSTALL_DIR"
New-Item -ItemType Directory -Force -Path $downloadsDir | Out-Null
New-Item -ItemType Directory -Force -Path $installDir | Out-Null
Write-Log "DownloadsDir: $downloadsDir"
Write-Log "InstallDir:   $installDir"

# --- Step 1: is pwsh7 already available anywhere on PATH? -------------
$existing = Get-Command pwsh -ErrorAction SilentlyContinue
$destDir = Join-Path $installDir "pwsh7"
$pwshExe = Join-Path $destDir "pwsh.exe"

if ($existing) {
  Write-Log "pwsh already on PATH at $($existing.Source) - skipping download"
  $pwshExe = $existing.Source
} elseif (Test-Path $pwshExe) {
  Write-Log "pwsh7 already installed at $pwshExe - skipping download"
} else {
  Write-Log "pwsh7 not found - downloading PowerShell 7 (portable, no admin)"

  # --- Step 2: resolve the latest release asset URL -------------------
  $repo = "PowerShell/PowerShell"
  $pattern = '^PowerShell-[\d.]+-win-x64\.zip$'
  Write-Log "Querying GitHub API for latest release of $repo"
  try {
    $release = Invoke-RestMethod -UseBasicParsing -TimeoutSec 30 -Uri "https://api.github.com/repos/$repo/releases/latest" -Headers @{ "User-Agent" = "dotfiles-bootstrap" }
  } catch {
    throw "Timed out or failed reaching GitHub API for $repo after 30s (offline? behind a proxy/firewall?): $($_.Exception.Message)"
  }
  $asset = $release.assets | Where-Object { $_.name -match $pattern } | Select-Object -First 1
  if (-not $asset) {
    throw "No release asset matching '$pattern' found in latest release of $repo"
  }
  $url = $asset.browser_download_url
  Write-Log "Resolved download URL: $url"

  # --- Step 3: download the zip into DownloadsDir (guarded with a timeout,
  # kept afterwards - not deleted - so a re-run skips re-downloading it) ---
  $zipFileName = Split-Path -Leaf ([Uri]$url).AbsolutePath
  $zipPath = Join-Path $downloadsDir $zipFileName
  if (Test-Path $zipPath) {
    Write-Log "Already downloaded at $zipPath - skipping download"
  } else {
    Write-Log "Downloading to $zipPath (timeout 300s)"
    try {
      Invoke-WebRequest -UseBasicParsing -TimeoutSec 300 -Uri $url -OutFile $zipPath
    } catch {
      throw "Timed out or failed downloading $url after 300s (offline? behind a proxy/firewall?): $($_.Exception.Message)"
    }
  }
  Write-Log "$((Get-Item $zipPath).Length) bytes - extracting to $destDir"

  # --- Step 4: extract ---------------------------------------------------
  New-Item -ItemType Directory -Force -Path $destDir | Out-Null
  Expand-Archive -Path $zipPath -DestinationPath $destDir -Force

  if (-not (Test-Path $pwshExe)) {
    throw "pwsh.exe not found at $pwshExe after extracting - archive layout may have changed"
  }
  Write-Log "pwsh7 extracted successfully to $pwshExe"
}

# --- Step 5: put pwsh7 on PATH (user scope, persisted + current session) ---
Write-Log "Adding $destDir to user PATH"
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
# -ExecutionPolicy Bypass on every single `pwsh -File ...` invocation.
$currentPolicy = Get-ExecutionPolicy -Scope CurrentUser
Write-Log "Current CurrentUser execution policy: $currentPolicy"
if ($currentPolicy -ne "RemoteSigned" -and $currentPolicy -ne "Unrestricted" -and $currentPolicy -ne "Bypass") {
  Write-Log "Setting CurrentUser execution policy to RemoteSigned"
  Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
}

Write-Log "pwsh7 executable: $pwshExe"
$pwshVersion = & $pwshExe -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'
Write-Log "pwsh7 version: $pwshVersion"

# --- Step 7: hand off to the unified bootstrap script, running under pwsh7 -
$mainScript = Join-Path $RepoRoot "bootstrap\bootstrap.ps1"
Write-Log "Handing off to $mainScript (now running under pwsh7)"
& $pwshExe -NoProfile -File $mainScript
exit $LASTEXITCODE
