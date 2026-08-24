#Requires -Version 7.0
# Installs git. Runs under pwsh7 on both Windows and Linux.
#   Windows: portable Git for Windows under ~/.local/opt/git - no admin,
#            no installer, works whether the profile lives on C: or D:.
#   Linux:   apt (sudo) if available; otherwise prints manual instructions -
#            most Ubuntu images already ship git, so this is usually a no-op.
$ErrorActionPreference = "Stop"
. "$PSScriptRoot/../bootstrap/common.ps1"

if (Get-Command git -ErrorAction SilentlyContinue) {
  Write-Host "==> [git] Already available: $(git --version)"
  exit 0
}

if ($IsWindows) {
  $homeDir = $env:USERPROFILE
  $destDir = "$homeDir/.local/opt/git"
  $gitExe = "$destDir/cmd/git.exe"

  Write-Host "==> [git] Target executable: $gitExe"

  if (-not (Test-Path $gitExe)) {
    Write-Host "==> [git] Downloading portable Git for Windows"
    $url = Get-LatestGithubAsset -Repo "git-for-windows/git" -Pattern '^PortableGit-.*-64-bit\.7z\.exe$'
    $sfx = Join-Path $env:TEMP ("PortableGit_" + [guid]::NewGuid().ToString() + ".7z.exe")
    Write-Host "==> [git] Downloading to $sfx (timeout 300s)"
    try {
      Invoke-WebRequest -UseBasicParsing -TimeoutSec 300 -Uri $url -OutFile $sfx
    } catch {
      throw "Timed out or failed downloading $url (offline? behind a proxy/firewall?): $($_.Exception.Message)"
    }
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null

    # Self-extracting 7z archive: -y = assume yes, -o<dir> = output dir (no
    # space). Guarded with a timeout: a stuck/hung SFX process would
    # otherwise block this script (and rotz install) forever with no
    # visible error.
    Write-Host "==> [git] Extracting self-extracting archive to $destDir (timeout 120s)"
    $proc = Start-Process -FilePath $sfx -ArgumentList "-y", "-o$destDir" -PassThru -WindowStyle Hidden
    if (-not $proc.WaitForExit(120000)) {
      $proc | Stop-Process -Force
      throw "PortableGit self-extraction did not finish within 120s - aborted"
    }
    Remove-Item $sfx -Force

    # Populates cmd\ with the wrapper executables (git.exe, gitk.exe, ...).
    # It also tries a couple of steps that assume the standard "C:\Program
    # Files\Git" install path and fail with "Permission denied" when
    # portable - that's expected and harmless, cmd\git.exe still works.
    Write-Host "==> [git] Running post-install.bat"
    Push-Location $destDir
    try { & ".\post-install.bat" 2>&1 | Out-Null } catch { }
    Pop-Location
  } else {
    Write-Host "==> [git] Already installed at $gitExe - skipping download"
  }

  Add-UserPath "$destDir/cmd"
  Write-Host "==> [git] Verifying installation"
  & $gitExe --version
} else {
  Write-Host "==> [git] Not found on PATH - checking for sudo"
  & sudo -n true 2>$null
  $sudoNonInteractive = ($LASTEXITCODE -eq 0)
  $hasSudo = ($env:USER -eq "root") -or $sudoNonInteractive
  Write-Host "==> [git] sudo available: $hasSudo"

  if ($hasSudo) {
    Write-Host "==> [git] Installing via apt-get"
    & sudo apt-get update -y
    & sudo apt-get install -y git
    if ($LASTEXITCODE -ne 0) { throw "apt-get install -y git exited with code $LASTEXITCODE" }
  } else {
    Write-Host @"
[git] git is missing and this account has no sudo access.
Options:
  - Ask an admin to run: sudo apt-get install -y git
  - Install Homebrew (https://brew.sh, no root required) and run: brew install git
"@
    exit 1
  }

  Write-Host "==> [git] Verifying installation"
  & git --version
}
