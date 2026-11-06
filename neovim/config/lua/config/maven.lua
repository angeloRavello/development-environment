-- Go-to-definition inside Maven poms: `gd` (or `gf`) on
--   - <module>core</module>         -> core/pom.xml
--   - anywhere inside <parent>      -> the parent pom (relativePath, default ../pom.xml)
--   - anywhere inside <dependency>  -> that artifact's pom: the reactor module's
--     <plugin>, <extension>             pom.xml if it's part of this build, else the
--                                       downloaded .pom in ~/.m2/repository
-- <C-o> jumps back. Outside those elements, gd/gf behave as usual.
--
-- No XML language server is involved - jdtls only handles .java buffers -
-- so this is plain text matching over the pom, which is enough for the
-- regular way poms are written (one element per line, standard section
-- order). ${property} versions are resolved from <properties> of the pom
-- and its parents on disk; when a version can't be resolved (managed by a
-- BOM / <dependencyManagement>), every version present in ~/.m2 is offered.

local M = {}

local skip_dirs = { target = true, build = true, out = true, bin = true, node_modules = true }

local function read(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local text = f:read("*a")
  f:close()
  return text
end

local function tag(xml, name)
  return xml and xml:match("<" .. name .. ">%s*(.-)%s*</" .. name .. ">")
end

local function exists(path)
  return path and vim.uv.fs_stat(path) ~= nil
end

-- Coordinates, parent and <properties> of one pom. `text` lets the current
-- buffer be parsed with its unsaved edits.
local function pom_info(path, text)
  text = text or read(path)
  if not text then
    return nil
  end
  local xml = text:gsub("<!%-%-.-%-%->", "")
  local info = { path = path, properties = {} }

  local parent = xml:match("<parent>(.-)</parent>")
  -- The project's own groupId/artifactId/version are the ones before the
  -- first big section (dependencies, build, ...), not nested inside one.
  local rest = xml:gsub("<parent>.-</parent>", "", 1)
  local cut = #rest
  for _, section in ipairs({
    "<properties>",
    "<dependencyManagement>",
    "<dependencies>",
    "<build>",
    "<profiles>",
    "<modules>",
    "<reporting>",
    "<repositories>",
  }) do
    local i = rest:find(section, 1, true)
    if i and i < cut then
      cut = i
    end
  end
  local header = rest:sub(1, cut)
  info.groupId = tag(header, "groupId")
  info.artifactId = tag(header, "artifactId")
  info.version = tag(header, "version")

  if parent then
    info.parent = {
      groupId = tag(parent, "groupId"),
      artifactId = tag(parent, "artifactId"),
      version = tag(parent, "version"),
      relativePath = tag(parent, "relativePath"),
    }
    -- An empty <relativePath/> means "never look on disk, only the repo".
    if parent:find("<relativePath%s*/>") then
      info.parent.relativePath = ""
    end
    info.groupId = info.groupId or info.parent.groupId
    info.version = info.version or info.parent.version
  end

  local props = xml:match("<properties>(.-)</properties>")
  if props then
    for k, v in props:gmatch("<([%w%._%-]+)>%s*(.-)%s*</%1>") do
      info.properties[k] = v
    end
  end
  return info
end

local function parent_pom(info)
  local rel = info.parent and info.parent.relativePath
  if not info.parent or rel == "" then
    return nil
  end
  local path = vim.fn.simplify(vim.fs.joinpath(vim.fs.dirname(info.path), rel or "../pom.xml"))
  if vim.fn.isdirectory(path) == 1 then
    path = vim.fs.joinpath(path, "pom.xml")
  end
  local parent = exists(path) and pom_info(path)
  if parent and parent.artifactId == info.parent.artifactId then
    return parent
  end
end

-- Expands ${...} using the pom's own coordinates and the <properties> of the
-- pom and its on-disk parents. Returns nil if anything stays unresolved.
local function resolve(value, info)
  if not value then
    return nil
  end
  local chain, cur = {}, info
  while cur and #chain < 10 do
    table.insert(chain, cur)
    cur = parent_pom(cur)
  end
  local builtins = {
    ["project.version"] = info.version,
    ["pom.version"] = info.version,
    ["project.groupId"] = info.groupId,
    ["project.artifactId"] = info.artifactId,
    ["project.parent.version"] = info.parent and info.parent.version,
    ["project.parent.groupId"] = info.parent and info.parent.groupId,
  }
  for _ = 1, 5 do
    if not value:find("${", 1, true) then
      return value
    end
    value = value:gsub("%${([^}]+)}", function(name)
      if builtins[name] then
        return builtins[name]
      end
      for _, pom in ipairs(chain) do
        if pom.properties[name] then
          return pom.properties[name]
        end
      end
    end)
  end
  return not value:find("${", 1, true) and value or nil
end

-- Top of the multi-module build: highest ancestor folder that still has a pom.xml.
local function reactor_root(pom_path)
  local dir = vim.fs.dirname(pom_path)
  while true do
    local up = vim.fs.dirname(dir)
    if up == dir or not exists(vim.fs.joinpath(up, "pom.xml")) then
      return dir
    end
    dir = up
  end
end

local function find_in_reactor(pom_path, group, artifact)
  local root = reactor_root(pom_path)
  for name, type in
    vim.fs.dir(root, {
      depth = 8,
      skip = function(dir)
        local base = vim.fs.basename(dir)
        return not (skip_dirs[base] or base:sub(1, 1) == ".")
      end,
    })
  do
    if type == "file" and vim.fs.basename(name) == "pom.xml" then
      local path = vim.fs.joinpath(root, name)
      local pom = pom_info(path)
      if pom and pom.artifactId == artifact and (not group or pom.groupId == group) then
        return path
      end
    end
  end
end

-- Candidate .pom files in the local repository: the exact version if known
-- and downloaded, else every downloaded version (newest first).
local function find_in_m2(group, artifact, version)
  if not group then
    return {}
  end
  local parts = { vim.uv.os_homedir(), ".m2", "repository" }
  vim.list_extend(parts, vim.split(group, ".", { plain = true }))
  table.insert(parts, artifact)
  local dir = vim.fs.joinpath(unpack(parts))

  local function pom_for(v)
    local p = vim.fs.joinpath(dir, v, artifact .. "-" .. v .. ".pom")
    return exists(p) and p or nil
  end
  if version and pom_for(version) then
    return { pom_for(version) }
  end
  local found = {}
  if vim.fn.isdirectory(dir) == 1 then
    for v, type in vim.fs.dir(dir) do
      if type == "directory" and pom_for(v) then
        table.insert(found, pom_for(v))
      end
    end
  end
  local function ver(p)
    return vim.version.parse(vim.fs.basename(vim.fs.dirname(p)), { strict = false })
  end
  table.sort(found, function(a, b)
    local va, vb = ver(a), ver(b)
    if va and vb and va ~= vb then
      return va > vb
    end
    return a > b
  end)
  return found
end

-- What's under the cursor: a <module> line, or the <parent>/<dependency>/
-- <plugin>/<extension> element enclosing it (nested blocks stripped out).
local function cursor_context(lines, row)
  local module = lines[row]:match("<module>%s*(.-)%s*</module>")
  if module then
    return { kind = "module", value = module }
  end
  local kinds = { "dependency", "parent", "plugin", "extension" }
  for i = row, math.max(1, row - 50), -1 do
    for _, kind in ipairs(kinds) do
      if lines[i]:find("<" .. kind .. ">", 1, true) then
        local block = {}
        for j = i, math.min(#lines, i + 80) do
          table.insert(block, lines[j])
          if lines[j]:find("</" .. kind .. ">", 1, true) then
            if j < row then
              return nil
            end
            local text = table.concat(block, "\n")
            for _, nested in ipairs({ "exclusions", "dependencies", "executions", "configuration" }) do
              text = text:gsub("<" .. nested .. ">.-</" .. nested .. ">", "")
            end
            return { kind = kind, block = text }
          end
        end
        return nil
      end
      -- Passed the end of a sibling element: the cursor isn't inside one.
      if i ~= row and lines[i]:find("</" .. kind .. ">", 1, true) then
        return nil
      end
    end
  end
end

local function open(path)
  vim.cmd.edit(vim.fn.fnameescape(path))
end

local function warn(msg)
  vim.notify(msg, vim.log.levels.WARN, { title = "Maven" })
end

-- Returns false when the cursor isn't on anything Maven-navigable.
function M.goto_definition()
  local buf = vim.api.nvim_get_current_buf()
  local pom_path = vim.fs.normalize(vim.api.nvim_buf_get_name(buf))
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local ctx = cursor_context(lines, vim.api.nvim_win_get_cursor(0)[1])
  if not ctx then
    return false
  end

  if ctx.kind == "module" then
    local path = vim.fn.simplify(vim.fs.joinpath(vim.fs.dirname(pom_path), ctx.value))
    if vim.fn.isdirectory(path) == 1 then
      path = vim.fs.joinpath(path, "pom.xml")
    end
    if exists(path) then
      open(path)
    else
      warn("Module pom not found: " .. path)
    end
    return true
  end

  local info = pom_info(pom_path, table.concat(lines, "\n"))
  if ctx.kind == "parent" then
    local parent = parent_pom(info)
    if parent then
      open(parent.path)
      return true
    end
  end

  local group = resolve(tag(ctx.block, "groupId"), info)
  if not group and ctx.kind == "plugin" then
    group = "org.apache.maven.plugins"
  end
  local artifact = resolve(tag(ctx.block, "artifactId"), info)
  local version = resolve(tag(ctx.block, "version"), info)
  if not artifact then
    warn("No <artifactId> in this <" .. ctx.kind .. ">")
    return true
  end

  local local_pom = find_in_reactor(pom_path, group, artifact)
  if local_pom then
    open(local_pom)
    return true
  end

  local candidates = find_in_m2(group, artifact, version)
  local gav = (group or "?") .. ":" .. artifact .. ":" .. (version or "?")
  if #candidates == 0 then
    warn(gav .. " is not in this build nor in ~/.m2 - build the project (mvn -q dependency:resolve) to download it")
  elseif #candidates == 1 then
    open(candidates[1])
  else
    vim.ui.select(candidates, {
      prompt = gav .. " - version not resolvable here, pick one from ~/.m2",
      format_item = function(p)
        return vim.fs.basename(vim.fs.dirname(p))
      end,
    }, function(choice)
      if choice then
        open(choice)
      end
    end)
  end
  return true
end

local function map(buf)
  for _, key in ipairs({ "gd", "gf" }) do
    vim.keymap.set("n", key, function()
      if M.goto_definition() then
        return
      end
      if key == "gd" and #vim.lsp.get_clients({ bufnr = buf, method = "textDocument/definition" }) > 0 then
        vim.lsp.buf.definition()
      else
        local ok, err = pcall(vim.cmd, "normal! " .. key)
        if not ok then
          vim.notify(err, vim.log.levels.ERROR)
        end
      end
    end, { buffer = buf, desc = "Maven: go to module / parent / dependency pom" })
  end
end

local function is_pom(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  return vim.fs.basename(name) == "pom.xml" or name:match("%.pom$") ~= nil
end

function M.setup()
  -- Poms downloaded into ~/.m2 are named <artifact>-<version>.pom, which
  -- Neovim doesn't recognize as XML on its own.
  vim.filetype.add({ extension = { pom = "xml" } })

  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("maven_pom_navigation", { clear = true }),
    pattern = "xml",
    callback = function(ev)
      if is_pom(ev.buf) then
        map(ev.buf)
      end
    end,
  })
  -- This runs on VeryLazy, so a pom passed on the command line (`nvim
  -- pom.xml`) already had its FileType event - map it now.
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == "xml" and is_pom(buf) then
      map(buf)
    end
  end
end

return M
