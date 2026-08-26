-- Linux-specific WezTerm config. Currently nothing needs overriding here:
-- WezTerm's own default (respecting $SHELL) is already correct, since
-- unlike Windows (pwsh7/PowerShell 5/cmd), this repo doesn't install or
-- pin a specific shell on Linux. Kept as its own module anyway, mirroring
-- windows.lua, so Linux-specific keys/launch_menu entries have an obvious
-- place to go if this ever needs any.
local module = {}

function module.apply_to_config(config)
  config.launch_menu = {
    { label = "bash", args = { "/bin/bash", "-l" } },
  }
end

return module
