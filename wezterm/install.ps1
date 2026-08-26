#Requires -Version 7.0
# Installs WezTerm - always the NIGHTLY build. This is a deliberate,
# one-off exception: every other portable tool in this repo pins to the
# latest STABLE release, but WezTerm is kept on nightly specifically.
#
# WezTerm's nightly release reuses the same GitHub release tag ("nightly")
# and the same asset filenames on every build - only the CONTENTS change -
# and it's marked as a prerelease, so /releases/latest would never return
# it (that endpoint skips prereleases). Two consequences, both handled
# below and NOT shared with any other install script in this repo:
#   - Get-LatestGithubAsset is called with -Tag "nightly" to fetch that
#     specific release instead of "latest".
#   - Install-PortableZip is called with -Force so it always re-downloads
#     over the cached .zip in DownloadsDir, instead of assuming a
#     same-named file means "already have the latest" (true for every
#     other tool here, false for a rolling release).
#   - This script never short-circuits on "already installed" the way
#     every other install.ps1 does - it always re-checks and re-installs,
#     since the whole point is staying current with nightly.
#
# Runs under pwsh7 on both Windows and Linux.
#   Windows: WezTerm-windows-nightly.zip, extracted into <InstallDir>/wezterm.
#   Linux:   the nightly AppImage, also into <InstallDir>/wezterm. No apt
#            path here even when sudo is available - WezTerm's apt repo
#            only ever carries stable releases, which would silently
#            defeat "always nightly" for anyone with sudo.
$ErrorActionPreference = "Stop"
. "$PSScriptRoot/../bootstrap/common.ps1"

$paths = Get-BootstrapPaths
$destDir = "$($paths.InstallDir)/wezterm"

if ($IsWindows) {
  $exe = "$destDir/wezterm.exe"
  Write-Log -Tag "wezterm" -Message "Installing nightly build to $destDir"
  $url = Get-LatestGithubAsset -Repo "wezterm/wezterm" -Tag "nightly" -Pattern '^WezTerm-windows-nightly\.zip$'
  Install-PortableZip -Url $url -DestDir $destDir -DownloadsDir $paths.DownloadsDir -Force

  # Some releases nest everything under a single subfolder - flatten it so
  # wezterm.exe always ends up directly in $destDir.
  if (-not (Test-Path $exe)) {
    $found = Get-ChildItem -Path $destDir -Recurse -Filter "wezterm.exe" | Select-Object -First 1
    if (-not $found) { throw "wezterm.exe not found after extracting WezTerm nightly zip (searched $destDir)" }
    $inner = $found.Directory
    Write-Log -Tag "wezterm" -Message "Flattening nested folder $($inner.FullName) into $destDir"
    Get-ChildItem -Path $inner.FullName | Move-Item -Destination $destDir -Force
    if ($inner.FullName -ne $destDir) { Remove-Item $inner.FullName -Recurse -Force }
  }

  Add-UserPath $destDir
  Write-Log -Tag "wezterm" -Message "Verifying installation"
  & $exe --version
}
if ($IsLinux) {
  New-Item -ItemType Directory -Force -Path $destDir | Out-Null
  $appImage = "$destDir/wezterm.AppImage"
  Write-Log -Tag "wezterm" -Message "Installing nightly AppImage to $destDir"
  # Pinned to the Ubuntu 20.04 build for broad compatibility: an AppImage
  # linked against an older glibc generally still runs fine on newer
  # distros (glibc is backward-compatible), which isn't true the other way
  # around. Bump this if it ever stops working on whatever you're running.
  $url = Get-LatestGithubAsset -Repo "wezterm/wezterm" -Tag "nightly" -Pattern '^WezTerm-nightly-Ubuntu20\.04\.AppImage$'
  Write-Log -Tag "wezterm" -Message "Downloading to $appImage (timeout 300s, always re-fetched)"
  try {
    Invoke-WebRequest -UseBasicParsing -TimeoutSec 300 -Uri $url -OutFile $appImage
  } catch {
    throw "Timed out or failed downloading $url (offline? behind a proxy/firewall?): $($_.Exception.Message)"
  }
  # && (PS7 pipeline chain operator): only symlink if chmod actually
  # succeeded, instead of silently proceeding on a failed chmod like a
  # plain sequence of two statements would.
  chmod +x $appImage && ln -sf $appImage "$destDir/wezterm"
  if (-not (Test-Path "$destDir/wezterm")) {
    throw "chmod +x / ln -sf on $appImage did not produce $destDir/wezterm - see the raw chmod/ln output above"
  }
  Add-UserPath $destDir

  Write-Log -Tag "wezterm" -Message "Verifying installation"
  & "$destDir/wezterm" --version
}

Sync-DotLink -Source "$PSScriptRoot/wezterm.lua" -Target "~/.config/wezterm/wezterm.lua" -BackupDir $paths.BackupDir
