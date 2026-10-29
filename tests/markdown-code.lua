-- nvim --headless -u NONE -l tests/markdown-code.lua
vim.opt.rtp:prepend(vim.fn.getcwd())
require("features.markdown.code").setup()
vim.cmd("syntax enable")
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  "Before", "```python", "print(123)", "```", "Between",
  "~~~~lua", "local value = 42", "~~~~", "After",
  "```unknown", "literal", "", -- unclosed block
})
vim.bo.filetype = "markdown"
vim.wo.conceallevel = 2
vim.wo.concealcursor = "nc"
local code = require("features.markdown.code")
local function concealed_rows(win)
  local rows = {}
  for _, match in ipairs(vim.fn.getmatches(win)) do
    for i = 1, 8 do
      if match["pos" .. i] then rows[match["pos" .. i][1]] = true end
    end
  end
  return rows
end
local win = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_cursor(win, { 1, 0 })
code.refresh()
assert(vim.deep_equal(concealed_rows(win), { [2]=true, [4]=true, [6]=true, [8]=true, [10]=true }))
vim.api.nvim_win_set_cursor(win, { 3, 0 })
code.refresh()
assert(vim.deep_equal(concealed_rows(win), { [6]=true, [8]=true, [10]=true }), "both fences reveal inside code")
vim.api.nvim_win_set_cursor(win, { 4, 0 })
code.refresh()
assert(not concealed_rows(win)[2], "closing fence is part of active block")
assert(vim.fn.synIDattr(vim.fn.synID(3, 7, 1), "name"):match("python"), "Python number is syntax-highlighted")
assert(vim.fn.synIDattr(vim.fn.synID(7, 1, 1), "name"):match("lua"), "Lua keyword is syntax-highlighted")
vim.cmd.vsplit()
local second = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_cursor(second, { 9, 0 })
code.refresh()
assert(concealed_rows(second)[2] and not concealed_rows(win)[2], "split windows have independent conceal")
vim.api.nvim_win_set_cursor(second, { 11, 0 })
code.refresh()
assert(not concealed_rows(second)[10], "unclosed block reveals its opening fence")
vim.api.nvim_buf_set_lines(buf, 1, 4, false, { "ordinary paragraph" })
code.refresh()
assert(not concealed_rows(second)[2], "editing reparses fences")
print("Markdown fence visibility, split windows, edits, and syntax highlighting passed")
