local defaults = require("config.defaults")
local ruff_defaults = defaults.python.ruff
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
        "ruff",
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

        init_options = {
          settings = {
            -- Ignore project ruff.toml/pyproject.toml settings and always use
            -- the settings from this Neovim configuration.
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
                ["quote-style"] =
                    ruff_defaults.format.quote_style,

                ["indent-style"] =
                    ruff_defaults.format.indent_style,

                ["line-ending"] =
                    ruff_defaults.format.line_ending,

                ["docstring-code-format"] =
                    ruff_defaults.format.docstring_code_format,

                ["skip-magic-trailing-comma"] =
                    ruff_defaults.format.skip_magic_trailing_comma,
              },
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
