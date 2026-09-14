return {
  root_search_depth = 5,
  compile_commands_search_depth = 3,
  base_markers = {
    ".git",
  },
  ignored_directories = {
    [".git"] = true,
    [".hg"] = true,
    [".svn"] = true,
    ["node_modules"] = true,
  },
}
