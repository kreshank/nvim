local M = {}
local cache, matches = {}, {}
local query

local function blocks(buf)
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  if cache[buf] and cache[buf].tick == tick then return cache[buf].blocks end
  local ok, parser = pcall(vim.treesitter.get_parser, buf, "markdown")
  if not ok then return {} end
  query = query or vim.treesitter.query.parse("markdown", "(fenced_code_block) @block")
  local result = {}
  for _, node in query:iter_captures(parser:parse()[1]:root(), buf) do
    local first, _, last, end_col = node:range()
    local block = { first = first, last = last - (end_col == 0 and 1 or 0), fences = {} }
    for child in node:iter_children() do
      if child:type() == "fenced_code_block_delimiter" then
        local row, col = child:range()
        local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
        -- Hide the fence and its language label, preserving list/quote prefixes.
        table.insert(block.fences, { row + 1, col + 1, #line - col })
      end
    end
    table.insert(result, block)
  end
  cache[buf] = { tick = tick, blocks = result }
  return result
end

local function clear(win)
  for _, id in ipairs(matches[win] or {}) do pcall(vim.fn.matchdelete, id, win) end
  matches[win] = nil
end

function M.refresh()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    clear(win)
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == "markdown" then
      local row = vim.api.nvim_win_get_cursor(win)[1] - 1
      local positions = {}
      for _, block in ipairs(blocks(buf)) do
        if row < block.first or row > block.last then
          vim.list_extend(positions, block.fences)
        end
      end
      -- Window-local matches keep independent cursors correct in split views.
      -- matchaddpos accepts at most eight positions per match.
      matches[win] = {}
      for i = 1, #positions, 8 do
        local batch = vim.list_slice(positions, i, math.min(i + 7, #positions))
        table.insert(matches[win], vim.fn.matchaddpos("Conceal", batch, 20, -1, {
          window = win, conceal = "",
        }))
      end
    end
  end
end

function M.setup()
  local defaults = require("features.markdown.defaults")
  vim.g.markdown_fenced_languages = defaults.code_languages
  -- The syntax file's unconditional concealends would also hide active fences.
  vim.g.markdown_syntax_conceal = 0
  local group = vim.api.nvim_create_augroup("MarkdownCodeFences", { clear = true })
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "TextChanged", "TextChangedI", "BufWinEnter", "WinEnter", "FileType" }, {
    group = group,
    callback = M.refresh,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(ev) cache[ev.buf] = nil end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(ev) matches[tonumber(ev.match)] = nil end,
  })
end

return M
