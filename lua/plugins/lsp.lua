return {
  {
    "williamboman/mason.nvim",
    config = true,
  },
  {
    "williamboman/mason-lspconfig.nvim",
    config = function()
      require("mason-lspconfig").setup({
        ensure_installed = {
          "clangd",
          "pyright",
          "rust_analyzer",
          "lua_ls",
        },
      })
    end,
  },
  {
    "neovim/nvim-lspconfig",
    config = function()
      vim.lsp.config("clangd", {})
      vim.lsp.config("pyright", {})
      vim.lsp.config("rust_analyzer", {})
      vim.lsp.config("lua_ls", {
        settings = {
          Lua = {
            diagnostics = { globals = { "vim" } },
          },
        },
      })

      vim.lsp.enable({
        "clangd",
        "pyright",
        "rust_analyzer",
        "lua_ls",
      })
    end,
  },
}
