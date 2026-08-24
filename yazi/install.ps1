#Requires -Version 7.0
# Installs yazi (via mise) and the official "y" shell wrapper function -
# https://yazi-rs.github.io/docs/quick-start#shell-wrapper - so that
# running `y` (instead of `yazi`) launches the file manager and, when you
# quit it, actually changes your shell's current directory to wherever you
# navigated to inside yazi. Without this, yazi only ever affects its own
# process - quitting always drops you back exactly where you started, no
# matter how far you browsed. Runs under pwsh7 on both Windows and Linux.
$ErrorActionPreference = "Stop"

Write-Host "==> [yazi] mise use --global yazi"
& mise use --global yazi
if ($LASTEXITCODE -ne 0) { throw "mise use --global yazi exited with code $LASTEXITCODE" }

# Idempotently writes $Content between two marker comment lines in
# $ProfilePath: if the markers are already there (from a previous run),
# everything between them is replaced in place - so re-running this after
# the wrapper's definition changes updates it instead of piling up
# duplicate function definitions. If the markers aren't there yet, the
# whole block is appended.
function Set-ManagedBlock {
  param(
    [Parameter(Mandatory)][string]$ProfilePath,
    [Parameter(Mandatory)][string]$BeginMarker,
    [Parameter(Mandatory)][string]$EndMarker,
    [Parameter(Mandatory)][string[]]$Content
  )

  $parent = Split-Path -Parent $ProfilePath
  if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  if (-not (Test-Path $ProfilePath)) { New-Item -ItemType File -Path $ProfilePath -Force | Out-Null }

  $existing = Get-Content -Path $ProfilePath
  $beginIdx = [array]::IndexOf($existing, $BeginMarker)
  $endIdx = [array]::IndexOf($existing, $EndMarker)
  $block = @($BeginMarker) + $Content + @($EndMarker)

  if ($beginIdx -ge 0 -and $endIdx -gt $beginIdx) {
    Write-Host "    [yazi] Updating existing managed block in $ProfilePath"
    $before = if ($beginIdx -gt 0) { $existing[0..($beginIdx - 1)] } else { @() }
    $after = if ($endIdx -lt $existing.Count - 1) { $existing[($endIdx + 1)..($existing.Count - 1)] } else { @() }
    @($before + $block + $after) | Set-Content -Path $ProfilePath
  } else {
    Write-Host "    [yazi] Appending managed block to $ProfilePath"
    Add-Content -Path $ProfilePath -Value ""
    Add-Content -Path $ProfilePath -Value $block
  }
}

$beginMarker = "# >>> yazi shell wrapper (managed by development-environment/yazi) >>>"
$endMarker   = "# <<< yazi shell wrapper (managed by development-environment/yazi) <<<"

if ($IsWindows) {
  # $PROFILE resolves to pwsh7's own CurrentUserCurrentHost profile - not
  # Windows PowerShell 5.1's (different, separate file). That's
  # deliberate: everything past bootstrap/prereq.ps1 in this repo assumes
  # pwsh7 is the shell you actually use day to day.
  Write-Host "==> [yazi] Installing 'y' wrapper into pwsh profile: $PROFILE"
  $pwshWrapper = @(
    'function y {',
    '  $tmp = [System.IO.Path]::GetTempFileName()',
    '  yazi $args --cwd-file="$tmp"',
    '  $cwd = Get-Content -Path $tmp -Encoding UTF8',
    '  if (-not [String]::IsNullOrEmpty($cwd) -and $cwd -ne $PWD.Path) {',
    '    Set-Location -LiteralPath $cwd',
    '  }',
    '  Remove-Item -Path $tmp -Force',
    '}'
  )
  Set-ManagedBlock -ProfilePath $PROFILE -BeginMarker $beginMarker -EndMarker $endMarker -Content $pwshWrapper
} else {
  $bashrc = "$HOME/.bashrc"
  Write-Host "==> [yazi] Installing 'y' wrapper into $bashrc"
  $bashWrapper = @(
    'function y() {',
    '  local tmp="$(mktemp -t "yazi-cwd.XXXXXX")"',
    '  yazi "$@" --cwd-file="$tmp"',
    '  if cwd="$(cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then',
    '    cd -- "$cwd" || exit',
    '  fi',
    '  rm -f -- "$tmp"',
    '}'
  )
  Set-ManagedBlock -ProfilePath $bashrc -BeginMarker $beginMarker -EndMarker $endMarker -Content $bashWrapper
}

Write-Host "==> [yazi] Done. Open a NEW terminal (or reload your profile) for the 'y' command to be available."
