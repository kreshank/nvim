local defaults = require("config.defaults")

local function get_formatters(bufnr)
  return vim.lsp.get_clients({
    bufnr = bufnr,
    method = "textDocument/formatting",
  })
end

local function formatter_names(clients)
  local names = {}

  for _, client in ipairs(clients) do
    table.insert(names, client.name)
  end

  table.sort(names)

  return table.concat(names, ", ")
end

local function select_formatter(bufnr)
  local filetype = vim.bo[bufnr].filetype
  local preferred = defaults.format.clients[filetype]
  local clients = get_formatters(bufnr)

  if #clients == 0 then
    return nil, string.format(
      "No formatter is attached for filetype %q",
      filetype
    )
  end

  if preferred then
    for _, client in ipairs(clients) do
      if client.name == preferred then
        return client
      end
    end

    return nil, string.format(
      "Preferred formatter %q is unavailable. Available: %s",
      preferred,
      formatter_names(clients)
    )
  end

  if #clients == 1 then
    return clients[1]
  end

  return nil, string.format(
    "Multiple formatters are available for %q: %s",
    filetype,
    formatter_names(clients)
  )
end

vim.api.nvim_create_user_command("Format", function()
  local bufnr = vim.api.nvim_get_current_buf()

  if vim.bo[bufnr].buftype ~= "" then
    vim.notify(
      "Cannot format a special buffer",
      vim.log.levels.WARN
    )
    return
  end

  if not vim.bo[bufnr].modifiable then
    vim.notify(
      "Current buffer is not modifiable",
      vim.log.levels.WARN
    )
    return
  end

  local client, err = select_formatter(bufnr)

  if not client then
    vim.notify(err or "", vim.log.levels.WARN)
    return
  end

  local ok, format_err = pcall(vim.lsp.buf.format, {
    bufnr = bufnr,
    id = client.id,
    async = false,
    timeout_ms = defaults.format.timeout_ms,
  })

  if not ok then
    vim.notify(
      string.format(
        "Formatting with %s failed: %s",
        client.name,
        format_err
      ),
      vim.log.levels.ERROR
    )
    return
  end

  vim.notify(
    "Formatted with " .. client.name,
    vim.log.levels.INFO
  )
end, {
  desc = "Format the current buffer",
})

vim.api.nvim_create_user_command("FormatInfo", function()
  local bufnr = vim.api.nvim_get_current_buf()
  local filetype = vim.bo[bufnr].filetype
  local preferred = defaults.format.clients[filetype]
  local clients = get_formatters(bufnr)

  vim.notify(
    table.concat({
      "Filetype: " .. filetype,
      "Preferred: " .. (preferred or "not configured"),
      "Available: "
      .. (#clients > 0 and formatter_names(clients) or "none"),
    }, "\n"),
    vim.log.levels.INFO
  )
end, {
  desc = "Show available formatters for the current buffer",
})
