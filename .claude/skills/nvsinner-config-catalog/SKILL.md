---
name: nvsinner-config-catalog
description: >
  Catalog of every configuration axis in NvSinner with its CURRENT value, file
  location, and stability status. Load when changing any option, tunable
  constant, lazy-load trigger, palette hex, terminal id/size, LSP server list,
  or notification timeout; when adding a plugin, a plugin category, a core
  module, or a new tunable; or when asking "where is X configured" / "what is
  the current value of Y". Do NOT load it for the rationale behind a value
  (nvsinner-architecture-contract), for change gates (nvsinner-change-control),
  or to debug a misbehaving value (nvsinner-debugging-playbook).
---

# NvSinner configuration catalog

Every knob in this config, with the value **as read from the code on
2026-07-02**. Values drift: before relying on one, re-run the one-line
re-verification command in *Provenance and maintenance*.

## When NOT to use this skill

- You want to know *why* a value is what it is → `nvsinner-architecture-contract`.
- You are about to change a value and need the gates → `nvsinner-change-control`.
- A value seems right but behavior is wrong → `nvsinner-debugging-playbook`.
- You need install-time configuration (PATH, launcher, XDG dirs) → `nvsinner-build-and-run`.

## 1. Core options — `lua/core/options.lua`

Leaders (set FIRST, before lazy.nvim reads any `keys` spec):

| Variable | Value |
|---|---|
| `vim.g.mapleader` | `" "` (Space) |
| `vim.g.maplocalleader` | `"\\"` (backslash) |

The file's single `vim.cmd([[ ... ]])` block — the ONLY Vimscript allowed in
the repo, and it must not grow — sets exactly: `relativenumber`,
`foldmethod=manual`, `mouse=a`, `number`, `expandtab`, `shiftwidth=2`,
`softtabstop=2`, `tabstop=2`, `fileencoding=utf-8`, `splitbelow`, `splitright`,
`linebreak`, `wrap`, `clipboard+=unnamedplus`. Outside the block:
`vim.opt.termguicolors = true`.

Note: `splitright` is load-bearing — it is why the AI column's
`direction = "vertical"` opens on the right.

## 2. Tunable constants (core modules)

| Constant | Value | File | Effect |
|---|---|---|---|
| `POLL_MS` | 120 | `lua/core/ai-activity.lua` | spinner frame rate + idle-check cadence (ms) |
| `IDLE_MS` | 1200 | `lua/core/ai-activity.lua` | quiet ms before busy→idle flip |
| `SPINNER` | 10 braille frames `⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏` | `lua/core/ai-activity.lua` | busy animation |
| `LABEL_BUSY` / `LABEL_IDLE` / `DOT_IDLE` | `"working…"` / `"idle"` / `"●"` | `lua/core/ai-activity.lua` | winbar labels |
| toast dedup window | **250 ms** | `lua/core/autoreload.lua` (`notify_ai_edit`) | suppress double toast for same file |
| AI-edit toast | msg `"edited <name>"`, title `"🤖 AI"`, `timeout = 250` | `lua/core/autoreload.lua` | external-edit notification |
| checktime poll timer | 1000 ms | `lua/core/autoreload.lua` | disk-change poll while focus sits in a terminal |
| checktime events | `FocusGained, BufEnter, WinEnter, TermLeave, CursorHold, CursorHoldI` | `lua/core/autoreload.lua` | prompt re-check triggers |
| hover debounce | 200 ms | `lua/core/ui-touch.lua` (`on_move`) | mouse-hover doc delay |
| hover float caps | width ≤ 80, height ≤ 18 | `lua/core/ui-touch.lua` (`open_float`) | doc float size |
| first-run toast defer | 800 ms after `User VeryLazy` | `lua/core/health.lua` (`M.setup`) | wait for nvim-notify |
| first-run marker | `stdpath("state") .. "/nvsinner-health-checked"` | `lua/core/health.lua` | greet-once file |
| `M.tools` | ripgrep(`rg`), node, stylua, prettier, eslint_d | `lua/core/health.lua` | probed externals (Nerd Font is info-only, not in this table) |
| updater title | `"🔥 NvSinner"` | `lua/core/update.lua` | toast title |

