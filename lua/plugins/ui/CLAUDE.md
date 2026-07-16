# lua/plugins/ui/ — UI chrome contracts

One palette, meaningful accents. Everything here pulls carbon roles from
`lua/core/carbon.lua` (bg `base00`, panels `base01`/`base02`, body `base04`,
muted `base03`, floats on `blend`) with accents used **semantically**: `base09`
blue = identity/active, `base10` magenta = modified/attention, `base12` pink =
busy, `base11` light blue = terminal focus. When editing these, do **not**
hardcode hexes or introduce off-palette colours (the old incline blue / the old
barbecue tokyonight defaults were removed for exactly this reason) — reference
a role. Full theme docs: `lua/core/CLAUDE.md` §Theme.

- `theme.lua` — a local virtual lazy spec (`lazy = false, priority = 1000`)
  whose only job is applying `:colorscheme carbon` at startup. The palette
  truth is `lua/core/carbon.lua`; the colorscheme is `colors/carbon.lua`.
- `lualine.lua` — statusline with the carbon **mode→accent** map: the mode
  block is a solid accent chip with dark `base00` text (normal `base09`,
  insert `base12`, visual `base14`, replace `base08`, command `base13`,
  terminal `base11`); all other sections stay `base04` on `base00`. The
  AI cockpit badge that used to ride `lualine_x` was removed for performance
  (see `docs/nvsinner-perf-analysis.md` §5); per-session status lives in the
  terminal winbars and the `<leader>ja` picker.
- `incline.lua` — **disabled** (`enabled = false`): replaced by the native
  winbar badge in `lua/core/filebadge.lua` — incline's float overlapped the
  first buffer line on winbar-less (markdown) windows and its non-focusable
  float couldn't host a clickable "Open view" chip. Kept as a one-line revert.
- `barbacue.lua` — `barbecue` breadcrumb winbar (path > LSP symbols) on code
  windows, recolored: muted dirname/separators, `base04` basename, soft
  `base09` symbol icons, `base10` reserved for the `modified` marker. Pairs
  with the terminal winbar so every window has a consistent top bar. Its
  `custom_section` appends the native file badge (focus dot · icon · filename ·
  modified dot) from `lua/core/filebadge.lua` at the right end.
  **markdown is in `exclude_filetypes`** so it doesn't fight
  `core/filebadge.lua`'s markdown winbar (badge + "Open view" chip) for the
  same line.
- `render-markdown.lua` — `render-markdown.nvim` is **disabled**
  (`enabled = false`): replaced by the native reading view in
  `lua/core/markdown.lua` (pattern-based visible-range scan — heading bars,
  bullets, checkboxes, quote bars, fence shading, rules — same `_G.NvMdReader`
  seam, same `<leader>m` / winbar "Open view" chip). The 0.12.x markdown
  injection-query patch moved to the top of that core module. Kept as a revert
  path, but reverting is NOT a one-liner: flipping `enabled = true` must be
  paired with removing the `require("core.markdown")` line from `init.lua`, or
  `_G.NvMdReader`/`<leader>m` double-register.
- `noice.lua` — `noice.nvim`: centered floating `:` cmdline
  (`command_palette` preset), messages routed through `nvim-notify`,
  carbon-recessed popups on `blend` with invisible borders
  (`NoiceCmdlinePopup*` re-applied on `ColorScheme`). **LSP hover/signature
  are off on purpose** — the markdown treesitter highlighter crashes on
  Neovim 0.12.x transient floats (same reason `core/ui-touch.lua` renders
  hover as plain text); `K` keeps the native handler. Do not enable noice's
  lsp markdown paths.
- `mini-animate.lua` — `mini.animate`: eases window open/close/resize (the AI
  column slides in) + a short cursor trail. **Scroll is disabled here** —
  that's `neoscroll`'s job (`smooth-scroll.lua`); don't enable both.
- `diagnostics.lua` lives in `lua/plugins/lsp/` (it owns
  `vim.diagnostic.config`) — see that folder's CLAUDE.md.
- `scrollbar.lua` — `satellite.nvim`: slim decoration-based right-edge
  scrollbar overlaying git hunks / diagnostics / search / cursor. Excludes
  neo-tree, toggleterm, telescope, dashboard, etc.
- `which-key.lua` — `which-key.nvim` with **group labels** in `opts.spec` for
  the leader namespaces (`a` ai, `c` code, `g` git, `h` hunks, `j` ai
  sessions, `l` lsp, `s` search, `S` session, `t` terminal, `x` trouble ·
  nvsinner — `x` is shared: trouble panels + the NvSinner command shortcuts in
  normal mode, the Ask-AI modal in visual mode, labeled via a `mode = "x"`
  spec entry); individual entries come from each map's `desc`. Do NOT add an
  empty `config` function — it would suppress the automatic `setup(opts)`
  (warned in the file).
- `illuminate.lua` — `vim-illuminate` is **disabled** (`enabled = false`):
  replaced by the native module `lua/core/illuminate.lua` (builtin
  `vim.lsp.buf.document_highlight` + a visible-range word scan fallback for
  parser-backed buffers, same delay/cutoff/denylist, panel-gray underlines on
  the `LspReference*` groups). Kept as a one-line revert.
- `identmini.lua` — `indentmini.nvim` is **disabled** (`enabled = false`):
  replaced by the native current-scope indent guide in `lua/core/indent.lua`
  (decoration-provider overlay, same only_current look, same
  `IndentLineCurrent` panel gray). Kept as a one-line revert.
- `colorizer.lua` — `nvim-colorizer` is **disabled** (`enabled = false`):
  replaced by the native hex-chip module in `lua/core/colorizer.lua`
  (visible-range `#hex` scan → bg extmarks; the plugin's css/tailwind
  machinery was unused). Kept as a one-line revert.
- `cursorline.lua` — `nvim-cursorline` is **disabled** (`enabled = false`):
  its cursorword duplicated `illuminate` and its cursorline fought
  `core/ui-touch.lua`. Kept as a one-line revert.
