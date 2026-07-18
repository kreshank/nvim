vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

vim.keymap.set("n", "<leader>cs", function()
  vim.notify(
    "Current C++ standard: "
      .. (vim.g.cpp_std or "c++20"),
    vim.log.levels.INFO
  )
end, {
  desc = "Show current C++ standard",
})
