local config_group = vim.api.nvim_create_augroup(
  "UserConfig",
  {
    clear = true,
  }
)

vim.api.nvim_create_autocmd("FileType", {
  group = config_group,
  pattern = "markdown",

  callback = function()
    vim.cmd("RenderMarkdown enable")
  end,
})
