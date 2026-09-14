local defaults = require("lang.defaults")

local M = {}

---Read a file under root, capped so detect stays cheap.
---@param root string
---@param name string
---@return string?
function M.read_root_file(root, name)
  if not root or root == "" or not name then
    return nil
  end

  local path = vim.fs.joinpath(root, name)
  local stat = vim.uv.fs_stat(path)

  if not stat or stat.type ~= "file" then
    return nil
  end

  local fd = vim.uv.fs_open(path, "r", 438)

  if not fd then
    return nil
  end

  local data = vim.uv.fs_read(
    fd,
    math.min(stat.size, defaults.max_file_bytes),
    0
  )

  vim.uv.fs_close(fd)

  if type(data) ~= "string" or data == "" then
    return nil
  end

  return data
end

---@param root string
---@param name string
---@return boolean
function M.file_exists(root, name)
  if not root or root == "" then
    return false
  end

  local stat = vim.uv.fs_stat(vim.fs.joinpath(root, name))

  return stat ~= nil
end

---Optional mise lookup. No-op if mise is missing or the root has no mise files.
---@param root string
---@param tool string
---@return string?
function M.mise_which(root, tool)
  if vim.fn.executable("mise") ~= 1 then
    return nil
  end

  local has_mise = M.file_exists(root, "mise.toml")
    or M.file_exists(root, ".mise.toml")
    or M.file_exists(root, ".tool-versions")

  if not has_mise then
    return nil
  end

  local result = vim.system(
    { "mise", "which", tool },
    { cwd = root, text = true, timeout = 1000 }
  ):wait()

  if result.code ~= 0 then
    return nil
  end

  local path = vim.trim(result.stdout or "")

  if path == "" then
    return nil
  end

  return path
end

---Parse a version from a mise install path such as
---`~/.local/share/mise/installs/python/3.11.9/bin/python`.
---@param path string?
---@param tool string?
---@return string?
function M.mise_install_version(path, tool)
  if not path or path == "" or not tool or tool == "" then
    return nil
  end

  local ver = path:match(
    "/installs/" .. vim.pesc(tool) .. "/([^/]+)/"
  )

  if ver and ver:match("%d") then
    return ver
  end

  return nil
end

---@param text string
---@return string?
function M.cpp_std_from_text(text)
  return text:match("%-std=(gnu%+%+%w+)")
    or text:match("%-std=(c%+%+%w+)")
end

---@param text string
---@return string?
function M.c_std_from_text(text)
  return text:match("%-std=(gnu%d+%w*)")
    or text:match("%-std=(c%d+%w*)")
end

return M
