# Shared helpers for bootstrap.ps1 and every tool's install.ps1 in this
# repo. This file targets pwsh7 (PowerShell Core) and runs unmodified on
# both Windows and Linux - it uses the $IsWindows/$IsLinux automatic
# variables, which only exist under pwsh7 (NOT Windows PowerShell 5.1).
# That's why bootstrap/prereq.ps1 and bootstrap/prereq.sh, which install
# pwsh7 itself, deliberately do NOT dot-source this file.
#
# Everything here installs into the current user's profile only - no
# admin/sudo required. There is no external orchestration tool (rotz or
# otherwise) anywhere in this repo - bootstrap.ps1 calls every tool's
# install.ps1 directly, in an explicit, hardcoded order.

# Standard log line format used by every script in this repo:
#   [yyyy-MM-dd HH:mm:ss.fff] [LEVEL] [tag] message
# The millisecond timestamp is the point - it's what lets you look at two
# consecutive lines and see exactly how long the gap between them was,
# which is the main tool for figuring out where a hang or a slow step is
# when something goes wrong. Level is one of INFO/WARN/ERROR, padded to a
# fixed width so lines stay aligned in the terminal, and color-coded
# (Yellow/Red) so a WARN/ERROR jumps out when scanning a long scrollback -
# `-ForegroundColor` renders correctly in both Windows Terminal and Linux
# terminals under pwsh7.
function Write-Log {
  param(
    [Parameter(Mandatory)][AllowEmptyString()][string]$Message,
    [ValidateSet("INFO", "WARN", "ERROR")][string]$Level = "INFO",
    [string]$Tag = "common"
  )
  $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
  $line = "[$timestamp] [$($Level.PadRight(5))] [$Tag] $Message"
  switch ($Level) {
    "WARN"  { Write-Host $line -ForegroundColor Yellow }
    "ERROR" { Write-Host $line -ForegroundColor Red }
    default { Write-Host $line }
  }
}

