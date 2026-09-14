local defaults = require("features.remote.defaults")
local remote = require("features.remote")

return {
  "uhs-robert/sshfs.nvim",
  lazy = false,
  dependencies = {
    "nvim-telescope/telescope.nvim",
    "nvim-lua/plenary.nvim",
    "nvim-tree/nvim-tree.lua",
  },
  opts = {
    connections = {
      sshfs_options = remote.sshfs_options(),
      control_persist = defaults.control_persist,
      socket_dir = defaults.sockets_dir,
    },
    mounts = {
      base_dir = defaults.mount_base,
    },
    hooks = {
      on_exit = {
        auto_unmount = false,
        clean_mount_folders = false,
      },
      on_mount = {
        auto_change_to_dir = true,
        auto_run = "none",
      },
    },
    ui = {
      local_picker = {
        preferred_picker = "nvim-tree",
      },
    },
    -- Keep plugin maps on <Plug> so they do not stack with <leader>r*
    lead_prefix = "<Plug>Sshfs",
  },
}
