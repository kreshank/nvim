local defaults = require("features.tex.defaults")

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

  if vim.b[bufnr].tex_autosave == false then return end

  if not vim.bo[bufnr].modifiable or not vim.bo[bufnr].modified then
    return
  end

  if save_timers[bufnr] then
    save_timers[bufnr]:stop()
    save_timers[bufnr]:close()
  end

  local timer = vim.uv.new_timer()
  save_timers[bufnr] = timer

  timer:start(defaults.autosave_ms, 0, vim.schedule_wrap(function()
    if save_timers[bufnr] == timer then
      save_timers[bufnr] = nil
    end

    pcall(function()
      timer:close()
    end)

    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end

    if vim.b[bufnr].tex_autosave ~= false and vim.bo[bufnr].modifiable and vim.bo[bufnr].modified then
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

-- Buffer-local controls; texlab resolves included files and build directories.
vim.api.nvim_create_autocmd("FileType", {
  group = group,
  pattern = { "tex", "plaintex", "bib" },
  callback = function(ev)
    local function map(key, action, desc)
      vim.keymap.set("n", key, action, { buffer = ev.buf, desc = desc })
    end
    local function command(name, save)
      return function()
        if vim.fn.exists(":" .. name) ~= 2 then
          vim.notify("texlab is not attached to this buffer", vim.log.levels.WARN)
          return
        end
        if save then vim.cmd.update() end
        vim.cmd(name)
      end
    end
    map(defaults.keys.build, command("LspTexlabBuild", true), "Build LaTeX")
    map(defaults.keys.forward, command("LspTexlabForward"), "SyncTeX to PDF")
    map(defaults.keys.view, command("LspTexlabForward"), "Open project PDF at cursor")
    map(defaults.keys.cancel, command("LspTexlabCancelBuild"), "Cancel LaTeX build")
    map(defaults.keys.errors, function()
      vim.diagnostic.setloclist({ open = true })
    end, "LaTeX diagnostics")
    map(defaults.keys.autosave, function()
      vim.b[ev.buf].tex_autosave = vim.b[ev.buf].tex_autosave == false
      vim.notify("TeX autosave " .. (vim.b[ev.buf].tex_autosave and "on" or "off"))
    end, "Toggle TeX autosave")
  end,
})
