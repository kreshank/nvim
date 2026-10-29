# Neovim configuration

## Layout and existing features

- `lua/config`: editor options, leaders and Lazy bootstrap. Light Everforest,
  relative numbers, wrapped/indented lines, two-space indentation.
- `lua/plugins`: plugin imports. NvimTree, Telescope, Gitsigns, Diffview,
  Mason/LSP, persistent LTeX dictionaries, Markdown preview and math.
- `lua/features`: project roots, remote mounts/LSP transport, diagnostic display
  and navigation, explicit `:Format` / `:FormatInfo`, TeX and Markdown controls.
- `lua/lang`: C/C++, Python (Pyright + Ruff), Java, Rust, Lua and TeX/BibTeX
  (texlab + LTeX+) definitions. `:LangVersion` reports detection from project
  files; `:LangVersion <version>` overrides it, `:LangVersion!` clears it.

`lua/config/lsp.lua` is a pre-existing untracked legacy file and is not loaded.
The live configuration is in `lua/lang` and `lua/features/lsp`.

## Git changes inside a file

Gitsigns shows changes live, including unsaved edits and untracked files inside
Git repositories. The gutter is reserved for both diagnostics and Git signs,
with colored line numbers and word-level highlighting for changed text.

| Gutter marker | Meaning |
| --- | --- |
| `+` | Added line (including new files) |
| `~` | Changed line, possibly also containing a deletion |
| `_` | Lines were deleted at this position |
| `‾` | Lines were deleted above the first line |

Deleted text no longer has its own buffer line; use a preview to see it.
Unstaged changes compare against the index; staged signs remain enabled.

| Key | Action |
| --- | --- |
| `]c` / `[c` | Next / previous Git change, including staged changes |
| `<leader>gp` | Preview change in a floating window |
| `<leader>gP` | Show the change and removed lines inline |
| `<leader>gd` | Split diff of this file against `HEAD` (last commit) |
| `<leader>gD` | Toggle all removed lines inline against `HEAD`, including staged deletions |
| `<leader>gl` | Toggle full-line change backgrounds |
| `<leader>gb` | Toggle blame annotation for the current line |

These mappings attach to files in Git repositories. Use `:DiffviewOpen` for the
existing repository-wide diff browser. Git-ignored files have no change markers.
Remote projects retain their opt-in Git integration: `<leader>rg` enables signs
for that mount. Git behavior lives in `lua/features/git`, with its plugin import
in `lua/plugins/gitsigns.lua`.

## SSH projects

Neovim, plugins, keys and the path proxy run locally. SSHFS provides file access;
remote language servers run over SSH stdio. No Neovim installation is needed on
servers. Install local system dependencies listed in `linux-deps.md`.

Keep connection definitions in standard OpenSSH configuration. Several files
are supported through `Include` in `~/.ssh/config`, for example:

```sshconfig
Include ~/.ssh/config.d/*
Include ~/.sshconfig

Host research
  HostName example.edu
  User your-login
  IdentityFile ~/.ssh/id_ed25519
```

Put Includes before broad `Host *` defaults: SSH uses the first obtained value.
The picker discovers literal aliases in included files; SSH resolves connection
options, including ProxyJump. Wildcard/negated aliases are not picker entries.

| Key (leader is Space) | Action |
| --- | --- |
| `<leader>rp` | Pick a new or remembered project |
| `<leader>rs` | SSH terminal in its project directory; tmux horizontal pane when available |
| `<leader>rd` | Disconnect the buffer/current-directory project |
| `<leader>rl` | Retry server discovery and reset fallback choices for this project |
| `<leader>rg` | Toggle Git integration on this mount |

Password, keyboard-interactive/MFA and key-passphrase prompts appear in a real
terminal. No password is collected by a Lua input box or stored in configuration.
Interactive SSH and SSHFS commands explicitly use `BatchMode=no`; background LSP
connections use batch mode after authentication. SSHFS keeps an independent
transport, so password-only hosts can prompt once for the mount and again for
the shared LSP connection. `:RemoteAuth alias` authenticates/rechecks that shared
connection when needed. A new server also uses SSH's normal host-key prompt.

| Command/key | Action |
| --- | --- |
| `:RemoteSSH user@server.example` | Direct interactive SSH, without a mount or saved alias |
| `:RemoteSSH` / `<leader>rt` | Pick an alias or type a direct destination |
| `:RemoteProject user@server.example /absolute/path` | Mount a direct destination; omit the path to be prompted |
| `:RemoteAuth [alias-or-user@host]` | Prompt for authentication for the shared SSH connection |
| `:RemoteHostAdd` / `<leader>rn` | Enter alias, hostname, username, port and optional identity file |
| `:RemoteConfig` / `<leader>rc` | Open the main SSH config or choose an included config file |
| `:RemoteConfig alias` | Jump to that alias's `Host` stanza, including in an included file |
| `:RemoteConfig ~/.sshconfig` | Open a specific configuration file |

