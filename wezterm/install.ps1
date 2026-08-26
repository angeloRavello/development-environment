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
. (Join-Path $PSScriptRoot ".." "bootstrap" "common.ps1")

$paths = Get-BootstrapPaths
$destDir = Join-Path $paths.InstallDir "wezterm"

if ($IsWindows) {
  # The Windows zip ships two relevant executables: wezterm.exe (console-
  # subsystem CLI wrapper - `wezterm cli ...`, `wezterm start`, etc.) and
  # wezterm-gui.exe (GUI-subsystem binary - the actual terminal window).
  # Launching wezterm.exe directly to open the terminal flashes/leaves a
  # console window behind it; wezterm-gui.exe is the one meant to be
  # launched directly (shortcut, taskbar, double-click). Both are kept on
  # PATH; only wezterm-gui.exe is used as the shortcut target below.
  $exe = Join-Path $destDir "wezterm.exe"
  $guiExe = Join-Path $destDir "wezterm-gui.exe"
  Write-Log -Tag "wezterm" -Message "Installing nightly build to $destDir"
  $url = Get-LatestGithubAsset -Repo "wezterm/wezterm" -Tag "nightly" -Pattern '^WezTerm-windows-nightly\.zip$'
  Install-PortableZip -Url $url -DestDir $destDir -DownloadsDir $paths.DownloadsDir -Force

  # Some releases nest everything under a single subfolder - flatten it so
  # both executables always end up directly in $destDir.
  if (-not (Test-Path $exe)) {
    $found = Get-ChildItem -Path $destDir -Recurse -Filter "wezterm.exe" | Select-Object -First 1
    if (-not $found) { throw "wezterm.exe not found after extracting WezTerm nightly zip (searched $destDir)" }
    $inner = $found.Directory
    Write-Log -Tag "wezterm" -Message "Flattening nested folder $($inner.FullName) into $destDir"
    Get-ChildItem -Path $inner.FullName | Move-Item -Destination $destDir -Force
    if ($inner.FullName -ne $destDir) { Remove-Item $inner.FullName -Recurse -Force }
  }
  if (-not (Test-Path $guiExe)) {
    throw "wezterm-gui.exe not found after extracting WezTerm nightly zip (searched $destDir) - this is the executable the Start Menu shortcut below points at"
  }

  Add-UserPath $destDir
  Write-Log -Tag "wezterm" -Message "Verifying installation"
  & $exe --version

  # A portable .exe isn't indexed by Windows Search on its own - only
  # things with a shortcut (.lnk) somewhere Windows looks, like the
  # per-user Start Menu Programs folder, are. Creating one there (no admin
  # needed, it's a per-user folder) is what actually makes "wezterm" show
  # up when you search the Start menu.
  $startMenuPrograms = Join-Path $env:APPDATA "Microsoft" "Windows" "Start Menu" "Programs"
  $shortcutPath = Join-Path $startMenuPrograms "WezTerm.lnk"
  Write-Log -Tag "wezterm" -Message "Creating Start Menu shortcut: $shortcutPath"
  $wshShell = New-Object -ComObject WScript.Shell
  $shortcut = $wshShell.CreateShortcut($shortcutPath)
  $shortcut.TargetPath = $guiExe
  $shortcut.WorkingDirectory = $destDir
  $shortcut.Description = "WezTerm - GPU-accelerated cross-platform terminal emulator"
  $shortcut.IconLocation = $guiExe
  $shortcut.Save()

  # Pinning to the TASKBAR, unlike Start Menu search, can't be automated on
  # modern Windows - Microsoft removed the scriptable "Pin to taskbar"
  # shell verb starting with Windows 10 2004 specifically so installers
  # can't silently modify the taskbar, and there's no supported replacement
  # for a plain portable .exe like this one (the newer pin API only exists
  # for a packaged app to pin itself). So: one manual click, once, ever -
  # not something any script can do for you on current Windows.
  Write-Log -Tag "wezterm" -Message "Shortcut created - WezTerm now shows up in Windows Search."
  Write-Log -Tag "wezterm" -Message "To pin it to the taskbar: search 'WezTerm' in the Start menu, right-click the result, choose 'Pin to taskbar'. This one step can't be scripted - Windows blocks taskbar changes from anything but the user."
}
if ($IsLinux) {
  New-Item -ItemType Directory -Force -Path $destDir | Out-Null
  $appImage = Join-Path $destDir "wezterm.AppImage"
  $wezSymlink = Join-Path $destDir "wezterm"
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
  chmod +x $appImage && ln -sf $appImage $wezSymlink
  if (-not (Test-Path $wezSymlink)) {
    throw "chmod +x / ln -sf on $appImage did not produce $wezSymlink - see the raw chmod/ln output above"
  }
  Add-UserPath $destDir

  Write-Log -Tag "wezterm" -Message "Verifying installation"
  & $wezSymlink --version
}

Sync-DotLink -Source (Join-Path $PSScriptRoot "wezterm.lua") -Target "~/.config/wezterm/wezterm.lua" -BackupDir $paths.BackupDir
