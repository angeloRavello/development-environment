-- WezTerm config - https://wezterm.org/config/files.html
-- Linked to ~/.config/wezterm/wezterm.lua on both Windows and Linux, along
-- with platform.lua/windows.lua/linux.lua (deployed to the same directory
-- by wezterm/install.ps1) - WezTerm's Lua `require` resolves relative to
-- this file's own directory, so they have to live alongside it.
--
-- Structure: settings shared across both OSes stay in this file; anything
-- OS-specific is delegated to windows.lua/linux.lua's apply_to_config,
-- selected via platform.lua. Keeps this file from accumulating OS checks
-- as more platform-specific config gets added over time.

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

local platform = require("platform")
if platform.is_win then
  require("windows").apply_to_config(config)
end
if platform.is_linux then
  require("linux").apply_to_config(config)
end

return config
