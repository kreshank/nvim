return {
  "neanias/everforest-nvim",
  priority = 1000,
  config = function()
    require("everforest").setup({
      background = "medium", -- soft | medium | hard
      italics = true,
      disable_italic_comments = false,
      inlay_hints_background = "dimmed",
    })
    vim.cmd.colorscheme("everforest")
  end
}
