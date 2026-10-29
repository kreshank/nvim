-- Run: nvim --headless -u init.lua -l tests/git.lua
vim.o.lines = 80
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
local function git(...)
  local cmd = { "git", "-C", root }
  vim.list_extend(cmd, { ... })
  local result = vim.system(cmd, { text = true }):wait()
  assert(result.code == 0, result.stderr)
end
local function wait_for(callback, reason)
  assert(vim.wait(5000, callback, 20), reason)
end
local ok, err = pcall(function()
  git("init", "--quiet")
  local baseline = {}
  for i = 1, 18 do baseline[i] = "original line " .. i end
  local path = root .. "/tracked.txt"
  vim.fn.writefile(baseline, path)
  git("add", "tracked.txt")
  git("-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "--quiet", "-m", "fixture")
  vim.cmd.edit(path)
  local buf = vim.api.nvim_get_current_buf()
  local gs = require("gitsigns")
  wait_for(function() return vim.b[buf].gitsigns_head ~= nil end, "tracked file did not attach")
  -- Unsaved edits: one changed, one deleted, and one added line.
  vim.api.nvim_buf_set_lines(buf, 2, 3, false, { "changed text" })
  vim.api.nvim_buf_set_lines(buf, 9, 10, false, {})
  vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "added text" })
  wait_for(function()
    local status = vim.b[buf].gitsigns_status_dict or {}
    return status.added == 1 and status.changed == 1 and status.removed == 1
  end, "unsaved added/changed/deleted lines were not detected")
  wait_for(function()
    vim.cmd.redraw()
    local signs = {}
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })) do
      if mark[4].sign_text then signs[vim.trim(mark[4].sign_text)] = true end
    end
    return signs["+"] and signs["~"] and signs["_"]
  end, "expected Git gutter signs")
  assert(vim.fn.maparg("<leader>gp", "n") ~= "", "preview key is missing")
  vim.api.nvim_win_set_cursor(0, { 3, 0 })
  gs.preview_hunk_inline()
  wait_for(function()
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })) do
      if mark[4].virt_lines then return true end
    end
    return false
  end, "removed lines did not appear inline")
  -- The file-wide toggle shows deletions from multiple hunks in one window.
  local function removed_text()
    vim.cmd.redraw()
    local text = {}
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })) do
      for _, line in ipairs(mark[4].virt_lines or {}) do
        for _, chunk in ipairs(line) do text[#text + 1] = chunk[1] end
      end
    end
    return table.concat(text)
  end
  local windows = #vim.api.nvim_list_wins()
  local toggle = vim.fn.maparg("<leader>gD", "n", false, true).callback
  toggle()
  wait_for(function()
    local text = removed_text()
    return text:find("original line 3", 1, true) and text:find("original line 10", 1, true)
  end, "file-wide inline diff did not show all removed text")
  assert(#vim.api.nvim_list_wins() == windows, "inline toggle opened another window")
  toggle()
  wait_for(function()
    return not removed_text():find("original line 10", 1, true)
  end, "file-wide inline diff did not toggle off")
  -- New files should also attach and show additions.
  vim.fn.writefile({ "new file" }, root .. "/new.txt")
  vim.cmd.edit(root .. "/new.txt")
  local untracked = vim.api.nvim_get_current_buf()
  wait_for(function()
    local status = vim.b[untracked].gitsigns_status_dict or {}
    return status.added == 1
  end, "untracked file did not show additions")
end)
vim.cmd("silent! %bwipeout!")
vim.fn.delete(root, "rf")
assert(ok, err)
print("Git signs, unsaved changes, inline deleted lines, and untracked files passed")
