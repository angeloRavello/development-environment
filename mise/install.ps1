#Requires -Version 7.0
# Installs mise (https://mise.jdx.dev) - no admin/sudo. Runs under pwsh7 on
# both Windows and Linux.
#   Windows: portable zip extracted into <InstallDir>/mise (see
#            bootstrap/paths.env), same pattern as git/wezterm.
#   Linux:   mise's own official installer script, which decides its own
#            install location (~/.local/bin/mise) - see the comment below
#            for why that's the one exception to the InstallDir convention.
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot ".." "bootstrap" "common.ps1")

$homeDir = Get-HomeDir

$miseBinName = $null
if ($IsWindows) { $miseBinName = "mise.exe" }
if ($IsLinux) { $miseBinName = "mise" }

if ($IsWindows) {
  $paths = Get-BootstrapPaths
  $installSubDir = Join-Path $paths.InstallDir "mise"
  $exe = $null
  $found = Get-ChildItem -Path $installSubDir -Recurse -Filter $miseBinName -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($found) { $exe = $found.FullName }

  if ($exe) {
    Write-Log -Tag "mise" -Message "Already installed at $exe - skipping download"
  } else {
    Write-Log -Tag "mise" -Message "Not found under $installSubDir - downloading portable zip for Windows"
    $url = Get-LatestGithubAsset -Repo "jdx/mise" -Pattern '^mise-v[\d.]+-windows-x64\.zip$'
    Install-PortableZip -Url $url -DestDir $installSubDir -DownloadsDir $paths.DownloadsDir
    # The zip nests the binary (e.g. mise/bin/mise.exe) - find it rather
    # than assuming the exact layout, in case that ever changes.
    $found = Get-ChildItem -Path $installSubDir -Recurse -Filter $miseBinName | Select-Object -First 1
    if (-not $found) { throw "mise.exe not found after extracting mise zip (searched $installSubDir)" }
    $exe = $found.FullName
    Write-Log -Tag "mise" -Message "Extracted to $exe"
  }

  Add-UserPath (Split-Path -Parent $exe)
}
if ($IsLinux) {
  $exe = Join-Path $homeDir ".local" "bin" $miseBinName
  Write-Log -Tag "mise" -Message "Target executable: $exe"

  if (Test-Path $exe) {
    Write-Log -Tag "mise" -Message "Already installed at $exe - skipping download"
  } else {
    # Linux: use mise's own official installer script rather than
    # hand-rolling a tarball download. This is the one place in the repo
    # that intentionally shells out to bash instead of doing the work in
    # pwsh - it's the vendor-documented install method, not custom logic
    # worth reimplementing. It also picks its own install location
    # (~/.local/bin/mise), which is why mise on Linux doesn't follow the
    # InstallDir/<tool> convention the other portable tools use here.
    Write-Log -Tag "mise" -Message "Not found - running the official installer (curl https://mise.run | sh)"
    Invoke-ExternalCommand -Exe "bash" -Arguments @("-c", "curl -fsSL --max-time 300 https://mise.run | sh") -Label "mise official installer"
  }

  Add-UserPath (Join-Path $homeDir ".local" "bin")
}

if (-not (Test-Path $exe)) {
  throw "mise did not end up at the expected path $exe after installation"
}

Add-UserPath (Join-Path $homeDir ".local" "share" "mise" "shims")

Write-Log -Tag "mise" -Message "Verifying installation"
& $exe --version
