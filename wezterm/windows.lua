-- Windows-specific WezTerm config: PowerShell 7 as the default shell
-- (matches this repo's Windows Terminal profile - see
-- ../windows-terminal/install.ps1, set up the same way), plus quick
-- access to PowerShell 5 and cmd via the launcher menu and Ctrl+Alt+1/2/3.
local wezterm = require("wezterm")
local act = wezterm.action
local module = {}

function module.apply_to_config(config)
  config.default_prog = { "pwsh.exe", "-NoLogo" }
  config.launch_menu = {
    { label = "PowerShell 7", args = { "pwsh.exe", "-NoLogo" } },
    { label = "Windows PowerShell 5", args = { "powershell.exe", "-NoLogo" } },
    { label = "Command Prompt", args = { "cmd.exe" } },
  }

  -- Ctrl+Alt+<digit> (no Shift) is unused by any of WezTerm's own default
  -- keybindings - confirmed via `wezterm show-keys` before picking this.
  -- Ctrl+Shift+<digit> looks like the obvious first choice but is already
  -- bound to jump-straight-to-tab-N (and Ctrl+Shift+0 resets font size),
  -- so binding over it would have silently broken those.
  config.keys = config.keys or {}
  table.insert(config.keys, {
    key = "1",
    mods = "CTRL|ALT",
    action = act.SpawnCommandInNewTab({ args = { "pwsh.exe", "-NoLogo" }, domain = { DomainName = "local" } }),
  })
  table.insert(config.keys, {
    key = "2",
    mods = "CTRL|ALT",
    action = act.SpawnCommandInNewTab({ args = { "powershell.exe", "-NoLogo" }, domain = { DomainName = "local" } }),
  })
  table.insert(config.keys, {
    key = "3",
    mods = "CTRL|ALT",
    action = act.SpawnCommandInNewTab({ args = { "cmd.exe" }, domain = { DomainName = "local" } }),
  })
end

return module
