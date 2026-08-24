# Shared helpers for bootstrap.ps1 and every dot's install.ps1 in this repo.
# This file targets pwsh7 (PowerShell Core) and runs unmodified on both
# Windows and Linux - it uses the $IsWindows/$IsLinux automatic variables,
# which only exist under pwsh7 (NOT Windows PowerShell 5.1). That's why
# bootstrap/prereq.ps1 and bootstrap/prereq.sh, which install pwsh7 itself,
# deliberately do NOT dot-source this file.
#
# Everything here installs into the current user's profile only - no
# admin/sudo required.

# Prints the browser_download_url of the first release asset whose name
# matches the given regex pattern.
function Get-LatestGithubAsset {
  param(
    [Parameter(Mandatory)][string]$Repo,     # "owner/name"
    [Parameter(Mandatory)][string]$Pattern,  # regex matched against the asset file name
    [int]$TimeoutSec = 30
  )
  Write-Host "    [common] Querying GitHub API for latest release of $Repo (timeout ${TimeoutSec}s)"
  try {
    $release = Invoke-RestMethod -UseBasicParsing -TimeoutSec $TimeoutSec -Uri "https://api.github.com/repos/$Repo/releases/latest" -Headers @{ "User-Agent" = "rotz-dotfiles-bootstrap" }
  } catch {
    throw "Timed out or failed reaching GitHub API for $Repo after ${TimeoutSec}s (offline? behind a proxy/firewall?): $($_.Exception.Message)"
  }
  $asset = $release.assets | Where-Object { $_.name -match $Pattern } | Select-Object -First 1
  if (-not $asset) {
    throw "No release asset matching '$Pattern' found in latest release of $Repo"
  }
  Write-Host "    [common] Resolved asset: $($asset.name)"
  return $asset.browser_download_url
}

# Downloads a .zip and extracts it into $DestDir. Works on both Windows and
# Linux (Expand-Archive is pure .NET, not Windows-only).
function Install-PortableZip {
  param(
    [Parameter(Mandatory)][string]$Url,
    [Parameter(Mandatory)][string]$DestDir,
    [int]$TimeoutSec = 300
  )
  New-Item -ItemType Directory -Force -Path $DestDir | Out-Null
  $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("dl_" + [guid]::NewGuid().ToString() + ".zip")
  Write-Host "    [common] Downloading $Url"
  Write-Host "    [common] -> $tmp (timeout ${TimeoutSec}s)"
  try {
    Invoke-WebRequest -UseBasicParsing -TimeoutSec $TimeoutSec -Uri $Url -OutFile $tmp
  } catch {
    throw "Timed out or failed downloading $Url after ${TimeoutSec}s (offline? behind a proxy/firewall?): $($_.Exception.Message)"
  }
  $size = (Get-Item $tmp).Length
  Write-Host "    [common] Downloaded $size bytes - extracting to $DestDir"
  Expand-Archive -Path $tmp -DestinationPath $DestDir -Force
  Remove-Item $tmp -Force
}

# Downloads a .tar.gz and extracts it into $DestDir. Linux-only (shells out
# to `tar`, which ships by default on virtually every distro - unlike .zip
# handling, .tar.gz needs no pure-.NET equivalent worth hand-rolling here).
function Install-PortableTarGz {
  param(
    [Parameter(Mandatory)][string]$Url,
    [Parameter(Mandatory)][string]$DestDir,
    [int]$TimeoutSec = 300
  )
  if (-not $IsLinux) {
    throw "Install-PortableTarGz is Linux-only"
  }
  New-Item -ItemType Directory -Force -Path $DestDir | Out-Null
  $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("dl_" + [guid]::NewGuid().ToString() + ".tar.gz")
  Write-Host "    [common] Downloading $Url"
  Write-Host "    [common] -> $tmp (timeout ${TimeoutSec}s)"
  try {
    Invoke-WebRequest -UseBasicParsing -TimeoutSec $TimeoutSec -Uri $Url -OutFile $tmp
  } catch {
    throw "Timed out or failed downloading $Url after ${TimeoutSec}s (offline? behind a proxy/firewall?): $($_.Exception.Message)"
  }
  $size = (Get-Item $tmp).Length
  Write-Host "    [common] Downloaded $size bytes - extracting to $DestDir"
  & tar -xzf $tmp -C $DestDir
  if ($LASTEXITCODE -ne 0) {
    throw "tar exited with code $LASTEXITCODE while extracting $tmp"
  }
  Remove-Item $tmp -Force
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
