-- Java + Maven support, on top of LazyVim's own Java extra
-- (https://www.lazyvim.org/extras/lang/java, imported from config/lazy.lua).
-- That extra already:
--   - attaches jdtls (Eclipse JDT Language Server) with LSP/completion/
--     refactoring, Mason-installs java-debug-adapter + java-test (only when
--     nvim-dap is present - hence the dap.core extra in config/lazy.lua), and
--     sets up treesitter for Java syntax.
--   - passes Mason's bundled lombok.jar to jdtls as a -javaagent, so Lombok
--     works with no extra setup.
--   - picks the project root by looking for mvnw/gradlew/.git before the
--     nearest pom.xml, so a multi-module build gets ONE jdtls for the whole
--     reactor instead of one per module.
--
-- Annotation processors (MapStruct, Lombok's mapstruct binding, Hibernate
-- metamodel, ...) run inside jdtls through its bundled m2e-apt, using
-- whatever maven-compiler-plugin <annotationProcessorPaths> the pom declares.
--
-- What this file adds on top:
--   - Every installed JDK registered as a jdtls runtime, so each project
--     compiles against the JDK its pom asks for.
--   - jdtls itself always runs on a known JDK (mise's Temurin 25) with a
--     bounded heap, instead of whatever `java` is first on PATH.
--   - Workspace data dirs that can't collide between two projects whose
--     root folders share a name (common across microservice repos).
--   - IDE-style settings: auto-reimport on pom changes, library sources and
--     decompiled classes for navigation, test-friendly static imports.

-- Max heap for jdtls. 1G is enough for a single service or a mid-size
-- multi-module build; raise it (e.g. JDTLS_XMX=2G) for a large monorepo.
local jdtls_xmx = vim.env.JDTLS_XMX or "1G"

-- JDK that runs jdtls itself (it needs 21+). Independent from the JDKs a
-- project compiles against - those are the runtimes below.
local launcher_jdk = "temurin-25"

-- Resolves each Temurin install's real path via `mise where` instead of
-- hardcoding one - mise's install folder names embed the full patch version
-- (e.g. "temurin-21.0.12+101.0.LTS"), which changes every time mise upgrades
-- that version, so a hardcoded path would silently go stale.
local function mise_java_home(version)
  local handle = io.popen("mise where java@" .. version .. " 2>" .. (vim.fn.has("win32") == 1 and "NUL" or "/dev/null"))
  if not handle then
    return nil
  end
  local path = handle:read("*l")
  handle:close()
  if path == nil or path == "" then
    return nil
  end
  return path
end

return {
  {
    "mfussenegger/nvim-jdtls",
    opts = function(_, opts)
      -- name must match Eclipse JDT's execution-environment names -
      -- JavaSE-1.8 for 8, JavaSE-<N> for everything since 9.
      local runtime_versions = {
        { name = "JavaSE-1.8", mise = "temurin-8" },
        { name = "JavaSE-11", mise = "temurin-11" },
        { name = "JavaSE-17", mise = "temurin-17" },
        { name = "JavaSE-21", mise = "temurin-21" },
        { name = "JavaSE-25", mise = "temurin-25", default = true }, -- matches java/install.ps1's mise global default
      }

      local homes = {}
      local runtimes = {}
      for _, rt in ipairs(runtime_versions) do
        local path = mise_java_home(rt.mise)
        if path then
          homes[rt.mise] = path
          table.insert(runtimes, { name = rt.name, path = path, default = rt.default })
        end
      end

      -- JVM flags are vscode-java's defaults (tuned for an interactive
      -- language server, not throughput), with -Xms lowered from the
      -- launcher's hardcoded 1G - later flags win, and --jvm-arg values are
      -- appended after the launcher's own.
      vim.list_extend(opts.cmd, {
        "--jvm-arg=-Xms256m",
        "--jvm-arg=-Xmx" .. jdtls_xmx,
        "--jvm-arg=-XX:+UseParallelGC",
        "--jvm-arg=-XX:GCTimeRatio=4",
        "--jvm-arg=-XX:AdaptiveSizePolicyWeight=90",
        "--jvm-arg=-Dsun.zip.disableMemoryMapping=true",
      })
      if homes[launcher_jdk] then
        local exe = vim.fn.has("win32") == 1 and "java.exe" or "java"
        table.insert(opts.cmd, "--java-executable=" .. vim.fs.joinpath(homes[launcher_jdk], "bin", exe))
      end

      -- Folder name + short hash of the full root path: two projects both
      -- rooted at a folder named "api" would otherwise share (and corrupt)
      -- one jdtls workspace.
      opts.project_name = function(root_dir)
        return root_dir and (vim.fs.basename(root_dir) .. "-" .. vim.fn.sha256(root_dir):sub(1, 8))
      end

      opts.settings = vim.tbl_deep_extend("force", opts.settings or {}, {
        java = {
          configuration = {
            runtimes = runtimes,
            -- Re-import the project as soon as a pom.xml changes (new
            -- dependency, new annotation processor) instead of prompting.
            updateBuildConfiguration = "automatic",
          },
          -- One build at a time: keeps CPU/RAM flat on small machines and
          -- when several services are open.
          maxConcurrentBuilds = 1,
          -- Library sources: javadoc on hover and real code on go-to-definition.
          maven = { downloadSources = true },
          eclipse = { downloadSources = true },
          -- Fall back to decompiling when a library ships no sources jar.
          contentProvider = { preferred = "fernflower" },
          references = { includeDecompiledSources = true },
          signatureHelp = { enabled = true, description = { enabled = true } },
          compile = { nullAnalysis = { mode = "automatic" } },
          sources = {
            -- Never collapse imports into a wildcard.
            organizeImports = { starThreshold = 9999, staticStarThreshold = 9999 },
          },
          completion = {
            -- Offered as static-import completions without typing the class.
            favoriteStaticMembers = {
              "org.junit.jupiter.api.Assertions.*",
              "org.junit.jupiter.api.Assumptions.*",
              "org.assertj.core.api.Assertions.*",
              "org.mockito.Mockito.*",
              "org.mockito.ArgumentMatchers.*",
              "org.hamcrest.Matchers.*",
              "org.hamcrest.MatcherAssert.assertThat",
              "io.restassured.RestAssured.*",
              "org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*",
              "org.springframework.test.web.servlet.result.MockMvcResultMatchers.*",
              "java.util.Objects.requireNonNull",
              "java.util.Objects.requireNonNullElse",
            },
            -- JDK-internal and AWT types that otherwise crowd completion
            -- and auto-import (java.awt.List vs java.util.List).
            filteredTypes = { "com.sun.*", "sun.*", "jdk.*", "java.awt.*", "io.micrometer.shaded.*" },
          },
          codeGeneration = {
            useBlocks = true,
            hashCodeEquals = { useJava7Objects = true },
          },
        },
      })

      return opts
    end,
  },
}
