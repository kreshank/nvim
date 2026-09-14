local function apply(_)
end

local function detect()
  return {
    version = "latex",
    source = "default",
  }
end

return {
  id = "tex",
  filetypes = { "tex", "plaintex", "bib" },
  servers = { "texlab", "ltex_plus" },
  formatter = "texlab",
  mason_tools = { "latexindent" },
  remote = false,
  versioned = false,
  versions = { "latex" },
  default_version = "latex",
  detect = detect,
  apply = apply,
  lsp = {
    texlab = {
      cmd = { "texlab" },
      settings = {
        texlab = {
          build = {
            onSave = true,
            forwardSearchAfter = true,
          },
          forwardSearch = {
            executable = "zathura",
            args = {
              "--synctex-forward",
              "%l:1:%f",
              "%p",
            },
          },
          chktex = {
            onOpenAndSave = true,
            onEdit = false,
          },
        },
      },
    },
    ltex_plus = {
      cmd = { "ltex-ls-plus" },
      filetypes = {
        "tex",
        "plaintex",
        "bib",
      },
      settings = {
        ltex = {
          language = "en-US",
          checkFrequency = "save",
        },
      },
    },
  },
}
