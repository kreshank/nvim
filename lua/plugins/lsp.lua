local defaults = require("config.defaults")
local project = require("config.project")

local clangd_query_driver = "--query-driver="
  .. table.concat(defaults.cpp.query_drivers, ",")

return {
  {
    "williamboman/mason.nvim",
    opts = {},
  },

  {
    "williamboman/mason-lspconfig.nvim",
    dependencies = {
      "williamboman/mason.nvim",
    },

    opts = {
      ensure_installed = {
        "clangd",
        "pyright",
        "rust_analyzer",
        "lua_ls",
      },
    },
  },

  {
    "neovim/nvim-lspconfig",
    dependencies = {
      "williamboman/mason-lspconfig.nvim",
    },

    config = function()
      vim.lsp.config("clangd", {
        cmd = {
          "clangd",
          "--background-index",
          "--clang-tidy",
          "--log=verbose",
          "--fallback-style=Google",
          clangd_query_driver,
        },

        root_dir = function(bufnr, on_dir)
          on_dir(project.find_root(bufnr))
        end,

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
        settings = {
          python = {
            analysis = {
              pythonVersion =
              defaults.python.analysis_version,

              typeCheckingMode =
              defaults.python.type_checking_mode,
            },
          },
        },
      })

      vim.lsp.config("rust_analyzer", {})

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

      vim.lsp.enable({
        "clangd",
        "pyright",
        "rust_analyzer",
        "lua_ls",
      })
    end,
  },
}
