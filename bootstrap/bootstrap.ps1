#Requires -Version 7.0
<#
  Unified bootstrap script - runs under pwsh7 on BOTH Windows and Linux.

  Do not run this directly on a brand new machine: use bootstrap/prereq.ps1
  (Windows) or bootstrap/prereq.sh (Linux) first. Those install pwsh7 if it
  isn't already present (nothing else is guaranteed to exist on a fresh
  machine) and then hand off to this script.

  There is no external orchestration tool involved (no rotz, no dot.yaml
  manifests) - this script IS the orchestrator. It calls each tool's own
  install.ps1 directly, in a fixed, explicit order:

    1. Environment variables ($DOTFILES, and on Windows only, XDG_*).
    2. mise       - hard dependency: python/rust/zig/java/yazi/neovim all
                    need it, and everything downstream would just fail
                    confusingly without it, so this aborts the whole
                    bootstrap on failure instead of continuing.
    3. git        - also a hard dependency: neovim's install step needs
                    `git` on PATH to clone LazyVim.
    4. wezterm, python, rust, zig, java, yazi, neovim, in that order -
       "soft" stages: a failure here is logged and the bootstrap keeps
       going (matching the old `rotz install --continue-on-error`
       behavior), since none of these block each other. neovim is last
       because it depends on both mise (Stage 2) and git (Stage 3).

  Every stage is run through Invoke-Stage (bootstrap/common.ps1), which
  logs a start line, an end line with elapsed time, and - on failure - an
  ERROR line, all in the same "[yyyy-MM-dd HH:mm:ss.fff] [LEVEL] [tag]
  message" format every script in this repo uses. That timestamp
  (millisecond resolution) is what lets you look at the console output
  after a hang and see exactly which stage was running and how long it
  had already been running for.

  Each tool's own install.ps1 deploys its own config files (if any) by
  calling Sync-DotLink directly - there's no separate "link" pass here.
#>

$ErrorActionPreference = "Stop"

if ($PSVersionTable.PSVersion.Major -lt 7) {
  throw "bootstrap.ps1 requires pwsh7, but is running under PowerShell $($PSVersionTable.PSVersion). Run bootstrap/prereq.ps1 (Windows) or bootstrap/prereq.sh (Linux) instead - they install pwsh7 and relaunch this script correctly."
}

. "$PSScriptRoot/common.ps1"

$RepoRoot = (Resolve-Path "$PSScriptRoot/..").Path
$HomeDir = $null
if ($IsWindows) { $HomeDir = $env:USERPROFILE }
if ($IsLinux) { $HomeDir = $HOME }

Write-Log -Tag "bootstrap" -Message "Dotfiles repo: $RepoRoot"
Write-Log -Tag "bootstrap" -Message "pwsh version: $($PSVersionTable.PSVersion)  IsWindows=$IsWindows  IsLinux=$IsLinux  Home=$HomeDir"

$bootstrapStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$results = [ordered]@{}

# --- Stage: environment variables (hard - nothing downstream works without $DOTFILES) ---
Invoke-Stage -Name "environment variables" -Action {
  Set-UserEnvVar -Name "DOTFILES" -Value $RepoRoot
  if ($IsWindows) {
    Set-UserEnvVar -Name "XDG_CONFIG_HOME" -Value (Join-Path $env:USERPROFILE ".config")
    Set-UserEnvVar -Name "XDG_DATA_HOME"   -Value (Join-Path $env:USERPROFILE ".local\share")
    Set-UserEnvVar -Name "XDG_CACHE_HOME"  -Value (Join-Path $env:USERPROFILE ".cache")
    Set-UserEnvVar -Name "XDG_STATE_HOME"  -Value (Join-Path $env:USERPROFILE ".local\state")
  }
  if ($IsLinux) {
    Write-Log -Tag "bootstrap" -Message "Linux: leaving XDG_* vars alone (tools default to ~/.config etc. on their own)"
  }
} | Out-Null

# --- Stage: mise (HARD dependency - aborts the bootstrap on failure) ---
Invoke-Stage -Name "mise" -Action {
  & "$RepoRoot/mise/install.ps1"
} | Out-Null

$miseCmd = Get-Command mise -ErrorAction SilentlyContinue
if (-not $miseCmd) {
  throw "mise did not install correctly - 'mise' not found on PATH after mise/install.ps1 ran"
}
Write-Log -Tag "bootstrap" -Message "mise executable: $($miseCmd.Source)"

# --- Stage: git (HARD dependency - neovim needs `git` on PATH to clone LazyVim) ---
Invoke-Stage -Name "git" -Action {
  & "$RepoRoot/git/install.ps1"
} | Out-Null

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  throw "git did not install correctly - 'git' not found on PATH after git/install.ps1 ran"
}

# --- Remaining stages: soft dependencies, explicit fixed order, continue past failures ---
$softStages = [ordered]@{
  "wezterm" = { & "$RepoRoot/wezterm/install.ps1" }
  "python"  = { & "$RepoRoot/python/install.ps1" }
  "rust"    = { & "$RepoRoot/rust/install.ps1" }
  "zig"     = { & "$RepoRoot/zig/install.ps1" }
  "java"    = { & "$RepoRoot/java/install.ps1" }
  "yazi"    = { & "$RepoRoot/yazi/install.ps1" }
  "neovim"  = { & "$RepoRoot/neovim/install.ps1" }   # last: needs both mise and git
}

foreach ($stageName in $softStages.Keys) {
  $results[$stageName] = Invoke-Stage -Name $stageName -Action $softStages[$stageName] -ContinueOnError
}

$bootstrapStopwatch.Stop()

Write-Log -Tag "bootstrap" -Message ""
Write-Log -Tag "bootstrap" -Message "===== Summary (total elapsed $([math]::Round($bootstrapStopwatch.Elapsed.TotalSeconds, 3))s) ====="
$failedStages = @()
foreach ($stageName in $results.Keys) {
  $status = "OK"
  if (-not $results[$stageName]) {
    $status = "FAILED"
    $failedStages += $stageName
  }
  Write-Log -Tag "bootstrap" -Message "  $stageName : $status"
}

if ($failedStages.Count -gt 0) {
  Write-Log -Tag "bootstrap" -Level "ERROR" -Message "Done, but $($failedStages.Count) stage(s) failed: $($failedStages -join ', '). Scroll up to the matching 'Stage FAILED' line for each to see why."
} else {
  Write-Log -Tag "bootstrap" -Message "Done, all stages succeeded. Open a NEW terminal so the updated PATH/env vars take effect."
}
