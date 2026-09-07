#Requires -Version 7.0
# Installs tmux (via mise) and deploys its config. LINUX ONLY - tmux has
# no native Windows build, so on Windows this is a no-op (use WezTerm's
# built-in multiplexer there). Runs under pwsh7.
#
# tmux is in mise's registry as `aqua:tmux/tmux-builds` (static prebuilt
# Linux binaries - verified with `mise registry tmux` / `mise latest
# tmux`), so a plain `mise use --global tmux` is all the install needs,
# same as python/yazi.
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot ".." "bootstrap" "common.ps1")

if (-not $IsLinux) {
  Write-Log -Tag "tmux" -Message "tmux is Linux-only in this repo - nothing to do on Windows"
  return
}

Invoke-ExternalCommand -Exe "mise" -Arguments @("use", "--global", "tmux") -Label "mise use --global tmux"

$paths = Get-BootstrapPaths
$homeDir = Get-HomeDir

# tmux < 3.1 read only ~/.tmux.conf; 3.1+ prefers
# $XDG_CONFIG_HOME/tmux/tmux.conf (~/.config/tmux/tmux.conf) and, with both
# present, loads the XDG one and ignores ~/.tmux.conf entirely (confirmed
# on tmux 3.6). This repo deploys to the XDG path per its "~/.config/<tool>"
# convention, so any leftover ~/.tmux.conf would just sit there dead and
# confusing - move it into BackupDir alongside every other config this repo
# replaces, rather than leaving two.
$legacyRc = Join-Path $homeDir ".tmux.conf"
if (Test-Path -LiteralPath $legacyRc) {
  $backupPath = Join-Path $paths.BackupDir (Get-Date -Format "yyyyMMdd-HHmmss") ".tmux.conf"
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backupPath) | Out-Null
  Write-Log -Tag "tmux" -Message "Moving legacy $legacyRc -> $backupPath (tmux now reads ~/.config/tmux/tmux.conf)"
  Move-Item -LiteralPath $legacyRc -Destination $backupPath -Force
}

Sync-DotLink -Source (Join-Path $PSScriptRoot "tmux.conf") -Target "~/.config/tmux/tmux.conf" -BackupDir $paths.BackupDir

Write-Log -Tag "tmux" -Message "Done. Run 'tmux' in a new terminal; inside a running server, reload with 'tmux source ~/.config/tmux/tmux.conf'."
