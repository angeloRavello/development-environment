-- WezTerm config - https://wezterm.org/config/files.html
-- Linked to ~/.config/wezterm/wezterm.lua on both Windows and Linux.

local wezterm = require("wezterm")
local act = wezterm.action
local config = wezterm.config_builder()

config.color_scheme = "Tokyo Night"
config.font = wezterm.font_with_fallback({ "JetBrains Mono", "Cascadia Code", "monospace" })
config.font_size = 11.0

config.window_decorations = "RESIZE"
config.window_close_confirmation = "NeverPrompt"
config.scrollback_lines = 10000
config.enable_scroll_bar = false

config.use_fancy_tab_bar = false
config.tab_bar_at_bottom = true
config.hide_tab_bar_if_only_one_tab = true

-- Prefer PowerShell 7 (installed by bootstrap/prereq.ps1) on Windows, fall
-- back to whatever is on PATH everywhere else.
if wezterm.target_triple:find("windows") then
  config.default_prog = { "pwsh.exe", "-NoLogo" }

  -- Windows-only: quick access to all three common Windows shells, not
  -- just the default (pwsh7). Bare exe names, not absolute paths - all
  -- three resolve via PATH (pwsh.exe once this repo's prereq.ps1/mise
  -- have run; powershell.exe/cmd.exe ship on Windows' own PATH already),
  -- so nothing here needs per-machine templating even though this file
  -- is deployed as a static copy (Sync-DotLink), not generated.
  config.launch_menu = {
    { label = "PowerShell 7",         args = { "pwsh.exe", "-NoLogo" } },
    { label = "Windows PowerShell 5", args = { "powershell.exe", "-NoLogo" } },
    { label = "Command Prompt",       args = { "cmd.exe" } },
  }

  -- Ctrl+Shift+<digit> is already WezTerm's default for jumping straight
  -- to tab N (confirmed via `wezterm show-keys` - easy to miss since it's
  -- not documented as prominently as Alt+<digit>) and Ctrl+Shift+0 resets
  -- font size, so those would have been silently overridden. Ctrl+Alt+
  -- <digit> (no Shift) is unused by any default binding - also confirmed
  -- via `wezterm show-keys` - and WezTerm's own defaults already use
  -- Ctrl+Alt combos for pane splitting, so this reaches WezTerm the same
  -- way on Spanish/Latin AltGr keyboards as those do.
  config.keys = {
    { key = "7", mods = "CTRL|ALT", action = act.SpawnCommandInNewTab({ args = { "pwsh.exe", "-NoLogo" } }) },
    { key = "5", mods = "CTRL|ALT", action = act.SpawnCommandInNewTab({ args = { "powershell.exe", "-NoLogo" } }) },
    { key = "0", mods = "CTRL|ALT", action = act.SpawnCommandInNewTab({ args = { "cmd.exe" } }) },
  }
end

return config
