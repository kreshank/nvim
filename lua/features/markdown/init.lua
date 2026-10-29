local M = {}
local defaults = require("features.markdown.defaults")

function M.setup()
  require("features.markdown.code").setup()
  require("features.markdown.preview").setup()
  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("MarkdownEditing", { clear = true }),
    pattern = "markdown",
    callback = function(ev)
      vim.opt_local.conceallevel = 2
      vim.opt_local.concealcursor = "nc"
      local function map(key, command, desc)
        vim.keymap.set("n", key, "<cmd>" .. command .. "<cr>", { buffer = ev.buf, desc = desc })
      end
      map(defaults.keys.preview, "MarkdownPreviewToggle", "Markdown browser preview")
      map(defaults.keys.equation, "RenderLatex equation_toggle", "Toggle equation source")
      map(defaults.keys.health, "RenderLatex doctor", "Check math rendering")
    end,
  })
end

return M