> ⚠️ **Known doc drift (2026-07-02):** CLAUDE.md's Auto-reload section says the
> dedup is 500 ms; the code says **250 ms**. The code wins. See also §3 for the
> terminal-bar color drift.

## 3. Palette — canonical hexes and every file that repeats them

Canonical glass palette (defined in `lua/plugins/ui/theme.lua` and mirrored in
`lua/core/ui-touch.lua`):

| Role | Hex | Defined in |
|---|---|---|
| base bg | `#0a0a0f` | theme.lua `BG`, ui-touch.lua `BG`, ai-activity.lua (NvAiBusy fg) |
| glass surface | `#111118` | theme.lua `GLASS`, ui-touch.lua `GLASS`, noice.lua, lualine.lua |
| float border | `#333345` | theme.lua `BORDER`, noice.lua |
| primary FG | `#c5c9d5` | theme.lua `FG`, barbacue.lua, dashboard.lua, incline.lua, lualine.lua, noice.lua |
| muted FG | `#7a7f8d` | ui-touch.lua `BAR_DIM_FG`, barbacue.lua `MUTED`, dashboard.lua, incline.lua, lualine.lua |
| lone accent (kanagawa dragonRed) | `#c4746e` | ai-activity.lua `NvAiBusy` bg, barbacue.lua `CRIMSON`, dashboard.lua `CRIMSON`, incline.lua, noice.lua |
| dim separator | `#2a2a38` | ui-touch.lua `SEP_DIM` |
| focused code-pane separator | `#5b5b70` | ui-touch.lua `SEP_ACTIVE` |
| focused-terminal bar/separator | **`#80949e`** | ui-touch.lua `SEP_TERM` |
| unfocused terminal bar bg | `#16161d` | ui-touch.lua `BAR_DIM` |
| focused cursorline | `#15151c` | ui-touch.lua `CURSORLINE` |

> ⚠️ **Known doc drift (2026-07-02):** CLAUDE.md describes the focused-terminal
> bar (`NvTermFocusBar`/`NvTermFocusSeparator`) as `#c4746e` dragonRed. The code
> has always shipped `SEP_TERM = "#80949e"` (a desaturated steel-blue). The
> accent chip `NvAiBusy` IS `#c4746e`. When editing either file, match the CODE.

Files containing hex colors as of 2026-07-02 (full list — anything new outside
this list is a palette-audit finding): `lua/core/ai-activity.lua`,
`lua/core/ui-touch.lua`, `lua/plugins/ui/{theme,noice,lualine,incline,
illuminate,identmini,dashboard,barbacue}.lua`. Secondary shades used by
dashboard/incline/illuminate/barbacue (logo gradient `#e8e8ee…#3c3c4e`, hover
`#20202c`, lifts `#1c1c26`/`#121219`, illuminate washes `#1b1b24`/`#211b22`,
barbecue `DIM #54546d`/`CONTEXT #9aa0b4`, indent guide `#676767`) are
monochrome-family and allowed; new *colored* hexes besides `#c4746e` are not.

Re-audit: `grep -rn '#[0-9a-fA-F]\{6\}' lua/ --include='*.lua'`

## 4. Lazy-loading trigger map

Read from each spec on 2026-07-02. "startup" = no trigger in the spec, so
lazy.nvim loads it eagerly (this config does not set `defaults.lazy = true`).

