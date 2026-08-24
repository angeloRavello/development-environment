#Requires -Version 7.0
# Installs WezTerm. Runs under pwsh7 on both Windows and Linux.
#   Windows: portable zip under ~/.local/opt/wezterm - no admin, no
#            installer. WezTerm is not in mise's registry, so this is a
#            direct GitHub-releases download like git.
#   Linux:   apt repo (sudo) for update-friendly installs, or the portable
#            AppImage (no sudo) into ~/.local/opt/wezterm.
$ErrorActionPreference = "Stop"
. "$PSScriptRoot/../bootstrap/common.ps1"

if (Get-Command wezterm -ErrorAction SilentlyContinue) {
  Write-Host "==> [wezterm] Already available: $(wezterm --version 2>&1)"
  exit 0
}

if ($IsWindows) {
  $destDir = "$env:USERPROFILE/.local/opt/wezterm"
  $exe = "$destDir/wezterm.exe"

  Write-Host "==> [wezterm] Target executable: $exe"

  if (Test-Path $exe) {
    Write-Host "==> [wezterm] Already installed at $exe - skipping download"
  } else {
    Write-Host "==> [wezterm] Downloading WezTerm"
    $url = Get-LatestGithubAsset -Repo "wezterm/wezterm" -Pattern '^WezTerm-windows-.*\.zip$'
    Install-PortableZip -Url $url -DestDir $destDir

    # Some releases nest everything under a single subfolder - flatten it
    # so wezterm.exe always ends up directly in $destDir.
    if (-not (Test-Path $exe)) {
      $found = Get-ChildItem -Path $destDir -Recurse -Filter "wezterm.exe" | Select-Object -First 1
      if (-not $found) { throw "wezterm.exe not found after extracting WezTerm zip (searched $destDir)" }
      $inner = $found.Directory
      Write-Host "==> [wezterm] Flattening nested folder $($inner.FullName) into $destDir"
      Get-ChildItem -Path $inner.FullName | Move-Item -Destination $destDir -Force
      if ($inner.FullName -ne $destDir) { Remove-Item $inner.FullName -Recurse -Force }
    }
  }

  Add-UserPath $destDir
  Write-Host "==> [wezterm] Verifying installation"
  & $exe --version
} else {
  Write-Host "==> [wezterm] Not found on PATH - checking for sudo"
  & sudo -n true 2>$null
  $sudoNonInteractive = ($LASTEXITCODE -eq 0)
  $hasSudo = ($env:USER -eq "root") -or $sudoNonInteractive
  Write-Host "==> [wezterm] sudo available: $hasSudo"

  if ($hasSudo) {
    Write-Host "==> [wezterm] Installing via the official apt repo"
    curl -fsSL --max-time 30 https://apt.fury.io/wezterm/gpg.key | sudo gpg --yes --dearmor -o /usr/share/keyrings/wezterm-fury.gpg
    'deb [signed-by=/usr/share/keyrings/wezterm-fury.gpg] https://apt.fury.io/wezterm/ * *' | sudo tee /etc/apt/sources.list.d/wezterm.list | Out-Null
    & sudo apt-get update -y
    & sudo apt-get install -y wezterm
    if ($LASTEXITCODE -ne 0) { throw "apt-get install -y wezterm exited with code $LASTEXITCODE" }
  } else {
    Write-Host "==> [wezterm] No sudo access - installing the portable AppImage into ~/.local/opt/wezterm"
    $destDir = "$HOME/.local/opt/wezterm"
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    $url = Get-LatestGithubAsset -Repo "wezterm/wezterm" -Pattern '\.AppImage$'
    $appImage = "$destDir/wezterm.AppImage"
    Write-Host "==> [wezterm] Downloading AppImage to $appImage (timeout 300s)"
    try {
      Invoke-WebRequest -UseBasicParsing -TimeoutSec 300 -Uri $url -OutFile $appImage
    } catch {
      throw "Timed out or failed downloading $url (offline? behind a proxy/firewall?): $($_.Exception.Message)"
    }
    & chmod +x $appImage
    & ln -sf $appImage "$destDir/wezterm"
    Add-UserPath $destDir
  }

  Write-Host "==> [wezterm] Verifying installation"
  & wezterm --version
}
