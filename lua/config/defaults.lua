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

      java = "jdtls",

      python = "ruff",

      rust = "rust_analyzer",
      lua = "lua_ls",

      tex = "texlab",
      plaintex = "texlab",
      bib = "texlab",
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

  remote = {
    mount_base = vim.fn.stdpath("state") .. "/mnt",
    sockets_dir = vim.fn.expand("$HOME/.ssh/sockets"),
    control_persist = "4h",
    recents_file = vim.fn.stdpath("data") .. "/remote-projects.json",
    recents_max = 20,
    ssh_probe_ms = 8000,
    ssh_cmd_ms = 15000,
    ssh_auth_ms = 120000,
    sshfs_ms = 30000,
    mount_ready_ms = 10000,
    git_default = false,
    path_proxy = vim.fn.stdpath("config")
      .. "/scripts/lsp-path-proxy.py",
    -- FUSE flags shared by sshfs.nvim and :RemoteProject.
    -- Access is the SSH login, not local UID matching. idmap is display-only.
    sshfs_options = {
      reconnect = true,
      ConnectTimeout = 15,
      compression = "no",
      ServerAliveInterval = 15,
      ServerAliveCountMax = 3,
      dir_cache = "yes",
      dcache_timeout = 300,
      dcache_max_size = 10000,
      cache = "yes",
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
