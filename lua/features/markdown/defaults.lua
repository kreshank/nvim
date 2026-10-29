return {
  sync_navigation = true,
  -- Fence label = bundled Vim syntax name; no language-server/parser install needed.
  code_languages = {
    "python", "py=python", "lua", "c", "cpp", "c++=cpp", "rust", "rs=rust",
    "java", "javascript", "js=javascript", "typescript", "ts=typescript",
    "bash=sh", "sh", "shell=sh", "json", "yaml", "yml=yaml", "toml",
    "html", "css", "sql", "tex", "latex=tex", "vim", "diff",
  },
  keys = {
    preview = "<leader>mp",
    equation = "<leader>me",
    health = "<leader>mh",
  },
  latex = {
    render = { inline = "conceal", inline_symbols = true },
  },
}
