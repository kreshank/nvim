return {
  "nvim-tree/nvim-tree.lua",
  version = "*",
  lazy = false,
  dependencies = {
    "nvim-tree/nvim-web-devicons",
    "nvim-telescope/telescope.nvim",
    "nvim-lua/plenary.nvim",
  },
  keys = {
    {
      "<leader>e",
      "<cmd>NvimTreeToggle<CR>",
      desc = "Toggle file explorer",
    },
  },
  config = function()
    local api = require("nvim-tree.api")
    local telescope = require("telescope.builtin")

    local function preview_file()
      local node = api.tree.get_node_under_cursor()
      if not node or node.type == "directory" then return end

      telescope.find_files({
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
      if path and require("config.remote").is_mount_path(path) then
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

    require("nvim-tree").setup({
      on_attach = function(bufnr)
        api.config.mappings.default_on_attach(bufnr)

        vim.keymap.set("n", "<CR>", function()
          open_tree_node("edit")
        end, {
          desc = "nvim-tree: Open",
          buffer = bufnr,
          noremap = true,
          silent = true,
          nowait = true,
        })
        vim.keymap.set("n", "o", function()
          open_tree_node("edit")
        end, {
          desc = "nvim-tree: Open",
          buffer = bufnr,
          noremap = true,
          silent = true,
          nowait = true,
        })
        vim.keymap.set("n", "<2-LeftMouse>", function()
          open_tree_node("edit")
        end, {
          desc = "nvim-tree: Open",
          buffer = bufnr,
          noremap = true,
          silent = true,
          nowait = true,
        })

        -- Tab
        vim.keymap.set('n', '<leader>t', function()
          open_tree_node("tabnew")
        end, {
          desc = 'nvim-tree: Open in New Tab',
          buffer = bufnr,
          noremap = true,
          silent = true,
          nowait = true
        })
        vim.keymap.set('n', '<leader>v', function()
          open_tree_node("vsplit")
        end, {
          desc = 'nvim-tree: Open vertical split',
          buffer = bufnr,
          noremap = true,
          silent = true,
          nowait = true
        })
        vim.keymap.set('n', '<leader>h', function()
          open_tree_node("split")
        end, {
          desc = 'nvim-tree: Open horizontal split',
          buffer = bufnr,
          noremap = true,
          silent = true,
          nowait = true
        })
        -- Preview
        vim.keymap.set("n", "<leader>p", preview_file, {
          desc = 'nvim-tree: Preview file with Telescope',
          buffer = bufnr,
          noremap = true,
          silent = true,
          nowait = true
        })
        -- Diffview
        vim.keymap.set('n', '<leader>gd', function()
          local node = api.tree.get_node_under_cursor()
          if node and node.absolute_path then
            vim.cmd("DiffviewFileHistory " .. node.absolute_path)
          end
        end, {
          desc = 'nvim-tree: Open Diffview for file',
          buffer = bufnr,
          noremap = true,
          silent = true,
          nowait = true
        })
    end,
    sync_root_with_cwd = true,
    git = {
      enable = true,
      timeout = 400,
      disable_for_dirs = function(path)
        return require("config.remote").should_disable_tree_git(path)
      end,
    },
    filters = {
      git_ignored = false,
    },
    filesystem_watchers = {
      enable = true,
      ignore_dirs = function(path)
        if require("config.remote").is_mount_path(path) then
          return true
        end
        local name = vim.fn.fnamemodify(path, ":t")
        return name == "node_modules"
          or name == ".git"
          or name == ".cache"
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
end,
}
