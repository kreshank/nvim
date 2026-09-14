local util = require("lang.util")

local warnings = {
  "-Wall",
  "-Wextra",
  "-Wshadow",
  "-Wpedantic",
  "-Wthread-safety",
}

local query_drivers = {
  "/usr/bin/g++*",
  "/usr/bin/gcc*",
  "/usr/bin/c++",
}

local function apply(resolved, params, _)
  params.initializationOptions = params.initializationOptions or {}

  local flags = {
    "-std=" .. resolved.version,
  }

  vim.list_extend(flags, warnings)
  params.initializationOptions.fallbackFlags = flags

  if resolved.compile_db then
    params.initializationOptions.compilationDatabasePath =
      resolved.compile_db
  end
end

local function compile_db_result(root, kind)
  local project = require("features.project")
  local dir = project.find_compile_commands(root)

  if not dir then
    return nil
  end

  local text = util.read_root_file(dir, "compile_commands.json")
  local std

  if text then
    if kind == "cpp" then
      std = util.cpp_std_from_text(text)
    else
      std = util.c_std_from_text(text)
    end
  end

  return {
    version = std,
    source = "compile_commands",
    compile_db = dir,
  }
end

local function compile_flags_result(root, kind)
  local text = util.read_root_file(root, "compile_flags.txt")

  if not text then
    return nil
  end

  local std = kind == "cpp" and util.cpp_std_from_text(text)
    or util.c_std_from_text(text)

  return {
    version = std,
    source = "compile_flags",
  }
end

local MAKEFILES = {
  "Makefile",
  "makefile",
  "GNUmakefile",
}

local function makefile_result(root, kind)
  for _, name in ipairs(MAKEFILES) do
    local text = util.read_root_file(root, name)

    if text then
      local std = kind == "cpp" and util.cpp_std_from_text(text)
        or util.c_std_from_text(text)

      if std then
        return {
          version = std,
          source = "makefile",
        }
      end
    end
  end
end

local function cmake_result(root, kind)
  local text = util.read_root_file(root, "CMakeLists.txt")

  if not text then
    return nil
  end

  local n

  if kind == "cpp" then
    n = text:match("CMAKE_CXX_STANDARD%s+(%d+)")
    if n then
      return {
        version = "c++" .. n,
        source = "cmake",
      }
    end
  else
    n = text:match("CMAKE_C_STANDARD%s+(%d+)")
    if n then
      return {
        version = "c" .. n,
        source = "cmake",
      }
    end
  end
end

local function detect_kind(kind, default_version)
  return function(root, _)
    local found = compile_db_result(root, kind)
      or compile_flags_result(root, kind)
      or makefile_result(root, kind)
      or cmake_result(root, kind)

    if found then
      found.version = found.version or default_version
      return found
    end

    return {
      version = default_version,
      source = "default",
    }
  end
end

local c_markers = {
  "CMakeLists.txt",
  "Makefile",
  "meson.build",
  "configure.ac",
  "compile_flags.txt",
}

local function clangd_kind_from_ft(ft)
  if ft == "c" or ft == "objc" then
    return "c"
  end

  return "cpp"
end

---Pick C vs C++ from loaded buffers under root, not the current window.
---Mixed or unknown workspaces default to C++ (one clangd client, one flag list).
---@param root string?
---@return string
local function clangd_kind(root)
  if not root or root == "" then
    return "cpp"
  end

  root = vim.fs.normalize(root)
  local prefix = root .. "/"
  local saw_c = false
  local saw_cpp = false

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local name = vim.api.nvim_buf_get_name(bufnr)

      if name ~= "" then
        name = vim.fs.normalize(name)

        if name == root or vim.startswith(name, prefix) then
          local ft = vim.bo[bufnr].filetype

          if ft == "c" or ft == "objc" then
            saw_c = true
          elseif ft == "cpp" or ft == "objcpp" then
            saw_cpp = true
          end
        end
      end
    end
  end

  if saw_c and not saw_cpp then
    return "c"
  end

  return "cpp"
end

local clangd_lsp = {
  cmd = {
    "clangd",
    "--background-index",
    "--clang-tidy",
    "--fallback-style=Google",
  },
  query_driver = true,
  before_init = function(params, config)
    local kind = clangd_kind(config.root_dir)
    local resolved = require("lang").resolve(0, {
      root = config.root_dir,
      filetype = kind,
    })
    if resolved.lang then
      apply(resolved, params, config)
    end
  end,
}

local c = {
  id = "c",
  filetypes = { "c", "objc" },
  servers = { "clangd" },
  formatter = "clangd",
  markers = c_markers,
  versions = { "c89", "c99", "c11", "c17", "c23" },
  default_version = "c17",
  format_style = "Google",
  warnings = warnings,
  query_drivers = query_drivers,
  detect = detect_kind("c", "c17"),
  apply = apply,
  clangd_kind = clangd_kind,
  clangd_kind_from_ft = clangd_kind_from_ft,
}

local cpp = {
  id = "cpp",
  filetypes = { "cpp", "objcpp" },
  servers = { "clangd" },
  formatter = "clangd",
  markers = c_markers,
  versions = {
    "c++11",
    "c++14",
    "c++17",
    "c++20",
    "c++23",
    "c++26",
  },
  default_version = "c++20",
  standard = "c++20",
  format_style = "Google",
  warnings = warnings,
  query_drivers = query_drivers,
  detect = detect_kind("cpp", "c++20"),
  apply = apply,
  clangd_kind = clangd_kind,
  clangd_kind_from_ft = clangd_kind_from_ft,
  lsp = {
    clangd = clangd_lsp,
  },
}

return { c, cpp }
