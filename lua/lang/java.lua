local util = require("lang.util")

local notified_missing_jdk = false

local function find_jvm(version)
  if vim.env.JAVA_HOME and vim.env.JAVA_HOME ~= "" then
    return vim.env.JAVA_HOME
  end

  local pattern = "/usr/lib/jvm/*" .. tostring(version) .. "*"
  local matches = vim.fn.glob(pattern, false, true)

  if type(matches) == "table" and matches[1] then
    return matches[1]
  end

  return nil
end

---@param dir string
---@return boolean
local function dir_has_jars(dir)
  local scanner = vim.uv.fs_scandir(dir)

  if not scanner then
    return false
  end

  while true do
    local name, entry_type = vim.uv.fs_scandir_next(scanner)

    if not name then
      return false
    end

    if entry_type ~= "directory" and name:sub(-4) == ".jar" then
      return true
    end
  end
end

---@param dir string
---@return boolean
local function is_project_root(dir)
  if not dir or dir == "" then
    return false
  end

  return dir_has_jars(dir)
    or dir_has_jars(vim.fs.joinpath(dir, "lib"))
end

---@param path string
---@return string?
local function java_package_of(path)
  local fd = vim.uv.fs_open(path, "r", 438)

  if not fd then
    return nil
  end

  local data = vim.uv.fs_read(fd, 4096, 0)
  vim.uv.fs_close(fd)

  if type(data) ~= "string" then
    return nil
  end

  return data:match("package%s+([%w.]+)%s*;")
end

---@param dir string
---@return boolean
local function package_matches_dirname(dir)
  local dirname = vim.fs.basename(dir)

  if not dirname or dirname == "" then
    return false
  end

  local scanner = vim.uv.fs_scandir(dir)

  if not scanner then
    return false
  end

  while true do
    local name, entry_type = vim.uv.fs_scandir_next(scanner)

    if not name then
      return false
    end

    if entry_type ~= "directory" and name:sub(-5) == ".java" then
      local pkg = java_package_of(vim.fs.joinpath(dir, name))

      if pkg == dirname or (pkg and pkg:sub(-(#dirname + 1)) == "." .. dirname) then
        return true
      end
    end
  end
end

---@param dir string
---@return string?
local function resolve_root(dir)
  if not is_project_root(dir) then
    return nil
  end

  if dir_has_jars(dir) and package_matches_dirname(dir) then
    local parent = vim.fs.dirname(dir)

    if parent and parent ~= dir then
      return parent
    end
  end

  return dir
end

---@param root string?
---@return string[]
local function collect_jars(root)
  if not root or root == "" then
    return {}
  end

  return vim.fs.find(function(name)
    return name:sub(-4) == ".jar"
  end, {
    path = root,
    type = "file",
    limit = 256,
  })
end

---@param root string?
---@return string
local function jdtls_data_dir(root)
  local base = vim.fs.joinpath(
    vim.fn.stdpath("cache"),
    "jdtls",
    "workspace"
  )

  if not root or root == "" then
    return base
  end

  local hash = vim.fn.sha256(vim.fs.normalize(root)):sub(1, 16)
  return vim.fs.joinpath(base, hash)
end

---@return string[]
local function jdtls_jvm_args()
  local args = {}
  local env = os.getenv("JDTLS_JVM_ARGS")

  for a in string.gmatch(env or "", "%S+") do
    args[#args + 1] = "--jvm-arg=" .. a
  end

  return args
end

local function apply(resolved, params, config)
  local home = resolved.java_home or find_jvm(resolved.version)

  if home then
    config.cmd_env = vim.tbl_extend("force", config.cmd_env or {}, {
      JAVA_HOME = home,
    })
  elseif vim.fn.executable("java") ~= 1 and not notified_missing_jdk then
    notified_missing_jdk = true
    vim.notify(
      "No JDK found; jdtls may fail until JDK 17+ is installed",
      vim.log.levels.WARN
    )
  end

  if type(config.settings) ~= "table" then
    config.settings = {}
  end

  if type(config.settings.java) ~= "table" then
    config.settings.java = {}
  end

  if type(config.settings.java.import) ~= "table" then
    config.settings.java.import = {}
  end

  config.settings.java.import.generatesMetadataFilesAtProjectRoot = false

  local jars = collect_jars(config.root_dir)

  if #jars > 0 then
    if type(config.settings.java.project) ~= "table" then
      config.settings.java.project = {}
    end

    config.settings.java.project.referencedLibraries = jars
  end

  if params then
    params.initializationOptions = params.initializationOptions or {}
    params.initializationOptions.settings = config.settings
  end
end

local function detect(root, _)
  local text = util.read_root_file(root, ".java-version")

  if text then
    local line = vim.trim(text:match("[^\r\n]+") or text)

    if line ~= "" then
      return {
        version = line,
        source = "java-version",
        java_home = find_jvm(line),
      }
    end
  end

  local mise_java = util.mise_which(root, "java")

  if mise_java then
    return {
      version = "17",
      source = "mise",
      interpreter = mise_java,
    }
  end

  local pom = util.read_root_file(root, "pom.xml")

  if pom then
    local n = pom:match("<maven%.compiler%.release>%s*(%d+)%s*<")
      or pom:match("<maven%.compiler%.source>%s*(%d+)%s*<")
      or pom:match("<release>%s*(%d+)%s*<")

    if n then
      return {
        version = n,
        source = "pom",
        java_home = find_jvm(n),
      }
    end
  end

  return {
    version = "17",
    source = "default",
    java_home = vim.env.JAVA_HOME,
  }
end

return {
  id = "java",
  filetypes = { "java" },
  servers = { "jdtls" },
  formatter = "jdtls",
  markers = {
    "pom.xml",
    "build.gradle",
    "build.gradle.kts",
    "settings.gradle",
    "settings.gradle.kts",
    ".classpath",
  },
  versions = { "11", "17", "21" },
  default_version = "17",
  detect = detect,
  apply = apply,
  is_project_root = is_project_root,
  resolve_root = resolve_root,
  lsp = {
    jdtls = {
      init_options = {},
      settings = {
        java = {
          import = {
            generatesMetadataFilesAtProjectRoot = false,
          },
        },
      },
      cmd = function(dispatchers, config)
        local lsp = require("features.lsp")
        local config_cmd = {
          lsp.mason_exe("jdtls"),
          "-data",
          jdtls_data_dir(config.root_dir),
        }

        vim.list_extend(config_cmd, jdtls_jvm_args())

        return vim.lsp.rpc.start(config_cmd, dispatchers, {
          cwd = config.cmd_cwd,
          env = config.cmd_env,
          detached = config.detached,
        })
      end,
      before_init = function(params, config)
        local resolved = require("lang").resolve(
          vim.api.nvim_get_current_buf(),
          { root = config.root_dir, filetype = "java" }
        )
        if resolved.lang == "java" then
          apply(resolved, params, config)
        end
      end,
    },
  },
}
