#Requires -Version 7.0
# Installs JetBrainsMono Nerd Font for the current user only (no admin):
# LazyVim, lazygit, yazi, etc. draw file-type/git/diagnostic icons from the
# Nerd Font private-use codepoints, which ordinary fonts (Cascadia Mono,
# Windows Terminal's default) don't have - they render as boxes/garbage.
#
# The font is drawn by the terminal on the machine showing the window, so
# this matters on the Windows side even when Neovim itself runs on Linux
# over SSH/WSL. windows-terminal/install.ps1 and wezterm/wezterm.lua then
# select it by family name ($FontFamily below).
#
#   Windows: .ttf files into %LOCALAPPDATA%\Microsoft\Windows\Fonts, each
#            registered under HKCU\...\Fonts - the per-user font install
#            Windows 10 1809+ supports without elevation.
#   Linux:   .ttf files into ~/.local/share/fonts/<family>, then fc-cache.
#
# Skips the download entirely once the Regular face is installed. The
# release asset is named plain "JetBrainsMono.zip" (no version), so
# Install-PortableZip's filename cache would pin the first download
# anyway - to update, delete the installed .ttf files and re-run.
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot ".." "bootstrap" "common.ps1")

$paths = Get-BootstrapPaths
$fileGlob = "JetBrainsMonoNerdFont-*.ttf"   # the plain variant - not *Mono* / *Propo* (narrower icons)
$regularFile = "JetBrainsMonoNerdFont-Regular.ttf"

if ($IsWindows) {
  $fontDir = Join-Path $env:LOCALAPPDATA "Microsoft" "Windows" "Fonts"
} else {
  $dataHome = $env:XDG_DATA_HOME ? $env:XDG_DATA_HOME : (Join-Path (Get-HomeDir) ".local" "share")
  $fontDir = Join-Path $dataHome "fonts" "JetBrainsMonoNerdFont"
}

if (Test-Path (Join-Path $fontDir $regularFile)) {
  Write-Log -Tag "fonts" -Message "JetBrainsMono Nerd Font already installed in $fontDir - skipping"
  return
}

$extractDir = Join-Path $paths.InstallDir "fonts" "JetBrainsMono"
$url = Get-LatestGithubAsset -Repo "ryanoasis/nerd-fonts" -Pattern '^JetBrainsMono\.zip$'
Install-PortableZip -Url $url -DestDir $extractDir -DownloadsDir $paths.DownloadsDir

$files = Get-ChildItem -Path $extractDir -Recurse -File -Filter $fileGlob
if (-not $files) {
  throw "No $fileGlob found in $extractDir - did the archive layout change?"
}

New-Item -ItemType Directory -Force -Path $fontDir | Out-Null
if ($IsWindows) {
  $regKey = "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts"
  if (-not (Test-Path $regKey)) { New-Item -Path $regKey -Force | Out-Null }
}

foreach ($file in $files) {
  $target = Join-Path $fontDir $file.Name
  Copy-Item -Path $file.FullName -Destination $target -Force
  if ($IsWindows) {
    # Value name is only a label; the data (full path) is what Windows
    # loads at logon and what DirectWrite apps like Windows Terminal see.
    New-ItemProperty -Path $regKey -Name "$($file.BaseName) (TrueType)" -Value $target -PropertyType String -Force | Out-Null
  }
}
Write-Log -Tag "fonts" -Message "Installed $($files.Count) font files into $fontDir"

if ($IsLinux) {
  if (Get-Command fc-cache -ErrorAction SilentlyContinue) {
    Invoke-ExternalCommand -Exe "fc-cache" -Arguments @("-f", $fontDir) -Label "fc-cache"
  } else {
    Write-Log -Tag "fonts" -Level "WARN" -Message "fc-cache not found - the font is copied but fontconfig apps may not see it until the cache is rebuilt"
  }
}

Write-Log -Tag "fonts" -Message "Done. Close ALL terminal windows and reopen them - running apps don't pick up newly installed fonts."
