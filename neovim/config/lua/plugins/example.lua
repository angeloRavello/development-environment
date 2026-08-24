-- Custom plugin overrides. LazyVim's own plugins live in the LazyVim plugin
-- itself (imported from lua/config/lazy.lua) - this file is only for
-- overrides/additions on top of that.
--
-- Language support matching the toolchains installed by this dotfiles repo
-- (../python, ../java, ../rust, ../zig): pulls in LazyVim's ready-made LSP +
-- treesitter + formatting setup for each via its "extras" system.
-- https://www.lazyvim.org/extras
return {
  { import = "lazyvim.plugins.extras.lang.python" },
  { import = "lazyvim.plugins.extras.lang.rust" },
  { import = "lazyvim.plugins.extras.lang.java" },
  { import = "lazyvim.plugins.extras.lang.zig" },
}
