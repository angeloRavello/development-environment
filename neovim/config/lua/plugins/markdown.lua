-- Overrides for LazyVim's markdown extra (lazyvim.plugins.extras.lang.markdown),
-- which lints markdown with markdownlint-cli2 via nvim-lint.
-- Points it at this repo's base config (deployed by neovim/install.ps1 to
-- <nvim config>/.markdownlint-cli2.yaml), which turns off line-length (MD013).
return {
  {
    "mfussenegger/nvim-lint",
    opts = {
      linters = {
        ["markdownlint-cli2"] = {
          -- "-" (lint stdin) is nvim-lint's default arg for this linter; keep it.
          args = { "--config", vim.fn.stdpath("config") .. "/.markdownlint-cli2.yaml", "-" },
        },
      },
    },
  },
}
