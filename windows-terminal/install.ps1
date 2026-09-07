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
#   - An in-app keybinding (Ctrl+Alt+P) to open a new PowerShell 7 tab in
#     the current WT window.
#   - windowingBehavior = "useExisting", so "Open in Terminal" from
#     Explorer (and any other `wt`/protocol launch) opens a new TAB in the
#     current window instead of spawning a fresh window every time.
#   - startOnUserLogin / minimizeToNotificationArea / alwaysShowNotificationIcon
#     all forced OFF, so WT never lives in the system tray: minimizing goes
#     to the taskbar like any normal window, and closing every window fully
#     exits WT - no lingering tray icon, no per-window list in a tray menu.
#     This script previously turned those ON to power a global Win+` "Quake
#     mode" summon (which needs WT always running in the background); that
#     feature was dropped - `git log -p -- windows-terminal/install.ps1` has
#     it if you ever want it back.
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
        # Drop our Ctrl+Alt+P binding (re-added below) and any Win+` binding
        # left over from a previous run - this script used to add a
        # globalSummon "Quake mode" action there and no longer does.
        $isStaleQuakeBinding = $a.ContainsKey("keys") -and $a["keys"] -eq 'win+`'
        $isOurTabBinding = $a.ContainsKey("keys") -and $a["keys"] -eq "ctrl+alt+p"
        if (-not $isStaleQuakeBinding -and -not $isOurTabBinding) { $actionList.Add($a) }
      }
      $actionList.Add(@{
        command = @{ action = "newTab"; profile = $profileGuid }
        keys    = "ctrl+alt+p"
      })
      $settings["actions"] = $actionList

      # Forced OFF (not just left unset): a previous run of this script may
      # have written these as true for the old Quake-mode feature, and the
      # whole point now is that WT never keeps running in the system tray -
      # minimize goes to the taskbar, closing all windows exits WT.
      $settings["startOnUserLogin"] = $false
      $settings["minimizeToNotificationArea"] = $false
      $settings["alwaysShowNotificationIcon"] = $false

      # Explorer's "Open in Terminal", a bare `wt` from Run, the shell
      # protocol handler, etc. all open as a new TAB in the current window
      # instead of a brand-new window each time. "useExisting" reuses the
      # most-recent window on the CURRENT virtual desktop; "useAnyExisting"
      # would also yank one over from another desktop, which is more jarring.
      $settings["windowingBehavior"] = "useExisting"

      if (Test-Path $settingsPath) {
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $backupPath = Join-Path $paths.BackupDir $timestamp "windows-terminal-settings.json"
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backupPath) | Out-Null
        Write-Log -Tag "windows-terminal" -Message "Backing up existing settings.json -> $backupPath"
        Copy-Item -Path $settingsPath -Destination $backupPath -Force
      }

      ($settings | ConvertTo-Json -Depth 32) | Set-Content -Path $settingsPath -Encoding utf8
      Write-Log -Tag "windows-terminal" -Message "Done: PowerShell 7 is now the default profile. Ctrl+Alt+P opens a new pwsh7 tab in the current window. New terminal launches (Explorer's 'Open in Terminal', bare 'wt', etc.) open as a tab in the current window, not a new one. WT no longer starts on login or minimizes to the system tray - minimizing goes to the taskbar, closing all windows exits WT."
    }
  }
}
if ($IsLinux) {
  Write-Log -Tag "windows-terminal" -Message "Windows Terminal is Windows-only - nothing to do on Linux"
}
