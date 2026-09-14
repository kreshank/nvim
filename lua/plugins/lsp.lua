return {
  {
    "williamboman/mason.nvim",
    lazy = false,
    config = function()
      require("features.lsp").setup_mason()
    end,
  },

  {
    "neovim/nvim-lspconfig",
    lazy = false,
  },

  {
    "williamboman/mason-lspconfig.nvim",
    lazy = false,
    dependencies = {
      "williamboman/mason.nvim",
      "neovim/nvim-lspconfig",
    },

    config = function()
      require("features.lsp").setup()
    end,
  },
}
