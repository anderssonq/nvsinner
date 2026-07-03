```
██▄   ██ ░▒    ░      ▄███▓▒░ ░█ ██▄   ██ ██▄   ██ ░▒▓██ ▒▄   █████░▄   
█▓░▒▄ ▀█ ▒▓    ▒░    ▀█▀ ▄    ██ █▓░▒▄ ▀█ █▓░▒▄ ▀█    ░  ▀▓░▄ ██   ▀░▒▄ 
▓▒ ▀▓▒▄░ ▐█▌   ▓▒       ▀░▒▄  ██ ▓▒ ▀▓▒▄░ ▓▒ ▀▓▒▄░   ░▒▀  ▀▀  ▓█▄█▄░▄▒▓▀
▒░   ▀▓█  ░▒▄ ▄█▌        ▄▒▓▀ █▓ ▒░   ▀▓█ ▒░   ▀▓█   ▒▓   ▄▀▀ ▒▓ ▀██░▀  
░     ▒▓   ▀▓▒░▀  ░▒▓███░░▀   ▓▒ ░     ▒▓ ░     ▒▓ ░▒▓███ ░▀▀ ░▒   ▀██▄ 
      ░▒     ▀                ▒░       ░▒       ░▒             ░     ▀█▀
                              ░                                         
```
A Neovim distribution managed with **lazy.nvim**, extended into a Cursor-like
AI terminal IDE with a native **carbon** theme (an oxocarbon / IBM Carbon port —
industrial grays, blue-forward accents; see `lua/core/carbon.lua`). Target editor:
**Neovim 0.11+**. Installs as an isolated `NVIM_APPNAME=nvsinner`, so it runs
side-by-side with any existing `~/.config/nvim` without touching it.

- **Fast startup** — almost everything is lazy-loaded (only ~12 of 42 plugins
  load at startup; cold start ≈ 60 ms).
- **AI via terminal** — run any CLI agent (e.g. `claude`, `kiro-cli`, `opencode`) in a dedicated
  right-hand column (`<leader>j`); buffers auto-reload when it edits files.

> *"I got tired of so many IDEs and code editors everywhere — they all end up
> forcing you to use the mouse. On top of that, I started seeing AI tools
> running in the terminal via CLI. That was it for me. Let's put everything
> in the terminal and call it done."*
> — Ander

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
column** (`toggleterm.lua`): press `<leader>j` to open the column. The first
time a session opens, a picker appears **in the column's own space** asking
which CLI to launch — `claude`, `kiro-cli`, `opencode` (uninstalled ones are
marked), or **plain terminal — no AI**, which starts your shell and titles the
column `term` like the horizontal terminals. Navigate with `j`/`k`, launch with
`Enter` (or click a row), cancel with `q`. When the CLI edits files on disk,
the corresponding buffers reload automatically — see the auto-reload setup in
`core/autoreload.lua`. The column's side (left/right) is configurable in
`:NvSinnerMenu`.

#### `:NvSinnerPrompts` — the prompt library

Press `<leader>p` (or run `:NvSinnerPrompts`) to open a floating library of
reusable AI prompts — PR description, strict code review, feature plan, bug
fix, tests-from-pattern ship as defaults. Each row shows a title and a short
description; picking one **copies the full prompt to the OS clipboard**, ready
to paste into the AI column's CLI (then fill in the `[PLACEHOLDERS]`).
Navigate with `j`/`k`, copy with `Enter`/`Space` (or click a row), jump with
`1`–`9`, close with `q` — same feel as `:NvSinnerMenu`.

The library is plain JSON at **`settings/prompts.json`**: press `e` inside the
modal to open it and add or edit prompts (`content` can be a string or an
array of lines; the file is re-read on every open, so no restart needed).

#### `:NvSinnerHelp` — the command palette

Can't remember a command? `:NvSinnerHelp` lists every NvSinner command
(`:NvSinnerMenu`, `:NvSinnerPrompts`, `:NvSinnerUpdate`, `:NvSinnerSync`, `:checkhealth
nvsinner`, …) with a one-line description. Navigate with `j`/`k` and press
`Enter` — or just click a row — to **run it**; the palette closes itself. New
commands are discovered automatically, so the list is never stale.

