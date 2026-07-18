local M = {
  neovim = {
    python_host = "/usr/bin/python3.12",
  },

  cpp = {
    standard = "c++20",

    format_style = "Google",

    warnings = {
      "-Wall",
      "-Wextra",
      "-Wshadow",
      "-Wpedantic",
      "-Wthread-safety",
    },

    query_drivers = {
      "/usr/bin/g++",
      "/usr/bin/gcc",
      "/usr/bin/c++",
    },
  },

  format = {
    timeout_ms = 3000,

    clients = {
      c = "clangd",
      cpp = "clangd",
      objc = "clangd",
      objcpp = "clangd",

      python = "ruff",

      rust = "rust_analyzer",
      lua = "lua_ls",
    },
  },

  python = {
    analysis_version = "3.12",
    type_checking_mode = "basic",

    ruff = {
      target_version = "py312",
      line_length = 88,
      indent_width = 4,

      format = {
        quote_style = "double",
        indent_style = "space",
        line_ending = "auto",
        docstring_code_format = true,
        skip_magic_trailing_comma = false,
      },

      lint = {
        select = {
          "E4", -- import errors
          "E7", -- statement errors
          "E9", -- runtime/syntax-like errors
          "F", -- Pyflakes
          "I", -- import sorting
        },

        ignore = {},
      },
    },
  },

  project = {
    root_search_depth = 5,
    compile_commands_search_depth = 3,

    markers = {
      ".git",
      "CMakeLists.txt",
      "Makefile",
      "meson.build",
      "configure.ac",
    },

    ignored_directories = {
      [".git"] = true,
      [".hg"] = true,
      [".svn"] = true,
      ["node_modules"] = true,
    },
  },
}

return M
