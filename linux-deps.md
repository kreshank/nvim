# Linux system dependencies

Packages and tools this Neovim config **expects on the system**. Mason / Lazy install language servers and plugins, but they do **not** install compilers, TeX Live collections, PDF viewers, or search tools listed here.

Commands target **Ubuntu / Debian** (`apt`).

Quick install of the common set:

```bash
sudo apt update
sudo apt install -y \
  build-essential g++ gcc \
  python3 python3.12 \
  openjdk-17-jdk \
  git ripgrep fd-find \
  latexmk chktex \
  texlive-latex-base texlive-latex-recommended \
  texlive-latex-extra texlive-science texlive-fonts-recommended \
  texlive-extra-utils \
  zathura zathura-pdf-poppler
```

On Ubuntu, `fd` is often installed as `fdfind`; create a symlink if needed:

```bash
mkdir -p ~/.local/bin
ln -sf "$(command -v fdfind)" ~/.local/bin/fd
```

---

## Core / Neovim host

**Used by:** Neovim itself (`init.lua` sets `python3_host_prog`)

| Need | Why |
|------|-----|
| Neovim 0.11+ | Native `vim.lsp.config` / `vim.lsp.enable` |
| `python3.12` | `vim.g.python3_host_prog` in [`lua/config/defaults.lua`](lua/config/defaults.lua) |

```bash
sudo apt install -y python3 python3.12 python3-pip
```

Optional (remote plugins / `pynvim`):

```bash
python3.12 -m pip install --user pynvim
```

---

## [`lua/plugins/lsp.lua`](lua/plugins/lsp.lua) — Mason + LSP

Mason installs: `clangd`, `jdtls`, `pyright`, `ruff`, `rust_analyzer`, `lua_ls`, `texlab`, `ltex_plus`, `latexindent`.

### C / C++ (`clangd`)

| Need | Why |
|------|-----|
| `g++` / `gcc` | `--query-driver` paths in defaults; compiling your code |
| C++20-capable toolchain | Project standard is `c++20` |

```bash
sudo apt install -y build-essential g++ gcc
```

### Java (`jdtls`)

| Need | Why |
|------|-----|
| JDK 17+ | Eclipse JDT language server runtime |

```bash
sudo apt install -y openjdk-17-jdk
```

### Python (`pyright`, `ruff`)

| Need | Why |
|------|-----|
| `python3.12` | Analysis / runtime version in defaults |

```bash
sudo apt install -y python3.12
```

### Rust (`rust_analyzer`)

Mason installs the analyzer; you still need a toolchain to build projects:

```bash
sudo apt install -y rustc cargo
# or (recommended): https://rustup.rs
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

### Lua (`lua_ls`)

No extra system packages; Mason installs the server.

### LaTeX (`texlab`, chktex, latexindent)

| Need | Why |
|------|-----|
| `latexmk` | texlab default build tool |
| `pdflatex` / TeX Live | Actual compilation |
| `chktex` | Style diagnostics (not in Mason) |
| TeX packages (e.g. `mathtools`) | Document `\usepackage{...}` |
| `latexindent` | Prefer Mason (auto-installed); TeX Live copy is optional |

```bash
sudo apt install -y \
  latexmk chktex \
  texlive-latex-base \
  texlive-latex-recommended \
  texlive-latex-extra \
  texlive-science \
  texlive-fonts-recommended \
  texlive-extra-utils
```

For fewer missing-`.sty` issues on larger docs:

```bash
sudo apt install -y texlive-full
```

### Grammar / spell (`ltex_plus`)

Mason installs `ltex-ls-plus` (bundled Java). No separate apt package required beyond a normal system. Dictionary files are managed by `ltex_extra.nvim` under Neovim’s data dir.

---

## [`lua/config/tex.lua`](lua/config/tex.lua) — preview / autosave

| Need | Why |
|------|-----|
| `zathura` + PDF backend | `<leader>lv` preview; texlab forward search |
| `latexmk` / TeX Live | Builds triggered on save |

```bash
sudo apt install -y zathura zathura-pdf-poppler
```

Keymaps:

- `<leader>lb` — build
- `<leader>lv` — open PDF in Zathura
- `<leader>lf` — SyncTeX forward search

Zathura auto-reloads when the PDF is rewritten.

---

## [`lua/plugins/ltex_extra.lua`](lua/plugins/ltex_extra.lua)

No system packages. Needs `ltex_plus` from Mason (see LSP section).

---

## [`lua/plugins/telescope.lua`](lua/plugins/telescope.lua)

| Need | Why |
|------|-----|
| `ripgrep` (`rg`) | Live grep (strongly recommended) |
| `fd` / `fdfind` | Faster file find (optional) |

```bash
sudo apt install -y ripgrep fd-find
mkdir -p ~/.local/bin
ln -sf "$(command -v fdfind)" ~/.local/bin/fd
```

Ensure `~/.local/bin` is on your `PATH`.

---

## [`lua/plugins/gitsigns.lua`](lua/plugins/gitsigns.lua) / [`lua/plugins/diffview.lua`](lua/plugins/diffview.lua)

| Need | Why |
|------|-----|
| `git` | Hunks, blame, diff views |

```bash
sudo apt install -y git
```

---

## [`lua/plugins/nvimtree.lua`](lua/plugins/nvimtree.lua) / [`lua/plugins/nvimtreedevicons.lua`](lua/plugins/nvimtreedevicons.lua)

No required system packages. A Nerd Font in the terminal improves icons.

---

## [`lua/plugins/render-markdown.lua`](lua/plugins/render-markdown.lua)

No required system packages.

---

## [`lua/plugins/everforest.lua`](lua/plugins/everforest.lua)

No required system packages.

---

## What Mason **does** install (do not apt these for LSP)

These are pulled by Mason when Neovim starts (see `ensure_installed` in `lsp.lua`):

- `clangd`, `jdtls`, `pyright`, `ruff`, `rust-analyzer`, `lua-language-server`, `texlab`, `ltex-ls-plus`
- `latexindent` (formatter binary)

If something is missing after a fresh clone, open Neovim once and let Mason finish, or run `:Mason`.
