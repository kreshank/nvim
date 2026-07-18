local defaults = require("config.defaults")

vim.g.python3_host_prog = defaults.neovim.python_host

require("config.options")
require("config.keymaps")
require("config.commands")
require("config.autocmds")
require("config.diagnostics")
require("config.lazy")
require("config.formats")
