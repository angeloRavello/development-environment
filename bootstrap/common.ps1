# Shared helpers for bootstrap.ps1 and every dot's install.ps1 in this repo.
# This file targets pwsh7 (PowerShell Core) and runs unmodified on both
# Windows and Linux - it uses the $IsWindows/$IsLinux automatic variables,
# which only exist under pwsh7 (NOT Windows PowerShell 5.1). That's why
# bootstrap/prereq.ps1 and bootstrap/prereq.sh, which install pwsh7 itself,
# deliberately do NOT dot-source this file.
#
# Everything here installs into the current user's profile only - no
# admin/sudo required.

# Resolves one raw value from paths.env into a final absolute path:
#   - Already absolute FOR THE CURRENT OS (Windows: "D:\..."/"D:/..." or a
#     "\\server\share" UNC path; Linux: starts with "/") -> used exactly as
#     given, never joined with home.
#   - Looks absolute but shaped for the OTHER OS (a Windows drive-letter
#     path while running on Linux, or a leading "/" path while running on
#     Windows) -> throws a clear, actionable error instead of silently
#     mangling it. Windows and Linux paths are never interchangeable -
#     backslashes and drive letters mean nothing on Linux, and a leading
#     "/" is just another path segment on Windows, not root.
#   - Otherwise (e.g. ".local/downloads") -> treated as relative and
#     joined with $HomeDir, same as before this could hold absolute paths.
function Resolve-ConfiguredPath {
  param(
    [Parameter(Mandatory)][string]$Value,
    [Parameter(Mandatory)][string]$HomeDir,
    [Parameter(Mandatory)][string]$KeyName   # only used to make error messages point at the right paths.env key
  )
  $looksWindowsAbsolute = ($Value -match '^[A-Za-z]:[\\/]') -or ($Value -match '^\\\\')
  $looksLinuxAbsolute = $Value -match '^/'

  if ($IsWindows) {
    if ($looksWindowsAbsolute) { return $Value }
    if ($looksLinuxAbsolute) {
      throw "$KeyName is set to '$Value', which looks like a Linux absolute path, but this is Windows. Set ${KeyName}_WINDOWS in bootstrap/paths.env to a Windows path (e.g. D:\tools\...) instead."
    }
  } else {
    if ($looksLinuxAbsolute) { return $Value }
    if ($looksWindowsAbsolute) {
      throw "$KeyName is set to '$Value', which looks like a Windows absolute path, but this is Linux. Set ${KeyName}_LINUX in bootstrap/paths.env to a Linux path (e.g. /opt/tools/...) instead."
    }
  }

  return "$HomeDir/$Value"
}

