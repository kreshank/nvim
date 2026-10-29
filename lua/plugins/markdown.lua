-- Browser typography and images work with Alacritty; math also has an in-buffer
-- renderer with automatic backend detection for compatible terminals.
return {
  {
    "techwizrd/render-latex.nvim",
    ft = "markdown",
    main = "render_latex",
    opts = function() return require("features.markdown.defaults").latex end,
  },
}
