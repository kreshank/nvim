vim.g.python3_host_prog = "/usr/bin/python3.12"

require("config.lazy")

-- Line numbers
vim.opt.number = true
vim.opt.relativenumber = true

-- Disable bells
vim.opt.errorbells = false
vim.opt.visualbell = false

-- Highlight current line 
vim.opt.cursorline = true
vim.opt.colorcolumn = "80"

-- Tab related stuff
vim.opt.expandtab = true
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2
vim.opt.smartindent = true
vim.opt.autoindent = true
vim.opt.wrap = false
vim.opt.linebreak = true

-- Themes
vim.o.background = "light";
vim.opt.termguicolors = true

-- YCM Configuration
vim.g.ycm_always_population_location_list = 1
vim.g.ycm_global_ycm_extra_conf = "~/.vim/.ycm_global_extra_conf.py"

-- Searching
vim.opt.smartcase = true

vim.keymap.set("n", "<leader>e", ":NvimTreeToggle<CR>")

vim.api.nvim_create_autocmd("FileType", {
  pattern = "markdown",
  callback = function()
    vim.cmd("RenderMarkdown enable")
  end,
})