# Reads bootstrap/paths.env - the single source of truth for where
# downloaded archives and extracted tools live - and resolves all three
# values to absolute paths, creating them if they don't exist yet. Every
# script that downloads/extracts a portable tool calls this instead of
# hardcoding ".local/downloads"/".local/opt" itself, so there's exactly
# one place to change where things land.
#
# Each key (DOWNLOADS_DIR/INSTALL_DIR/BACKUP_DIR) can be overridden with a
# separate value per OS by adding a "_WINDOWS" or "_LINUX" suffixed key -
# e.g. DOWNLOADS_DIR_WINDOWS=D:\tools\download. If no suffixed key exists
# for the current OS, the bare key is used (and can itself be either an
# absolute path for the current OS, or a relative fragment joined with
# home - see Resolve-ConfiguredPath above).
function Get-BootstrapPaths {
  $homeDir = if ($IsWindows) { $env:USERPROFILE } else { $HOME }
  $configPath = "$PSScriptRoot/paths.env"

  if (-not (Test-Path $configPath)) {
    throw "Missing config file: $configPath"
  }

  $raw = @{}
  Get-Content $configPath | ForEach-Object {
    if ($_ -match '^\s*#' -or $_ -match '^\s*$') { return }
    if ($_ -match '^([A-Z_]+)=(.*)$') { $raw[$matches[1]] = $matches[2].Trim() }
  }
  foreach ($key in @("DOWNLOADS_DIR", "INSTALL_DIR", "BACKUP_DIR")) {
    if (-not $raw.ContainsKey($key)) { throw "$configPath is missing required key $key" }
  }

  $osSuffix = if ($IsWindows) { "_WINDOWS" } else { "_LINUX" }
  $downloadsRaw = if ($raw.ContainsKey("DOWNLOADS_DIR$osSuffix")) { $raw["DOWNLOADS_DIR$osSuffix"] } else { $raw['DOWNLOADS_DIR'] }
  $installRaw = if ($raw.ContainsKey("INSTALL_DIR$osSuffix")) { $raw["INSTALL_DIR$osSuffix"] } else { $raw['INSTALL_DIR'] }
  $backupRaw = if ($raw.ContainsKey("BACKUP_DIR$osSuffix")) { $raw["BACKUP_DIR$osSuffix"] } else { $raw['BACKUP_DIR'] }

  $downloadsDir = Resolve-ConfiguredPath -Value $downloadsRaw -HomeDir $homeDir -KeyName "DOWNLOADS_DIR"
  $installDir = Resolve-ConfiguredPath -Value $installRaw -HomeDir $homeDir -KeyName "INSTALL_DIR"
  $backupDir = Resolve-ConfiguredPath -Value $backupRaw -HomeDir $homeDir -KeyName "BACKUP_DIR"

  New-Item -ItemType Directory -Force -Path $downloadsDir | Out-Null
  New-Item -ItemType Directory -Force -Path $installDir | Out-Null
  New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

  Write-Host "    [common] DownloadsDir: $downloadsDir"
  Write-Host "    [common] InstallDir:   $installDir"
  Write-Host "    [common] BackupDir:    $backupDir"

  return [pscustomobject]@{
    DownloadsDir = $downloadsDir
    InstallDir   = $installDir
    BackupDir    = $backupDir
  }
}

# Prints the browser_download_url of the first release asset whose name
# matches the given regex pattern. By default queries /releases/latest
# (GitHub's "latest" endpoint, which skips prereleases). Pass -Tag to
# instead fetch a specific release by tag (e.g. "nightly") - needed for
# rolling/prerelease channels that /releases/latest would never return.
function Get-LatestGithubAsset {
  param(
    [Parameter(Mandatory)][string]$Repo,     # "owner/name"
    [Parameter(Mandatory)][string]$Pattern,  # regex matched against the asset file name
    [string]$Tag,                            # optional: e.g. "nightly" - fetches /releases/tags/<Tag> instead of /releases/latest
    [int]$TimeoutSec = 30
  )
  $uri = if ($Tag) { "https://api.github.com/repos/$Repo/releases/tags/$Tag" } else { "https://api.github.com/repos/$Repo/releases/latest" }
  $what = if ($Tag) { "tag '$Tag'" } else { "latest release" }
  Write-Host "    [common] Querying GitHub API for $what of $Repo (timeout ${TimeoutSec}s)"
  try {
    $release = Invoke-RestMethod -UseBasicParsing -TimeoutSec $TimeoutSec -Uri $uri -Headers @{ "User-Agent" = "rotz-dotfiles-bootstrap" }
  } catch {
    throw "Timed out or failed reaching GitHub API for $Repo after ${TimeoutSec}s (offline? behind a proxy/firewall?): $($_.Exception.Message)"
  }
  $asset = $release.assets | Where-Object { $_.name -match $Pattern } | Select-Object -First 1
  if (-not $asset) {
    throw "No release asset matching '$Pattern' found in $what of $Repo"
  }
  Write-Host "    [common] Resolved asset: $($asset.name)"
  return $asset.browser_download_url
}

