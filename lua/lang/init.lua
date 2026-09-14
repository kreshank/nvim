local defaults = require("lang.defaults")

local M = {}

local by_id = {}
local by_ft = {}
local modules = {}
local store_cache

local function register(mod)
  if type(mod) ~= "table" then
    return
  end

  if mod.id then
    by_id[mod.id] = mod
    table.insert(modules, mod)

    for _, ft in ipairs(mod.filetypes or {}) do
      by_ft[ft] = mod
    end

    return
  end

  for _, child in ipairs(mod) do
    register(child)
  end
end

register(require("lang.c"))
register(require("lang.python"))
register(require("lang.java"))
register(require("lang.rust"))
register(require("lang.lua"))
register(require("lang.tex"))

local function state_path()
  return M._state_path or defaults.persist_file
end

local function load_store()
  if store_cache then
    return store_cache
  end

  local file = io.open(state_path(), "r")

  if not file then
    store_cache = {}
    return store_cache
  end

  local raw = file:read("*a")
  file:close()

  local ok, decoded = pcall(vim.json.decode, raw)

  if ok and type(decoded) == "table" then
    store_cache = decoded
  else
    store_cache = {}
  end

  return store_cache
end

local function save_store()
  local path = state_path()
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")

  local file = io.open(path, "w")

  if not file then
    return
  end

  file:write(vim.json.encode(load_store()))
  file:close()
end

function M.all()
  return modules
end

function M.markers()
  local seen = {}
  local list = {}

  for _, mod in ipairs(modules) do
    for _, marker in ipairs(mod.markers or {}) do
      if not seen[marker] then
        seen[marker] = true
        table.insert(list, marker)
      end
    end
  end

  return list
end

function M.markers_for(filetype)
  if not filetype or filetype == "" then
    return {}
  end

  local mod = by_ft[filetype]

  if not mod then
    return {}
  end

  return vim.deepcopy(mod.markers or {})
end

function M.servers()
  local seen = {}
  local list = {}

  for _, mod in ipairs(modules) do
    for _, name in ipairs(mod.servers or {}) do
      if not seen[name] then
        seen[name] = true
        table.insert(list, name)
      end
    end
  end

  return list
end

function M.project_servers()
  local seen = {}
  local list = {}

  for _, mod in ipairs(modules) do
    if mod.remote ~= false then
      for _, name in ipairs(mod.servers or {}) do
        if not seen[name] then
          seen[name] = true
          table.insert(list, name)
        end
      end
    end
  end

  return list
end

function M.mason_tools()
  local seen = {}
  local list = {}

  for _, mod in ipairs(modules) do
    for _, name in ipairs(mod.mason_tools or {}) do
      if not seen[name] then
        seen[name] = true
        table.insert(list, name)
      end
    end
  end

  return list
end

function M.get(id)
  return by_id[id]
end

function M.for_filetype(filetype)
  return by_ft[filetype]
end

function M.formatter_for(filetype)
  local mod = by_ft[filetype]

  if mod and mod.formatter then
    return mod.formatter
  end

  return nil
end

function M.store_key(root)
  root = vim.fs.normalize(root)
  local ok, remote = pcall(require, "features.remote")

  if ok then
    local proj = remote.project_for_path(root)

    if proj then
      return "remote:" .. remote.project_key(proj.host, proj.remote_root)
    end
  end

  return "local:" .. root
end

local function override_for(root, lang_id)
  local entry = load_store()[M.store_key(root)]

  if not entry or not entry.versions then
    return nil
  end

  return entry.versions[lang_id]
end

function M.set_override(root, lang_id, version)
  local store = load_store()
  local key = M.store_key(root)

  store[key] = store[key] or { versions = {}, hints = {} }
  store[key].versions = store[key].versions or {}
  store[key].hints = store[key].hints or {}
  store[key].versions[lang_id] = version
  save_store()
end

function M.clear_override(root, lang_id)
  local store = load_store()
  local key = M.store_key(root)
  local entry = store[key]

  if not entry or not entry.versions then
    return
  end

  entry.versions[lang_id] = nil
  save_store()
end

