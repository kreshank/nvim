# Config / lang / features split

## Done
- `lua/config/` is editor core only: host Python, options, keymaps, lazy.
- Language opinions (versions, formatters, LSP specs, markers) live in `lua/lang/`.
- Workflows live in `lua/features/`: diagnostics, formatter, tex preview, project roots, LSP glue, remote/.
- `lua/plugins/lsp.lua` is a thin Mason bootstrap. Adding a language is a `lua/lang/*.lua` module plus `register()` in `lang/init.lua`.

## Layout
- `lua/config/defaults.lua` — `python_host` only
- `lua/lang/defaults.lua` — persist path, detect file-size cap
- `lua/lang/{c,python,java,rust,lua,tex}.lua` — per-language versions, formatter, markers, LSP spec
- `lua/features/remote/defaults.lua` — SSHFS / probe / sockets
- `lua/features/formatter/defaults.lua` — format timeout
- `lua/features/project/defaults.lua` — search depths, `.git`, ignored dirs

## Test this
1. `nvim --headless -u tests/lang_resolve.lua`
2. Restart Neovim. `:Mason` still lists clangd, pyright, ruff, jdtls, rust_analyzer, lua_ls, texlab, ltex_plus.
3. Open a Lua file from this config. `:lua print(vim.lsp.get_clients({name="lua_ls"})[1].config.cmd[1])` should contain `mason/bin/lua-language-server`.
4. Open a `.cpp` file. Same check for `clangd` → `mason/bin/clangd`. `:LangVersion` still reports/applies.
5. Open Python: pyright cmd should be `mason/bin/pyright-langserver`. `:FormatInfo` preferred is still `ruff`.
6. TeX preview, nvim-tree, and `:RemoteProject` still load.

## Not in this check-in
- Remote probe / compile_commands mapping / `linux-deps.md` (check-in 3).
- `:LspInfo`, TypeScript, new Mason servers.
