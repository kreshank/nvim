-- lua/diffview.lua
return {
  "sindrets/diffview.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
  cmd = { "DiffviewOpen", "DiffviewFileHistory" },
  config = function()
    local ok, diffview = pcall(require, "diffview")
    if not ok then return end

    diffview.setup({
      enhanced_diff_hl = true,
      use_icons = true,
    })

    -- Automatically link Diffview highlights to your colorscheme
    vim.api.nvim_create_autocmd("ColorScheme", {
      callback = function()
        -- General background
        vim.cmd("hi link DiffviewNormal Normal")
        -- File panel
        vim.cmd("hi link DiffviewFilePanelTitle Directory")
        vim.cmd("hi link DiffviewFilePanelCounter Comment")
        vim.cmd("hi link DiffviewFilePanelPath Comment")
        vim.cmd("hi link DiffviewFilePanelRoot FolderName")
        -- Git states
        vim.cmd("hi link DiffviewFilePanelModified DiffAdd")
        vim.cmd("hi link DiffviewFilePanelAdded DiffAdd")
        vim.cmd("hi link DiffviewFilePanelDeleted DiffDelete")
        vim.cmd("hi link DiffviewFilePanelRenamed DiffChange")
        vim.cmd("hi link DiffviewFilePanelCopied DiffChange")
        vim.cmd("hi link DiffviewFilePanelUntracked DiffText")
        vim.cmd("hi link DiffviewFilePanelStaged DiffChange")
        vim.cmd("hi link DiffviewFilePanelConflicted DiffText")
        -- Diff view area
        vim.cmd("hi link DiffviewDiffAdd DiffAdd")
        vim.cmd("hi link DiffviewDiffDelete DiffDelete")
        vim.cmd("hi link DiffviewDiffChange DiffChange")
      end
    })

    -- Also run once immediately so highlights are correct on startup
    vim.cmd("doautocmd ColorScheme")
  end,
}
