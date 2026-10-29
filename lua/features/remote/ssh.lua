local M = {}

-- Discover aliases only; OpenSSH itself resolves options, Match and ProxyJump.
-- Include paths in user configuration are relative to ~/.ssh, per ssh_config.
function M.scan(files)
  local hosts, seen, visited, paths, entries = {}, {}, {}, {}, {}
  local function read(path, base)
    path = vim.fs.normalize(path)
    if visited[path] then return end
    visited[path] = true
    table.insert(paths, path)
    if vim.fn.filereadable(path) == 0 then return end
    local row = 0
    for line in io.lines(path) do
      row = row + 1
      local key, value = line:match("^%s*([%w]+)%s+(.+)")
      if key then
        key = key:lower()
        value = value:gsub("%s+#.*$", "")
        if key == "host" then
          for host in value:gmatch("%S+") do
            if not host:find("[*?!]") and not seen[host] then
              seen[host] = true
              table.insert(hosts, host)
              entries[host] = { path = path, line = row }
            end
          end
        elseif key == "include" then
          -- Quoted include filenames may contain spaces.
          for quoted in value:gmatch('("[^"]+")') do
            local pattern = vim.fn.expand(quoted:sub(2, -2))
            if pattern:sub(1, 1) ~= "/" then pattern = base .. "/" .. pattern end
            for _, child in ipairs(vim.fn.glob(pattern, false, true)) do read(child, base) end
          end
          value = value:gsub('"[^"]+"', '')
          for pattern in value:gmatch("%S+") do
            pattern = vim.fn.expand(pattern)
            if pattern:sub(1, 1) ~= "/" then pattern = base .. "/" .. pattern end
            for _, child in ipairs(vim.fn.glob(pattern, false, true)) do read(child, base) end
          end
        end
      end
    end
  end
  for _, path in ipairs(files or { vim.fn.expand("~/.ssh/config"), "/etc/ssh/ssh_config" }) do
    read(path, path:match("^/etc/") and "/etc/ssh" or vim.fn.expand("~/.ssh"))
  end
  table.sort(hosts)
  return { hosts = hosts, files = paths, entries = entries }
end

function M.hosts(files)
  return M.scan(files).hosts
end

-- Destination is an alias, hostname, or user@hostname, never an SSH option.
function M.destination(value)
  value = vim.trim(value or "")
  if value:sub(1, 1) == "-" then return nil end
  local user, host = value:match("^([^@]+)@([^@]+)$")
  host = host or value
  if user and not user:match("^[%w_.-]+$") then return nil end
  if host:sub(1, 1) == "-" then return nil end
  if not host:match("^[%w_.-]+$") and not host:match("^%[[%x:.]+%]$") then return nil end
  return value ~= "" and value or nil
end

function M.auth_terminal(cmd, host, callback)
  -- Scope TERM to this child instead of changing Neovim's environment while
  -- multiple authentication prompts can be open.
  if vim.env.TMUX or (vim.env.TERM or ""):match("^screen") then
    cmd = vim.list_extend({ "env", "TERM=xterm-256color" }, cmd)
  end
  require("sshfs.ui.terminal").open_auth_floating(cmd, host, callback)
end

function M.pick_host(callback)
  local items = { "+ Enter hostname or user@host", "+ Add SSH host configuration", "Edit SSH configuration" }
  vim.list_extend(items, M.hosts())
  vim.ui.select(items, { prompt = "SSH destination" }, function(choice, index)
    if not choice then return end
    if index == 1 then
      vim.ui.input({ prompt = "SSH hostname or user@host: " }, function(value)
        if value == nil then return end
        local host = M.destination(value)
        if host then callback(host)
        else vim.notify("Enter a hostname, alias, or user@host (set custom ports in SSH config)", vim.log.levels.ERROR) end
      end)
    elseif index == 2 then M.add_host()
    elseif index == 3 then M.edit_config()
    else callback(choice) end
  end)
end