### 🎨 Appearance

| File | Plugin | What it does |
|------|--------|--------------|
| `theme.lua` | — (native) | Active colorscheme: **carbon**, a self-contained oxocarbon/IBM Carbon port (`colors/carbon.lua` + `lua/core/carbon.lua`) |
| `lualine.lua` | lualine.nvim | Global statusline with the carbon mode→accent chip |
| `incline.lua` | incline.nvim | Floating filename label, top-right of each window |
| `barbacue.lua` | barbecue.nvim | VS Code-style breadcrumbs (winbar) |
| `dashboard.lua` | alpha-nvim | Start screen — the README's distressed "NvSinner" ASCII mark + quick-action menu (mouse: hover highlights an item, click runs it); rotating dev quote |
| `colorizer.lua` | nvim-colorizer | Inline color previews for hex/rgb |
| `cursorline.lua` | nvim-cursorline | Highlights current line and word under cursor |
| `identmini.lua` | indentmini.nvim | Indentation guides |
| `notify.lua` | nvim-notify | Pretty notifications (replaces `vim.notify`) |

#### `:NvSinnerMenu` — the settings modal

The easiest way to configure the theme (and a few layout choices) is
**`:NvSinnerMenu`**: a Mason-style floating panel where every change applies
live and persists across restarts (stored as JSON in the distro's `settings/`
folder, next to the `:NvSinnerPrompts` library; an older cache under the data
dir is migrated automatically).
Navigate with `j`/`k`, change a value with `h`/`l` (or `Enter`/`Space`),
jump with `1`–`9`, close with `q` — or use the mouse: hovering moves the
selection onto the row under the pointer (dashboard-style) and a click cycles
its value.

| Row | Values |
|-----|--------|
| Theme | `dark` / `light` |
| Transparency | `off` / `on` |
| Accent | `blue` / `magenta` / `green` / `purple` — swaps only the identity text accent (keywords, active markers, numbers), never the gray surfaces |
| Folder color | `accent` / `teal` / `aqua` / `pink` / `green` / `purple` / `gray` — recolors Neo-tree's folder names + icons (`accent` follows the Accent pack; `gray` gives a monochrome tree) |
| Notif color | `default` / `accent` / `teal` / `aqua` / `magenta` / `pink` / `green` / `purple` / `plain` — recolors everyday info toasts (warnings/errors keep their semantic colors) |
| Variables | same choices — recolors syntax variables, parameters and fields (`default` = plain gray) |
| Strings | same choices — recolors syntax strings (`default` = carbon purple) |
| Functions | same choices — paints the whole function/method family in one accent (`default` = the stock carbon mix) |
| Neo-tree side | `left` / `right` |
| AI column side | `left` / `right` |
| Notifications | `shown` / `hidden` (hides info toasts; warnings/errors still show) |

#### Theme options (carbon)

The theme flags can also be set per launch via an environment variable, or
with a `vim.g` global early in `lua/core/options.lua`. Precedence: `vim.g`
wins over the environment, which wins over the persisted `:NvSinnerMenu`
value:

| Flag | Values | Per launch | Persistent |
|------|--------|-----------|------------|
| Background variant | `dark` (default) / `light` | `NVSINNER_BACKGROUND=light nvsinner` | `vim.g.nvsinner_background = "light"` |
| Transparency | off (default) / on | `NVSINNER_TRANSPARENT=1 nvsinner` | `vim.g.nvsinner_transparent = true` |
| Accent pack | `blue` (default) / `magenta` / `green` / `purple` | `NVSINNER_ACCENT=green nvsinner` | `vim.g.nvsinner_accent = "green"` |
| Folder color | `accent` (default) / `teal` / `aqua` / `pink` / `green` / `purple` / `gray` | `NVSINNER_FOLDER=aqua nvsinner` | `vim.g.nvsinner_folder = "aqua"` |
| Notif color | `default` / `accent` / `teal` / `aqua` / `magenta` / `pink` / `green` / `purple` / `plain` | `NVSINNER_NOTIF=pink nvsinner` | `vim.g.nvsinner_notif = "pink"` |
| Variables color | same choices as Notif color | `NVSINNER_VARIABLES=aqua nvsinner` | `vim.g.nvsinner_variables = "aqua"` |
| Strings color | same choices as Notif color | `NVSINNER_STRINGS=green nvsinner` | `vim.g.nvsinner_strings = "green"` |
| Functions color | same choices as Notif color | `NVSINNER_FUNCTIONS=purple nvsinner` | `vim.g.nvsinner_functions = "purple"` |

