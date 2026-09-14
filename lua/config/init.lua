local defaults = require("config.defaults")

vim.g.python3_host_prog = defaults.python_host

require("config.options")
require("config.keymaps")
require("config.lazy")
