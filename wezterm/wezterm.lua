-- WezTerm config - https://wezterm.org/config/files.html
-- Linked to ~/.config/wezterm/wezterm.lua on both Windows and Linux.

local wezterm = require("wezterm")
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

-- Prefer PowerShell 7 (installed by bootstrap/prereq.ps1 before rotz even
-- runs) on Windows, fall back to whatever is on PATH everywhere else.
if wezterm.target_triple:find("windows") then
  config.default_prog = { "pwsh.exe", "-NoLogo" }
end

return config
