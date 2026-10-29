local defaults = require("features.remote.defaults")
local remote = require("features.remote")
local lang = require("lang")
local M = {}

-- Commands and filetypes come from the same registry as local LSPs. A language
-- may supply remote_lsp[server] when its remote command/settings need overrides.
local function spec_for(server, mod)
  local cfg = vim.deepcopy(vim.lsp.config[server] or {})
  local spec = vim.tbl_deep_extend("force", {}, cfg, (mod.lsp or {})[server] or {})
  return spec
end

local function servers_for(bufnr)
  local mod = lang.for_filetype(vim.bo[bufnr].filetype)
  return mod and mod.servers or {}, mod
end

function M.stop_for_project(proj)
  for _, client in ipairs(vim.lsp.get_clients()) do
    if client.config and client.config.root_dir == proj.mount_path then
      client:stop(true)
    end
  end
end

local function attach_project(proj)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf)
      and remote.project_for_path(vim.api.nvim_buf_get_name(buf)) == proj then
      M.attach_buffer(buf)
    end
  end
end

local function start(proj, server, mod, bufnr, mode, binary)
  local cfg = spec_for(server, mod)
  local cmd = cfg.cmd
  if type(cmd) ~= "table" or not cmd[1] then
    vim.notify("Remote LSP needs an argv command for " .. server, vim.log.levels.WARN)
    return
  end
  cfg.name = mode == "remote" and "remote_" .. server or server
  cfg.root_dir = proj.mount_path
  cfg.root_markers, cfg.query_driver = nil, nil
  cfg.capabilities = cfg.capabilities or vim.lsp.protocol.make_client_capabilities()
  cfg.capabilities.workspace = cfg.capabilities.workspace or {}
  cfg.capabilities.workspace.didChangeWatchedFiles = { dynamicRegistration = false }

  if mode == "remote" then
    -- Host callbacks/settings can contain local SDKs, runtimes and Python paths.
    -- Keep upstream attach handlers (e.g. texlab commands), but let remote project
    -- configuration win. Language-specific remote overrides stay in /lang.
    cfg.before_init, cfg.on_init, cfg.cmd_env, cfg.cmd_cwd = nil, nil, nil, nil
    cfg.settings, cfg.init_options = nil, nil
    local override = (mod.remote_lsp or {})[server] or {}
    cfg = vim.tbl_deep_extend("force", cfg, override)
    cmd = vim.deepcopy(override.cmd or cmd)
    cmd[1] = binary
    local quoted = {}
    for _, arg in ipairs(cmd) do
      table.insert(quoted, vim.fn.shellescape(arg))
    end
    local command = "cd " .. vim.fn.shellescape(proj.remote_root)
      .. " && exec " .. table.concat(quoted, " ")
    local ssh = remote.ssh_argv(proj.host, { command })
    cfg.cmd = {
      require("config.defaults").python_host, defaults.path_proxy,
      "--local-root", proj.mount_path, "--remote-root", proj.remote_root, "--",
    }
    vim.list_extend(cfg.cmd, ssh)
  else
    cfg.cmd = vim.deepcopy(cmd)
    cfg.cmd[1] = require("features.lsp").mason_exe(cmd[1])
    if vim.fn.executable(cfg.cmd[1]) ~= 1 then
      vim.notify("Local server unavailable: " .. cmd[1], vim.log.levels.WARN)
      return
    end
  end
  vim.lsp.start(cfg, { bufnr = bufnr })
end

local function probe(proj, server, mod, callback)
  local cfg = spec_for(server, mod)
  local cmd = ((mod.remote_lsp or {})[server] or {}).cmd or cfg.cmd
  if type(cmd) ~= "table" or not cmd[1] then
    callback(nil)
    return
  end
  local executable = vim.fs.basename(cmd[1])
  -- OpenSSH joins remote arguments with spaces: send one quoted shell command.
  -- The same login environment is used for discovery and server startup.
  remote.ssh_run(proj.host, {
    "cd " .. vim.fn.shellescape(proj.remote_root)
      .. " && command -v " .. vim.fn.shellescape(executable),
  }, defaults.ssh_probe_ms, function(ok, stdout)
    local path = ok and stdout:match("(/[^\r\n]+)%s*$") or nil
    callback(path)
  end)
end

function M.attach_buffer(bufnr)
  if not vim.api.nvim_buf_is_loaded(bufnr) or vim.bo[bufnr].buftype ~= "" then
    return
  end
  local proj = remote.project_for_path(vim.api.nvim_buf_get_name(bufnr))
  if not proj or not proj._lsp_ready then return end
  local servers, mod = servers_for(bufnr)
  proj._servers = proj._servers or {}
  for _, server in ipairs(servers) do
    local entry = proj._servers[server]
    if entry then
      if entry.mode == "remote" or entry.mode == "local" then
        start(proj, server, mod, bufnr, entry.mode, entry.binary)
      end
    else
      proj._servers[server] = { mode = "pending" }
      local generation = proj._servers
      probe(proj, server, mod, function(binary)
        if not proj._lsp_ready or proj._servers ~= generation then return end
        if binary then
          proj._servers[server] = { mode = "remote", binary = binary }
          attach_project(proj)
          return
        end
        vim.ui.select({ "Use local " .. server, "Skip " .. server }, {
          prompt = server .. " unavailable over SSH on " .. proj.host
            .. "; local fallback may lack remote libraries",
        }, function(_, index)
          if not proj._lsp_ready or proj._servers ~= generation then return end
          proj._servers[server] = { mode = index == 1 and "local" or "skip" }
          attach_project(proj)
        end)
      end)
    end
  end
end

function M.ensure(proj, opts)
  opts = opts or {}
  if opts.force then
    M.stop_for_project(proj)
    proj._servers = {}
  end
  proj._lsp_ready = true
  proj.lsp_mode = "auto"
  attach_project(proj)
end

function M.setup()
  vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile", "FileType", "BufEnter" }, {
    group = vim.api.nvim_create_augroup("RemoteLsp", { clear = true }),
    callback = function(ev) M.attach_buffer(ev.buf) end,
  })
end

return M