local function open_config(path, line)
  path = vim.fs.normalize(vim.fn.expand(path))
  vim.fn.mkdir(vim.fs.dirname(path), "p", "0700")
  local new = vim.fn.filereadable(path) == 0
  vim.cmd.edit(vim.fn.fnameescape(path))
  vim.bo.filetype = "sshconfig"
  if line then vim.api.nvim_win_set_cursor(0, { line, 0 }) end
  if new then
    vim.api.nvim_create_autocmd("BufWritePost", {
      buffer = 0, once = true,
      callback = function() vim.fn.setfperm(path, "rw-------") end,
    })
  end
end

function M.edit_config(target)
  local config = M.scan()
  if target and target ~= "" then
    local entry = config.entries[target]
    if entry then open_config(entry.path, entry.line)
    elseif target:find("/", 1, true) or target:sub(1, 1) == "~" then open_config(target)
    else vim.notify("No SSH alias found: " .. target, vim.log.levels.WARN) end
    return
  end
  local files = {}
  for _, path in ipairs(config.files) do
    if path:sub(1, 5) ~= "/etc/" then table.insert(files, path) end
  end
  if #files == 1 then open_config(files[1]); return end
  vim.ui.select(files, { prompt = "Edit SSH configuration" }, function(path)
    if path then open_config(path) end
  end)
end

function M.host_entry(fields)
  assert(fields.alias:match("^[%w_.-]+$") and fields.alias:sub(1, 1) ~= "-", "Invalid SSH alias")
  assert(M.destination(fields.hostname) == fields.hostname and not fields.hostname:find("@", 1, true), "Invalid hostname")
  assert(fields.user == "" or fields.user:match("^[%w_.-]+$"), "Invalid SSH username")
  local port = tonumber(fields.port)
  assert(port and port % 1 == 0 and port >= 1 and port <= 65535, "Invalid port")
  assert(not fields.identity:find('[\r\n"]'), "Invalid identity file path")
  local lines = { "Host " .. fields.alias, "  HostName " .. fields.hostname }
  if fields.user ~= "" then table.insert(lines, "  User " .. fields.user) end
  table.insert(lines, "  Port " .. port)
  if fields.identity ~= "" then table.insert(lines, '  IdentityFile "' .. fields.identity .. '"') end
  -- Restore the original default context before existing global settings/Includes.
  vim.list_extend(lines, { "", "Host *", "" })
  return lines
end

function M.add_host()
  local fields = {}
  local prompts = {
    { "alias", "New SSH alias: ", "" },
    { "hostname", "Server hostname: ", "" },
    { "user", "Username (blank uses SSH default): ", "" },
    { "port", "SSH port: ", "22" },
    { "identity", "IdentityFile (blank for password/default keys): ", "" },
  }
  local function ask(index)
    local field = prompts[index]
    if field then
      vim.ui.input({ prompt = field[2], default = field[3] }, function(value)
        if value == nil then return end
        fields[field[1]] = vim.trim(value)
        ask(index + 1)
      end)
      return
    end
    local ok, lines = pcall(M.host_entry, fields)
    if not ok then vim.notify(tostring(lines), vim.log.levels.ERROR); return end
    if M.scan().entries[fields.alias] then
      vim.notify("SSH alias already exists; opening it for editing", vim.log.levels.INFO)
      M.edit_config(fields.alias)
      return
    end
    open_config(vim.fn.expand("~/.ssh/config"))
    for _, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
      local aliases = line:match("^%s*[Hh][Oo][Ss][Tt]%s+(.+)")
      if aliases then
        for alias in aliases:gmatch("%S+") do
          if alias == fields.alias then
            vim.notify("Alias already exists in this buffer", vim.log.levels.WARN)
            return
          end
        end
      end
    end
    vim.api.nvim_buf_set_lines(0, 0, 0, false, lines)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.notify("SSH entry prepared. Edit as needed, then :write to save; retry the picker after saving.")
  end
  ask(1)
end

return M
