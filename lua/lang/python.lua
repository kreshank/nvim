local util = require("lang.util")

local function analysis_version(version)
  local major, minor = tostring(version):match("(%d+)%.(%d+)")

  if major then
    return major .. "." .. minor
  end

  return version
end

local function ruff_target(version)
  local major, minor = tostring(version):match("(%d+)%.(%d+)")

  if major then
    return "py" .. major .. minor
  end

  return "py312"
end

local ruff = {
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
      "E4",
      "E7",
      "E9",
      "F",
      "I",
    },
    ignore = {},
  },
}

local function ruff_init_options(resolved)
  local target = ruff.target_version

  if resolved and resolved.version then
    target = ruff_target(resolved.version)
  end

  return {
    settings = {
      configurationPreference = "editorOnly",
      lineLength = ruff.line_length,
      lint = {
        select = ruff.lint.select,
        ignore = ruff.lint.ignore,
      },
      configuration = {
        ["target-version"] = target,
        ["indent-width"] = ruff.indent_width,
        format = {
          ["quote-style"] = ruff.format.quote_style,
          ["indent-style"] = ruff.format.indent_style,
          ["line-ending"] = ruff.format.line_ending,
          ["docstring-code-format"] = ruff.format.docstring_code_format,
          ["skip-magic-trailing-comma"] =
            ruff.format.skip_magic_trailing_comma,
        },
      },
    },
  }
end

local function apply(resolved, params, config)
  local version = analysis_version(resolved.version) or "3.12"

  config.settings = vim.tbl_deep_extend("force", config.settings or {}, {
    python = {
      analysis = {
        pythonVersion = version,
      },
    },
  })

  if resolved.interpreter then
    config.settings.python.pythonPath = resolved.interpreter
  end

  params.initializationOptions = params.initializationOptions or {}
end

local function venv_python(root)
  local candidates = {
    ".venv/bin/python",
    ".venv/bin/python3",
    "venv/bin/python",
    "venv/bin/python3",
  }

  for _, rel in ipairs(candidates) do
    if util.file_exists(root, rel) then
      return vim.fs.joinpath(root, rel),
        vim.fs.dirname(vim.fs.dirname(vim.fs.joinpath(root, rel)))
    end
  end
end

local function version_from_pyvenv(venv_dir)
  local text = util.read_root_file(venv_dir, "pyvenv.cfg")

  if not text then
    return nil
  end

  local ver = text:match("\nversion%s*=%s*([%d.]+)")
    or text:match("^version%s*=%s*([%d.]+)")

  if not ver then
    return nil
  end

  return analysis_version(ver)
end

local function detect(root, _)
  local interpreter, venv_dir = venv_python(root)

  if interpreter then
    return {
      version = version_from_pyvenv(venv_dir) or "3.12",
      source = "venv",
      interpreter = interpreter,
    }
  end

  local pyver = util.read_root_file(root, ".python-version")

  if pyver then
    local line = vim.trim(pyver:match("[^\r\n]+") or pyver)

    if line ~= "" then
      return {
        version = line,
        source = "python-version",
      }
    end
  end

  local mise_python = util.mise_which(root, "python")

  if mise_python then
    return {
      version = "3.12",
      source = "mise",
      interpreter = mise_python,
    }
  end

  local pyproject = util.read_root_file(root, "pyproject.toml")

  if pyproject then
    local spec = pyproject:match("requires%-python%s*=%s*[\"']([^\"']+)[\"']")

    if spec then
      local major, minor = spec:match("(%d+)%.(%d+)")

      if major then
        return {
          version = major .. "." .. minor,
          source = "pyproject",
        }
      end
    end
  end

  return {
    version = "3.12",
    source = "default",
  }
end

local function resolve_python(config)
  return require("lang").resolve(vim.api.nvim_get_current_buf(), {
    root = config.root_dir,
    filetype = "python",
  })
end

return {
  id = "python",
  filetypes = { "python" },
  servers = { "pyright", "ruff" },
  formatter = "ruff",
  markers = { "pyproject.toml", ".python-version" },
  versions = { "3.10", "3.11", "3.12", "3.13" },
  default_version = "3.12",
  analysis_version = "3.12",
  type_checking_mode = "basic",
  analysis_version_of = analysis_version,
  ruff_target = ruff_target,
  ruff_init_options = ruff_init_options,
  ruff = ruff,
  detect = detect,
  apply = apply,
  lsp = {
    pyright = {
      cmd = { "pyright-langserver", "--stdio" },
      settings = {
        python = {
          analysis = {
            pythonVersion = "3.12",
            typeCheckingMode = "basic",
          },
        },
      },
      before_init = function(params, config)
        local resolved = resolve_python(config)
        if resolved.lang == "python" then
          apply(resolved, params, config)
        end
      end,
    },
    ruff = {
      cmd = { "ruff", "server" },
      init_options = ruff_init_options(),
      before_init = function(params, config)
        local resolved = resolve_python(config)
        local init = ruff_init_options(resolved)
        config.init_options = init
        params.initializationOptions = init
      end,
    },
  },
}
