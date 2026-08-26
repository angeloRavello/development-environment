#Requires -Version 7.0
# Installs yazi (via mise), deploys its config files, and installs the
# official "y" shell wrapper function -
# https://yazi-rs.github.io/docs/quick-start#shell-wrapper - so that
# running `y` (instead of `yazi`) launches the file manager and, when you
# quit it, actually changes your shell's current directory to wherever you
# navigated to inside yazi. Without this, yazi only ever affects its own
# process - quitting always drops you back exactly where you started, no
# matter how far you browsed. Runs under pwsh7 on both Windows and Linux.
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot ".." "bootstrap" "common.ps1")

Invoke-ExternalCommand -Exe "mise" -Arguments @("use", "--global", "yazi") -Label "mise use --global yazi"

$paths = Get-BootstrapPaths
Sync-DotLink -Source (Join-Path $PSScriptRoot "yazi.toml") -Target "~/.config/yazi/yazi.toml" -BackupDir $paths.BackupDir
Sync-DotLink -Source (Join-Path $PSScriptRoot "theme.toml") -Target "~/.config/yazi/theme.toml" -BackupDir $paths.BackupDir

# keymap.toml: on Windows, append a "g" + <DRIVE LETTER> jump for every
# FIXED drive actually present on THIS machine (e.g. "g C" -> cd C:\) -
# generated here at install time, not hardcoded in the tracked file,
# since a different machine running this same repo could have completely
# different drive letters. yazi's config is plain TOML with no scripting
# (unlike wezterm.lua/java.lua, both Lua), so there's no way for yazi
# itself to detect drives at its own runtime - this has to happen here.
#
# Uppercase second key (g + Shift+C, not g + c) deliberately: checked
# yazi's real default keymap
# (github.com/sxyazi/yazi/blob/main/yazi-config/preset/keymap-default.toml)
# before picking this - lowercase "g c" is already bound to cd ~/.config
# and "g d" to cd ~/Downloads, so lowercase drive letters would have
# silently overridden those.
$keymapSource = Join-Path $PSScriptRoot "keymap.toml"
if ($IsWindows) {
  $driveBlocks = [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq "Fixed" -and $_.IsReady } | ForEach-Object {
    $letter = $_.Name.Substring(0, 1).ToUpper()
    Write-Log -Tag "yazi" -Message "Drive shortcut: g $letter -> $($_.Name)"
    @"
[[mgr.prepend_keymap]]
on = [ "g", "$letter" ]
run = "cd ${letter}:\\"
desc = "Go to ${letter}:\\"
"@
  }
  $generatedKeymap = Join-Path ([System.IO.Path]::GetTempPath()) "yazi-keymap-with-drives.toml"
  $combined = (Get-Content -Path $keymapSource -Raw) + "`n`n" + ($driveBlocks -join "`n`n")
  Set-Content -Path $generatedKeymap -Value $combined -Encoding utf8 -NoNewline
  $keymapSource = $generatedKeymap
}
Sync-DotLink -Source $keymapSource -Target "~/.config/yazi/keymap.toml" -BackupDir $paths.BackupDir

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
    Write-Log -Tag "yazi" -Message "Updating existing managed block in $ProfilePath"
    $before = $beginIdx -gt 0 ? $existing[0..($beginIdx - 1)] : @()
    $after = $endIdx -lt $existing.Count - 1 ? $existing[($endIdx + 1)..($existing.Count - 1)] : @()
    @($before + $block + $after) | Set-Content -Path $ProfilePath
  } else {
    Write-Log -Tag "yazi" -Message "Appending managed block to $ProfilePath"
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
  Write-Log -Tag "yazi" -Message "Installing 'y' wrapper into pwsh profile: $PROFILE"
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
}
if ($IsLinux) {
  $bashrc = "$HOME/.bashrc"
  Write-Log -Tag "yazi" -Message "Installing 'y' wrapper into $bashrc"
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

Write-Log -Tag "yazi" -Message "Done. Open a NEW terminal (or reload your profile) for the 'y' command to be available."
