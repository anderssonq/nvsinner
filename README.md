
██▄   ██ ░▒    ░      ▄███▓▒░ ░█ ██▄   ██ ██▄   ██ ░▒▓██ ▒▄   █████░▄   
█▓░▒▄ ▀█ ▒▓    ▒░    ▀█▀ ▄    ██ █▓░▒▄ ▀█ █▓░▒▄ ▀█    ░  ▀▓░▄ ██   ▀░▒▄ 
▓▒ ▀▓▒▄░ ▐█▌   ▓▒       ▀░▒▄  ██ ▓▒ ▀▓▒▄░ ▓▒ ▀▓▒▄░   ░▒▀  ▀▀  ▓█▄█▄░▄▒▓▀
▒░   ▀▓█  ░▒▄ ▄█▌        ▄▒▓▀ █▓ ▒░   ▀▓█ ▒░   ▀▓█   ▒▓   ▄▀▀ ▒▓ ▀██░▀  
░     ▒▓   ▀▓▒░▀  ░▒▓███░░▀   ▓▒ ░     ▒▓ ░     ▒▓ ░▒▓███ ░▀▀ ░▒   ▀██▄ 
      ░▒     ▀                ▒░       ░▒       ░▒             ░     ▀█▀
                              ░                                         

A Neovim distribution managed with **lazy.nvim**, extended into a Cursor-like
AI terminal IDE with a dark monochrome glassmorphism theme. Target editor:
**Neovim 0.11+**. Installs as an isolated `NVIM_APPNAME=nvsinner`, so it runs
side-by-side with any existing `~/.config/nvim` without touching it.

- ⚡ **Fast startup** — almost everything is lazy-loaded (only ~12 of 42 plugins
  load at startup; cold start ≈ 60 ms).
- 🤖 **AI via terminal** — run any CLI agent (e.g. `claude`) in a dedicated
  right-hand column (`<leader>j`); buffers auto-reload when it edits files.
- 🌑 **Glass theme** — kanagawa "dragon" with a near-black background.

---

## 📦 Requirements

| Tool | Used by |
|------|---------|
| Neovim **0.11+** | native `vim.lsp` API, `vim.uv` |
| `git` | lazy.nvim plugin fetch |
| `ripgrep` | Telescope live grep |
| `node` | `prettier` / `eslint_d` |
| A **Nerd Font** | icons (FiraCode Nerd Font is bundled in `fonts/`) |
| `eslint_d`, `prettier`, `stylua` | none-ls formatting/linting |
| an AI CLI, e.g. `claude` | AI terminal column (optional) |

The AI workflow is just a CLI agent run in the terminal column — install one
(e.g. `npm i -g @anthropic-ai/claude-code`) and run it once to log in. No
`ANTHROPIC_API_KEY` needed by the config; the CLI handles its own auth.

---

## 📁 Folder structure

```
init.lua                       Bootstraps lazy.nvim, loads lua/core/*, imports the plugin folders
lua/core/options.lua           Leaders + core vim options
lua/core/keymaps.lua           Global keymaps (save/undo/redo, folds, split-resize, buffers)
lua/core/autoreload.lua        Disk auto-reload for the AI terminal workflow
lua/core/ui-touch.lua          Active-window glow + mouse-hover docs (native)
lua/plugins/<category>/*.lua   One plugin per file; grouped by category folder
fonts/                         Bundled FiraCode Nerd Font .ttf files
session/                       Saved sessions (git-ignored)
CLAUDE.md                      Technical notes for AI agents working on this repo
NVSINNER.md                    Plan to package this config as the "NvSinner" distro
```

Plugins are grouped into category folders under `lua/plugins/`
(`ui/`, `lsp/`, `git/`, `editor/`, `navigation/`, `terminal/`). To add a plugin,
create a new `lua/plugins/<category>/<name>.lua` that returns a lazy spec; new
files in an existing category are picked up automatically.

---

## 🔌 Plugins & their commands

### 🤖 AI

There are no in-editor AI plugins. AI is a **CLI agent run in the terminal
column** (`toggleterm.lua`): press `<leader>j` to open the right-hand column and
type `claude` (or any other CLI). When it edits files on disk, the corresponding
buffers reload automatically — see the auto-reload setup in `core/autoreload.lua`.

### 🎨 Appearance

