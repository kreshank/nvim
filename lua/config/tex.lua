local group = vim.api.nvim_create_augroup("TexPreview", {
  clear = true,
})

-- Debounced autosave so texlab's build.onSave keeps the PDF fresh
-- without rebuilding on every keystroke.
local save_timers = {}

local function schedule_tex_save(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  if not vim.bo[bufnr].modifiable or not vim.bo[bufnr].modified then
    return
  end

  if save_timers[bufnr] then
    save_timers[bufnr]:stop()
    save_timers[bufnr]:close()
  end

  local timer = vim.uv.new_timer()
  save_timers[bufnr] = timer

  timer:start(1000, 0, vim.schedule_wrap(function()
    if save_timers[bufnr] == timer then
      save_timers[bufnr] = nil
    end

    pcall(function()
      timer:close()
    end)

    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end

    if vim.bo[bufnr].modifiable and vim.bo[bufnr].modified then
      vim.api.nvim_buf_call(bufnr, function()
        vim.cmd("silent! update")
      end)
    end
  end))
end

vim.api.nvim_create_autocmd({
  "InsertLeave",
  "TextChanged",
  "TextChangedI",
}, {
  group = group,
  pattern = {
    "*.tex",
    "*.bib",
  },

  callback = function(event)
    schedule_tex_save(event.buf)
  end,
})

vim.api.nvim_create_autocmd("BufUnload", {
  group = group,
  pattern = {
    "*.tex",
    "*.bib",
  },

  callback = function(event)
    local timer = save_timers[event.buf]

    if timer then
      timer:stop()
      timer:close()
      save_timers[event.buf] = nil
    end
  end,
})

vim.keymap.set("n", "<leader>lb", "<cmd>LspTexlabBuild<cr>", {
  desc = "Build LaTeX (texlab)",
})

vim.keymap.set("n", "<leader>lv", function()
  local tex = vim.api.nvim_buf_get_name(0)

  if tex == "" then
    vim.notify("No file name", vim.log.levels.WARN)
    return
  end

  local pdf = tex:gsub("%.tex$", ".pdf")

  if vim.fn.filereadable(pdf) == 0 then
    vim.notify("PDF not found: " .. pdf, vim.log.levels.WARN)
    return
  end

  if vim.fn.executable("zathura") == 0 then
    vim.notify(
      "zathura not found; install with: sudo apt install zathura zathura-pdf-poppler",
      vim.log.levels.ERROR
    )
    return
  end

  vim.fn.jobstart({ "zathura", pdf }, {
    detach = true,
  })
end, {
  desc = "Open LaTeX PDF in Zathura",
})

vim.keymap.set("n", "<leader>lf", "<cmd>LspTexlabForward<cr>", {
  desc = "Forward search to Zathura",
})
