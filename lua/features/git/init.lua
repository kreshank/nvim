local M = {}
local defaults = require("features.git.defaults")

function M.attach(bufnr)
  local remote = require("features.remote")
  local path = vim.api.nvim_buf_get_name(bufnr)
  if remote.is_mount_path(path) and not remote.git_enabled_for_path(path) then
    return false
  end

  local gs = require("gitsigns")
  local function map(key, action, desc)
    vim.keymap.set("n", key, action, { buffer = bufnr, desc = desc })
  end
  for _, direction in ipairs({ "next", "prev" }) do
    map(defaults.keys[direction], function()
      if vim.wo.diff then
        vim.cmd.normal({ direction == "next" and "]c" or "[c", bang = true })
      else
        gs.nav_hunk(direction, { target = "all" })
      end
    end, direction == "next" and "Next Git change" or "Previous Git change")
  end
  map(defaults.keys.preview, gs.preview_hunk, "Preview Git change")
  map(defaults.keys.inline, gs.preview_hunk_inline, "Preview removed lines inline")
  map(defaults.keys.diff, function() gs.diffthis("HEAD") end, "Diff file against last commit")
  map(defaults.keys.deleted, function()
    gs.diffthis("HEAD", { unified = true })
  end, "Toggle all removed lines inline")
  map(defaults.keys.lines, gs.toggle_linehl, "Toggle Git line backgrounds")
  map(defaults.keys.blame, gs.toggle_current_line_blame, "Toggle Git line blame")
end

function M.setup()
  require("gitsigns").setup({
    signs = defaults.signs,
    signs_staged = vim.deepcopy(defaults.signs),
    signs_staged_enable = true,
    signcolumn = true,
    numhl = true,
    word_diff = true,
    attach_to_untracked = true,
    max_file_length = 40000,
    on_attach = M.attach,
    preview_config = { border = "rounded" },
  })
end

return M