| File | Plugin | What it does |
|------|--------|--------------|
| `theme.lua` | kanagawa.nvim | Active colorscheme: dragon variant, glass floats (`#0a0a0f` bg) |
| `lualine.lua` | lualine.nvim | Minimal monochrome global statusline |
| `incline.lua` | incline.nvim | Floating filename label, top-right of each window |
| `barbacue.lua` | barbecue.nvim | VS Code-style breadcrumbs (winbar) |
| `dashboard.lua` | alpha-nvim | Start screen — "NvSinner" block logo + quick-action menu |
| `colorizer.lua` | nvim-colorizer | Inline color previews for hex/rgb |
| `cursorline.lua` | nvim-cursorline | Highlights current line and word under cursor |
| `identmini.lua` | indentmini.nvim | Indentation guides |
| `notify.lua` | nvim-notify | Pretty notifications (replaces `vim.notify`) |

### 🔭 Navigation & search

| File | Plugin | Keys |
|------|--------|------|
| `telescope.lua` | telescope.nvim | `<leader>f` files · `<leader>sf` grep · `<leader>fb` buffers |
| `neo-tree.lua` | neo-tree.nvim | `<leader>e` toggle file explorer (reveals current file) |
| `leap.lua` | leap.nvim | `s` forward · `S` backward · `gs` across windows |
| `smooth-scroll.lua` | neoscroll.nvim | `<PageUp>` / `<PageDown>` smooth scroll |
| `nvim-window-picker.lua` | window-picker | Window selection (used by Neo-tree) |

### ✏️ Editing

| File | Plugin | Keys |
|------|--------|------|
| `completions.lua` | nvim-cmp + LuaSnip | `<CR>` confirm · `<C-Space>` trigger · `<C-b>`/`<C-f>` scroll docs · `<C-e>` abort |
| `comment.lua` | Comment.nvim | `gcc` line · `gbc` block · `gc{motion}` / `gb{motion}` |
| `surround.lua` | nvim-surround | `ys{motion}{char}` add · `ds{char}` delete · `cs{old}{new}` change |
| `autopairs.lua` | nvim-autopairs | Auto-closes brackets/quotes |

### 🧠 Language tooling

| File | Plugin | Keys / notes |
|------|--------|--------------|
| `lsp-config.lua` | mason + nvim-lspconfig | `K` hover · `gd` definition · `<leader>lf` format · `<leader>ca` code action · `:Mason` |
| `none-ls.lua` | none-ls + extras | Formatters/linters: stylua, prettier, eslint_d |
| `nvim-treesitter.lua` | nvim-treesitter | Syntax highlighting & indentation |

### 🛠️ Workflow

| File | Plugin | Keys |
|------|--------|------|
| `toggleterm.lua` | toggleterm.nvim | `<leader>t` / `<leader>t2…9` horizontal terms (20% height) · `<leader>j` / `<leader>j2…9` AI sessions |
| `persistence.lua` | persistence.nvim | `<leader>SQ` / `<leader>Sc` / `<leader>Sl` sessions |
| `git-blame.lua` | git-blame.nvim | Inline git blame virtual text |
| `gitsigns.lua` | gitsigns.nvim | Sign-column markers for added/changed/deleted lines · `]h` / `[h` hunks · `<leader>h*` actions |
| `todocomment.lua` | todo-comments.nvim | Highlights `TODO` / `FIXME` / etc. |
| `which-key.lua` | which-key.nvim | `<leader>?` shows buffer keymaps |
| `lsp/neoconf.lua` | neoconf.nvim | `:Neoconf` project-local settings |

---

## ⌨️ Full keybindings reference

