local defaults = require("features.remote.defaults")

local M = {}

local STATE_FILE = defaults.recents_file
local setup_done = false

---@class RemoteProject
---@field host string
---@field remote_root string
---@field mount_path string
---@field lsp_mode? "remote"|"local"|"syntax"
---@field probe_ok? boolean
---@field git_enabled? boolean
---@field last_used integer

local state = {
  ---@type RemoteProject[]
  recents = {},
  active = {},
  ---@type RemoteProject|nil
  current = nil,
}

local function normalize_abs(path)
  if type(path) ~= "string" then
    return nil
  end

  path = vim.trim(path)
  if not path:match("^/") then
    return nil
  end

  path = path:gsub("/+", "/"):gsub("/$", "")
  if path == "" then
    path = "/"
  end

  return path
end

function M.project_key(host, remote_root)
  return host .. ":" .. remote_root
end

local function load_state()
  local file = io.open(STATE_FILE, "r")
  if not file then
    return
  end

  local raw = file:read("*a")
  file:close()

  local ok, decoded = pcall(vim.json.decode, raw)
  if not ok or type(decoded) ~= "table" then
    return
  end

  state.recents = {}
  for _, entry in ipairs(decoded.recents or {}) do
    if type(entry.host) == "string" and type(entry.remote_root) == "string" then
      local root = normalize_abs(entry.remote_root)
        or vim.trim(entry.remote_root)
      if root ~= "" then
        table.insert(state.recents, {
          host = entry.host,
          remote_root = root,
          mount_path = entry.mount_path,
          lsp_mode = entry.lsp_mode,
          probe_ok = entry.probe_ok,
          git_enabled = entry.git_enabled == true,
          last_used = entry.last_used or 0,
        })
      end
    end
  end
end

local function save_state()
  vim.fn.mkdir(vim.fn.fnamemodify(STATE_FILE, ":h"), "p")

  local file = io.open(STATE_FILE, "w")
  if not file then
    return
  end

  local recents = {}
  for _, entry in ipairs(state.recents) do
    table.insert(recents, {
      host = entry.host, remote_root = entry.remote_root, mount_path = entry.mount_path,
      git_enabled = entry.git_enabled, last_used = entry.last_used,
    })
  end
  file:write(vim.json.encode({ recents = recents }))
  file:close()
end

---@param host string
---@param remote_root string
---@param fields? table
---@return RemoteProject
function M.remember(host, remote_root, fields)
  remote_root = normalize_abs(remote_root) or remote_root
  local key = M.project_key(host, remote_root)
  local entry

  for i, existing in ipairs(state.recents) do
    if M.project_key(existing.host, existing.remote_root) == key then
      entry = existing
      table.remove(state.recents, i)
      break
    end
  end

  entry = entry or { host = host, remote_root = remote_root, git_enabled = defaults.git_default }
  for field, value in pairs(fields or {}) do entry[field] = value end

  entry.host = host
  entry.remote_root = remote_root
  entry.last_used = os.time()

  table.insert(state.recents, 1, entry)

  while #state.recents > defaults.recents_max do
    table.remove(state.recents)
  end

  save_state()
  return entry
end

function M.current()
  return M.project_for_path(vim.api.nvim_buf_get_name(0))
    or M.project_for_path(vim.fn.getcwd()) or state.current
end

function M.mount_path_for(host, remote_root)
  for _, entry in ipairs(state.recents) do
    if entry.host == host and entry.remote_root == remote_root and entry.mount_path then
      return entry.mount_path
    end
  end
  local label = host:gsub("[^%w._-]", "_")
  return vim.fs.joinpath(defaults.mount_base,
    label .. "_" .. vim.fn.sha256(M.project_key(host, remote_root)):sub(1, 16))
end

