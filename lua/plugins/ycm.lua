return {
  {
    "ycm-core/YouCompleteMe",
    lazy = false,   -- load immediately
    build = nil,    -- do not rebuild; use your manual build
    config = function()
      -- Use clangd for C++ projects
      vim.g.ycm_use_clangd = 1

      -- Python interpreter path (adjust per environment)
      vim.g.ycm_python_binary_path = "/usr/bin/python3"

      -- Disable extra conf prompt
      vim.g.ycm_confirm_extra_conf = 0

      -- Enable identifier suggestions
      vim.g.ycm_seed_identifiers_with_suggestions = 1
    end,
  },
}
