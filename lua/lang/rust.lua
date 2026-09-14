local util = require("lang.util")

local function apply(resolved, _, config)
  if resolved.source ~= "override" then
    return
  end

  config.settings = vim.tbl_deep_extend("force", config.settings or {}, {
    ["rust-analyzer"] = {
      cargo = {
        extraEnv = {
          RUSTUP_TOOLCHAIN = resolved.version,
        },
      },
    },
  })
end

local function channel_from_toml(text)
  return text:match("%[toolchain%][^\n]*\n.-channel%s*=%s*[\"']([^\"']+)[\"']")
    or text:match("channel%s*=%s*[\"']([^\"']+)[\"']")
end

local function detect(root, _)
  local toml = util.read_root_file(root, "rust-toolchain.toml")

  if toml then
    local channel = channel_from_toml(toml)

    if channel then
      return {
        version = channel,
        source = "rust-toolchain",
        toolchain = channel,
      }
    end
  end

  local plain = util.read_root_file(root, "rust-toolchain")

  if plain then
    local line = vim.trim(plain:match("[^\r\n]+") or plain)

    if line ~= "" then
      return {
        version = line,
        source = "rust-toolchain",
        toolchain = line,
      }
    end
  end

  local mise_rust = util.mise_which(root, "rust")

  if mise_rust then
    return {
      version = "stable",
      source = "mise",
      toolchain = mise_rust,
    }
  end

  return {
    version = "stable",
    source = "default",
  }
end

return {
  id = "rust",
  filetypes = { "rust" },
  servers = { "rust_analyzer" },
  formatter = "rust_analyzer",
  markers = { "Cargo.toml" },
  versions = { "stable", "beta", "nightly" },
  default_version = "stable",
  detect = detect,
  apply = apply,
  lsp = {
    rust_analyzer = {
      cmd = { "rust-analyzer" },
      before_init = function(params, config)
        local resolved = require("lang").resolve(
          vim.api.nvim_get_current_buf(),
          { root = config.root_dir, filetype = "rust" }
        )
        if resolved.lang == "rust" then
          apply(resolved, params, config)
        end
      end,
    },
  },
}