---@param path string
---@return RemoteProject|nil
function M.project_for_path(path)
  if not path or path == "" then
    return nil
  end

  path = vim.fs.normalize(path)

  local best
  for _, entry in pairs(state.active) do
    local mount = entry.mount_path
    if (path == mount or path:sub(1, #mount + 1) == mount .. "/")
      and (not best or #mount > #best.mount_path) then best = entry end
  end
  if best then return best end

  if state.current and state.current.mount_path then
    local mount = vim.fs.normalize(state.current.mount_path)
    if path == mount or path:sub(1, #mount + 1) == mount .. "/" then
      return state.current
    end
  end

  local base = vim.fs.normalize(defaults.mount_base)
  if path ~= base and path:sub(1, #base + 1) ~= base .. "/" then
    return nil
  end

  for _, entry in ipairs(state.recents) do
    if entry.mount_path then
      local mount = vim.fs.normalize(entry.mount_path)
      if path == mount or path:sub(1, #mount + 1) == mount .. "/" then
        return entry
      end
    end
  end

  return nil
end

function M.is_mount_path(path)
  return M.project_for_path(path) ~= nil
end

function M.is_mount_buffer(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  return M.is_mount_path(name)
end

function M.mount_root_for_path(path)
  local proj = M.project_for_path(path)
  if proj then
    return proj.mount_path
  end
end

function M.git_enabled_for_path(path)
  local proj = M.project_for_path(path)
  if not proj then
    return true
  end
  return proj.git_enabled == true
end

function M.should_disable_tree_git(path)
  local proj = M.project_for_path(path)
  if not proj then
    return false
  end
  return proj.git_enabled ~= true
end

---Display mapping only. Do not use FUSE uid=/gid= for access: sshfs
---already allows whatever the SSH user can do, and numeric UIDs differ
---on every campus host.
---@return table
function M.sshfs_identity()
  return { idmap = "user" }
end

---@param extra? table
---@return table
function M.sshfs_options(extra)
  return vim.tbl_extend(
    "force",
    {},
    defaults.sshfs_options,
    M.sshfs_identity(),
    extra or {}
  )
end

local function keep_editor_state_local(ev)
  local path = ev.match ~= "" and ev.match or vim.api.nvim_buf_get_name(ev.buf)
  if not M.is_mount_path(path) then
    return
  end

  -- Swap/undo next to the file uses FUSE write + kernel ownership checks.
  vim.bo[ev.buf].swapfile = false
  vim.bo[ev.buf].undofile = false
end

---OpenSSH client options. Pubkey and password/keyboard-interactive are both
---on; private keys are never copied to the remote.
---@param opts? { batch?: boolean, master?: "yes"|"auto", connect_timeout?: integer }
---@return string[]
function M.ssh_client_options(opts)
  opts = opts or {}
  local Config = require("sshfs.config")
  local options = {}

  if opts.master == "yes" then
    table.insert(options, "ControlMaster=yes")
  else
    table.insert(options, "ControlMaster=auto")
  end

  for _, opt in ipairs(Config.get_control_master_options()) do
    if not opt:match("^ControlMaster=") then
      table.insert(options, opt)
    end
  end

  table.insert(options, "PubkeyAuthentication=yes")
  table.insert(options, "PasswordAuthentication=yes")
  table.insert(options, "KbdInteractiveAuthentication=yes")
  table.insert(
    options,
    "PreferredAuthentications=publickey,keyboard-interactive,password"
  )
  table.insert(options, "NumberOfPasswordPrompts=3")
  table.insert(
    options,
    "ConnectTimeout=" .. tostring(opts.connect_timeout or 15)
  )

  table.insert(options, opts.batch and "BatchMode=yes" or "BatchMode=no")

  return options
end

function M.ssh_argv(host, extra, opts)
  opts = opts or {}
  local cmd = { "ssh" }

  for _, opt in ipairs(M.ssh_client_options({
    batch = opts.batch ~= false,
    master = opts.master,
    connect_timeout = opts.connect_timeout,
  })) do
    table.insert(cmd, "-o")
    table.insert(cmd, opt)
  end

  table.insert(cmd, host)

  if extra then
    vim.list_extend(cmd, extra)
  end

  return cmd
end

function M.drop_control_master(host)
  local ok, Ssh = pcall(require, "sshfs.lib.ssh")
  if ok then
    Ssh.cleanup_control_master(host)
  end
end

---@param host string
---@param remote_argv string[]
---@param timeout_ms? integer
---@param callback fun(ok: boolean, stdout: string, err: string|nil)
---@param opts? { drop_mux_on_timeout?: boolean }
function M.ssh_run(host, remote_argv, timeout_ms, callback, opts)
  opts = opts or {}
  local cmd = M.ssh_argv(host, remote_argv, { batch = true })

  vim.system(cmd, {
    text = true,
    timeout = timeout_ms or defaults.ssh_cmd_ms,
  }, function(obj)
    vim.schedule(function()
      local stdout = vim.trim(obj.stdout or "")
      local stderr = vim.trim(obj.stderr or "")

      if obj.code == 0 then
        callback(true, stdout, nil)
        return
      end

      if obj.signal then
        if opts.drop_mux_on_timeout then
          M.drop_control_master(host)
        end
        callback(false, stdout, "ssh timed out")
        return
      end

      callback(false, stdout, stderr ~= "" and stderr or "ssh failed")
    end)
  end)
end

---@param host string
---@param callback fun(success: boolean, exit_code: number)
local function open_auth_terminal(host, callback)
  vim.fn.mkdir(defaults.sockets_dir, "p", "0700")

  -- Real TTY password prompt. ControlPersist keeps the master after `exit`.
  -- Do not use ssh -N as a Neovim job: closing that window kills SSH.
  local cmd = { "ssh", "-tt" }
  for _, opt in ipairs(M.ssh_client_options({
    batch = false,
    master = "yes",
    connect_timeout = 20,
  })) do
    table.insert(cmd, "-o")
    table.insert(cmd, opt)
  end
  table.insert(cmd, host)
  table.insert(cmd, "exit")

  require("features.remote.ssh").auth_terminal(cmd, host, callback)
end

---@param host string
---@param callback fun(ok: boolean, err?: string)
function M.authenticate(host, callback)
  vim.notify("Checking SSH to " .. host .. "…", vim.log.levels.INFO)

  -- Fast path: key already loaded, or an existing ControlMaster.
  -- BatchMode cannot prompt for a password; that is the next step.
  M.ssh_run(host, { "true" }, defaults.ssh_probe_ms, function(ok)
    if ok then
      callback(true)
      return
    end

    vim.notify(
      "SSH needs a password or key passphrase for " .. host,
      vim.log.levels.INFO
    )

    open_auth_terminal(host, function(success)
      if not success then
        callback(false, "SSH authentication failed for " .. host)
        return
      end

      M.ssh_run(
        host,
        { "true" },
        defaults.ssh_probe_ms,
        function(ready)
          if ready then
            callback(true)
            return
          end
          callback(
            false,
            "SSH login succeeded but the shared connection is not ready"
          )
        end,
        { drop_mux_on_timeout = false }
      )
    end)
  end)
end

---Turn a typed path into an sshfs suffix with no extra SSH.
---`host:foo` is relative to remote home; `host:/foo` is absolute.
---Never pass `~` to sshfs.nvim — that plugin SSHes for $HOME and hangs
---on campus login shells.
---@param remote_path string
---@return string
local function to_sshfs_suffix(remote_path)
  remote_path = vim.trim(remote_path or "")

  if remote_path == "" or remote_path == "~" or remote_path == "." then
    return "."
  end

  if remote_path:sub(1, 2) == "~/" or remote_path:sub(1, 2) == "./" then
    local rest = remote_path:sub(3)
    if rest == "" then
      return "."
    end
    return rest
  end

  return remote_path
end

---@param mount_path string
---@return string|nil
local function mounted_remote_path(mount_path)
  local ok, MountPoint = pcall(require, "sshfs.lib.mount_point")
  if not ok then
    return nil
  end

  for _, conn in ipairs(MountPoint.list_active()) do
    if conn.mount_path == mount_path then
      local path = conn.remote_path
      if type(path) == "string" and path:match("^/") then
        return normalize_abs(path)
      end
    end
  end
end

---@param mount_path string
---@param timeout_ms integer
---@param callback fun(ok: boolean)
local function wait_until_mounted(mount_path, timeout_ms, callback)
  local started = vim.uv.now()
  local timer = vim.uv.new_timer()
  if not timer then
    callback(false)
    return
  end

  timer:start(0, 120, function()
    vim.schedule(function()
      local MountPoint = require("sshfs.lib.mount_point")
      if MountPoint.is_active(mount_path) and vim.uv.fs_stat(mount_path) then
        timer:stop()
        timer:close()
        callback(true)
        return
      end

      if vim.uv.now() - started > timeout_ms then
        timer:stop()
        timer:close()
        callback(false)
      end
    end)
  end)
end

local function apply_tree_root(mount_path, host, remote_root)
  vim.schedule(function()
    vim.api.nvim_set_current_dir(mount_path)

    local ok, api = pcall(require, "nvim-tree.api")
    if ok then
      pcall(api.tree.open)
      pcall(api.tree.change_root, mount_path)
    end

    vim.notify(
      string.format(
        "Remote project ready: %s:%s\nmount=%s",
        host,
        remote_root,
        mount_path
      ),
      vim.log.levels.INFO
    )
  end)
end

---@param extra? table
---@return string[]
local function sshfs_dash_o(extra)
  local options = {}
  local merged = M.sshfs_options(extra)
  for key, value in pairs(merged) do
    if value == true then
      table.insert(options, key)
    elseif value ~= false and value ~= nil then
      table.insert(options, string.format("%s=%s", key, tostring(value):gsub("[\\,]", "\\%0")))
    end
  end
  return options
end

---@param mount_path string
---@return boolean
local function mount_files_readable(mount_path)
  local function first_file(dir, depth)
    local req = vim.uv.fs_scandir(dir)
    if not req then
      return nil
    end
    local subdirs = {}
    while true do
      local name, kind = vim.uv.fs_scandir_next(req)
      if not name then
        break
      end
      local path = dir .. "/" .. name
      if kind == "file" or kind == "link" then
        return path
      end
      if kind == "directory" and depth > 0 then
        table.insert(subdirs, path)
      end
    end
    for _, sub in ipairs(subdirs) do
      local found = first_file(sub, depth - 1)
      if found then
        return found
      end
    end
  end

  local path = first_file(mount_path, 2) or mount_path
  local fd = vim.uv.fs_open(path, "r", 0)
  if not fd then
    return false
  end
  vim.uv.fs_close(fd)
  return true
end

local function unmount_path(mount_path)
  local ok, MountPoint = pcall(require, "sshfs.lib.mount_point")
  if ok then
    pcall(MountPoint.unmount, mount_path)
  end
end

---SSHFS keeps its own ssh child. A ControlMaster owned by the Neovim
---password window dies when that window closes, which makes every open fail.
---@param host string
---@param mount_point string
---@param remote_suffix string
---@param callback fun(ok: boolean, err?: string)
local function mount_in_terminal(host, mount_point, remote_suffix, callback)
  vim.fn.mkdir(defaults.sockets_dir, "p", "0700")

  local ssh = { "ssh", "-o", "ControlMaster=no", "-o", "ControlPath=none" }
  for _, option in ipairs(M.ssh_client_options({ batch = false })) do
    if not option:match("^Control") then vim.list_extend(ssh, { "-o", option }) end
  end
  local quoted = {}
  for _, arg in ipairs(ssh) do table.insert(quoted, vim.fn.shellescape(arg)) end
  local spec = host .. ":" .. remote_suffix
  local cmd = {
    "sshfs",
    spec,
    mount_point,
    "-o",
    table.concat(
      sshfs_dash_o({
        -- Independent of Neovim's ControlMaster. Sharing that socket is
        -- what made tree listings work while every :edit failed.
        ssh_command = table.concat(quoted, " "),
      }),
      ","
    ),
  }

  require("features.remote.ssh").auth_terminal(cmd, host, function(success)
    if not success then
      callback(false, "SSHFS authentication failed for " .. host)
      return
    end
    callback(true)
  end)
end

local function wait_for_readable_mount(mount_path, timeout_ms, callback)
  local started = vim.uv.now()
  wait_until_mounted(mount_path, timeout_ms, function(mounted)
    if not mounted then
      callback(false, "mount did not become visible")
      return
    end

    local function tick()
      if mount_files_readable(mount_path) then
        callback(true)
        return
      end
      if vim.uv.now() - started > timeout_ms then
        callback(false, "mounted but files are not readable")
        return
      end
      vim.defer_fn(tick, 150)
    end
    tick()
  end)
end

---@param host string
---@param remote_path string
---@param opts? { prompt_lsp?: boolean }
---@param callback? fun(proj?: RemoteProject, err?: string)
function M.open_project(host, remote_path, opts, callback)
  opts = opts or {}
  callback = callback or function() end
  if vim.fn.executable("sshfs") ~= 1 then
    local err = "sshfs is not installed locally. Install sshfs and fuse3; RemoteSSH works without them."
    vim.notify(err, vim.log.levels.ERROR)
    callback(nil, err)
    return
  end

  local remote_root = to_sshfs_suffix(remote_path)
  local mount_path = M.mount_path_for(host, remote_root)
  local MountPoint = require("sshfs.lib.mount_point")
  local Lockfile = require("sshfs.lib.lockfile")

  local function finish()
    local proj = M.remember(host, remote_root, {
      mount_path = mount_path,
    })
    state.current = proj
    state.active[mount_path] = proj
    apply_tree_root(mount_path, host, remote_root)
    M.authenticate(host, function(ok, err)
      if not ok then
        vim.notify(err, vim.log.levels.WARN)
        return
      end
      if remote_root:sub(1, 1) ~= "/" then
        M.ssh_run(host, { "cd " .. vim.fn.shellescape(remote_root) .. " && pwd -P" },
          defaults.ssh_cmd_ms, function(resolved, stdout)
            if resolved and stdout:sub(1, 1) == "/" then
              proj.remote_root = stdout
              save_state()
              require("features.remote.lsp").ensure(proj)
            else
              vim.notify("Cannot resolve remote root for LSP", vim.log.levels.WARN)
            end
          end)
      else
        require("features.remote.lsp").ensure(proj)
      end
    end)
    callback(proj)
  end

  local function fail(err)
    vim.notify("SSHFS mount failed: " .. tostring(err), vim.log.levels.ERROR)
    callback(nil, err)
  end

  local function after_sshfs(ok, err)
    if not ok then
      fail(err)
      return
    end

    wait_for_readable_mount(
      mount_path,
      defaults.mount_ready_ms,
      function(readable, read_err)
        if not readable then
          unmount_path(mount_path)
          fail(read_err)
          return
        end
        pcall(Lockfile.register, mount_path)
        remote_root = mounted_remote_path(mount_path) or remote_root
        finish()
      end
    )
  end

  local function mount_with_tty()
    vim.notify(
      "Mounting SSHFS " .. host .. ":" .. remote_root .. " (password in the float)…",
      vim.log.levels.INFO
    )
    if not MountPoint.get_or_create(mount_path) then
      fail("Failed to create mount directory: " .. mount_path)
      return
    end
    mount_in_terminal(host, mount_path, remote_root, after_sshfs)
  end

  if MountPoint.is_active(mount_path) then
    if mount_files_readable(mount_path) then
      remote_root = mounted_remote_path(mount_path) or remote_root
      vim.notify("Already mounted: " .. mount_path, vim.log.levels.INFO)
      finish()
      return
    end
    vim.notify("Stale SSHFS mount (unreadable); remounting", vim.log.levels.WARN)
    unmount_path(mount_path)
  end

  mount_with_tty()
end

function M.disconnect()
  local proj = M.current()
  if not proj then
    local ok, sshfs = pcall(require, "sshfs")
    if ok then
      sshfs.unmount()
    end
    return
  end

  local home = vim.fn.expand("~")
  pcall(vim.api.nvim_set_current_dir, home)
  local ok_tree, api = pcall(require, "nvim-tree.api")
  if ok_tree then
    pcall(api.tree.change_root, home)
  end

  local Session = require("sshfs.session")
  local disconnected = Session.disconnect_from({
    host = proj.host,
    mount_path = proj.mount_path,
  })

  if not disconnected then return end

  -- Other projects and tmux panes may still share this host's SSH master.
  require("features.remote.lsp").stop_for_project(proj)
  state.active[proj.mount_path] = nil
  proj._lsp_ready = false
  proj._servers = nil
  if state.current == proj then state.current = nil end
end

-- Every interactive shell uses the same authentication options as the LSP
-- master, with BatchMode=no so password, passphrase and MFA prompts can appear.
function M.open_ssh(host, remote_root)
  if not host then
    require("features.remote.ssh").pick_host(function(chosen) M.open_ssh(chosen) end)
    return
  end
  host = require("features.remote.ssh").destination(host)
  if not host then vim.notify("Invalid SSH destination", vim.log.levels.ERROR); return end
  local extra = remote_root and {
    "cd " .. vim.fn.shellescape(remote_root) .. ' && exec "$SHELL" -l',
  } or nil
  local cmd = M.ssh_argv(host, extra, { batch = false })
  table.insert(cmd, 2, "-tt")
  if vim.env.TMUX then
    local quoted = {}
    for _, arg in ipairs(cmd) do table.insert(quoted, vim.fn.shellescape(arg)) end
    vim.system({ "tmux", "split-window", "-h", table.concat(quoted, " ") }, { text = true }, function(result)
      if result.code ~= 0 then
        vim.schedule(function() vim.notify(result.stderr or "tmux SSH failed", vim.log.levels.ERROR) end)
      end
    end)
    return
  end
  vim.cmd("botright 12new")
  vim.fn.jobstart(cmd, { term = true })
  vim.cmd.startinsert()
end

function M.open_shell()
  local proj = M.current()
  M.open_ssh(proj and proj.host, proj and proj.remote_root)
end

function M.toggle_git()
  local proj = M.current()
  if not proj then
    vim.notify("No remote project is connected", vim.log.levels.WARN)
    return
  end

  proj.git_enabled = not proj.git_enabled
  M.remember(proj.host, proj.remote_root, {
    mount_path = proj.mount_path,
    lsp_mode = proj.lsp_mode,
    probe_ok = proj.probe_ok,
    git_enabled = proj.git_enabled,
  })

  local ok, api = pcall(require, "nvim-tree.api")
  if ok then
    pcall(api.tree.reload)
  end

  local gs_ok, gitsigns = pcall(require, "gitsigns")
  if gs_ok then
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      local name = vim.api.nvim_buf_get_name(bufnr)
      if M.project_for_path(name) == proj then
        if proj.git_enabled then
          pcall(gitsigns.attach, bufnr)
        else
          pcall(gitsigns.detach, bufnr)
        end
      end
    end
  end

  vim.notify(
    "Remote git " .. (proj.git_enabled and "enabled" or "disabled"),
    vim.log.levels.INFO
  )
end

function M.connect(host, path)
  if not host or host == "" then
    require("features.remote.ssh").pick_host(function(chosen) M.connect(chosen, path) end)
    return
  end
  host = require("features.remote.ssh").destination(host)
  if not host then vim.notify("Invalid SSH destination", vim.log.levels.ERROR); return end
  if path and path ~= "" then M.open_project(host, path); return end
  vim.ui.input({ prompt = "Remote path: ", default = "~" }, function(value)
    if value and vim.trim(value) ~= "" then M.open_project(host, value) end
  end)
end

local function connect_new() M.connect() end

function M.pick_project()
  local items = {}

  table.insert(items, {
    kind = "new",
    display = "+ Connect to new project",
  })

  for _, entry in ipairs(state.recents) do
    table.insert(items, {
      kind = "recent",
      entry = entry,
      display = string.format(
        "%s:%s%s",
        entry.host,
        entry.remote_root,
        entry.lsp_mode and ("  [" .. entry.lsp_mode .. "]") or ""
      ),
    })
  end

  local ok_tele, pickers = pcall(require, "telescope.pickers")
  if not ok_tele then
    local labels = {}
    for _, item in ipairs(items) do
      table.insert(labels, item.display)
    end
    vim.ui.select(labels, { prompt = "Remote project" }, function(_, idx)
      if not idx then
        return
      end
      local item = items[idx]
      if item.kind == "new" then
        connect_new()
      else
        M.open_project(
          item.entry.host,
          item.entry.remote_root,
          { prompt_lsp = false }
        )
      end
    end)
    return
  end

  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  pickers.new({}, {
    prompt_title = "Remote project",
    finder = finders.new_table({
      results = items,
      entry_maker = function(item)
        return {
          value = item,
          display = item.display,
          ordinal = item.display,
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if not selection then
          return
        end
        local item = selection.value
        if item.kind == "new" then
          connect_new()
        else
          M.open_project(
            item.entry.host,
            item.entry.remote_root,
            { prompt_lsp = false }
          )
        end
      end)
      return true
    end,
  }):find()
end

function M.setup()
  if setup_done then
    return
  end
  setup_done = true

  load_state()
  vim.fn.mkdir(defaults.mount_base, "p")
  vim.fn.mkdir(defaults.sockets_dir, "p", "0700")
  require("features.remote.lsp").setup()

  vim.opt.backupskip:append(defaults.mount_base .. "/*")
  vim.api.nvim_create_autocmd({ "BufNewFile", "BufReadPre" }, {
    group = vim.api.nvim_create_augroup("RemoteFsLocalState", { clear = true }),
    callback = keep_editor_state_local,
  })

  local hosts = function() return require("features.remote.ssh").hosts() end
  vim.api.nvim_create_user_command("RemoteProject", function(opts)
    if #opts.fargs == 0 then M.pick_project()
    elseif #opts.fargs <= 2 then M.connect(opts.fargs[1], opts.fargs[2])
    else vim.notify("Usage: RemoteProject [user@host [path]]", vim.log.levels.ERROR) end
  end, { nargs = "*", complete = hosts, desc = "Pick or directly connect to an SSH project" })

  vim.api.nvim_create_user_command("RemoteSSH", function(opts)
    M.open_ssh(opts.args ~= "" and opts.args or nil)
  end, { nargs = "?", complete = hosts, desc = "Open SSH without mounting a project" })

  vim.api.nvim_create_user_command("RemoteAuth", function(opts)
    local function authenticate(host)
      if not require("features.remote.ssh").destination(host) then
        vim.notify("Invalid SSH destination", vim.log.levels.ERROR)
        return
      end
      M.authenticate(host, function(ok, err)
        vim.notify(ok and ("SSH ready: " .. host) or err, ok and vim.log.levels.INFO or vim.log.levels.ERROR)
      end)
    end
    if opts.args ~= "" then authenticate(opts.args)
    else require("features.remote.ssh").pick_host(authenticate) end
  end, { nargs = "?", complete = hosts, desc = "Authenticate SSH interactively and share the connection" })

  vim.api.nvim_create_user_command("RemoteConfig", function(opts)
    require("features.remote.ssh").edit_config(opts.args)
  end, { nargs = "?", complete = hosts, desc = "Edit an SSH config or jump to a host alias" })

  vim.api.nvim_create_user_command("RemoteHostAdd", function()
    require("features.remote.ssh").add_host()
  end, { desc = "Prepare a new SSH host entry for editing and saving" })

  vim.api.nvim_create_user_command("RemoteDisconnect", function()
    M.disconnect()
  end, { desc = "Unmount the current remote project" })

  vim.api.nvim_create_user_command("RemoteShell", function()
    M.open_shell()
  end, { desc = "Open an SSH shell at the remote project" })

  vim.api.nvim_create_user_command("RemoteLspMode", function()
    local proj = M.current()
    if not proj then
      vim.notify("No remote project is connected", vim.log.levels.WARN)
      return
    end
    require("features.remote.lsp").ensure(proj, { prompt = true, force = true })
  end, { desc = "Retry remote discovery and fallback choices for this project" })

  vim.api.nvim_create_user_command("RemoteGitToggle", function()
    M.toggle_git()
  end, { desc = "Toggle git integration on the remote mount" })

  vim.keymap.set("n", defaults.keys.project, M.pick_project, {
    desc = "Remote project",
  })
  vim.keymap.set("n", defaults.keys.direct, function() M.open_ssh() end, { desc = "Direct SSH terminal" })
  vim.keymap.set("n", defaults.keys.config, function() require("features.remote.ssh").edit_config() end, { desc = "Edit SSH configuration" })
  vim.keymap.set("n", defaults.keys.add_host, function() require("features.remote.ssh").add_host() end, { desc = "Add SSH host" })
  vim.keymap.set("n", defaults.keys.disconnect, M.disconnect, {
    desc = "Remote disconnect",
  })
  vim.keymap.set("n", defaults.keys.shell, M.open_shell, {
    desc = "Remote shell",
  })
  vim.keymap.set("n", defaults.keys.lsp_mode, function()
    vim.cmd("RemoteLspMode")
  end, {
    desc = "Remote LSP mode",
  })
  vim.keymap.set("n", defaults.keys.git, M.toggle_git, {
    desc = "Remote git toggle",
  })
end

load_state()

return M
