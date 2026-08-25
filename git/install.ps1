#Requires -Version 7.0
# Installs git and deploys gitconfig -> ~/.gitconfig. Runs under pwsh7 on
# both Windows and Linux.
#   Windows: portable Git for Windows under <InstallDir>/git (see
#            bootstrap/paths.env) - no admin, no installer.
#   Linux:   apt (sudo) if available; otherwise prints manual instructions -
#            most Ubuntu images already ship git, so this is usually a no-op.
$ErrorActionPreference = "Stop"
. "$PSScriptRoot/../bootstrap/common.ps1"

$paths = Get-BootstrapPaths

if (Get-Command git -ErrorAction SilentlyContinue) {
  Write-Log -Tag "git" -Message "Already available: $(git --version)"
} elseif ($IsWindows) {
  $destDir = "$($paths.InstallDir)/git"
  $gitExe = "$destDir/cmd/git.exe"

  Write-Log -Tag "git" -Message "Target executable: $gitExe"

  Write-Log -Tag "git" -Message "Downloading portable Git for Windows"
  $url = Get-LatestGithubAsset -Repo "git-for-windows/git" -Pattern '^PortableGit-.*-64-bit\.7z\.exe$'
  $sfxFileName = Split-Path -Leaf ([Uri]$url).AbsolutePath
  $sfx = "$($paths.DownloadsDir)/$sfxFileName"
  if (Test-Path $sfx) {
    Write-Log -Tag "git" -Message "Already downloaded at $sfx - skipping download"
  } else {
    Write-Log -Tag "git" -Message "Downloading to $sfx (timeout 300s)"
    try {
      Invoke-WebRequest -UseBasicParsing -TimeoutSec 300 -Uri $url -OutFile $sfx
    } catch {
      throw "Timed out or failed downloading $url (offline? behind a proxy/firewall?): $($_.Exception.Message)"
    }
  }
  New-Item -ItemType Directory -Force -Path $destDir | Out-Null

  # Self-extracting 7z archive: -y = assume yes, -o<dir> = output dir (no
  # space). Guarded with a timeout: a stuck/hung SFX process would
  # otherwise block this script forever with no visible error.
  Write-Log -Tag "external" -Message "STARTING PortableGit self-extraction (timeout 120s)"
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $proc = Start-Process -FilePath $sfx -ArgumentList "-y", "-o$destDir" -PassThru -WindowStyle Hidden
  if (-not $proc.WaitForExit(120000)) {
    $proc | Stop-Process -Force
    throw "PortableGit self-extraction did not finish within 120s - aborted"
  }
  $sw.Stop()
  Write-Log -Tag "external" -Message "FINISHED PortableGit self-extraction (elapsed $([math]::Round($sw.Elapsed.TotalSeconds, 3))s)"

  # Populates cmd\ with the wrapper executables (git.exe, gitk.exe, ...).
  # It also tries a couple of steps that assume the standard "C:\Program
  # Files\Git" install path and fail with "Permission denied" when
  # portable - that's expected and harmless, cmd\git.exe still works.
  Write-Log -Tag "git" -Message "Running post-install.bat"
  Push-Location $destDir
  try { & ".\post-install.bat" 2>&1 | Out-Null } catch { }
  Pop-Location

  Add-UserPath "$destDir/cmd"
  Write-Log -Tag "git" -Message "Verifying installation"
  & $gitExe --version
} elseif ($IsLinux) {
  Write-Log -Tag "git" -Message "Not found on PATH - checking for sudo"
  & sudo -n true 2>$null
  $sudoNonInteractive = ($LASTEXITCODE -eq 0)
  $hasSudo = ($env:USER -eq "root") -or $sudoNonInteractive
  Write-Log -Tag "git" -Message "sudo available: $hasSudo"

  if ($hasSudo) {
    Write-Log -Tag "git" -Message "Installing via apt-get"
    Invoke-ExternalCommand -Exe "sudo" -Arguments @("apt-get", "update", "-y") -Label "apt-get update"
    Invoke-ExternalCommand -Exe "sudo" -Arguments @("apt-get", "install", "-y", "git") -Label "apt-get install git"
  } else {
    Write-Log -Tag "git" -Level "ERROR" -Message @"
git is missing and this account has no sudo access.
Options:
  - Ask an admin to run: sudo apt-get install -y git
  - Install Homebrew (https://brew.sh, no root required) and run: brew install git
"@
    exit 1
  }

  Write-Log -Tag "git" -Message "Verifying installation"
  & git --version
}

Sync-DotLink -Source "$PSScriptRoot/gitconfig" -Target "~/.gitconfig" -BackupDir $paths.BackupDir
