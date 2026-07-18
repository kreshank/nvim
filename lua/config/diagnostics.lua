local severity_names = {
  [vim.diagnostic.severity.ERROR] = "error",
  [vim.diagnostic.severity.WARN] = "warning",
  [vim.diagnostic.severity.INFO] = "info",
  [vim.diagnostic.severity.HINT] = "hint",
}

local severity_highlights = {
  [vim.diagnostic.severity.ERROR] = "DiagnosticError",
  [vim.diagnostic.severity.WARN] = "DiagnosticWarn",
  [vim.diagnostic.severity.INFO] = "DiagnosticInfo",
  [vim.diagnostic.severity.HINT] = "DiagnosticHint",
}

local function same_diagnostic(a, b)
  return a.namespace == b.namespace
    and a.lnum == b.lnum
    and a.col == b.col
    and a.end_lnum == b.end_lnum
    and a.end_col == b.end_col
    and a.severity == b.severity
    and a.message == b.message
end

local function diagnostic_contains_position(diagnostic, line, col)
  local start_line = diagnostic.lnum
  local start_col = diagnostic.col

  local end_line =
    diagnostic.end_lnum or start_line

  local end_col =
    diagnostic.end_col or start_col

  if line < start_line or line > end_line then
    return false
  end

  if start_line == end_line then
    if end_col <= start_col then
      return line == start_line and col == start_col
    end

    return line == start_line
      and col >= start_col
      and col < end_col
  end

  if line == start_line then
    return col >= start_col
  end

  if line == end_line then
    return col < end_col
  end

  return true
end

local function sort_diagnostics(diagnostics)
  table.sort(diagnostics, function(a, b)
    if a.col ~= b.col then
      return a.col < b.col
    end

    local a_end_col = a.end_col or a.col
    local b_end_col = b.end_col or b.col

    if a_end_col ~= b_end_col then
      return a_end_col < b_end_col
    end

    local a_severity =
      a.severity or vim.diagnostic.severity.ERROR

    local b_severity =
      b.severity or vim.diagnostic.severity.ERROR

    if a_severity ~= b_severity then
      return a_severity < b_severity
    end

    return a.message < b.message
  end)
end

local function selected_line_diagnostic()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)

  local line = cursor[1] - 1
  local col = cursor[2]

  local diagnostics = vim.diagnostic.get(bufnr, {
    lnum = line,
  })

  if #diagnostics == 0 then
    return nil, nil
  end

  sort_diagnostics(diagnostics)

  for index, diagnostic in ipairs(diagnostics) do
    if diagnostic_contains_position(diagnostic, line, col) then
      return diagnostic, index
    end
  end

  return diagnostics[1], 1
end

local function diagnostic_float_width()
  local window_width = vim.api.nvim_win_get_width(0)

  local minimum_visible_code = 40
  local preferred_max_width = 80
  local minimum_float_width = 20

  return math.max(
    minimum_float_width,
    math.min(
      preferred_max_width,
      window_width - minimum_visible_code
    )
  )
end

vim.diagnostic.config({
  virtual_text = {
    current_line = true,
    spacing = 2,
    source = false,

    format = function(diagnostic)
      local selected, index =
        selected_line_diagnostic()

      if
        not selected
        or not same_diagnostic(diagnostic, selected)
      then
        return nil
      end

      local severity =
        diagnostic.severity
        or vim.diagnostic.severity.ERROR

      local severity_name =
        severity_names[severity] or "diagnostic"

      return string.format(
        "%d [%s] %s",
        index,
        severity_name,
        diagnostic.message
      )
    end,
  },

  underline = true,
  signs = true,
  update_in_insert = false,
  severity_sort = true,

  float = {
    border = "rounded",
    source = "if_many",
    focusable = true,
    wrap = true,
  },
})

local refresh_group = vim.api.nvim_create_augroup(
  "CursorDiagnosticVirtualText",
  {
    clear = true,
  }
)

vim.api.nvim_create_autocmd({
  "CursorMoved",
  "CursorMovedI",
}, {
  group = refresh_group,

  callback = function(event)
    if not vim.api.nvim_buf_is_valid(event.buf) then
      return
    end

    vim.diagnostic.show(nil, event.buf)
  end,
})

-- Show all diagnostics on the current line in a numbered floating window.
vim.keymap.set("n", "gl", function()
  vim.diagnostic.open_float({
    scope = "line",
    focusable = true,
    border = "rounded",
    source = "if_many",
    header = "Diagnostics:",
    max_width = diagnostic_float_width(),
    wrap = true,

    prefix = function(diagnostic, index)
      local severity =
        diagnostic.severity
        or vim.diagnostic.severity.ERROR

      return string.format("%d. ", index),
        severity_highlights[severity]
    end,
  })
end, {
  desc = "Show line diagnostics",
})

-- Navigate all diagnostics.
vim.keymap.set("n", "]d", function()
  vim.diagnostic.jump({
    count = 1,
    float = true,
  })
end, {
  desc = "Next diagnostic",
})

vim.keymap.set("n", "[d", function()
  vim.diagnostic.jump({
    count = -1,
    float = true,
  })
end, {
  desc = "Previous diagnostic",
})

-- Navigate errors only.
vim.keymap.set("n", "]e", function()
  vim.diagnostic.jump({
    count = 1,
    severity = vim.diagnostic.severity.ERROR,
    float = true,
  })
end, {
  desc = "Next error",
})

vim.keymap.set("n", "[e", function()
  vim.diagnostic.jump({
    count = -1,
    severity = vim.diagnostic.severity.ERROR,
    float = true,
  })
end, {
  desc = "Previous error",
})

-- Open all diagnostics for the current buffer in the location list.
vim.keymap.set("n", "<leader>dl", function()
  vim.diagnostic.setloclist({
    open = true,
    title = "Buffer diagnostics",
  })
end, {
  desc = "List buffer diagnostics",
})