# Downloads a .zip into $DownloadsDir (skipping the download if a file by
# that name is already there - cheap caching, since GitHub release asset
# names virtually always include the version) and extracts it into
# $DestDir. Works on both Windows and Linux (Expand-Archive is pure .NET,
# not Windows-only). The downloaded .zip is kept, not deleted, so re-runs
# don't re-fetch it and you can always see what actually got downloaded.
#
# Pass -Force to always re-download and re-extract even if a same-named
# file already exists - needed for rolling releases (e.g. WezTerm's
# "nightly" tag) whose asset filename never changes even though its
# contents do, which would otherwise make the filename-based cache above
# stick forever on the first build ever downloaded.
function Install-PortableZip {
  param(
    [Parameter(Mandatory)][string]$Url,
    [Parameter(Mandatory)][string]$DestDir,
    [Parameter(Mandatory)][string]$DownloadsDir,
    [switch]$Force,
    [int]$TimeoutSec = 300
  )
  New-Item -ItemType Directory -Force -Path $DestDir | Out-Null
  New-Item -ItemType Directory -Force -Path $DownloadsDir | Out-Null

  $fileName = Split-Path -Leaf ([Uri]$Url).AbsolutePath
  $dest = "$DownloadsDir/$fileName"

  if ((Test-Path $dest) -and -not $Force) {
    Write-Host "    [common] Already downloaded at $dest - skipping download"
  } else {
    if ($Force -and (Test-Path $dest)) {
      Write-Host "    [common] -Force set (rolling release) - re-downloading over cached $dest"
    } else {
      Write-Host "    [common] Downloading $Url"
    }
    Write-Host "    [common] -> $dest (timeout ${TimeoutSec}s)"
    try {
      Invoke-WebRequest -UseBasicParsing -TimeoutSec $TimeoutSec -Uri $Url -OutFile $dest
    } catch {
      throw "Timed out or failed downloading $Url after ${TimeoutSec}s (offline? behind a proxy/firewall?): $($_.Exception.Message)"
    }
  }

  $size = (Get-Item $dest).Length
  Write-Host "    [common] $size bytes - extracting to $DestDir"
  Expand-Archive -Path $dest -DestinationPath $DestDir -Force
}

# Downloads a .tar.gz into $DownloadsDir (same caching/keep-the-file
# behavior as Install-PortableZip) and extracts it into $DestDir.
# Linux-only (shells out to `tar`, which ships by default on virtually
# every distro - unlike .zip handling, .tar.gz needs no pure-.NET
# equivalent worth hand-rolling here).
function Install-PortableTarGz {
  param(
    [Parameter(Mandatory)][string]$Url,
    [Parameter(Mandatory)][string]$DestDir,
    [Parameter(Mandatory)][string]$DownloadsDir,
    [int]$TimeoutSec = 300
  )
  if (-not $IsLinux) {
    throw "Install-PortableTarGz is Linux-only"
  }
  New-Item -ItemType Directory -Force -Path $DestDir | Out-Null
  New-Item -ItemType Directory -Force -Path $DownloadsDir | Out-Null

  $fileName = Split-Path -Leaf ([Uri]$Url).AbsolutePath
  $dest = "$DownloadsDir/$fileName"

  if (Test-Path $dest) {
    Write-Host "    [common] Already downloaded at $dest - skipping download"
  } else {
    Write-Host "    [common] Downloading $Url"
    Write-Host "    [common] -> $dest (timeout ${TimeoutSec}s)"
    try {
      Invoke-WebRequest -UseBasicParsing -TimeoutSec $TimeoutSec -Uri $Url -OutFile $dest
    } catch {
      throw "Timed out or failed downloading $Url after ${TimeoutSec}s (offline? behind a proxy/firewall?): $($_.Exception.Message)"
    }
  }

  $size = (Get-Item $dest).Length
  Write-Host "    [common] $size bytes - extracting to $DestDir"
  & tar -xzf $dest -C $DestDir
  if ($LASTEXITCODE -ne 0) {
    throw "tar exited with code $LASTEXITCODE while extracting $dest"
  }
}

