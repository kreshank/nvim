local defaults = require("config.defaults")
local project = require("config.project")
local lsp = require("config.lsp")
local remote = require("config.remote")

local M = {}

local FILETYPE_SERVERS = {
  c = { "clangd" },
  cpp = { "clangd" },
  objc = { "clangd" },
  objcpp = { "clangd" },
  python = { "pyright", "ruff" },
  java = { "jdtls" },
  rust = { "rust_analyzer" },
}

local SYNTAX_SERVERS = {
  clangd = true,
  pyright = true,
  ruff = true,
}

local PROBE_COMMANDS = {
  clangd = { "clangd" },
  pyright = { "pyright-langserver", "pyright" },
  ruff = { "ruff" },
  rust_analyzer = { "rust-analyzer", "rust_analyzer" },
  jdtls = { "jdtls" },
}

local function no_watch_capabilities()
  local caps = vim.lsp.protocol.make_client_capabilities()
  caps.workspace = caps.workspace or {}
  caps.workspace.didChangeWatchedFiles = {
    dynamicRegistration = false,
    relativePatternSupport = false,
  }
  return caps
end

local function disable_watchers(client)
  if not client.server_capabilities then
    return
  end
  client.server_capabilities.workspace =
    client.server_capabilities.workspace or {}
  client.server_capabilities.workspace.didChangeWatchedFiles = {
    dynamicRegistration = false,
  }
end

local function client_name(mode, server)
  if mode == "remote" then
    return "remote_" .. server
  end
  if mode == "syntax" then
    return "syntax_" .. server
  end
  return server
end

function M.stop_for_project(proj)
  local names = {}
  for _, server in ipairs(lsp.project_servers) do
    table.insert(names, "remote_" .. server)
    table.insert(names, "syntax_" .. server)
  end

  local get_clients = vim.lsp.get_clients
  for _, client in ipairs(get_clients()) do
    for _, name in ipairs(names) do
      if client.name == name then
        client.stop(true)
      end
    end
    if client.config and client.config.root_dir == proj.mount_path then
      if vim.tbl_contains(lsp.project_servers, lsp.logical_name(client.name)) then
        client.stop(true)
      end
    end
  end
end

---@param host string
---@param callback fun(found: table<string, string>)
function M.probe(host, callback)
  local script = [[
for c in clangd pyright-langserver pyright ruff rust-analyzer rust_analyzer jdtls; do
  p=$(command -v "$c" 2>/dev/null) || continue
  printf '%s=%s\n' "$c" "$p"
done
]]

  remote.ssh_run(host, {
    "bash",
    "-lc",
    script,
  }, defaults.remote.ssh_cmd_ms, function(ok, stdout)
    local found = {}
    if ok then
      for line in stdout:gmatch("[^\r\n]+") do
        local cmd, path = line:match("^([^=]+)=(.+)$")
        if cmd and path then
          found[cmd] = path
        end
      end
    end
    callback(found)
  end)
end

local function resolve_bin(found, server)
  for _, name in ipairs(PROBE_COMMANDS[server] or { server }) do
    if found[name] then
      return found[name], name
    end
  end
end

local function proxy_cmd(proj, remote_cmd)
  local cmd = {
    defaults.neovim.python_host,
    defaults.remote.path_proxy,
    "--local-root",
    proj.mount_path,
    "--remote-root",
    proj.remote_root,
    "--",
  }
  vim.list_extend(cmd, remote_cmd)
  return cmd
end

local function remote_server_cmd(proj, server, bin)
  local ssh = remote.ssh_argv(proj.host, nil, { batch = true })

  if server == "clangd" then
    vim.list_extend(ssh, {
      bin,
      "--background-index",
      "--clang-tidy",
      "--fallback-style=Google",
      "--path-mappings="
        .. proj.mount_path
        .. "="
        .. proj.remote_root,
    })
    return ssh
  end

  if server == "pyright" then
    vim.list_extend(ssh, { bin, "--stdio" })
    return proxy_cmd(proj, ssh)
  end

  if server == "ruff" then
    vim.list_extend(ssh, { bin, "server" })
    return proxy_cmd(proj, ssh)
  end

  if server == "rust_analyzer" then
    vim.list_extend(ssh, { bin })
    return proxy_cmd(proj, ssh)
  end

  if server == "jdtls" then
    vim.list_extend(ssh, { bin })
    return proxy_cmd(proj, ssh)
  end

  vim.list_extend(ssh, { bin })
  return proxy_cmd(proj, ssh)
end

local function local_syntax_config(server, root)
  if server == "clangd" then
    return {
      cmd = {
        "clangd",
        "--background-index=false",
        "--clang-tidy=false",
        "--fallback-style=Google",
        lsp.clangd_query_driver(),
      },
      root_dir = root,
      init_options = {
        fallbackFlags = project.cpp_fallback_flags(),
      },
    }
  end

  if server == "pyright" then
    return {
      cmd = { "pyright-langserver", "--stdio" },
      root_dir = root,
      settings = {
        python = {
          analysis = {
            pythonVersion = defaults.python.analysis_version,
            typeCheckingMode = "off",
            diagnosticMode = "openFilesOnly",
            useLibraryCodeForTypes = false,
          },
        },
      },
    }
  end

  if server == "ruff" then
    return {
      cmd = { "ruff", "server" },
      root_dir = root,
      init_options = lsp.ruff_init_options(),
    }
  end
