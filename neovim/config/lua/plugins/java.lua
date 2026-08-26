-- Java + Maven support, on top of LazyVim's own Java extra
-- (https://www.lazyvim.org/extras/lang/java). That extra already:
--   - attaches jdtls (Eclipse JDT Language Server) with LSP/completion/
--     refactoring, Mason-installs java-debug-adapter + java-test for
--     debugging/testing, and sets up treesitter for Java syntax.
--   - recognizes `pom.xml` as a project root on its own (Eclipse JDT's
--     Maven/M2E integration reads it directly), so opening any file
--     inside a Maven project just works - no extra plugin needed for
--     Maven detection itself.
--
-- What this file adds on top: this dotfiles repo installs five JDKs
-- side by side (../../../java/install.ps1 - Temurin 8/11/17/21/25), and
-- jdtls only uses ONE of them (whatever `java` resolves to - Temurin 25,
-- this repo's mise global default) unless told about the others. A real
-- Maven project frequently pins an older <maven.compiler.release>/
-- <source>/<target> than 25 - without registering every installed JDK as
-- a named "runtime", jdtls would try to compile/run that code against
-- JDK 25 anyway, which can misbehave or just be wrong for that project.
return {
  { import = "lazyvim.plugins.extras.lang.java" },
  {
    "mfussenegger/nvim-jdtls",
    opts = function(_, opts)
      -- Resolves each Temurin install's real path via `mise where`
      -- instead of hardcoding one - mise's install folder names embed
      -- the full patch version (e.g. "temurin-21.0.12+101.0.LTS"), which
      -- changes every time mise upgrades that version, so a hardcoded
      -- path would silently go stale.
      local function mise_java_home(version)
        local handle = io.popen("mise where java@" .. version .. " 2>" .. (vim.fn.has("win32") == 1 and "NUL" or "/dev/null"))
        if not handle then
          return nil
        end
        local path = handle:read("*l")
        handle:close()
        return path
      end

      -- name must match Eclipse JDT's execution-environment names -
      -- JavaSE-1.8 for 8, JavaSE-<N> for everything since 9.
      local runtime_versions = {
        { name = "JavaSE-1.8", mise = "temurin-8" },
        { name = "JavaSE-11", mise = "temurin-11" },
        { name = "JavaSE-17", mise = "temurin-17" },
        { name = "JavaSE-21", mise = "temurin-21" },
        { name = "JavaSE-25", mise = "temurin-25", default = true }, -- matches java/install.ps1's mise global default
      }

      local runtimes = {}
      for _, rt in ipairs(runtime_versions) do
        local path = mise_java_home(rt.mise)
        if path and path ~= "" then
          table.insert(runtimes, { name = rt.name, path = path, default = rt.default })
        end
      end

      opts.settings = vim.tbl_deep_extend("force", opts.settings or {}, {
        java = {
          configuration = { runtimes = runtimes },
        },
      })

      return opts
    end,
  },
}
