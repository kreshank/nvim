local defaults = require("config.defaults")
local project = require("config.project")

local M = {}

local ruff_defaults = defaults.python.ruff

local clangd_query_driver = "--query-driver="

    .. table.concat(defaults.cpp.query_drivers, ",")

-- Local/host LSP configuration.
--
-- These settings are specifically for this machine.
M.local_servers = {
  clangd = {
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
  },


  pyright = {
    settings = {

      python = {
        analysis = {
          pythonVersion = defaults.python.analysis_version,
          typeCheckingMode = defaults.python.type_checking_mode,
        },
      },
    },
  },

  ruff = {
    cmd = {
      "ruff",
      "server",
    },

    init_options = {
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

  },

  jdtls = {},

  rust_analyzer = {},

  lua_ls = {
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
  },
}

M.enabled_local_servers = {

  "clangd",

  "pyright",
  "rust_analyzer",
  "lua_ls",
}

-- Which remote language server should handle each filetype.
M.remote_filetype_to_server = {
  c = "clangd",
  cpp = "clangd",
  objc = "clangd",
  objcpp = "clangd",

  python = "pyright",

  rust = "rust_analyzer",
  lua = "lua_ls",
}

-- Remote configuration is intentionally minimal.
--
-- Do NOT put desktop paths, compiler paths, Python versions, etc. here.
-- The remote project's own configuration should win.
M.remote_servers = {
  clangd = {
    filetypes = {
      "c",
      "cpp",
      "objc",
      "objcpp",
    },

    root_patterns = {

      "compile_commands.json",
      "compile_flags.txt",
      ".git",
      "CMakeLists.txt",
      "Makefile",
    },
  },

  pyright = {
    filetypes = {
      "python",
    },


    root_patterns = {
      "pyproject.toml",
      "pyrightconfig.json",
      "setup.py",
      "requirements.txt",
      ".git",
    },
  },

  rust_analyzer = {
    filetypes = {
      "rust",

    },

    root_patterns = {
      "Cargo.toml",
      "Cargo.lock",
      "rust-project.json",

      ".git",
    },
  },

  lua_ls = {

    filetypes = {
      "lua",
    },


    root_patterns = {
      ".luarc.json",
      ".luarc.jsonc",

      ".git",
    },
  },
}

return M
