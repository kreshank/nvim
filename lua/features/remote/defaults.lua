return {
  mount_base = vim.fn.stdpath("state") .. "/mnt",
  sockets_dir = vim.fn.expand("$HOME/.ssh/sockets"),
  control_persist = "4h",
  recents_file = vim.fn.stdpath("data") .. "/remote-projects.json",
  recents_max = 20,
  ssh_probe_ms = 8000,
  ssh_cmd_ms = 15000,
  ssh_auth_ms = 120000,
  sshfs_ms = 30000,
  mount_ready_ms = 10000,
  git_default = false,
  path_proxy = vim.fn.stdpath("config")
    .. "/scripts/lsp-path-proxy.py",
  keys = {
    project = "<leader>rp",
    disconnect = "<leader>rd",
    shell = "<leader>rs",
    lsp_mode = "<leader>rl",
    git = "<leader>rg",
  },
  -- FUSE flags shared by sshfs.nvim and :RemoteProject.
  -- Access is the SSH login, not local UID matching. idmap is display-only.
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
}