# Persists a directory to the user's PATH and to the current session.
#   Windows: HKCU\Environment (registry), never the machine-wide PATH.
#   Linux:   ~/.profile and ~/.bashrc (idempotent), same spirit - user-scope
#            only, no /etc/environment, no sudo.
function Add-UserPath {
  param([Parameter(Mandatory)][string]$Dir)

  Write-Host "    [common] Add-UserPath: $Dir"

  if ($IsWindows) {
    $current = [Environment]::GetEnvironmentVariable("Path", "User")
    $parts = @()
    if ($current) { $parts = $current -split ";" }
    if (-not ($parts -contains $Dir)) {
      $new = if ($current) { "$current;$Dir" } else { $Dir }
      [Environment]::SetEnvironmentVariable("Path", $new, "User")
      Write-Host "    [common] -> written to HKCU\Environment\Path"
    } else {
      Write-Host "    [common] -> already present in HKCU\Environment\Path"
    }
    if (($env:Path -split ";") -notcontains $Dir) {
      $env:Path = "$env:Path;$Dir"
    }
  } else {
    if (($env:Path -split ":") -notcontains $Dir) {
      $env:Path = "$env:Path`:$Dir"
    }
    foreach ($rc in @("$HOME/.profile", "$HOME/.bashrc")) {
      if (-not (Test-Path $rc)) { New-Item -ItemType File -Path $rc -Force | Out-Null }
      $marker = "PATH=`"`$PATH:$Dir`""
      if (-not (Select-String -Path $rc -Pattern ([regex]::Escape($marker)) -Quiet -ErrorAction SilentlyContinue)) {
        Add-Content -Path $rc -Value "`nexport PATH=`"`$PATH:$Dir`""
        Write-Host "    [common] -> appended to $rc"
      } else {
        Write-Host "    [common] -> already present in $rc"
      }
    }
  }
}

# Extracts the target (right-hand) side of every entry under a `links:`
# block in a dot.yaml, e.g. for:
#   links:
#     gitconfig: ~/.gitconfig
# this returns @("~/.gitconfig"). Handles both a top-level `links:` and one
# nested under `global:` (this repo uses both styles - see CLAUDE.md) by
# tracking indentation relative to wherever `links:` itself appears, rather
# than assuming a fixed indent level.
#
# This is NOT a general YAML parser - it only understands the narrow shape
# every dot.yaml in this repo actually uses (flat `key: value` lines under
# `links:`, no lists, no quoting). If a future dot.yaml's `links:` block
# needs something fancier than that, this needs updating too.
function Get-DotLinkTargets {
  param([Parameter(Mandatory)][string]$DotYamlPath)

  $targets = @()
  $inLinks = $false
  $linksIndent = 0

  foreach ($line in (Get-Content $DotYamlPath)) {
    if ($line -match '^(\s*)links:\s*$') {
      $inLinks = $true
      $linksIndent = $matches[1].Length
      continue
    }
    if (-not $inLinks) { continue }
    if ($line -notmatch '\S') { continue }   # blank line - stay in the block

    $indent = ($line -replace '^(\s*).*$', '$1').Length
    if ($indent -le $linksIndent) {
      $inLinks = $false
      continue
    }
    if ($line -match '^\s+[^:\s][^:]*:\s*(.+?)\s*$') {
      $targets += $matches[1]
    }
  }

  return $targets
}

