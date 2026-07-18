vim.api.nvim_create_user_command("CppStd", function(opts)
  vim.g.cpp_std = opts.args

  vim.notify(
    "C++ fallback standard set to " .. vim.g.cpp_std,
    vim.log.levels.INFO
  )

  vim.cmd("LspRestart clangd")
end, {
  nargs = 1,

  complete = function()
    return {
      "c++11",
      "c++14",
      "c++17",
      "c++20",
      "c++23",
      "c++26",
    }
  end,
})

vim.api.nvim_create_user_command("LspLog", function()
  local path = vim.lsp.log.get_filename()

  vim.cmd(
    "edit " .. vim.fn.fnameescape(path)
  )
end, {
  desc = "Open Neovim LSP log",
})
