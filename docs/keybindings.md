# Keybindings

[← README](../README.md)

## Full keybindings reference

> Leader = `Space`, localleader = `\`. Mode legend: **n** normal · **i** insert
> · **v/x** visual · **o** operator-pending · **t** terminal.

### Files, search & navigation

| Keys | Mode | Action |
|------|------|--------|
| `<leader>f` | n | Telescope find files |
| `<leader>sf` | n | Telescope live grep |
| `<leader>fb` | n | Telescope buffers |
| `<leader>sd` / `<leader>sk` / `<leader>sc` | n | Telescope diagnostics / keymaps / commands |
| `<leader>sr` / `<leader>sh` | n | Telescope resume last search / help tags |
| `<leader>ss` / `<leader>sR` | n | Telescope document symbols / LSP references |
| `<leader>e` | n | Toggle Neo-tree (reveals the current file; side set in `:NvSinnerMenu`) |
| `<` / `>` | n | Neo-tree: previous / next tab (Files · Buffers · Git) — landing on **Git** opens the `<leader>gd` diff |
| Click a tree row | mouse | Open the file / expand the folder — **one click**, not two (switch to stock double-click in `:NvSinnerMenu` → "Explorer click") |
| `s` / `S` / `gs` | n, x, o | Leap forward / backward / across windows |
| `<PageUp>` / `<PageDown>` | n, v, x | Smooth scroll up / down — a quarter of the window (~8 rows in Neo-tree, where a page should keep more context) |
| `<S-Down>` / `<S-Up>` | n, v, x | Vim builtins (`CTRL-F` / `CTRL-B`) — a full window, the long jump |

Search pickers adapt to the available space: results and a larger dark preview
sit side by side on wide screens, then stack vertically on narrow screens. The
editor behind preview-based searches is dimmed; small selection dropdowns are
not.

### LSP & editing

| Keys | Mode | Action |
|------|------|--------|
| `K` | n | Hover docs |
| `gd` | n | Go to definition |
| `<leader>ld` / `<leader>lt` | n | Peek at the definition / type definition in a Telescope modal with preview — `q`/`<Esc>` closes without leaving where you were |
| `<leader>lf` | n | Format buffer |
| `<leader>lh` | n | Toggle LSP **inlay hints** (parameter names, inferred types). Off by default; the same switch as `:NvSinnerMenu` → "Inlay hints", so the two can't disagree |
| `<leader>ca` | n | Code action |
| `<leader>rn` | n | Rename symbol |
| `<leader>rw` | n, v | **Replace word** (`:NvSinnerReplace`) — opens a modal over the word under the cursor (or the visual selection) with four actions: `f` replace every exact match in this file · `c` replace asking `y`/`n`/`a`/`q` per match · `o` one by one with `cgn` (then `.` repeats, `n` skips) · `p` replace across the whole project. Matching is exact — replacing `foo` never touches `foobar` |
| `grn` / `gra` / `grr` / `gri` / `grt` / `gO` | n | Neovim's stock LSP maps: rename / code action / references / implementation / type definition / document symbols. Left as-is, never remapped — `<leader>rn` and `<leader>ca` are the mnemonic aliases. (`grx` runs a codelens where your Neovim provides it.) |
| `]d` / `[d` | n | Neovim builtins: next / previous diagnostic |
| `<leader>xx` / `<leader>xX` | n | Trouble: workspace / buffer diagnostics |
| `<leader>xs` / `<leader>xl` / `<leader>xq` | n | Trouble: symbols / location list / quickfix list |
| `gcc` | n | Toggle line comment (Neovim builtin; `gc{motion}` / visual `gc` for regions) |
| `ys` / `ds` / `cs` | n | Add / delete / change surround |
| `<leader>cs` | n | Document symbols modal (`:NvSinnerSymbols`) — pick a symbol to jump to it |
| `<leader>m` | n | Markdown "Open view" — toggle the reading view (also the clickable winbar button) |

### Terminals & AI (toggleterm)

> `<leader>t`, `<leader>j`, `<leader>jx` (and `<leader>f` in the table above)
> are prefixes of longer maps, so a bare press waits one `timeoutlen` — **300
> ms**, tunable in `:NvSinnerMenu` → "Key timeout" — before falling back to
> terminal/session 1. Typing the digit right after the prefix skips the wait
> entirely.

| Keys | Mode | Action |
|------|------|--------|
| `<leader>t` | n | Toggle horizontal terminal 1 |
| `<leader>t2` … `<leader>t9` | n | Toggle horizontal terminals 2–9 (independent) |
| `<leader>j` | n | Toggle AI session 1 (vertical column; first open asks which CLI to run) |
| `<leader>j2` … `<leader>j9` | n | Toggle AI sessions 2–9 (independent columns) |
| `<leader>jx` | n | Focus AI session 1 (open it if closed) with the CLI input primed with `@path` mentions of every file buffer visible in a window |
| `<leader>jx2` … `<leader>jx9` | n | Same focus-or-open + prime for AI sessions 2–9 |
| `<leader>ja` | n | AI session picker — jump to (or reopen) a session with its status |
| `<leader>jc` | n | Clear an AI session — kill the CLI + forget the choice, next open re-asks (`:NvSinnerAIClear`) |
| `<leader>jh` | n | Hide every open AI column at once — the CLIs keep running; `<leader>j` / `<leader>jN` brings one back |
| `<leader>x` | x | Ask AI about the selection — Fix / Refactor / Explain / custom question modal (also `:NvSinnerAskAI`) |
| triple-click | n, x | Ask AI about the word under the pointer (or the active selection) — same modal. A double-click is left alone: it is Vim's stock word-select |
| `<leader>as` | x | Send visual selection to the AI column (lands in the CLI input, not submitted) |
| `<leader>ab` | n | Send an `@path` mention of the current buffer to the AI column |
| `<leader>ad` | n | Send the current line's diagnostics to the AI column |
| `<C-l>` | i | Request an inline AI completion (ghost text) at the cursor (`:NvSinnerComplete`) |
| `<Tab>` | i | Accept the AI ghost text (falls through to a literal Tab when none is pending or cmp's menu is open) |
| `<C-]>` | i | Dismiss the AI ghost text |
| `<leader>p` | n | Prompt library (`:NvSinnerPrompts`) — copy a reusable AI prompt to the clipboard |
| `<M-J>` | n, i, t | Toggle the AI session you're inside, else session 1 (sent by iTerm2's `⌘⌥J`) |
| `<D-M-j>` | n, t | Toggle the AI session you're inside, else session 1 (GUI Neovim `⌘⌥J`) |
| `<Esc>` | t | Leave terminal mode (no `jk` map on purpose — it would delay every literal `j` typed into the CLI) |
| `<C-h/j/k/l>` | t | Move to window left/down/up/right |
| `<C-w>` | t | Leave terminal mode + start a window command (`<C-w>` prefix) |

### NvSinner commands (`<leader>x*` shortcuts)

Normal-mode `<leader>x` is shared with Trouble (`xx`/`xX`/`xs`/`xl`/`xq`
above); these letters deliberately avoid those. Visual `<leader>x` stays the
Ask-AI modal.

| Keys | Mode | Action |
|------|------|--------|
| `<leader>xm` | n | `:NvSinnerMenu` — settings modal |
| `<leader>xi` | n | `:NvSinnerIA` — AI hub (completion on/off, model picker, Ask-AI, prompts) |
| `<leader>xa` | n | `:NvSinnerAgents` — agent cockpit: every AI column with its status, a live chat preview, focus (`⏎`) + close (`d`) |
| `<leader>xh` | n | `:NvSinnerHelp` — command palette |
| `<leader>xp` | n | `:NvSinnerPrompts` — prompt library (same as `<leader>p`) |
| `<leader>xo` | n | `:NvSinnerSymbols` — document symbols modal (same as `<leader>cs`; `xo` = outline, Trouble owns `xs`) |
| `<leader>xn` | n | `:NvSinnerMinimap` — code minimap on the right edge (`xm` is the menu, so mi**n**imap takes `n`); click or drag it to jump |
| `<leader>xu` | n | `:NvSinnerUpdate` — update to the pinned plugin set |
| `<leader>xS` | n | `:NvSinnerSync` — float plugins to latest (**rewrites `lazy-lock.json`**; capital on purpose) |
| `<leader>xc` | n | `:checkhealth nvsinner` — external-tools health check |

### Git

| Keys | Mode | Action |
|------|------|--------|
| `]h` / `[h` | n | Next / previous changed hunk |
| `<leader>hp` | n | Preview hunk (inline diff) |
| `<leader>hs` / `<leader>hr` | n | Stage / reset hunk |
| `<leader>hS` / `<leader>hR` | n | Stage / reset whole buffer |
| `<leader>hb` | n | Blame current line (full popup) |
| *(automatic)* | — | Inline blame on the cursor line: ` summary • date • author • <sha>` plus ` branch #PR` for the merge that brought it in. `:NvSinnerBlameToggle` turns it off |
| `<leader>gd` | n | Diffview: working tree vs index — **at most one tab**: pressed again it returns to the view already open (refreshing its file list) instead of stacking a second one |
| `<leader>gh` / `<leader>gH` | n | Diffview: current-file / whole-repo history. `<leader>gH` is **one tab** like `<leader>gd`; `<leader>gh` opens one per file, since two files are two histories |
| `<leader>gq` | n | Diffview: close |
| `<leader>gi` | n | Diffview: **into** the diff — open on the current file (or the one selected in the tree) at the current line, focus the working-tree pane; inside the view, toggle diff ⇄ file list |
| `gf` | n | Diffview (inside the view): **out** to the editable file, leaving the tab open — `<leader>gd` comes back to it, `<leader>gq` closes it |
| `<leader>gu` | n | Git: **unified inline diff** toggle — the old version of each hunk as virtual lines above the new one, changed lines washed, word-level changes tinted, in the real editable buffer |
| Click a diff file row | mouse | Preview that file's diff — **one click**, not two; focus stays in the list so you can walk the changes (same `:NvSinnerMenu` → "Explorer click" setting as the tree) |

### Sessions, folds, windows & misc

| Keys | Mode | Action |
|------|------|--------|
| `<leader>SQ` | n | Stop session, quit without saving |
| `<leader>Sc` | n | Restore last session for current dir |
| `<leader>Sl` | n | Restore last session |
| `<leader>za` | n | Toggle fold |
| `<leader>zl` | n | Toggle **LSP structural folding** in this window (Neovim 0.12 `vim.lsp.foldexpr`). While it is on, `<leader>zf` cannot create manual folds — the two `'foldmethod'`s are exclusive, which is why this is a toggle and not a default |
| `<leader>zf` | v | Fold selected lines |
| `<C-Y>` | n | Save file (with notification) |
| `<C-U>` / `<C-R>` | n | Undo / redo (with notification) |
| `<leader>u` | n | Undo-history browser (`:Undotree`, Neovim 0.12 builtin) — press again to close |
| `<Tab>` / `<S-Tab>` | i, s | Jump to the next / previous snippet placeholder. Insert-mode `<Tab>` is shared: an open completion popup wins, then a pending AI ghost, then the snippet jump, then a literal Tab |
| `<C-Up>` | n | Grow window height (+2) |
| `<C-,>` / `<C-.>` | n, t | Grow / shrink window width (±20 columns) — also from inside a terminal (resize the AI column) |
| `<C-;>` / `<C-'>` | n, t | Grow / shrink window height (±5 rows) — also from inside a terminal |
| `<leader>?` | n | Show buffer-local keymaps (which-key) |
| `<cr>` / `gO` | n (image buffer) | Reopen image in Quick Look / open in Preview.app |

## Plugins & their commands

### Appearance

| File | Plugin | What it does |
|------|--------|--------------|
| `theme.lua` | — (native) | Active colorscheme: **carbon**, a self-contained oxocarbon/IBM Carbon port (`colors/carbon.lua` + `lua/core/carbon.lua`) |
| `lualine.lua` | lualine.nvim | Global statusline with the carbon mode→accent chip |
| `incline.lua` | incline.nvim | **Disabled** — replaced by the native winbar file badge (`lua/core/filebadge.lua`) |
| `barbacue.lua` | barbecue.nvim | VS Code-style breadcrumbs (winbar) |
| `render-markdown.lua` | render-markdown.nvim | **Disabled** — replaced by the native markdown reading view (`lua/core/markdown.lua`, same "Open view" chip + `<leader>m`) |
| `dashboard.lua` | alpha-nvim | Start screen — the NvSinner ASCII mark + clickable quick-action menu over the wallpaper |
| `noice.lua` | noice.nvim | Centered floating `:` cmdline; messages routed through nvim-notify |
| `colorizer.lua` | nvim-colorizer | **Disabled** — replaced by the native hex color chips (`lua/core/colorizer.lua`) |
| `identmini.lua` | indentmini.nvim | **Disabled** — replaced by the native current-scope indent guide (`lua/core/indent.lua`) |
| `notify.lua` | nvim-notify | Pretty notifications (replaces `vim.notify`) |
| `illuminate.lua` | vim-illuminate | **Disabled** — replaced by the native occurrence highlight (`lua/core/illuminate.lua`) |
| `scrollbar.lua` | satellite.nvim | Slim right-edge scrollbar with hunk/diagnostic/search marks (sits beside the minimap, not under it) |
| `mini-animate.lua` | mini.animate | Window open/close/resize easing + cursor trail |
| `cursorline.lua` | nvim-cursorline | **Disabled** — the cursor-word highlight it provided is covered by the native occurrence highlight (`lua/core/illuminate.lua`) |

### Navigation & search

| File | Plugin | Keys |
|------|--------|------|
| `telescope.lua` | telescope.nvim | `<leader>f` files · `<leader>sf` grep · `<leader>fb` buffers · `<leader>sd/sk/sc/sr/sh/ss/sR` diagnostics/keymaps/commands/resume/help/symbols/references |
| `neo-tree.lua` | neo-tree.nvim | `<leader>e` toggle file explorer (reveals current file) · Files / Buffers / **Git** tabs — Git opens the `<leader>gd` diff |
| `leap.lua` | leap.nvim | `s` forward · `S` backward · `gs` across windows |
| `smooth-scroll.lua` | neoscroll.nvim | `<PageUp>` / `<PageDown>` smooth scroll — a quarter window, smaller in Neo-tree |
| `nvim-window-picker.lua` | window-picker | **Disabled** — replaced by the native letter-overlay picker (`lua/core/window-picker.lua`, still drives Neo-tree's `w`) |

### Editing

| File | Plugin | Keys |
|------|--------|------|
| `completions.lua` | nvim-cmp + LuaSnip | `<CR>` confirm · `<C-Space>` trigger · `<C-b>`/`<C-f>` scroll docs · `<C-e>` abort |
| `comment.lua` | Comment.nvim | **Disabled** — Neovim's builtin commenting covers it: `gcc` line · `gc{motion}` / visual `gc` |
| `surround.lua` | nvim-surround | `ys{motion}{char}` add · `ds{char}` delete · `cs{old}{new}` change |
| `autopairs.lua` | nvim-autopairs | Auto-closes brackets/quotes |

### Language tooling

| File | Plugin | Keys / notes |
|------|--------|--------------|
| `lsp-config.lua` | mason + native `vim.lsp` | `K` hover · `gd` definition · `<leader>lf` format · `<leader>lh` inlay hints · `<leader>ca` code action · `<leader>rn` rename · `:Mason` |
| `trouble.lua` | trouble.nvim | `<leader>xx` diagnostics · `<leader>xX` buffer · `<leader>xs` symbols · `<leader>xl`/`<leader>xq` loclist/qflist |
| `none-ls.lua` | none-ls + extras | Formatters/linters: stylua, prettier, eslint_d, shfmt |
| `mason-tools.lua` | mason-tool-installer | Auto-installs stylua/prettier/eslint_d/shfmt via Mason on first boot (`:MasonToolsInstall` retries) |
| `diagnostics.lua` | tiny-inline-diagnostic | Rounded inline bubble for the cursor-line diagnostic |
| `nvim-treesitter.lua` | nvim-treesitter | Syntax highlighting & indentation |

### Workflow

| File | Plugin | Keys |
|------|--------|------|
| `toggleterm.lua` | toggleterm.nvim | `<leader>t` / `<leader>t2…9` horizontal terms (20% height) · `<leader>j` / `<leader>j2…9` AI sessions |
| `persistence.lua` | persistence.nvim | **Disabled** — native sessions in `lua/core/sessions.lua` keep `<leader>SQ` / `<leader>Sc` / `<leader>Sl` |
| `git-blame.lua` | git-blame.nvim | **Disabled** — native inline blame in `lua/core/git-blame.lua`, which also names the merged-from branch + PR (`:NvSinnerBlameToggle`) |
| `gitsigns.lua` | gitsigns.nvim | Sign-column hunk markers · `]h` / `[h` hunks · `<leader>h*` actions |
| `diffview.lua` | diffview.nvim | `<leader>gd` diff (one tab, always the same one) · `<leader>gh`/`<leader>gH` file/repo history (`gH` one tab too) · `<leader>gq` close · `<leader>gi` into the diff, `gf` out |
| `todocomment.lua` | todo-comments.nvim | **Disabled** — replaced by the native keyword chips + gutter icons (`lua/core/todo.lua`) |
| `which-key.lua` | which-key.nvim | `<leader>?` shows buffer keymaps · group labels for the leader namespaces |
| `lsp/neoconf.lua` | neoconf.nvim | `:Neoconf` project-local settings |
