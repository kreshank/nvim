return {
  "nvim-tree/nvim-tree.lua",
  version = "*",
  lazy = false,
  dependencies = {
    "nvim-tree/nvim-web-devicons",
    "nvim-telescope/telescope.nvim",
    "nvim-lua/plenary.nvim",
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

    require("nvim-tree").setup({
      on_attach = function(bufnr)
        api.config.mappings.default_on_attach(bufnr)

        -- Tab
        vim.keymap.set('n', '<leader>t', api.node.open.tab, {
          desc = 'nvim-tree: Open in New Tab', 
          buffer = bufnr,
          noremap = true,
          silent = true,
          nowait = true
        })
        -- Splits
        vim.keymap.set('n', '<leader>v', api.node.open.vertical, {
          desc = 'nvim-tree: Open vertical split',
          buffer = bufnr,
          noremap = true,
          silent = true,
          nowait = true
        })
        vim.keymap.set('n', '<leader>h', api.node.open.horizontal, {
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
    git = {
      enable = true,
      ignore = false,
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
      update_cwd = true,
    },
    actions = {
      open_file = {
        quit_on_open = true,
      },
    },
  })
end,
}