| File | Plugin | Trigger |
|---|---|---|
| editor/autopairs.lua | nvim-autopairs | `event = "InsertEnter"` |
| editor/comment.lua | Comment.nvim | `event = "VeryLazy"` |
| editor/nvim-treesitter.lua | nvim-treesitter | `event = {BufReadPost, BufNewFile}` |
| editor/surround.lua | nvim-surround | `event = "VeryLazy"` |
| editor/todocomment.lua | todo-comments.nvim | `event = {BufReadPost, ...}` |
| git/diffview.lua | diffview.nvim | `cmd = {Diffview*}` + `keys` |
| git/git-blame.lua | git-blame.nvim | `event = "VeryLazy"` |
| git/gitsigns.lua | gitsigns.nvim | `event = {BufReadPre, ...}` |
| lsp/completions.lua | nvim-cmp | `event = "InsertEnter"` |
| lsp/diagnostics.lua | tiny-inline-diagnostic.nvim | `event = "LspAttach"`, `priority = 1000` |
| lsp/lsp-config.lua | mason(+lspconfig) | `cmd = "Mason"` / `event = "VeryLazy"` / `event = {BufReadPre, ...}` (three specs) |
| lsp/neoconf.lua | neoconf.nvim | `cmd = "Neoconf"` |
| lsp/none-ls.lua | none-ls.nvim | **startup** (no trigger) |
| navigation/leap.lua | leap.nvim (**Codeberg url**: `codeberg.org/andyg/leap.nvim`) | **startup** (no trigger) |
| navigation/neo-tree.lua | neo-tree.nvim | `cmd = "Neotree"` + `keys` |
| navigation/nvim-window-picker.lua | nvim-window-picker | `event = "VeryLazy"`, `version = "2.*"` |
| navigation/telescope.lua | telescope.nvim | `cmd = "Telescope"` + `keys` |
| terminal/persistence.lua | persistence.nvim | `event = "BufReadPre"` |
| terminal/toggleterm.lua | toggleterm.nvim | **startup** (no trigger; defines its own keymaps in `config`) |
| ui/barbacue.lua | barbecue.nvim | `event = {BufReadPost, ...}` |
| ui/colorizer.lua | nvim-colorizer.lua | `event = {BufReadPost, ...}` |
| ui/cursorline.lua | nvim-cursorline | **`enabled = false`** (disabled, kept as one-line revert) |
| ui/dashboard.lua | alpha-nvim | `event = "VimEnter"`, `priority = 1000` |
| ui/identmini.lua | indentmini.nvim | `event = {BufReadPost, ...}` |
| ui/illuminate.lua | vim-illuminate | `event = {BufReadPost, ...}` |
| ui/incline.lua | incline.nvim | `event = "VeryLazy"` |
| ui/lualine.lua | lualine.nvim | `event = "VeryLazy"` |
| ui/mini-animate.lua | mini.animate | `event = "VeryLazy"` (scroll module disabled — neoscroll owns scroll) |
| ui/noice.lua | noice.nvim | `event = "VeryLazy"` (lsp hover/signature `enabled = false` — do not enable) |
| ui/notify.lua | nvim-notify | `event = "VeryLazy"` |
| ui/scrollbar.lua | satellite.nvim | `event = {BufReadPost, ...}` |
| ui/smooth-scroll.lua | neoscroll.nvim | `event = "VeryLazy"` |
| ui/theme.lua | kanagawa.nvim | `lazy = false`, `priority = 1000` (must theme at startup) |
| ui/which-key.lua | which-key.nvim | `event = "VeryLazy"` + `keys` |

## 5. Terminal / AI axes — `lua/plugins/terminal/toggleterm.lua`

| Axis | Value |
|---|---|
| horizontal terminal height | `math.floor(vim.o.lines * 0.20)` (20%) |
| AI column width | `AI_WIDTH = 50` columns (fixed, not percentual) |
| horizontal ids | 1–9 (`<leader>t`, `<leader>t2`…`<leader>t9`) |
| AI panel ids | `99 + n` → 100–108 (`<leader>j`, `<leader>j2`…`<leader>j9`) — reserved so they never collide with 1–9 |
| AI panel flags | `direction = "vertical"`, `hidden = true` (not in the `<leader>t` list), `close_on_exit = false` |
| winbar label | `b:nv_term_label` set in `on_panel_open`: `"AI · <id-99>"` for ids ≥ 100, `"term <id>"` otherwise |
| extra toggles for session 1 | `<M-J>` (n,i,t — iTerm2 sends Esc-J for ⌘⌥J), `<D-M-j>` (n,t — GUI Neovim) |
| terminal-mode keys | `<esc>`/`jk` → terminal-normal; `<C-h/j/k/l>` window nav; `<C-w>` window prefix |
| layout enforcement | `restore_layout()`: horizontals `wincmd J` + resize, AI columns `wincmd L` + vertical resize, columns applied LAST so they win the right edge |

## 6. LSP / tooling axes