Direct terminals open a tmux pane when Neovim runs in tmux, otherwise a Neovim
terminal split. `<leader>rs` opens the selected project's directory; with no
selected project it offers the destination picker. Set custom ports and jump
hosts in an SSH host entry. In a direct command, enter a hostname/alias or
`user@host`, without SSH flags. Escape spaces in command paths using Neovim's
normal command-line escaping.

The new-host wizard prepares an editable entry in `~/.ssh/config`; save with
`:write`. It puts the entry before existing defaults and resets the `Host *`
context so existing global options and Includes keep applying. No password goes
in the entry. Config changes are discovered again when you reopen the picker;
reconnect existing sessions to apply changed connection settings.

SSHFS mounts require local `sshfs` and `fuse3`. Direct `:RemoteSSH` works without
SSHFS. This workspace currently has SSH but no SSHFS executable, so live mounts
remain untested here.

Multiple projects may stay mounted. Switch buffers or reopen a remembered
project to switch context. Shell, Git and disconnect commands use the buffer's
project, then the working directory, then the last selected project. Disconnect
keeps host-wide SSH masters alive for other projects/tmux panes. Plugin lockfiles
protect mounts used by another Neovim instance. Modified buffers block unmount.

LSP discovery happens once per project/server as relevant files are opened, using
`/lang` filetypes and commands. A server found on the remote SSH `PATH` starts
there. Otherwise choose local Mason/PATH fallback or skip, individually for each
server. Adding a registered language needs no remote filetype table. Functional
LSP launchers need an explicit argv override in `remote_lsp[server].cmd`.

Discovery uses the SSH command environment: put server executables on its PATH
(test with `ssh alias 'command -v texlab'`). Local-only runtime settings and
callbacks are omitted remotely; optional `remote_lsp[server]` overrides belong
in the language file. A detected executable that subsequently crashes is reported
by Neovim; use `<leader>rl` to retry after fixing it. Local fallback cannot see
remote installed libraries/toolchains outside the mount. Cross-root remote files
outside the mounted tree are not mapped; mount a common parent for those projects.

## Markdown with Alacritty

Press `<leader>mp` (Space mp) to toggle a live browser preview. It opens one
browser tab, follows Markdown buffers, and updates without saving. Linked Markdown
documents reuse that tab. `:MarkdownPreview` and `:MarkdownPreviewStop` are also
available. The local backend lives in `lua/features/markdown/preview.lua` and
`lua/features/markdown/browser`; it replaces the old iamcco preview plugin so the
navigation integration is maintained in this configuration rather than patched
inside a downloaded plugin.

Requires Node.js 22.12+ and npm plus a local browser opener (`vim.ui.open`, normally
`xdg-open` or `wslview`). On first use it installs pinned npm dependencies locally;
subsequent previews need no CDN or internet access for rendering. The service
listens on loopback with a per-session URL and exits with Neovim.

| Feature | Browser behavior |
| --- | --- |
| `$x$` and `\(x\)` | Inline KaTeX math |
| `$$x$$` and `\[x\]` | Display KaTeX math, including multiline blocks |
| `[Section](#heading)` | Scrolls to the section and moves Neovim to its source line |
| `[Other](notes.md#heading)` | Opens the document in Neovim and in the same preview tab; preserves unsaved buffer contents |
| External links / email links | Browser-only; web links open in another tab |
| Relative images and PDFs | Resolved from the document directory, including SSHFS mounts |
| Reference links and autolinks | Supported |
| Headings | ATX/Setext, Unicode, GitHub-style slugs; duplicates get `-1`, `-2`, etc. |
| Explicit anchors | `## Title {#custom-id}` and sanitized HTML anchors |
| Tables, task lists, strikethrough | Supported; task checkboxes are read-only |
| Footnotes, definition lists, emoji | Supported |
| Code fences | Highlighted; math delimiters inside code stay literal |
| Mermaid fences | Rendered locally |
| HTML / details blocks | Sanitized; scripts and event handlers removed |
| YAML front matter | Hidden without shifting source-line locations |

Browser Back/Forward navigates preview history. Uncheck **Section clicks move
Neovim** in the browser to disable cursor jumps; the default is configured by
`sync_navigation` in `lua/features/markdown/defaults.lua`. Relative document
navigation always opens the target in Neovim so the preview can use live buffer
contents. Clicking sections scrolls the browser; ordinary edits preserve its
scroll position (there is no continuous cursor-follow scrolling).

