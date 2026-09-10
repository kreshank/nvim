local defaults = require("config.defaults")
local project = require("config.project")

local M = {}

local ruff_defaults = defaults.python.ruff

local clangd_query_driver = "--query-driver="
  .. table.concat(defaults.cpp.query_drivers, ",")

M.local_servers = {
  "clangd",
  "pyright",
  "ruff",
  "jdtls",
  "rust_analyzer",
  "lua_ls",
  "texlab",
  "ltex_plus",
}

M.project_servers = {
  "clangd",
  "pyright",
  "ruff",
  "jdtls",
  "rust_analyzer",
}

---Map a client name to the logical server used by format preferences.
---@param name string
---@return string
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
  return clangd_query_driver
end

function M.ruff_init_options()
  return {
    settings = {
      configurationPreference = "editorOnly",
      lineLength = ruff_defaults.line_length,
      lint = {
        select = ruff_defaults.lint.select,
        ignore = ruff_defaults.lint.ignore,
      },
      configuration = {
        ["target-version"] = ruff_defaults.target_version,
        ["indent-width"] = ruff_defaults.indent_width,
        format = {
          ["quote-style"] = ruff_defaults.format.quote_style,
          ["indent-style"] = ruff_defaults.format.indent_style,
          ["line-ending"] = ruff_defaults.format.line_ending,
          ["docstring-code-format"] =
            ruff_defaults.format.docstring_code_format,
          ["skip-magic-trailing-comma"] =
            ruff_defaults.format.skip_magic_trailing_comma,
        },
      },
    },
  }
end

---Skip Mason auto-start on SSHFS mounts; remote_lsp owns those buffers.
---@param bufnr integer
---@param on_dir fun(dir: string)
function M.local_root_dir(bufnr, on_dir)
  local remote = require("config.remote")

  if remote.is_mount_buffer(bufnr) then
    return
  end

  on_dir(project.find_root(bufnr))
end

function M.configure()
  vim.lsp.config("clangd", {
    cmd = {
      "clangd",
      "--background-index",
      "--clang-tidy",
      "--fallback-style=Google",
      clangd_query_driver,
    },

    root_dir = M.local_root_dir,

    init_options = {
      fallbackFlags = project.cpp_fallback_flags(),
    },

    before_init = function(params, config)
      local compile_commands_dir =
        project.find_compile_commands(config.root_dir)

      if compile_commands_dir then
        params.initializationOptions =
          params.initializationOptions or {}

        params.initializationOptions.compilationDatabasePath =
          compile_commands_dir
      end
    end,
  })

  vim.lsp.config("pyright", {
    root_dir = M.local_root_dir,
    settings = {
      python = {
        analysis = {
          pythonVersion = defaults.python.analysis_version,
          typeCheckingMode = defaults.python.type_checking_mode,
        },
      },
    },
  })

  vim.lsp.config("ruff", {
    cmd = {
      "ruff",
      "server",
    },
    root_dir = M.local_root_dir,
    init_options = M.ruff_init_options(),
  })

  vim.lsp.config("jdtls", {
    root_dir = M.local_root_dir,
  })

  vim.lsp.config("rust_analyzer", {
    root_dir = M.local_root_dir,
  })

  vim.lsp.config("lua_ls", {
    settings = {
      Lua = {
        diagnostics = {
          globals = {
            "vim",
          },
        },
        workspace = {
          library = {
            vim.env.VIMRUNTIME,
          },
        },
      },
    },
  })

  vim.lsp.config("texlab", {
    settings = {
      texlab = {
        build = {
          onSave = true,
          forwardSearchAfter = true,
        },
        forwardSearch = {
          executable = "zathura",
          args = {
            "--synctex-forward",
            "%l:1:%f",
            "%p",
          },
        },
        chktex = {
          onOpenAndSave = true,
          onEdit = false,
        },
      },
    },
  })

  vim.lsp.config("ltex_plus", {
    filetypes = {
      "tex",
      "plaintex",
      "bib",
    },
    settings = {
      ltex = {
        language = "en-US",
        checkFrequency = "save",
      },
    },
  })
end

function M.enable_local()
  vim.lsp.enable(M.local_servers)
end

return M
