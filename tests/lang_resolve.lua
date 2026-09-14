-- Headless resolve tests. Does not load init.lua or plugins.
-- nvim --headless -u tests/lang_resolve.lua

vim.opt.loadplugins = false

local config = vim.fn.stdpath("config")
vim.opt.runtimepath:prepend(config)

local lang = require("lang")
local project = require("features.project")
local fixtures = vim.fs.joinpath(config, "tests", "fixtures")

-- Do not read or write the user's real lang-versions.json.
lang._state_path = vim.fn.tempname()

local failures = {}

local function eq(name, expected, actual)
  if expected ~= actual then
    table.insert(
      failures,
      string.format(
        "%s: expected %q, got %q",
        name,
        tostring(expected),
        tostring(actual)
      )
    )
  end
end

local function resolve(dir, filetype)
  return lang.resolve(0, {
    root = vim.fs.joinpath(fixtures, dir),
    filetype = filetype,
  })
end

local cpp_make = resolve("cpp-makefile", "cpp")
eq("cpp makefile version", "c++23", cpp_make.version)
eq("cpp makefile source", "makefile", cpp_make.source)
eq("cpp makefile lang", "cpp", cpp_make.lang)

local c_cmake = resolve("c-cmake", "c")
eq("c cmake version", "c11", c_cmake.version)
eq("c cmake source", "cmake", c_cmake.source)

local cpp_db = resolve("cpp-compile-commands", "cpp")
eq("cpp compile_commands version", "c++17", cpp_db.version)
eq("cpp compile_commands source", "compile_commands", cpp_db.source)

local cpp_flags = resolve("cpp-compile-flags", "cpp")
eq("cpp compile_flags version", "c++14", cpp_flags.version)
eq("cpp compile_flags source", "compile_flags", cpp_flags.source)

local py_ver = resolve("python-version", "python")
eq("python-version version", "3.11", py_ver.version)
eq("python-version source", "python-version", py_ver.source)

local py_proj = resolve("python-pyproject", "python")
eq("pyproject version", "3.10", py_proj.version)
eq("pyproject source", "pyproject", py_proj.source)

local py_venv = resolve("python-venv", "python")
eq("venv version", "3.11", py_venv.version)
eq("venv source", "venv", py_venv.source)

local rust = resolve("rust-toolchain", "rust")
eq("rust version", "1.85.0", rust.version)
eq("rust source", "rust-toolchain", rust.source)

local java_ver = resolve("java-version", "java")
eq("java-version version", "21", java_ver.version)
eq("java-version source", "java-version", java_ver.source)

local java_pom = resolve("java-pom", "java")
eq("java pom version", "17", java_pom.version)
eq("java pom source", "pom", java_pom.source)

local cpp_default = resolve("empty", "cpp")
eq("cpp default version", "c++20", cpp_default.version)
eq("cpp default source", "default", cpp_default.source)

local none = lang.resolve(0, { root = fixtures, filetype = "lua" })
eq("lua source", "none", none.source)
eq("lua lang", nil, none.lang)

local flags = project.cpp_fallback_flags()
eq("fallback std", "-std=c++20", flags[1])
eq("fallback no -xc++", true, flags[1] ~= "-xc++")

eq("cpp formatter", "clangd", lang.formatter_for("cpp"))
eq("python formatter", "ruff", lang.formatter_for("python"))
eq("lua formatter", "lua_ls", lang.formatter_for("lua"))

local empty_root = vim.fs.joinpath(fixtures, "empty")
lang.set_override(empty_root, "cpp", "c++23")
local over = resolve("empty", "cpp")
eq("override version", "c++23", over.version)
eq("override source", "override", over.source)
lang.clear_override(empty_root, "cpp")
local cleared = resolve("empty", "cpp")
eq("cleared source", "default", cleared.source)

local apply_params = { initializationOptions = {} }
lang.get("cpp").apply(resolve("cpp-makefile", "cpp"), apply_params, {})
eq("apply cpp std", "-std=c++23", apply_params.initializationOptions.fallbackFlags[1])

local has_xcpp = false
for _, flag in ipairs(apply_params.initializationOptions.fallbackFlags) do
  if flag == "-xc++" then
    has_xcpp = true
  end
end
eq("apply no -xc++", false, has_xcpp)

local c_params = { initializationOptions = {} }
lang.get("c").apply(resolve("c-cmake", "c"), c_params, {})
eq("apply c std", "-std=c11", c_params.initializationOptions.fallbackFlags[1])

if #failures > 0 then
  for _, failure in ipairs(failures) do
    io.stderr:write(failure .. "\n")
  end
  vim.cmd("cquit 1")
else
  print("lang_resolve: ok")
  vim.cmd("qall!")
end
