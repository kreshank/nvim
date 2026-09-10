local defaults = require("config.defaults")

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
      sshfs_options = {
        reconnect = true,
        ConnectTimeout = 15,
        compression = "no",
        ServerAliveInterval = 15,
        ServerAliveCountMax = 3,
        dir_cache = "yes",
        dcache_timeout = 300,
        dcache_max_size = 10000,
        cache = "yes",
      },
      control_persist = defaults.remote.control_persist,
      socket_dir = defaults.remote.sockets_dir,
    },
    mounts = {
      base_dir = defaults.remote.mount_base,
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
