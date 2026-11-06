-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- Java files use the same 2-space indentation as the rest of this config
-- (explicit here, not just relying on the global default, so it's clear
-- this was a deliberate choice and not an oversight).
vim.api.nvim_create_autocmd("FileType", {
  pattern = "java",
  callback = function()
    vim.bo.shiftwidth = 2
    vim.bo.tabstop = 2
    vim.bo.softtabstop = 2
    vim.bo.expandtab = true
  end,
})

-- Maven projects: import the project as soon as nvim opens a folder that
-- contains a pom.xml (`nvim .`, `nvim path/to/service`, or a later `:cd`
-- / project switch), instead of waiting for the first .java buffer.
--
-- LazyVim's java extra only starts jdtls from a FileType=java autocmd, using
-- the current buffer's path to find the root. So rather than duplicating its
-- whole jdtls config here, this loads one of the project's .java files into
-- a hidden, unlisted buffer: that fires the extra's own FileType handler
-- (plus plugins/java.lua's overrides), and jdtls starts importing the Maven
-- build in the background. Opening any real file later reuses that client.
local maven_started = {}

-- Folders never worth walking into to find a source file.
local maven_skip_dirs = { target = true, build = true, out = true, bin = true, node_modules = true }

local function maven_first_java_file(root)
  -- Standard Maven layout first (cheap), then any module of a multi-module
  -- build (root pom only lists <modules>, sources live one level down).
  local starts = {
    vim.fs.joinpath(root, "src", "main", "java"),
    vim.fs.joinpath(root, "src", "test", "java"),
    root,
  }
  for _, start in ipairs(starts) do
    if vim.fn.isdirectory(start) == 1 then
      for name, type in
        vim.fs.dir(start, {
          depth = 12,
          skip = function(dir)
            local base = vim.fs.basename(dir)
            return not (maven_skip_dirs[base] or base:sub(1, 1) == ".")
          end,
        })
      do
        if type == "file" and name:match("%.java$") then
          return vim.fs.joinpath(start, name)
        end
      end
    end
  end
end

local function maven_autostart(dir)
  dir = vim.fs.normalize(vim.fn.fnamemodify(dir, ":p"))
  dir = (dir:gsub("(.)/$", "%1"))
  if maven_started[dir] or not vim.uv.fs_stat(vim.fs.joinpath(dir, "pom.xml")) then
    return
  end
  maven_started[dir] = true

  local file = maven_first_java_file(dir)
  if not file then
    vim.notify("pom.xml found but no .java files yet - jdtls will start with the first one", vim.log.levels.INFO, { title = "Maven" })
    return
  end

  vim.notify("Importing Maven project " .. vim.fs.basename(dir), vim.log.levels.INFO, { title = "Maven" })
  local buf = vim.fn.bufadd(file)
  if vim.fn.bufloaded(buf) == 0 then
    vim.bo[buf].buflisted = false
    -- bufload() runs filetype detection with `buf` as the current buffer,
    -- which is exactly what the java extra's attach function expects.
    vim.fn.bufload(buf)
  end
end

local function maven_autostart_startup()
  local argv = vim.fn.argv()
  if #argv == 0 then
    maven_autostart(vim.fn.getcwd())
  elseif #argv == 1 and vim.fn.isdirectory(argv[1]) == 1 then
    maven_autostart(argv[1])
  end
  -- Explicit file arguments: nothing to do, a .java file attaches jdtls on
  -- its own and anything else isn't "opening a folder".
end

-- This file loads on VeryLazy (after VimEnter) when nvim starts without file
-- arguments, but before VimEnter when it starts with them - handle both.
if vim.v.vim_did_enter == 1 then
  vim.schedule(maven_autostart_startup)
else
  vim.api.nvim_create_autocmd("VimEnter", {
    once = true,
    callback = function()
      vim.schedule(maven_autostart_startup)
    end,
  })
end

vim.api.nvim_create_autocmd("DirChanged", {
  pattern = "global",
  callback = function()
    local cwd = vim.v.event.cwd
    vim.schedule(function()
      maven_autostart(cwd)
    end)
  end,
})

-- gd/gf inside pom.xml: jump to module, parent and dependency poms.
require("config.maven").setup()
