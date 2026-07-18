local defaults = require("config.defaults")

local M = {}

-- Capture the directory from which Neovim was launched.
-- This remains unchanged if :cd or :lcd is used later.
local launch_directory =
  vim.fs.normalize(vim.fn.getcwd())

---Return the directory where Neovim was launched.
---@return string
function M.launch_directory()
  return launch_directory
end

---Search upward from a buffer for a project marker.
---
---If no marker is found within the configured number of parent directories,
---return the directory where Neovim was launched.
---@param bufnr integer
---@param max_depth? integer
---@return string
function M.find_root(bufnr, max_depth)
  max_depth =
    max_depth
    or defaults.project.root_search_depth

  local filename =
    vim.api.nvim_buf_get_name(bufnr)

  local current

  if filename ~= "" then
    filename = vim.fs.normalize(filename)
    current = vim.fs.dirname(filename)
  else
    current = launch_directory
  end

  for _ = 0, max_depth do
    for _, marker in ipairs(defaults.project.markers) do
      local marker_path =
        vim.fs.joinpath(current, marker)

      if vim.uv.fs_stat(marker_path) then
        return current
      end
    end

    local parent = vim.fs.dirname(current)

    if not parent or parent == current then
      break
    end

    current = parent
  end

  return launch_directory
end

---Search downward for compile_commands.json.
---
---The supplied root is depth 0. Its subdirectories are searched through
---the configured maximum depth.
---
---Returns the directory containing compile_commands.json, rather than the
---path to the file itself.
---@param root string
---@param max_depth? integer
---@return string?
function M.find_compile_commands(root, max_depth)
  if not root or root == "" then
    return nil
  end

  max_depth =
    max_depth
    or defaults.project.compile_commands_search_depth

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
            and not defaults.project.ignored_directories[name]
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

---Return the flags clangd should use when no compilation command applies.
---@return string[]
function M.cpp_fallback_flags()
  local standard =
    vim.g.cpp_std
    or defaults.cpp.standard

  local flags = {
    "-xc++",
    "-std=" .. standard,
  }

  vim.list_extend(
    flags,
    defaults.cpp.warnings
  )

  return flags
end

return M
