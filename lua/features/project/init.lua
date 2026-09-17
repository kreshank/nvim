local defaults = require("features.project.defaults")

local M = {}

local launch_directory =
  vim.fs.normalize(vim.fn.getcwd())

function M.launch_directory()
  return launch_directory
end

local function lang_mod_for_buf(bufnr)
  local ok, lang = pcall(require, "lang")

  if not ok then
    return nil
  end

  local ft = ""

  if bufnr then
    local ft_ok, value = pcall(function()
      return vim.bo[bufnr].filetype
    end)

    if ft_ok then
      ft = value or ""
    end
  end

  return lang.for_filetype(ft)
end

local function markers_for_buf(bufnr)
  local list = vim.deepcopy(defaults.base_markers)
  local mod = lang_mod_for_buf(bufnr)

  if mod then
    vim.list_extend(list, mod.markers or {})
  end

  return list, mod
end

function M.find_root(bufnr, max_depth)
  max_depth =
    max_depth
    or defaults.root_search_depth

  local filename =
    vim.api.nvim_buf_get_name(bufnr)

  local current
  local mount_root

  if filename ~= "" then
    filename = vim.fs.normalize(filename)
    current = vim.fs.dirname(filename)
    local ok, remote = pcall(require, "features.remote")
    if ok then
      mount_root = remote.mount_root_for_path(filename)
    end
  else
    current = launch_directory
  end

  local marker_list, mod = markers_for_buf(bufnr)

  for _ = 0, max_depth do
    if mount_root and current == mount_root then
      return mount_root
    end

    for _, marker in ipairs(marker_list) do
      local marker_path =
        vim.fs.joinpath(current, marker)

      if vim.uv.fs_stat(marker_path) then
        return current
      end
    end

    if mod then
      if type(mod.resolve_root) == "function" then
        local found = mod.resolve_root(current)

        if found then
          return found
        end
      elseif
        type(mod.is_project_root) == "function"
        and mod.is_project_root(current)
      then
        return current
      end
    end

    local parent = vim.fs.dirname(current)

    if not parent or parent == current then
      break
    end

    if mount_root and #parent < #mount_root then
      break
    end

    current = parent
  end

  return mount_root or launch_directory
end

function M.find_compile_commands(root, max_depth)
  if not root or root == "" then
    return nil
  end

  max_depth =
    max_depth
    or defaults.compile_commands_search_depth

  root = vim.fs.normalize(root)

  local queue = {
    {
      path = root,
      depth = 0,
    },
  }

  local head = 1

  while head <= #queue do
    local current = queue[head]
    head = head + 1

    local database_path =
      vim.fs.joinpath(
        current.path,
        "compile_commands.json"
      )

    local database_stat =
      vim.uv.fs_stat(database_path)

    if
      database_stat
      and database_stat.type == "file"
    then
      return current.path
    end

    if current.depth < max_depth then
      local scanner =
        vim.uv.fs_scandir(current.path)

      if scanner then
        while true do
          local name, entry_type =
            vim.uv.fs_scandir_next(scanner)

          if not name then
            break
          end

          if
            entry_type == "directory"
            and not defaults.ignored_directories[name]
          then
            queue[#queue + 1] = {
              path = vim.fs.joinpath(
                current.path,
                name
              ),
              depth = current.depth + 1,
            }
          end
        end
      end
    end
  end

  return nil
end

function M.cpp_fallback_flags()
  local cpp = require("lang").get("cpp")
  local flags = {
    "-std=" .. cpp.default_version,
  }

  vim.list_extend(
    flags,
    cpp.warnings
  )

  return flags
end

---Fallback flags for clangd using lang.resolve (project std and :LangVersion).
---@param bufnr integer?
---@param root string?
---@return string[]
function M.clangd_fallback_flags(bufnr, root)
  bufnr = bufnr or 0
  local ft = ""

  if type(bufnr) == "number" then
    local ok, value = pcall(function()
      return vim.bo[bufnr].filetype
    end)

    if ok then
      ft = value or ""
    end
  end

  local lang = require("lang")
  local kind = lang.get("c").clangd_kind_from_ft(ft)
  local resolved = lang.resolve(bufnr, {
    root = root,
    filetype = kind,
  })
  local mod = lang.get(resolved.lang or kind)
  local flags = {
    "-std=" .. (resolved.version or mod.default_version),
  }

  vim.list_extend(flags, mod.warnings)
  return flags
end

return M