Transparent mode drops every full-surface background (editor, floats, side
panels) so your terminal's own background/blur shows through; small solid
elements (the statusline mode chip, the AI busy chip, the terminal focus bar,
prompt panels) keep their color so the UI stays legible.

#### Migrating from the glass theme (kanagawa-dragon)

Nothing is required for a stock install — `:NvSinnerUpdate` (or `git pull`
followed by `nvim --headless "+Lazy! restore" +qa`) picks up the new theme
automatically, since the carbon colorscheme ships inside this repo. Two
optional cleanups if you customized things:

- **Leftover plugin:** kanagawa.nvim is no longer in the plugin set; run
  `:Lazy clean` once to delete it from disk.
- **Personal highlight tweaks:** anything referencing the old glass hexes
  (`#0a0a0f`, `#111118`, `#c4746e`, …) should switch to palette roles —
  `local c = require("core.carbon").colors()` and use `c.base00`, `c.base09`,
  etc. (the full role table and design notes live in `lua/core/carbon.lua`).
  Rough mapping: bg `#0a0a0f` → `base00`, glass `#111118` → `blend`, FG
  `#c5c9d5` → `base04`, muted `#7a7f8d` → `base03`, accent `#c4746e` →
  `base09` (identity) or `base10` (attention).

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
| `<leader>e` | n | Toggle Neo-tree (reveals the current file; side set in `:NvSinnerMenu`) |
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
| `<leader>j` | n | Toggle AI session 1 (vertical column; first open asks which CLI to run) |
| `<leader>j2` … `<leader>j9` | n | Toggle AI sessions 2–9 (independent columns) |
| `<leader>p` | n | Prompt library (`:NvSinnerPrompts`) — copy a reusable AI prompt to the clipboard |
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
- **Float to latest (opt-in):** run `:NvSinnerSync`. It runs `:Lazy sync`
  (updates every plugin to its latest commit and **rewrites `lazy-lock.json`**)
  and then updates any outdated Mason packages. This deliberately leaves the
  tested, pinned plugin set — retest afterwards, and commit the new
  `lazy-lock.json` if you maintain your own clone. If a plugin **changes
  branch** during the sync (an upstream default-branch flip usually means a
  rewrite), a warning names it and gives the rollback recipe:
  `git restore lazy-lock.json` + `:Lazy restore`.
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

---

## 🩺 Health check

Missing external tools (ripgrep, node, stylua, prettier, eslint_d, a Nerd Font)
make features silently no-op rather than error. To see what's present at a glance:

```vim
:checkhealth nvsinner
```

It lists each external with an install hint for anything missing. On the **first
interactive launch** NvSinner also pops a one-time toast if something's missing,
pointing you here — it never nags again.

---

## 🧹 Uninstalling

NvSinner keeps everything under its own `nvsinner` app name, so removing it never
touches your other `~/.config/nvim`. Run the uninstaller (prompts for
confirmation from a terminal; pass `--yes` when piping):

```bash
curl -fsSL https://raw.githubusercontent.com/anderssonq/nvsinner/main/uninstall.sh | bash -s -- --yes
# or, from a clone:  ./uninstall.sh
```

It removes the four `nvsinner` dirs — config (`~/.config/nvsinner`), data
(`~/.local/share/nvsinner`), state (`~/.local/state/nvsinner`), cache
(`~/.cache/nvsinner`) — and the `~/.local/bin/nvsinner` launcher. If your config
dir is a symlink (e.g. a dev checkout), only the link is removed; the target is
left intact. Or remove those five paths by hand.
