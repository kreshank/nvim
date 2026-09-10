local lsp = require("config.lsp")

return {
  {
    "williamboman/mason.nvim",
    opts = {},
    config = function(_, opts)
      require("mason").setup(opts)

      local registry = require("mason-registry")

      registry.refresh(function()
        local package = registry.get_package("latexindent")

        if not package:is_installed() then
          package:install()
        end
      end)
    end,
  },

  {
    "williamboman/mason-lspconfig.nvim",
    dependencies = {
      "williamboman/mason.nvim",
    },

    opts = {
      automatic_enable = false,
      ensure_installed = {
        "clangd",
        "jdtls",
        "pyright",
        "ruff",
        "rust_analyzer",
        "lua_ls",
        "texlab",
        "ltex_plus",
      },
    },
  },

  {
    "neovim/nvim-lspconfig",
    dependencies = {
      "williamboman/mason-lspconfig.nvim",
    },

    config = function()
      lsp.configure()
      lsp.enable_local()
    end,
  },
}