| Axis | Value | File |
|---|---|---|
| Mason auto-install | `ensure_installed = {lua_ls, ts_ls, html}`, `automatic_enable = false` | `lua/plugins/lsp/lsp-config.lua` |
| enabled servers | `vim.lsp.enable`: ts_ls, solargraph, html, lua_ls (solargraph NOT ensure_installed — needs Ruby; harmless if absent) | `lua/plugins/lsp/lsp-config.lua` |
| semantic tokens | nilled in `"*"` `on_attach` (`semanticTokensProvider = nil`) — treesitter is the only syntax-color source | `lua/plugins/lsp/lsp-config.lua` |
| none-ls sources | stylua, prettier, eslint_d (eslint_d via none-ls-extras; binary must be on PATH) | `lua/plugins/lsp/none-ls.lua` |
| diagnostics UI owner | `lua/plugins/lsp/diagnostics.lua` owns `vim.diagnostic.config` (`virtual_text = false`, rounded floats, sign icons) — keep diagnostic UI config there |
| notification timeout | `timeout = 250`, `stages = "fade"`, `fps = 60` (stages animation adds to lifetime; "fade" chosen to keep total ≈250 ms) | `lua/plugins/ui/notify.lua` |

## 7. Temporary / experimental flags

All three sites of the **Neovim 0.12.x markdown-treesitter crash workaround**
(remove together once upstream fixes `runtime/treesitter.lua` nil-node crash):

1. `lua/plugins/editor/nvim-treesitter.lua` — `highlight.disable = {markdown, markdown_inline}`
2. `lua/plugins/navigation/telescope.lua` — previewer treesitter disable for the same two
3. `after/ftplugin/markdown.lua` — `pcall(vim.treesitter.stop, 0)` + regex `syntax = "markdown"`

Also temporary-adjacent: `lua/core/ui-touch.lua` renders the mouse-hover doc as
**plain text** (not markdown) for the same crash class, and
`lua/plugins/ui/noice.lua` keeps LSP hover/signature `enabled = false`. These
stay until the project drops 0.12.x-affected versions. Full story:
`nvsinner-failure-archaeology`.

## 8. How to add …

**(a) A plugin in an existing category** — create
`lua/plugins/<category>/<name>.lua` returning a lazy spec (picked up
automatically); give it a lazy trigger (`event`/`cmd`/`keys`/`ft`) unless it
must theme startup (`lazy = false, priority = 1000`); then run the gates in
`nvsinner-change-control` and add doc rows per `nvsinner-docs-and-style`.

**(b) A NEW category folder** — same as (a) PLUS add
`{ import = "plugins.<category>" }` to `init.lua`'s spec list. lazy.nvim's
`import` does **not** recurse; without the line the folder silently never loads.

**(c) A new core module** — create `lua/core/<name>.lua`, add
`require("core.<name>")` to `init.lua` in the right position (after
`core.options`, before `lazy.setup` — order matters; see
`nvsinner-architecture-contract`).

**(d) A new tunable** — top-of-file `local UPPER_CASE = value` constant with a
comment (the ai-activity.lua pattern); document it in CLAUDE.md's subsystem
section and in THIS catalog; if behavior-bearing, add a spec
(`nvsinner-testing-and-qa`).

**(e) Disabling a plugin** — add `enabled = false` to its spec; never delete
the file (the cursorline.lua pattern — keeps a one-line revert).

## Provenance and maintenance

Facts verified: 2026-07-02, against the working tree at commit `a65af7f`, by
reading each file named above. Two CLAUDE.md discrepancies found and flagged
(§2 dedup 250 ms, §3 `SEP_TERM #80949e`).

Re-verification one-liners:

- Tunables: `grep -n 'POLL_MS\|IDLE_MS' lua/core/ai-activity.lua` · `grep -n '250\|1000' lua/core/autoreload.lua`
- Palette: `grep -rn '#[0-9a-fA-F]\{6\}' lua/ --include='*.lua'`
- Trigger map: `grep -n 'event\s*=\|cmd\s*=\|keys\s*=\|lazy\s*=\|enabled\s*=' lua/plugins/*/*.lua`
- Terminal ids/width: `grep -n 'AI_WIDTH\|99 + n\|0.20' lua/plugins/terminal/toggleterm.lua`
- LSP lists: `grep -n 'ensure_installed\|vim.lsp.enable\|semanticTokensProvider' lua/plugins/lsp/lsp-config.lua`
- Health tools: `grep -n 'name = ' lua/core/health.lua`
- Category imports: `grep -n 'import' init.lua`
