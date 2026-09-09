return {
  "barreiroleo/ltex_extra.nvim",
  event = "VeryLazy",
  dependencies = {
    "neovim/nvim-lspconfig",
  },

  opts = {
    load_langs = { "en-US" },
    -- Do not reload until ltex_plus is attached; catch_ltex errors otherwise.
    init_check = false,
    path = vim.fn.stdpath("data") .. "/ltex",
    server_start = false,
  },

  config = function(_, opts)
    -- Registers client commands (_ltex.addToDictionary, etc.).
    require("ltex_extra").setup(opts)

    vim.api.nvim_create_autocmd("LspAttach", {
      group = vim.api.nvim_create_augroup("LtexExtra", {
        clear = true,
      }),

      callback = function(event)
        local client =
          vim.lsp.get_client_by_id(event.data.client_id)

        if not client or client.name ~= "ltex_plus" then
          return
        end

        vim.api.nvim_buf_call(event.buf, function()
          require("ltex_extra").reload({ "en-US" })
        end)
      end,
    })
  end,
}
