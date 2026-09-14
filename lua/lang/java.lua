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

local function apply(resolved, _, config)
  local home = resolved.java_home or find_jvm(resolved.version)

  if home then
    config.cmd_env = vim.tbl_extend("force", config.cmd_env or {}, {
      JAVA_HOME = home,
    })
    return
  end

  if vim.fn.executable("java") ~= 1 and not notified_missing_jdk then
    notified_missing_jdk = true
    vim.notify(
      "No JDK found; jdtls may fail until JDK 17+ is installed",
      vim.log.levels.WARN
    )
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
  markers = { "pom.xml", "build.gradle" },
  versions = { "11", "17", "21" },
  default_version = "17",
  detect = detect,
  apply = apply,
  lsp = {
    jdtls = {
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
