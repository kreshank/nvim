return {
  "MeanderingProgrammer/render-markdown.nvim",
  ft = { "markdown" },
  config = function()
    require("render-markdown").setup({})

    vim.api.nvim_create_autocmd("FileType", {
      group = vim.api.nvim_create_augroup("RenderMarkdownUser", {
        clear = true,
      }),
      pattern = "markdown",
      callback = function()
        vim.cmd("RenderMarkdown enable")
      end,
    })

    if vim.bo.filetype == "markdown" then
      vim.cmd("RenderMarkdown enable")
    end
  end,
}