# Before `rotz link` overwrites a target with a symlink, this moves
# whatever is CURRENTLY there into <BackupDir>/<timestamp>/<same relative
# path under home> - but only if it's a real file/folder, not already a
# symlink (which almost certainly means a previous run of this same repo
# already linked it, so there's nothing of the user's to lose). Reads every
# dot.yaml's `links:` block via Get-DotLinkTargets so this stays in sync
# with the repo automatically - no separate list of targets to maintain.
function Backup-ExistingLinkTargets {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$BackupDir
  )

  $homeDir = if ($IsWindows) { $env:USERPROFILE } else { $HOME }
  $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $dotYamlFiles = Get-ChildItem -Path $RepoRoot -Recurse -Depth 1 -Filter "dot.yaml" -File
  $backedUpCount = 0

  foreach ($dotYaml in $dotYamlFiles) {
    foreach ($target in (Get-DotLinkTargets -DotYamlPath $dotYaml.FullName)) {
      $resolvedTarget = if ($target.StartsWith("~")) { $homeDir + $target.Substring(1) } else { $target }

      if (-not (Test-Path $resolvedTarget)) { continue }

      $item = Get-Item -Path $resolvedTarget -Force
      $isSymlink = [bool]($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)
      if ($isSymlink) {
        Write-Host "    [common] $resolvedTarget is already a symlink - nothing to back up"
        continue
      }

      $relative = $resolvedTarget.Substring($homeDir.Length).TrimStart('/', '\')
      $backupPath = "$BackupDir/$timestamp/$relative"
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backupPath) | Out-Null

      Write-Host "    [common] Backing up existing $resolvedTarget -> $backupPath"
      Move-Item -Path $resolvedTarget -Destination $backupPath -Force
      $backedUpCount++
    }
  }

  if ($backedUpCount -gt 0) {
    Write-Host "    [common] Backed up $backedUpCount pre-existing config(s) under $BackupDir/$timestamp"
  } else {
    Write-Host "    [common] No pre-existing configs found that needed backing up"
  }
}

# Runs an external program (mise, rotz, git, apt-get, ...) and prints clear
# boundary markers around it, so it's unambiguous in the console where this
# repo's own diagnostic Write-Host lines end and the program's OWN output
# begins - and exactly when that program started and finished. The
# program's stdout/stderr are left completely untouched (not captured, not
# piped, not prefixed) so its own live progress bars/spinners still render
# correctly; only the >>>/<<< lines around it come from us.
function Invoke-ExternalCommand {
  param(
    [Parameter(Mandatory)][string]$Exe,
    [string[]]$Arguments = @(),
    [string]$Label = $Exe   # short human name shown in the banners, e.g. "rotz install"
  )

  $argString = ($Arguments -join " ")
  Write-Host ">>> [external] STARTING $Label  (started $(Get-Date -Format 'HH:mm:ss'))"
  Write-Host ">>> [external] command: $Exe $argString"
  Write-Host ">>> [external] --- everything below, until the matching <<< line, is printed by $Exe itself, not by this repo's scripts ---"

  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  & $Exe @Arguments
  $exitCode = $LASTEXITCODE
  $sw.Stop()
  $elapsed = "$([math]::Round($sw.Elapsed.TotalSeconds, 1))s"

  Write-Host "<<< [external] --- end of $Exe output ---"
  Write-Host "<<< [external] FINISHED $Label  (exit code $exitCode, elapsed $elapsed)"

  if ($exitCode -ne 0) {
    throw "$Label exited with code $exitCode"
  }
}

# Sets a user-scope environment variable, persisted and in the current
# session.
#   Windows: HKCU\Environment (registry).
#   Linux:   ~/.profile (idempotent export line).
function Set-UserEnvVar {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$Value
  )
  Write-Host "    [common] Set-UserEnvVar: $Name=$Value"

  if ($IsWindows) {
    [Environment]::SetEnvironmentVariable($Name, $Value, "User")
  } else {
    $rc = "$HOME/.profile"
    if (-not (Test-Path $rc)) { New-Item -ItemType File -Path $rc -Force | Out-Null }
    $marker = "export $Name="
    if (Select-String -Path $rc -Pattern ([regex]::Escape($marker)) -Quiet -ErrorAction SilentlyContinue) {
      # Replace the existing line so re-runs update the value instead of
      # accumulating duplicate exports.
      (Get-Content $rc) | ForEach-Object {
        if ($_ -match "^export $([regex]::Escape($Name))=") { "export $Name=`"$Value`"" } else { $_ }
      } | Set-Content $rc
      Write-Host "    [common] -> updated existing export in $rc"
    } else {
      Add-Content -Path $rc -Value "`nexport $Name=`"$Value`""
      Write-Host "    [common] -> appended new export to $rc"
    }
  }
  Set-Item -Path "Env:$Name" -Value $Value
}
