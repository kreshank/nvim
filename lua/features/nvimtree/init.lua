local defaults = require("features.nvimtree.defaults")

local M = {}

local function map(bufnr, lhs, rhs, desc)
  vim.keymap.set("n", lhs, rhs, {
    desc = desc,
    buffer = bufnr,
    noremap = true,
    silent = true,
    nowait = true,
  })
end

local function preview_file()
  local api = require("nvim-tree.api")
  local node = api.tree.get_node_under_cursor()

  if not node or node.type == "directory" then
    return
  end

  require("telescope.builtin").find_files({
    prompt_title = "Preview",
    cwd = vim.fn.fnamemodify(node.absolute_path, ":h"),
    default_text = node.name,
  })
end

-- Open SSHFS files in a real editor window via nvim-tree's opener.
-- `:edit` in the tree window + tree.close() discarded the buffer
-- with no message. Use absolute_path so symlink link_to (a remote
-- /home/ryan/... path) is never opened on the laptop.
local function open_tree_node(mode)
  local api = require("nvim-tree.api")

  mode = mode or "edit"
  local node = api.tree.get_node_under_cursor()

  if not node then
    return
  end

  if node.type == "directory" or node.type == "directory_link" then
    api.node.open.edit()
    return
  end

  local path = node.absolute_path

  if path and require("features.remote").is_mount_path(path) then
    require("nvim-tree.actions.node.open-file").fn(mode, path)
    return
  end

  if mode == "tabnew" then
    api.node.open.tab()
  elseif mode == "vsplit" then
    api.node.open.vertical()
  elseif mode == "split" then
    api.node.open.horizontal()
  else
    api.node.open.edit()
  end
end

local function on_attach(bufnr)
  local api = require("nvim-tree.api")
  local keys = defaults.keys

  api.config.mappings.default_on_attach(bufnr)

  for _, lhs in ipairs(keys.open) do
    map(bufnr, lhs, function()
      open_tree_node("edit")
    end, "nvim-tree: Open")
  end

  map(bufnr, keys.tab, function()
    open_tree_node("tabnew")
  end, "nvim-tree: Open in New Tab")

  map(bufnr, keys.vsplit, function()
    open_tree_node("vsplit")
  end, "nvim-tree: Open vertical split")

  map(bufnr, keys.split, function()
    open_tree_node("split")
  end, "nvim-tree: Open horizontal split")

  map(bufnr, keys.preview, preview_file, "nvim-tree: Preview file with Telescope")

  map(bufnr, keys.diff, function()
    local node = api.tree.get_node_under_cursor()

    if node and node.absolute_path then
      vim.cmd("DiffviewFileHistory " .. node.absolute_path)
    end
  end, "nvim-tree: Open Diffview for file")
end

function M.setup()
  vim.keymap.set("n", defaults.keys.toggle, "<cmd>NvimTreeToggle<CR>", {
    desc = "Toggle file explorer",
  })

  require("nvim-tree").setup({
    on_attach = on_attach,
    sync_root_with_cwd = true,
    git = {
      enable = true,
      timeout = defaults.git_timeout_ms,
      disable_for_dirs = function(path)
        return require("features.remote").should_disable_tree_git(path)
      end,
    },
    filters = {
      git_ignored = false,
    },
    filesystem_watchers = {
      enable = true,
      ignore_dirs = function(path)
        if require("features.remote").is_mount_path(path) then
          return true
        end

        return defaults.watcher_ignore[vim.fn.fnamemodify(path, ":t")]
          or false
      end,
    },
    renderer = {
      highlight_git = true,
      root_folder_modifier = ":t",
      icons = {
        show = {
          git = true,
          folder = true,
          file = true,
        },
        glyphs = {
          default = "",
          symlink = "",
          git = {
            unstaged = "M",
            staged = "S",
            renamed = "R",
            untracked = "",
            deleted = "D",
            ignored = "I",
          },
          folder = {
            default = "",
            open = "",
            empty = "",
            empty_open = "",
            symlink = "",
          },
        },
      },
    },
    update_focused_file = {
      enable = true,
      update_root = false,
    },
    actions = {
      open_file = {
        quit_on_open = true,
        -- Relative paths break :edit on SSHFS when cwd is not the mount.
        relative_path = false,
      },
    },
  })
end

return M