# Runs $Action as a named, timed stage: logs when it starts, how long it
# took, and whether it succeeded or failed - the single mechanism behind
# every "step" bootstrap.ps1 runs, so every stage is logged exactly the
# same way with no copy-pasted try/catch boilerplate per call site.
#
# -ContinueOnError: log the failure (as ERROR) and return $false instead
# of throwing. Used for every stage except the ones later stages can't
# possibly succeed without (mise, git) - those are left to throw and abort
# the whole bootstrap, since continuing past them would just produce a
# longer, more confusing cascade of unrelated failures.
function Invoke-Stage {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][scriptblock]$Action,
    [switch]$ContinueOnError
  )
  Write-Log -Tag "bootstrap" -Message "Starting stage: $Name"
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  try {
    & $Action
    $sw.Stop()
    Write-Log -Tag "bootstrap" -Message "Finished stage: $Name (elapsed $([math]::Round($sw.Elapsed.TotalSeconds, 3))s)"
    return $true
  } catch {
    $sw.Stop()
    Write-Log -Tag "bootstrap" -Level "ERROR" -Message "Stage FAILED: $Name (elapsed $([math]::Round($sw.Elapsed.TotalSeconds, 3))s) - $($_.Exception.Message)"
    if (-not $ContinueOnError) { throw }
    return $false
  }
}

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
  }
  if ($IsLinux) {
    if ($looksLinuxAbsolute) { return $Value }
    if ($looksWindowsAbsolute) {
      throw "$KeyName is set to '$Value', which looks like a Windows absolute path, but this is Linux. Set ${KeyName}_LINUX in bootstrap/paths.env to a Linux path (e.g. /opt/tools/...) instead."
    }
  }

  # $Value comes straight from paths.env and may use either slash style
  # (e.g. ".local/downloads") - normalize it to this OS's separator before
  # joining, so the result is never a Windows base path with a stray "/"
  # spliced in (or vice versa on Linux).
  $normalized = $Value -replace '[\\/]', [System.IO.Path]::DirectorySeparatorChar
  return Join-Path $HomeDir $normalized
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
  $homeDir = $null
  if ($IsWindows) { $homeDir = $env:USERPROFILE }
  if ($IsLinux) { $homeDir = $HOME }
  $configPath = Join-Path $PSScriptRoot "paths.env"

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

  $osSuffix = $null
  if ($IsWindows) { $osSuffix = "_WINDOWS" }
  if ($IsLinux) { $osSuffix = "_LINUX" }
  $downloadsRaw = $raw.ContainsKey("DOWNLOADS_DIR$osSuffix") ? $raw["DOWNLOADS_DIR$osSuffix"] : $raw['DOWNLOADS_DIR']
  $installRaw = $raw.ContainsKey("INSTALL_DIR$osSuffix") ? $raw["INSTALL_DIR$osSuffix"] : $raw['INSTALL_DIR']
  $backupRaw = $raw.ContainsKey("BACKUP_DIR$osSuffix") ? $raw["BACKUP_DIR$osSuffix"] : $raw['BACKUP_DIR']

  $downloadsDir = Resolve-ConfiguredPath -Value $downloadsRaw -HomeDir $homeDir -KeyName "DOWNLOADS_DIR"
  $installDir = Resolve-ConfiguredPath -Value $installRaw -HomeDir $homeDir -KeyName "INSTALL_DIR"
  $backupDir = Resolve-ConfiguredPath -Value $backupRaw -HomeDir $homeDir -KeyName "BACKUP_DIR"

  New-Item -ItemType Directory -Force -Path $downloadsDir | Out-Null
  New-Item -ItemType Directory -Force -Path $installDir | Out-Null
  New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

  Write-Log -Message "DownloadsDir: $downloadsDir"
  Write-Log -Message "InstallDir:   $installDir"
  Write-Log -Message "BackupDir:    $backupDir"

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
  $uri = $Tag ? "https://api.github.com/repos/$Repo/releases/tags/$Tag" : "https://api.github.com/repos/$Repo/releases/latest"
  $what = $Tag ? "tag '$Tag'" : "latest release"
  Write-Log -Message "Querying GitHub API for $what of $Repo (timeout ${TimeoutSec}s)"
  try {
    $release = Invoke-RestMethod -UseBasicParsing -TimeoutSec $TimeoutSec -Uri $uri -Headers @{ "User-Agent" = "dotfiles-bootstrap" }
  } catch {
    throw "Timed out or failed reaching GitHub API for $Repo after ${TimeoutSec}s (offline? behind a proxy/firewall?): $($_.Exception.Message)"
  }
  $asset = $release.assets | Where-Object { $_.name -match $Pattern } | Select-Object -First 1
  if (-not $asset) {
    throw "No release asset matching '$Pattern' found in $what of $Repo"
  }
  Write-Log -Message "Resolved asset: $($asset.name)"
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
  $dest = Join-Path $DownloadsDir $fileName

  if ((Test-Path $dest) -and -not $Force) {
    Write-Log -Message "Already downloaded at $dest - skipping download"
  } else {
    if ($Force -and (Test-Path $dest)) {
      Write-Log -Message "-Force set (rolling release) - re-downloading over cached $dest"
    } else {
      Write-Log -Message "Downloading $Url"
    }
    Write-Log -Message "-> $dest (timeout ${TimeoutSec}s)"
    try {
      Invoke-WebRequest -UseBasicParsing -TimeoutSec $TimeoutSec -Uri $Url -OutFile $dest
    } catch {
      throw "Timed out or failed downloading $Url after ${TimeoutSec}s (offline? behind a proxy/firewall?): $($_.Exception.Message)"
    }
  }

  $size = (Get-Item $dest).Length
  Write-Log -Message "$size bytes - extracting to $DestDir"
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
  $dest = Join-Path $DownloadsDir $fileName

  if (Test-Path $dest) {
    Write-Log -Message "Already downloaded at $dest - skipping download"
  } else {
    Write-Log -Message "Downloading $Url"
    Write-Log -Message "-> $dest (timeout ${TimeoutSec}s)"
    try {
      Invoke-WebRequest -UseBasicParsing -TimeoutSec $TimeoutSec -Uri $Url -OutFile $dest
    } catch {
      throw "Timed out or failed downloading $Url after ${TimeoutSec}s (offline? behind a proxy/firewall?): $($_.Exception.Message)"
    }
  }

  $size = (Get-Item $dest).Length
  Write-Log -Message "$size bytes - extracting to $DestDir"
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

  Write-Log -Message "Add-UserPath: $Dir"

  if ($IsWindows) {
    $current = [Environment]::GetEnvironmentVariable("Path", "User")
    $parts = @()
    if ($current) { $parts = $current -split ";" }
    if (-not ($parts -contains $Dir)) {
      $new = $current ? "$current;$Dir" : $Dir
      [Environment]::SetEnvironmentVariable("Path", $new, "User")
      Write-Log -Message "-> written to HKCU\Environment\Path"
    } else {
      Write-Log -Message "-> already present in HKCU\Environment\Path"
    }
    if (($env:Path -split ";") -notcontains $Dir) {
      $env:Path = "$env:Path;$Dir"
    }
  }
  if ($IsLinux) {
    if (($env:Path -split ":") -notcontains $Dir) {
      $env:Path = "$env:Path`:$Dir"
    }
    foreach ($rc in @("$HOME/.profile", "$HOME/.bashrc")) {
      if (-not (Test-Path $rc)) { New-Item -ItemType File -Path $rc -Force | Out-Null }
      $marker = "PATH=`"`$PATH:$Dir`""
      if (-not (Select-String -Path $rc -Pattern ([regex]::Escape($marker)) -Quiet -ErrorAction SilentlyContinue)) {
        Add-Content -Path $rc -Value "`nexport PATH=`"`$PATH:$Dir`""
        Write-Log -Message "-> appended to $rc"
      } else {
        Write-Log -Message "-> already present in $rc"
      }
    }
  }
}