end

local function start_client(proj, mode, server, found, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local name = client_name(mode, server)
  local root = proj.mount_path

  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
    if client.name == name then
      return
    end
  end

  local config = {
    name = name,
    root_dir = root,
    capabilities = no_watch_capabilities(),
    on_init = disable_watchers,
  }

  if mode == "remote" then
    local bin = select(1, resolve_bin(found, server))
    if not bin then
      return
    end
    config.cmd = remote_server_cmd(proj, server, bin)
    if server == "clangd" then
      config.init_options = {
        fallbackFlags = project.cpp_fallback_flags(),
      }
    elseif server == "ruff" then
      config.init_options = lsp.ruff_init_options()
    elseif server == "pyright" then
      config.settings = {
        python = {
          analysis = {
            pythonVersion = defaults.python.analysis_version,
            typeCheckingMode = defaults.python.type_checking_mode,
          },
        },
      }
    end
  elseif mode == "syntax" then
    if not SYNTAX_SERVERS[server] then
      return
    end
    config = vim.tbl_extend("force", config, local_syntax_config(server, root))
  else
    if server == "clangd" then
      config.cmd = {
        "clangd",
        "--background-index",
        "--clang-tidy",
        "--fallback-style=Google",
        lsp.clangd_query_driver(),
      }
      config.init_options = {
        fallbackFlags = project.cpp_fallback_flags(),
      }
      config.before_init = function(params, cfg)
        local compile_commands_dir =
          project.find_compile_commands(cfg.root_dir)
        if compile_commands_dir then
          params.initializationOptions =
            params.initializationOptions or {}
          params.initializationOptions.compilationDatabasePath =
            compile_commands_dir
        end
      end
    elseif server == "ruff" then
      config.cmd = { "ruff", "server" }
      config.init_options = lsp.ruff_init_options()
    elseif server == "pyright" then
      config.cmd = { "pyright-langserver", "--stdio" }
      config.settings = {
        python = {
          analysis = {
            pythonVersion = defaults.python.analysis_version,
            typeCheckingMode = defaults.python.type_checking_mode,
          },
        },
      }
    elseif server == "rust_analyzer" then
      config.cmd = { "rust-analyzer" }
    elseif server == "jdtls" then
      config.cmd = { "jdtls" }
    end
  end

  vim.lsp.start(config, { bufnr = bufnr })
end

local function servers_for_buf(bufnr)
  local ft = vim.bo[bufnr].filetype
  return FILETYPE_SERVERS[ft] or {}
end

function M.attach_buffer(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  if vim.bo[bufnr].buftype ~= "" then
    return
  end

  local name = vim.api.nvim_buf_get_name(bufnr)
  local proj = remote.project_for_path(name)
  if not proj or not proj.lsp_mode then
    return
  end

  local found = proj._probe_found or {}
  for _, server in ipairs(servers_for_buf(bufnr)) do
    start_client(proj, proj.lsp_mode, server, found, bufnr)
  end
end

local function apply_mode(proj, mode, found)
  proj.lsp_mode = mode
  proj.probe_ok = next(found) ~= nil
  proj._probe_found = found

  remote.remember(proj.host, proj.remote_root, {
    mount_path = proj.mount_path,
    lsp_mode = mode,
    probe_ok = proj.probe_ok,
    git_enabled = proj.git_enabled,
  })

  M.stop_for_project(proj)

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if remote.project_for_path(vim.api.nvim_buf_get_name(bufnr)) then
      M.attach_buffer(bufnr)
    end
  end

  vim.notify(
    "Remote LSP mode: " .. mode,
    vim.log.levels.INFO
  )
end

local function prompt_mode(proj, found, callback)
  local available = {}
  for server, _ in pairs(PROBE_COMMANDS) do
    if resolve_bin(found, server) then
      table.insert(available, server)
    end
  end
  table.sort(available)

  local options = {}
  if #available > 0 then
    table.insert(options, {
      id = "remote",
      label = "Remote LSP (" .. table.concat(available, ", ") .. ")",
    })
  end

  table.insert(options, {
    id = "local",
    label = "Local LSP (Mason; toolchain/paths may be wrong)",
  })
  table.insert(options, {
    id = "syntax",
    label = "Syntax / stdlib only (no project packages)",
  })

  vim.ui.select(options, {
    prompt = "LSP for " .. proj.host .. ":" .. proj.remote_root,
    format_item = function(item)
      return item.label
    end,
  }, function(choice)
    if not choice then
      callback(nil)
      return
    end
    callback(choice.id)
  end)
end

---@param proj table
---@param opts? { prompt?: boolean, force?: boolean }
function M.ensure(proj, opts)
  opts = opts or {}

  M.probe(proj.host, function(found)
    local probe_ok = next(found) ~= nil
    local should_prompt = opts.force
      or opts.prompt
      or not proj.lsp_mode
      or (proj.lsp_mode == "remote" and not probe_ok)

    if should_prompt then
      prompt_mode(proj, found, function(mode)
        if not mode then
          return
        end
        apply_mode(proj, mode, found)
      end)
      return
    end

    apply_mode(proj, proj.lsp_mode, found)
  end)
end

function M.setup()
  vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile", "FileType" }, {
    group = vim.api.nvim_create_augroup("RemoteLsp", { clear = true }),
    callback = function(ev)
      M.attach_buffer(ev.buf)
    end,
  })
end

return M
