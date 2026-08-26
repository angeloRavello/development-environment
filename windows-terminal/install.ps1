#Requires -Version 7.0
# Configures Windows Terminal - Windows only. Not a tool this repo
# installs (Windows 11 ships it by default; if it's missing, install it
# from the Microsoft Store first, then re-run this). What this adds on
# top of whatever WT already has configured:
#   - A "PowerShell 7" profile pointing at the pwsh7 this repo's
#     prereq.ps1 installs, resolved dynamically via `Get-Command pwsh`
#     (never hardcoded - depending on whether pwsh was already on PATH
#     before this repo ran, it can end up in different places).
#   - That profile set as the default profile.
#   - A global "Quake mode" hotkey (Win+`) that drops down a PowerShell 7
#     window from ANYWHERE in Windows, not just while a WT window is
#     already open - see https://learn.microsoft.com/windows/terminal/tips-and-tricks#quake-mode.
#     This needs WT running in the background to catch the hotkey, so
#     startOnUserLogin/notification-area settings are turned on too so
#     it's always listening even with every WT window closed.
#   - A plain in-app keybinding (Ctrl+Alt+P) to open a new PowerShell 7 tab
#     in an already-open WT window, as a simpler non-global fallback.
#
# This MERGES into WT's existing settings.json (matched by a fixed GUID,
# so re-running this updates the same profile/actions instead of
# duplicating them) instead of overwriting it outright the way
# Sync-DotLink does for static config files - settings.json is a live
# file WT itself rewrites (color schemes, other profiles, window state),
# so blindly replacing it would silently discard anything not defined
# here. The previous file is still backed up first, into the same
# BackupDir every other tool's config backups land in.
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot ".." "bootstrap" "common.ps1")

if ($IsWindows) {
  $pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue
  if (-not $pwshCmd) {
    Write-Log -Tag "windows-terminal" -Level "WARN" -Message "pwsh not found on PATH - run bootstrap/prereq.ps1 first. Skipping Windows Terminal configuration."
  } else {
    $pwshExe = $pwshCmd.Source

    # The Store-packaged build (how Windows 11 ships it by default) keeps
    # user settings under a per-package LocalState folder whose exact name
    # embeds a fixed publisher suffix - matched with a wildcard instead of
    # hardcoding it, in case that ever changes across WT versions.
    $wtPackageDir = Get-ChildItem -Path (Join-Path $env:LOCALAPPDATA "Packages") -Filter "Microsoft.WindowsTerminal_*" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $wtPackageDir) {
      Write-Log -Tag "windows-terminal" -Level "WARN" -Message "Windows Terminal package folder not found under $(Join-Path $env:LOCALAPPDATA 'Packages') - open Windows Terminal at least once (its settings.json is only created on first run), then re-run this script."
    } else {
      $settingsPath = Join-Path $wtPackageDir.FullName "LocalState" "settings.json"
      Write-Log -Tag "windows-terminal" -Message "Configuring $settingsPath"

      $paths = Get-BootstrapPaths
      # Fixed, arbitrary GUID - not meant to be "real"/random, just stable
      # across re-runs so this always updates the SAME profile entry
      # instead of appending a duplicate one every time.
      $profileGuid = "{574e775e-4f2a-5b96-ac1e-a2962a402336}"

      $settings = @{}
      if (Test-Path $settingsPath) {
        $settings = Get-Content -Path $settingsPath -Raw | ConvertFrom-Json -AsHashtable -Depth 32
      } else {
        Write-Log -Tag "windows-terminal" -Message "$settingsPath does not exist yet - creating a new one"
      }

      if (-not $settings.ContainsKey("profiles")) { $settings["profiles"] = @{} }
      if (-not $settings["profiles"].ContainsKey("list")) { $settings["profiles"]["list"] = @() }
      $profileList = [System.Collections.Generic.List[object]]::new()
      foreach ($p in $settings["profiles"]["list"]) {
        if ($p["guid"] -ne $profileGuid) { $profileList.Add($p) }
      }
      $profileList.Add(@{
        guid              = $profileGuid
        name              = "PowerShell 7"
        commandline       = $pwshExe
        icon              = $pwshExe
        startingDirectory = "%USERPROFILE%"
      })
      $settings["profiles"]["list"] = $profileList
      $settings["defaultProfile"] = $profileGuid

      if (-not $settings.ContainsKey("actions")) { $settings["actions"] = @() }
      $actionList = [System.Collections.Generic.List[object]]::new()
      foreach ($a in $settings["actions"]) {
        $isOurQuakeBinding = $a.ContainsKey("keys") -and $a["keys"] -eq 'win+`'
        $isOurTabBinding = $a.ContainsKey("keys") -and $a["keys"] -eq "ctrl+alt+p"
        if (-not $isOurQuakeBinding -and -not $isOurTabBinding) { $actionList.Add($a) }
      }
      $actionList.Add(@{
        command = @{ action = "globalSummon"; name = "_quake"; desktop = "toCurrent" }
        keys    = 'win+`'
      })
      $actionList.Add(@{
        command = @{ action = "newTab"; profile = $profileGuid }
        keys    = "ctrl+alt+p"
      })
      $settings["actions"] = $actionList

      # Needed for the global hotkey to work even with no WT window open -
      # otherwise Win+` only works while some WT window already exists.
      $settings["startOnUserLogin"] = $true
      $settings["minimizeToNotificationArea"] = $true
      $settings["alwaysShowNotificationIcon"] = $true

      if (Test-Path $settingsPath) {
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $backupPath = Join-Path $paths.BackupDir $timestamp "windows-terminal-settings.json"
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backupPath) | Out-Null
        Write-Log -Tag "windows-terminal" -Message "Backing up existing settings.json -> $backupPath"
        Copy-Item -Path $settingsPath -Destination $backupPath -Force
      }

      ($settings | ConvertTo-Json -Depth 32) | Set-Content -Path $settingsPath -Encoding utf8
      Write-Log -Tag "windows-terminal" -Message "Done: PowerShell 7 is now the default profile. Win+backtick summons a Quake-style pwsh7 window from anywhere (WT now starts on login and keeps running in the notification area so the hotkey always works). Ctrl+Alt+P opens a new pwsh7 tab inside an existing WT window."
    }
  }
}
if ($IsLinux) {
  Write-Log -Tag "windows-terminal" -Message "Windows Terminal is Windows-only - nothing to do on Linux"
}
