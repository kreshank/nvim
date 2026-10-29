local M = {}

function M.setup()
  require("features.diagnostics")
  require("features.formatter")
  require("features.markdown").setup()
  require("features.tex")
  require("lang").setup()
  require("features.remote").setup()
end

return M
