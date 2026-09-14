local function apply(_)
end

local function detect()
  return {
    version = "luajit",
    source = "default",
  }
end

return {
  id = "lua",
  filetypes = { "lua" },
  servers = { "lua_ls" },
  formatter = "lua_ls",
  remote = false,
  versioned = false,
  markers = {
    ".luarc.json",
    ".luarc.jsonc",
    ".luacheckrc",
    ".stylua.toml",
    "stylua.toml",
    "selene.toml",
    "selene.yml",
  },
  versions = { "luajit" },
  default_version = "luajit",
  detect = detect,
  apply = apply,
  lsp = {
    lua_ls = {
      cmd = { "lua-language-server" },
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
  },
}
