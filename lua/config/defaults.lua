local M = {
  neovim = {
    python_host = "/usr/bin/python3.12",
  },

  cpp = {
    standard = "c++20",

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

  python = {
    analysis_version = "3.12",
    type_checking_mode = "basic",
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
