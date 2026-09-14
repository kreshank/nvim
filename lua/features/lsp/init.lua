local lang = require("lang")
local project = require("features.project")

local M = {}

function M.mason_exe(name)
  local path = vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "bin", name)

  if vim.uv.fs_stat(path) then
    return path
  end

  return name
end

function M.local_servers()
  return lang.servers()
end

function M.project_servers()
  return lang.project_servers()
end

function M.logical_name(name)
  if not name or name == "" then
    return name
  end

  local remote = name:match("^remote_(.+)$")
  if remote then
    return remote
  end

  local syntax = name:match("^syntax_(.+)$")
  if syntax then
    return syntax
  end

  return name
end

function M.clangd_query_driver()
  local cpp = lang.get("cpp")
  return "--query-driver="
    .. table.concat(cpp.query_drivers, ",")
end

function M.ruff_init_options(resolved)
  return lang.get("python").ruff_init_options(resolved)
end

function M.local_root_dir(bufnr, on_dir)
  local remote = require("features.remote")

  if remote.is_mount_buffer(bufnr) then
    return
  end

  on_dir(project.find_root(bufnr))
end

local function masonify_cmd(cmd)
  if type(cmd) ~= "table" or not cmd[1] then
    return cmd
  end

  local out = vim.deepcopy(cmd)
  out[1] = M.mason_exe(out[1])
  return out
end

function M.configure()
  for _, mod in ipairs(lang.all()) do
    for server, spec in pairs(mod.lsp or {}) do
      local cfg = vim.deepcopy(spec)
      local query_driver = cfg.query_driver
      cfg.query_driver = nil

      if cfg.cmd then
        cfg.cmd = masonify_cmd(cfg.cmd)
        if query_driver then
          table.insert(cfg.cmd, M.clangd_query_driver())
        end
      end

      cfg.root_dir = M.local_root_dir
      vim.lsp.config(server, cfg)
    end
  end
end

function M.enable_local()
  vim.lsp.enable(lang.servers())
end

function M.setup_mason()
  require("mason").setup()

  local registry = require("mason-registry")

  registry.refresh(function()
    for _, name in ipairs(lang.mason_tools()) do
      local package = registry.get_package(name)

      if package and not package:is_installed() then
        package:install()
      end
    end
  end)
end

function M.setup()
  require("mason-lspconfig").setup({
    automatic_enable = false,
    ensure_installed = lang.servers(),
  })

  M.configure()
  M.enable_local()

  vim.api.nvim_create_user_command("LspLog", function()
    local path = vim.lsp.log.get_filename()

    vim.cmd(
      "edit " .. vim.fn.fnameescape(path)
    )
  end, {
    desc = "Open Neovim LSP log",
  })
end

return M
