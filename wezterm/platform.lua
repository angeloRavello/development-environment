-- OS detection - lets wezterm.lua decide which of windows.lua/linux.lua to
-- load, split into its own module (rather than inlining
-- wezterm.target_triple:find(...) checks directly in wezterm.lua) so any
-- other file could check platform.is_win/is_linux too if it ever needs to.
-- No is_mac: this repo's core invariant (see CLAUDE.md) only ever targets
-- Windows 11 and Ubuntu/Linux, so a branch for macOS would be dead code.
local wezterm = require("wezterm")
local module = {}

module.is_win = wezterm.target_triple:find("windows") ~= nil
module.is_linux = wezterm.target_triple:find("linux") ~= nil

return module
