local M = {}
local defaults = require("features.markdown.defaults")
local directory = vim.fn.stdpath("config") .. "/lua/features/markdown/browser"
local job, buffer, pending_fragment, starting, session_root
local stopped = false
local receive = ""

local function project_root(name)
  local remote = require("features.remote").project_for_path(name)
  return remote and remote.mount_path
    or vim.fs.root(name, { ".git", ".hg", "package.json", "mkdocs.yml" })
    or vim.fs.dirname(name)
end

function M.update()
  if not job or not buffer or not vim.api.nvim_buf_is_valid(buffer) then return end
  local name = vim.api.nvim_buf_get_name(buffer)
  if not session_root or (name ~= session_root and not vim.startswith(name, session_root .. "/")) then
    session_root = project_root(name)
  end
  local payload = {
    path = name,
    root = session_root,
    source = table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n"),
    fragment = pending_fragment,
    sync_navigation = defaults.sync_navigation,
  }
  vim.fn.chansend(job, vim.json.encode(payload) .. "\n")
end

local function show_buffer(path, line)
  local target = vim.fn.bufnr(path)
  if target < 0 then target = vim.fn.bufadd(path) end
  vim.fn.bufload(target)
  -- Prefer the existing Markdown window, avoiding a terminal or unrelated split.
  local window = buffer and vim.fn.bufwinid(buffer) or -1
  if window == -1 then window = vim.api.nvim_get_current_win() end
  local ok, err = pcall(vim.api.nvim_win_set_buf, window, target)
  if not ok then vim.notify(tostring(err), vim.log.levels.WARN); return false end
  vim.api.nvim_set_current_win(window)
  buffer = target
  if line then
    line = math.min(line, vim.api.nvim_buf_line_count(target))
    vim.api.nvim_win_set_cursor(window, { line, 0 })
    vim.cmd("normal! zvzz")
  end
  return true
end

local function message(data)
  if data.event == "ready" then
    M.update()
    local _, err = vim.ui.open(data.url)
    if err then vim.notify(err, vim.log.levels.ERROR) end
  elseif data.event == "navigate" then
    if show_buffer(data.path) then
      pending_fragment = data.fragment
      M.update()
    end
  elseif data.event == "jump" then
    if data.sync ~= false then show_buffer(data.path, data.line) end
    if pending_fragment then
      pending_fragment = nil
      M.update()
    end
  elseif data.event == "error" then
    vim.notify("Markdown preview: " .. data.message, vim.log.levels.ERROR)
  end
end

function M.stop()
  stopped = true
  if job then vim.fn.jobstop(job) end
  job, buffer, session_root = nil, nil, nil
end

local function launch()
  receive = ""
  local stderr = {}
  local id
  id = vim.fn.jobstart({ "node", directory .. "/server.mjs" }, {
    on_stdout = function(_, lines)
      receive = receive .. table.concat(lines, "\n")
      while true do
        local at = receive:find("\n", 1, true)
        if not at then break end
        local raw = receive:sub(1, at - 1)
        receive = receive:sub(at + 1)
        local ok, data = pcall(vim.json.decode, raw)
        if ok then vim.schedule(function() if job == id then message(data) end end) end
      end
    end,
    on_stderr = function(_, lines)
      for _, line in ipairs(lines) do if line ~= "" then table.insert(stderr, line) end end
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        if job ~= id then return end
        job = nil
        if code ~= 0 then
          vim.notify("Markdown preview failed: " .. table.concat(stderr, "\n"), vim.log.levels.ERROR)
        end
      end)
    end,
  })
  if id <= 0 then vim.notify("Could not start Markdown preview", vim.log.levels.ERROR); return end
  job = id
end

function M.start()
  if job then M.update(); return end
  if starting then return end
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].filetype ~= "markdown" or vim.api.nvim_buf_get_name(buf) == "" then
    vim.notify("Open a named Markdown file first", vim.log.levels.WARN)
    return
  end
  if vim.fn.executable("node") ~= 1 then
    vim.notify("Markdown preview requires Node.js 22.12+ and npm", vim.log.levels.ERROR)
    return
  end
  buffer = buf
  stopped = false
  if vim.fn.filereadable(directory .. "/node_modules/markdown-it/package.json") == 1 then
    launch()
  elseif vim.fn.executable("npm") == 1 then
    starting = true
    vim.notify("Installing Markdown preview dependencies…")
    vim.system({ "npm", "ci", "--omit=dev", "--no-audit", "--no-fund" }, { cwd = directory, text = true }, function(result)
      vim.schedule(function()
        starting = false
        if result.code == 0 and not stopped then launch()
        elseif result.code == 0 then return
        else vim.notify(result.stderr or "npm install failed", vim.log.levels.ERROR) end
      end)
    end)
  else
    vim.notify("Install npm, then retry MarkdownPreview", vim.log.levels.ERROR)
  end
end

function M.setup()
  vim.api.nvim_create_user_command("MarkdownPreview", M.start, {})
  vim.api.nvim_create_user_command("MarkdownPreviewStop", M.stop, {})
  vim.api.nvim_create_user_command("MarkdownPreviewToggle", function()
    if job then M.stop() else M.start() end
  end, {})
  local group = vim.api.nvim_create_augroup("MarkdownBrowserPreview", { clear = true })
  local generation = 0
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufWritePost", "BufEnter" }, {
    group = group,
    callback = function(ev)
      if not job or vim.bo[ev.buf].filetype ~= "markdown" then return end
      buffer = ev.buf
      generation = generation + 1
      local current = generation
      vim.defer_fn(function() if current == generation then M.update() end end, 100)
    end,
  })
  vim.api.nvim_create_autocmd("VimLeavePre", { group = group, callback = M.stop })
end

return M
