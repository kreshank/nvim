return {
  git_timeout_ms = 400,
  watcher_ignore = {
    node_modules = true,
    [".git"] = true,
    [".cache"] = true,
  },
  keys = {
    toggle = "<leader>e",
    open = { "<CR>", "o", "<2-LeftMouse>" },
    tab = "<leader>t",
    vsplit = "<leader>v",
    split = "<leader>h",
    preview = "<leader>p",
    diff = "<leader>gd",
  },
}