function M.valid_version(mod, version)
  for _, item in ipairs(mod.versions or {}) do
    if item == version then
      return true
    end
  end

  if mod.id == "cpp" then
    return version:match("^c%+%+%w+$") ~= nil
      or version:match("^gnu%+%+%w+$") ~= nil
  end

  if mod.id == "c" then
    return version:match("^c%d+") ~= nil
      or version:match("^gnu%d+") ~= nil
  end

  if mod.id == "python" then
    return version:match("^%d+%.%d+") ~= nil
  end

  if mod.id == "java" then
    return version:match("^%d+$") ~= nil
  end

  if mod.id == "rust" then
    return version ~= ""
  end

  return false
end

function M.resolve(bufnr, opts)
  opts = opts or {}
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local filetype = opts.filetype

  if not filetype or filetype == "" then
    filetype = vim.bo[bufnr].filetype
  end

  local mod = M.for_filetype(filetype)

  if not mod or mod.versioned == false then
    return {
      version = "",
      source = "none",
      lang = nil,
    }
  end

  local root = opts.root

  if not root or root == "" then
    root = require("features.project").find_root(bufnr)
  end

  local detected = mod.detect(root, bufnr) or {}

  detected.lang = mod.id
  detected.version = detected.version or mod.default_version
  detected.source = detected.source or "default"

  local override = override_for(root, mod.id)

  if override then
    detected.version = override
    detected.source = "override"
  end

  return detected
end

function M.restart_servers(mod)
  local lsp = require("features.lsp")
  local wanted = {}

  for _, name in ipairs(mod.servers or {}) do
    wanted[name] = true
  end

  for _, client in ipairs(vim.lsp.get_clients()) do
    if wanted[lsp.logical_name(client.name)] then
      client:stop(true)
    end
  end

  vim.defer_fn(function()
    for _, name in ipairs(mod.servers or {}) do
      pcall(vim.cmd, "lsp restart " .. name)
    end
  end, 50)
end

function M.complete(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local mod = M.for_filetype(vim.bo[bufnr].filetype)

  if not mod or mod.versioned == false then
    return {}
  end

  return vim.deepcopy(mod.versions)
end

function M.report(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local filetype = vim.bo[bufnr].filetype
  local resolved = M.resolve(bufnr)

  if not resolved.lang then
    vim.notify(
      "No versioned language for filetype " .. filetype,
      vim.log.levels.INFO
    )
    return
  end

  local mod = M.get(resolved.lang)
  local lines = {
    "Language: " .. resolved.lang,
    "Version: " .. resolved.version,
    "Source: " .. resolved.source,
    "Formatter: " .. (mod.formatter or "not configured"),
    "Alternatives: " .. table.concat(mod.versions, ", "),
  }

  if resolved.interpreter then
    table.insert(lines, "Interpreter: " .. resolved.interpreter)
  end

  if resolved.compile_db then
    table.insert(lines, "Compile DB: " .. resolved.compile_db)
  end

  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

function M.command(opts)
  local bufnr = vim.api.nvim_get_current_buf()
  local filetype = vim.bo[bufnr].filetype
  local mod = M.for_filetype(filetype)

  if not mod or mod.versioned == false then
    vim.notify(
      "No versioned language for filetype " .. filetype,
      vim.log.levels.INFO
    )
    return
  end

  local root = require("features.project").find_root(bufnr)

  if opts.bang or opts.args == "clear" then
    M.clear_override(root, mod.id)
    M.restart_servers(mod)
    vim.notify(
      "Cleared " .. mod.id .. " version override",
      vim.log.levels.INFO
    )
    M.report(bufnr)
    return
  end

  if opts.args == "" then
    M.report(bufnr)
    return
  end

  if not M.valid_version(mod, opts.args) then
    vim.notify(
      "Invalid " .. mod.id .. " version: " .. opts.args,
      vim.log.levels.ERROR
    )
    return
  end

  local before = M.resolve(bufnr)
  M.set_override(root, mod.id, opts.args)
  M.restart_servers(mod)

  local lines = {
    "Set " .. mod.id .. " version to " .. opts.args,
  }

  if before.compile_db then
    table.insert(
      lines,
      "compile_commands.json still wins for files in the database"
    )
  end

  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

function M.setup()
  vim.api.nvim_create_user_command("LangVersion", function(opts)
    M.command(opts)
  end, {
    nargs = "?",
    bang = true,
    complete = function()
      return M.complete()
    end,
    desc = "Show or set the language version for this buffer",
  })
end

return M
