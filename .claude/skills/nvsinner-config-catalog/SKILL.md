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
| `POLL_MS` | 120 | `lua/core/ai-activity.lua` | spinner frame rate + idle-check cadence (ms); busy-gated — the timer runs only while a terminal is busy (`M._ticking`) |
| `IDLE_MS` | 1200 | `lua/core/ai-activity.lua` | quiet ms before busy→idle flip |
| `SPINNER` | 10 braille frames `⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏` | `lua/core/ai-activity.lua` | busy animation |
| `LABEL_BUSY` / `LABEL_IDLE` / `DOT_IDLE` | `"working…"` / `"idle"` / `"●"` | `lua/core/ai-activity.lua` | winbar labels |
| `DEBOUNCE_MS` | 50 | `lua/core/colorizer.lua` | edit/scroll rescan coalescing (BufWinEnter/InsertLeave stay immediate) |
| `DEBOUNCE_MS` | 50 | `lua/core/todo.lua` | edit/scroll rescan coalescing (same shape as colorizer) |
| `DEBOUNCE_MS` | 50 | `lua/core/markdown.lua` | edit/scroll rescan coalescing; the autocmds cost one `M.on` boolean while the view is off |
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

## 3. Palette — carbon roles, single source

The palette is the **carbon** base16 role table (oxocarbon / IBM Carbon port),
defined ONCE in `lua/core/carbon.lua` (dark + light variants + design notes).
Every consumer — `colors/carbon.lua` (the colorscheme), `lua/core/ui-touch.lua`,
`lua/core/ai-activity.lua`, and the UI chrome specs — pulls roles via
`require("core.carbon").colors()`; raw hexes never appear in consumers.

Key role values (dark, the reference variant):

| Role | Hex | Meaning / notable consumers |
|---|---|---|
| `base00` | `#161616` | editor bg; dark text on accent chips |
| `base01` | `#262626` | panels, CursorLine, dim term bar, WinSeparator |
| `base02` | `#393939` | Visual, prompt panels, active incline chip |
| `base03` | `#525252` | comments (italic), muted/inactive text |
| `base04` | `#d0d0d0` | main body text (never pure white) |
| `base05` | `#f2f2f2` | brightest fg: float text, cmp match |
| `base09` | `#78a9ff` | blue — keywords, Type, the identity accent (incline dot, dashboard keys, NvMdBtn, cmdline icon) |
| `base10` | `#ee5396` | magenta — errors, markdown headings, modified markers |
| `base11` | `#33b1ff` | light blue — focused terminal bar (`SEP_TERM`), CurSearch |
| `base12` | `#ff7eb6` | pink — `@function`, insert mode, `NvAiBusy` busy chip bg |
| `blend`  | `#131313` | recessed float bg (borderless floats) |
| `lift`   | `#1c1c1c` | focused-pane surface (`NvFocusNormal`) |

Full table (base00–base15 + diff washes, dark AND light): `lua/core/carbon.lua`.
Statusline mode→accent map (lualine.lua): normal `base09`, insert `base12`,
visual `base14`, replace `base08`, command `base13`, terminal `base11`.

Theme feature flags (resolved by `core/carbon.lua`; `vim.g` wins over env;
pinned by `tests/core/carbon_spec.lua`):

| Flag | Default | Set via |
|---|---|---|
| background variant | `"dark"` | `vim.g.nvsinner_background` or `$NVSINNER_BACKGROUND` (`"light"` for the light table) |
| transparency | off | `vim.g.nvsinner_transparent` or `$NVSINNER_TRANSPARENT` (`true`/`1` drops surface bgs; chips/bars stay solid) |

Sanctioned hand-tuned hexes OUTSIDE the role table: the four diff washes (in
carbon.lua itself) and dashboard.lua's logo-ramp midpoint grays
(`#b6b6b6`/`#9c9c9c`/`#838383`/`#6a6a6a`) — monochrome-family only. (The
dashboard subtitle's old off-palette `#a2a9b0` was replaced with the `base04`
role on 2026-07-04.) Any other literal hex in `lua/` is a palette-audit
finding.

Re-audit: `grep -rn '#[0-9a-fA-F]\{6\}' lua/ --include='*.lua' | grep -v lua/core/carbon.lua`

## 4. Lazy-loading trigger map

Read from each spec on 2026-07-04. "startup" = loads eagerly (this config
does not set `defaults.lazy = true`); the only sanctioned eager plugins are
theme.lua and toggleterm.lua (both carry an explicit `lazy = false` with an
inline justification).

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
| lsp/mason-tools.lua | mason-tool-installer.nvim | `event = "VeryLazy"` (auto-installs stylua/prettier/eslint_d; `auto_update = false`) |
| lsp/neoconf.lua | neoconf.nvim | `cmd = "Neoconf"` |
| lsp/none-ls.lua | none-ls.nvim | `event = {BufReadPre, BufNewFile}` |
| navigation/leap.lua | leap.nvim (**Codeberg url**: `codeberg.org/andyg/leap.nvim`) | `keys = s/S/gs` (modes n/x/o) |
| navigation/neo-tree.lua | neo-tree.nvim | `cmd = "Neotree"` + `keys` |
| navigation/nvim-window-picker.lua | nvim-window-picker | `event = "VeryLazy"`, `version = "2.*"` |
| navigation/telescope.lua | telescope.nvim | `cmd = "Telescope"` + `keys` |
| terminal/persistence.lua | persistence.nvim | `event = "BufReadPre"` |
| terminal/toggleterm.lua | toggleterm.nvim | **startup** (explicit `lazy = false` — deliberate, documented in the spec: its keymaps are closures over memoised panel tables built in `config()`) |
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
| ui/theme.lua | — (local virtual spec; scheme in `colors/carbon.lua`) | `lazy = false`, `priority = 1000` (must theme at startup) |
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