For example, `## My Section` is linked with `[Jump](#my-section)`. Use percent
encoding for spaces in file links, e.g. `[Notes](my%20notes.md#overview)`.
Relative document links must end in `.md` or `.markdown`. Local files must stay
within the project root (Git/Hg, package.json, mkdocs.yml, or the SSHFS mount;
otherwise the initial document's directory). Broken links show a message in the
preview. KaTeX supports a subset of LaTeX, not arbitrary packages. PlantUML,
Chart.js and other non-Mermaid diagrams remain code blocks. Obsidian wikilinks,
transclusions and GitHub alert styling are not enabled.

Inside Neovim, fenced code blocks hide their backticks/tilde fences and language
label while the cursor is outside the block. Entering any line of the block
reveals both fences, including the closing fence. This is cursor-based, not mouse
hover, and works independently in split windows. Conceal leaves blank fence lines
in place; it does not fold code or change file contents/line numbers.

Fenced code uses Neovim's bundled language syntax highlighting. Common labels
include `python`/`py`, `lua`, `c`, `cpp`/`c++`, `rust`/`rs`, `java`, `javascript`/`js`,
`typescript`/`ts`, `bash`/`sh`, `json`, `yaml`, `toml`, `html`, `css`, `sql`, and
`latex`/`tex`. Customize `code_languages` in `lua/features/markdown/defaults.lua`.
Use a language label after the opening fence for highlighting. Unknown or missing
labels remain plain code. Fence detection uses the bundled Markdown Tree-sitter
parser; code coloring uses Vim syntax files rather than per-language parsers.

`render-latex.nvim` provides inline math conceal and, with a compatible terminal,
rendered display equations. `<leader>me` toggles equation source and
`<leader>mh` runs its doctor. It targets Markdown math, not complete `.tex` files.
Its worker installs on first load; `:RenderLatex install` retries installation.

Alacritty cannot display the required image protocol or variable-size text.
Images, typeset display math and differently sized headings are therefore in the
browser preview. For future Kitty use, enable `set -g allow-passthrough on` in
tmux and run `:RenderLatex tmux_check`. This does not add a general inline Markdown
image plugin; ordinary images continue to use the browser preview.

## TeX controls

Mappings are buffer-local to TeX/plainTeX/BibTeX. Existing auto-save after a
one-second editing pause is retained; texlab builds on save. Automatic forward
search after every build is disabled to avoid moving the PDF while typing.

| Key | Action |
| --- | --- |
| `<leader>lb` | Save and build with texlab |
| `<leader>lv` / `<leader>lf` | Open/forward-search the project PDF through texlab + Zathura |
| `<leader>lc` | Cancel current build |
| `<leader>le` | Buffer diagnostics in location list |
| `<leader>la` | Toggle autosave for this buffer |

Texlab resolves the main document and output path for included chapters, instead
of guessing `chapter.pdf`. Build once before forward search. Use TeX root magic
comments/project configuration when the main file is ambiguous. `:Format` uses
texlab/latexindent; `:LspTexlabCleanAuxiliary` is available explicitly. Autosave
toggle affects automatic writes only; manual saves still trigger build-on-save.

Remote texlab follows its remote project settings; launching a **local** PDF
viewer from a remote texlab process is not bridged by this configuration. Local
TeX compilation/preview is the supported integrated PDF workflow.

## Validation

```sh
nvim --headless -u init.lua -l tests/git.lua
nvim --headless -u NONE -l tests/remote.lua
nvim --headless -u NONE -l tests/remote-ssh.lua
nvim --headless -u NONE -l tests/markdown-code.lua
python3 -B -m unittest discover -s tests
```

These cover server discovery/fallback, two-project isolation, SSH quoting and
Includes, JSON-RPC Unicode framing, URI-key workspace edits and path boundaries.
Markdown parser/server tests:

```sh
npm ci --prefix lua/features/markdown/browser
node --test tests/markdown.test.mjs
```

Browser integration tests use Playwright and a local Chromium executable:

```sh
MARKDOWN_BROWSER=/path/to/chrome node --test tests/markdown-browser.test.mjs
```

These launch headless Neovim and Chromium to verify live unsaved edits, all four
math delimiters, images, Mermaid, sanitized HTML, section-to-source navigation,
the cursor-sync toggle, linked unsaved documents, and browser Back. Actual SSH
mounts and PDF SyncTeX still need an interactive session with your hosts/desktop.