# True if $Source and $Target are files with identical content (compared
# by hash) or directories whose files all match (same relative paths, same
# hashes). False if $Target doesn't exist, or differs in any way. Used by
# Sync-DotLink to decide whether a link needs (re)deploying at all.
function Test-DotLinkUpToDate {
  param(
    [Parameter(Mandatory)][string]$Source,
    [Parameter(Mandatory)][string]$Target
  )
  if (-not (Test-Path $Target)) { return $false }

  $sourceIsDir = (Get-Item $Source).PSIsContainer
  $targetIsDir = (Get-Item $Target).PSIsContainer
  if ($sourceIsDir -ne $targetIsDir) { return $false }

  if (-not $sourceIsDir) {
    return (Get-FileHash $Source).Hash -eq (Get-FileHash $Target).Hash
  }

  $sourceFiles = @(Get-ChildItem -Path $Source -Recurse -File)
  $targetFiles = @(Get-ChildItem -Path $Target -Recurse -File)
  if ($sourceFiles.Count -ne $targetFiles.Count) { return $false }

  foreach ($sf in $sourceFiles) {
    $relative = $sf.FullName.Substring($Source.Length).TrimStart('\', '/')
    $tf = Join-Path $Target $relative
    if (-not (Test-Path $tf)) { return $false }
    if ((Get-FileHash $sf.FullName).Hash -ne (Get-FileHash $tf).Hash) { return $false }
  }
  return $true
}

# Deploys ONE config file/folder by COPYING (not symlinking) $Source onto
# $Target (accepts "~/..." - expanded against the current OS's home dir).
# Every tool's install.ps1 calls this directly for whatever config it owns
# - there's no repo-wide manifest of links to auto-discover, each script
# just declares its own.
#
# Copying, not symlinking: a real symlink needs either Windows Developer
# Mode (itself needs admin to turn on) or same-volume hard links/junctions
# (which fail the moment the dotfiles repo and $HOME are on different
# drives - an ordinary setup, not an edge case). Copying works everywhere
# with no admin and across drives, at the cost of live sync: editing a
# tracked file in this repo needs another Sync-DotLink call (i.e. another
# bootstrap run) to reach the deployed copy.
#
# Behavior per call:
#   - Target missing entirely -> just copy, nothing to back up.
#   - Target already matches Source (Test-DotLinkUpToDate) -> skip
#     entirely, so re-running this on an unchanged repo doesn't churn out
#     a fresh backup and a fresh copy every single time.
#   - Target exists and differs -> back it up to
#     <BackupDir>/<timestamp>/<same relative path under home> first (never
#     silently discard whatever was actually there, whether that's the
#     user's own pre-existing file or a stale previous deploy from before
#     the repo's tracked version changed), then copy the current source
#     over it.
function Sync-DotLink {
  param(
    [Parameter(Mandatory)][string]$Source,
    [Parameter(Mandatory)][string]$Target,
    [Parameter(Mandatory)][string]$BackupDir
  )

  $homeDir = $null
  if ($IsWindows) { $homeDir = $env:USERPROFILE }
  if ($IsLinux) { $homeDir = $HOME }

  # Call sites write $Target as "~/some/relative/path" using "/" regardless
  # of OS (it reads better than picking a separator per call site) - so
  # normalize to this OS's separator before Join-Path, otherwise Windows
  # ends up with a backslash home dir plus a literal "/" splice.
  $resolvedTarget = $Target
  if ($Target.StartsWith("~")) {
    $relative = ($Target.Substring(1).TrimStart('/', '\')) -replace '[\\/]', [System.IO.Path]::DirectorySeparatorChar
    $resolvedTarget = Join-Path $homeDir $relative
  }

  if (-not (Test-Path $Source)) {
    Write-Log -Level "WARN" -Message "Sync-DotLink source $Source does not exist - skipping"
    return
  }

  if (Test-DotLinkUpToDate -Source $Source -Target $resolvedTarget) {
    Write-Log -Message "$resolvedTarget already matches $Source - skipping"
    return
  }

  if (Test-Path $resolvedTarget) {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $relative = $resolvedTarget.Substring($homeDir.Length).TrimStart('/', '\')
    $backupPath = Join-Path $BackupDir $timestamp $relative
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backupPath) | Out-Null
    Write-Log -Message "Backing up existing $resolvedTarget -> $backupPath"
    Move-Item -Path $resolvedTarget -Destination $backupPath -Force
  }

  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $resolvedTarget) | Out-Null
  Write-Log -Message "Copying $Source -> $resolvedTarget"
  Copy-Item -Path $Source -Destination $resolvedTarget -Recurse -Force
}

# Runs an external program (mise, git, apt-get, ...) and prints clear
# boundary markers around it, so it's unambiguous in the console where this
# repo's own log lines end and the program's OWN output begins - and
# exactly when that program started and finished. The program's
# stdout/stderr are left completely untouched (not captured, not piped,
# not prefixed) so its own live progress bars/spinners still render
# correctly; only the >>>/<<< lines around it come from us.
function Invoke-ExternalCommand {
  param(
    [Parameter(Mandatory)][string]$Exe,
    [string[]]$Arguments = @(),
    [string]$Label = $Exe   # short human name shown in the banners, e.g. "git clone LazyVim/starter"
  )

  $argString = ($Arguments -join " ")
  Write-Log -Tag "external" -Message "STARTING $Label"
  Write-Log -Tag "external" -Message "command: $Exe $argString"
  Write-Log -Tag "external" -Message "--- everything below, until the matching FINISHED line, is printed by $Exe itself, not by this repo's scripts ---"

  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  & $Exe @Arguments
  $exitCode = $LASTEXITCODE
  $sw.Stop()

  Write-Log -Tag "external" -Message "--- end of $Exe output ---"
  Write-Log -Tag "external" -Message "FINISHED $Label (exit code $exitCode, elapsed $([math]::Round($sw.Elapsed.TotalSeconds, 3))s)"

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
  Write-Log -Message "Set-UserEnvVar: $Name=$Value"

  if ($IsWindows) {
    [Environment]::SetEnvironmentVariable($Name, $Value, "User")
  }
  if ($IsLinux) {
    $rc = "$HOME/.profile"
    if (-not (Test-Path $rc)) { New-Item -ItemType File -Path $rc -Force | Out-Null }
    $marker = "export $Name="
    if (Select-String -Path $rc -Pattern ([regex]::Escape($marker)) -Quiet -ErrorAction SilentlyContinue) {
      # Replace the existing line so re-runs update the value instead of
      # accumulating duplicate exports.
      (Get-Content $rc) | ForEach-Object {
        if ($_ -match "^export $([regex]::Escape($Name))=") { "export $Name=`"$Value`"" } else { $_ }
      } | Set-Content $rc
      Write-Log -Message "-> updated existing export in $rc"
    } else {
      Add-Content -Path $rc -Value "`nexport $Name=`"$Value`""
      Write-Log -Message "-> appended new export to $rc"
    }
  }
  Set-Item -Path "Env:$Name" -Value $Value
}