> Leader = `Space`, localleader = `\`. Mode legend: **n** normal · **i** insert
> · **v/x** visual · **o** operator-pending · **t** terminal.

> AI is a CLI agent in the terminal column — see **Terminals** below for the
> `<leader>j` toggle.

### Files, search & navigation

| Keys | Mode | Action |
|------|------|--------|
| `<leader>f` | n | Telescope find files |
| `<leader>sf` | n | Telescope live grep |
| `<leader>fb` | n | Telescope buffers |
| `<leader>e` | n | Toggle Neo-tree (reveals the current file in the tree) |
| `s` / `S` / `gs` | n, x, o | Leap forward / backward / across windows |
| `<PageUp>` / `<PageDown>` | n, v, x | Smooth scroll up / down |

### LSP & editing

| Keys | Mode | Action |
|------|------|--------|
| `K` | n | Hover docs |
| `gd` | n | Go to definition |
| `<leader>lf` | n | Format buffer |
| `<leader>ca` | n | Code action |
| `gcc` / `gbc` | n | Toggle line / block comment |
| `ys` / `ds` / `cs` | n | Add / delete / change surround |

### Terminals (toggleterm)

| Keys | Mode | Action |
|------|------|--------|
| `<leader>t` | n | Toggle horizontal terminal 1 |
| `<leader>t2` … `<leader>t9` | n | Toggle horizontal terminals 2–9 (independent) |
| `<leader>j` | n | Toggle AI session 1 (right-hand column) |
| `<leader>j2` … `<leader>j9` | n | Toggle AI sessions 2–9 (independent columns) |
| `<M-J>` | n, i, t | Toggle AI session 1 (sent by iTerm2's `⌘⌥J`) |
| `<D-M-j>` | n, t | Toggle AI session 1 (GUI Neovim `⌘⌥J`) |
| `<Esc>` / `jk` | t | Leave terminal mode |
| `<C-h/j/k/l>` | t | Move to window left/down/up/right |

### Git

| Keys | Mode | Action |
|------|------|--------|
| `]h` / `[h` | n | Next / previous changed hunk |
| `<leader>hp` | n | Preview hunk (inline diff) |
| `<leader>hs` / `<leader>hr` | n | Stage / reset hunk |
| `<leader>hS` / `<leader>hR` | n | Stage / reset whole buffer |
| `<leader>hb` | n | Blame current line (full popup) |

### Sessions, folds, windows & misc

| Keys | Mode | Action |
|------|------|--------|
| `<leader>SQ` | n | Stop session, quit without saving |
| `<leader>Sc` | n | Restore last session for current dir |
| `<leader>Sl` | n | Restore last session |
| `<leader>za` | n | Toggle fold |
| `<leader>zf` | v | Fold selected lines |
| `<C-Y>` | n | Save file (with notification) |
| `<C-U>` / `<C-R>` | n | Undo / redo (with notification) |
| `<C-Up>` | n | Grow window height (+2) |
| `<C-,>` / `<C-.>` | n, t | Grow / shrink window width (±20%) — also from inside a terminal (resize the AI chat) |
| `<C-;>` / `<C-'>` | n, t | Grow / shrink window height (±5%) — also from inside a terminal |
| `<leader>?` | n | Show buffer-local keymaps (which-key) |

---

## ⚡ Performance notes

Plugins are lazy-loaded via lazy.nvim triggers:

- `event = "InsertEnter"` — completion (`nvim-cmp`), autopairs.
- `event = { "BufReadPost", "BufNewFile" }` — treesitter, LSP, colorizer,
  cursorline, indent guides, breadcrumbs, todo-comments.
- `event = { "BufReadPre", "BufNewFile" }` — gitsigns (sign-column markers).
- `event = "VeryLazy"` — statusline, comments, scroll, notifications, git-blame,
  surround, which-key, window-picker, incline.
- `cmd` / `keys` — Telescope, Neo-tree, toggleterm AI column.

Only the colorscheme (`theme.lua`) and start screen (`dashboard.lua`) load
eagerly. Check the breakdown anytime with `:Lazy profile`.

---

## 🚀 Getting started

### One-liner

```bash
curl -fsSL https://raw.githubusercontent.com/anderssonq/nvsinner/main/install.sh | bash
```

Clones NvSinner into `~/.config/nvsinner`, installs a `nvsinner` launcher into
`~/.local/bin`, and bootstraps every plugin. Then just run:

```bash
nvsinner
```

### Manual

```bash
git clone https://github.com/anderssonq/nvsinner.git ~/.config/nvsinner
NVIM_APPNAME=nvsinner nvim     # lazy.nvim bootstraps + installs on first launch
```

`NVIM_APPNAME=nvsinner` gives the distro its own config/data/state/cache dirs, so
it never collides with another Neovim setup. LSP servers (`lua_ls`, `ts_ls`,
`html`) auto-install via Mason on first launch — no manual `:MasonInstall`
needed. Verify anytime inside Neovim with `:Lazy` and `:checkhealth`.

---

## 🔄 Updating

NvSinner is just a git clone, so an update is a `git pull` plus a plugin restore.
Pick whichever you like:

- **In-editor (recommended):** run `:NvSinnerUpdate`. It `git pull`s the config,
  restores plugins to the pinned `lazy-lock.json`, and runs `:checkhealth`.
  **Restart Neovim afterwards** so the new Lua config loads.
- **Re-run the installer:** the one-liner is idempotent — on an existing clone it
  `git pull`s and re-installs plugins instead of skipping.

  ```bash
  curl -fsSL https://raw.githubusercontent.com/anderssonq/nvsinner/main/install.sh | bash
  ```

- **By hand:**

  ```bash
  git -C ~/.config/nvsinner pull
  NVIM_APPNAME=nvsinner nvim --headless "+Lazy! restore" +qa
  ```

Plugins are pinned in the committed `lazy-lock.json` and updates use `Lazy!
restore` (not `sync`), so you get the exact plugin versions the distro was tested
with. To deliberately float to the newest plugins instead, run `:Lazy sync` (this
rewrites your local `lazy-lock.json`).
