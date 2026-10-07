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
- `dashboard.lua` — alpha-nvim start screen (`event = "VimEnter"`, shows on a
  bare `nvim`). The footer line is the version-check surface
  (`lua/core/version.lua`). **It no longer rotates a random dev quote; that
  was removed on request, so don't bring it back.** `footer.val` is a
  **function** re-resolved on every draw. It shows:
  - a spinner while the once-per-session check runs (a self-stopping
    `vim.uv` timer drives `alpha.redraw()`);
  - the `:NvSinnerUpdate` prompt (`NvSinnerUpdateAvail`, `base10` attention)
    when an update is available;
  - an empty line otherwise. When current, the separate muted "up to date"
    element (`NvSinnerVersion`, `base03`) carries the message. The function
  must return a **table of lines, never a `\n` string** — alpha renders `\n`
  strings across multiple screen lines but advances its line accounting by
  only 1, corrupting every later element's highlights. All groups live in
  `apply_dashboard_hl()` (carbon roles, re-applied on `ColorScheme`).
  Just before `alpha.setup()` it calls
  `require("core.wallpaper").attach_alpha(alpha)`, which wraps `alpha.draw` so
  the optional wallpaper is repainted after every draw (alpha's draw clears
  **every** namespace). Contract in `lua/core/CLAUDE.md` §Dashboard wallpaper.
- `lualine.lua` — statusline with the carbon **mode→accent** map: the mode
  block is a solid accent chip with dark `base00` text (normal `base09`,
  insert `base12`, visual `base14`, replace `base08`, command `base13`,
  terminal `base11`); all other sections stay `base04` on `base00`. The
  AI cockpit badge that used to ride `lualine_x` was removed for performance
  (statusline components re-evaluate on every redraw); per-session status
  lives in the terminal winbars and the `<leader>ja` picker.
  `lualine_b` opens with two **clickable icons** in `base09`: a terminal
  (`\u{f489}`, left click → `statusmark.terminal_click` = the `<leader>t` map,
  toggle horizontal terminal 1) and a robot (`\u{f06a9}`, →
  `statusmark.agents_click` = the `<leader>xa` map, `:NvSinnerAgents`). Both
  come from `statusmark.map_click(lhs)`, which looks the map up with `maparg`
  and runs its callback or `<Cmd>…<CR>` rhs — never feedkeys, which would pay
  the `timeoutlen` wait. They are icons, so NOT shimmer-wrapped. **Write the
  glyphs as `\u{…}` escapes**: a literal private-use glyph was silently stripped
  once, leaving an empty string that lualine hides.
  `lualine_c` leads with the **project name** from `lua/core/project.lua`
  (`󰉋` icon in `base09`, name in the section's inherited `base04` — the
  icon-colored/name-muted split `filebadge.lua` uses, so the bar stays
  gray-dominant). It obeys the same redraw doctrine as the removed badge: the
  root lookup is cached in `core/project.lua` and only re-resolved on
  `DirChanged`, so the component is a table read per redraw.
  **That left-hand project component only shows under `MIN_COLUMNS` (120)**:
  from there up the name moves into the centered mark below, and both `cond`s
  read `core/statusmark.lua`'s one constant, so the name appears exactly once at
  any width.
  `lualine_c` then closes with the **centered identity mark**
  `‹ NvSinner ▏<project> ›`; a **left click on it opens `:NvSinnerHelp`**
  (lualine's per-component `on_click` → `statusmark.click`).
  **The whole bar shimmers**: every gray text component (branch, project,
  filename, the mark, filetype, progress) carries `fmt = mark.fmt(<id>)` from
  `lua/core/statusmark.lua` (full contract in `lua/core/CLAUDE.md`
  §Statusline shimmer), and one subtle band sweeps the bar every few seconds —
  italic `NvStatusMark*` grays between `base03` and `base04`, peak `base04`, so
  it never outshines body text. The mode + location chips and diagnostics are
  NOT wrapped (their colors are semantic; the chips' bg is not `base00`).
  **The `fmt` ids must ascend left→right** — the module detects each evaluation
  pass by them; a new wrapped component takes the id that keeps the order.
  `fmt` hands lualine a `%{%…%}` **expression**, not the text: lualine stores
  its statusline as a literal string and does not escape it, so Neovim
  re-evaluates the expression on every repaint and an animation frame repaints
  one row instead of re-running lualine. The mark is centred by a bare `"%="` string component: lualine
  emits exactly one `%=` of its own ahead of the first non-empty x/y/z section,
  so a second one makes **two** separation points and Neovim splits the free
  space equally between them. That centres the mark in the space the real
  sections leave — screen-centre only when the two sides weigh the same; with a
  heavy left side it sits `(left − right) / 2` columns right of true centre
  (measured: +14 at 160 columns with branch + project + filename). Exact
  centring is NOT reachable this way — it needs the rendered widths of both
  sides, which lualine does not expose. A `cond` hides the mark under 120
  columns so it never crowds a narrow terminal. `NvSinner` is written in
  **plain letters on purpose**, so the mark reads like the rest of the bar; an
  earlier draft used superscript modifier letters (`ᴺⱽˢᴵᴺᴺᴱᴿ`), which no
  FiraCode face carries — they came from font fallback and looked foreign next
  to the other sections. Every glyph in the mark (`‹ › ▏` included) is in
  FiraCode itself.
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
  Barbecue's own navic attacher is disabled; navic auto-attaches with
  `vue_ls > vtsls` preference so the intentional two-client Vue stack does not
  warn or let TypeScript-only symbols win for an SFC.
  **markdown is in `exclude_filetypes`** so it doesn't fight
  `core/filebadge.lua`'s markdown winbar (badge + "Open view" chip) for the
  same line.
- `render-markdown.lua` — `render-markdown.nvim` is **disabled**
  (`enabled = false`): replaced by the native reading view in
  `lua/core/markdown.lua` (pattern-based visible-range scan — heading bars,
  bullets, checkboxes, quote bars, fence shading, rules — same `_G.NvMdReader`
  seam, same `<leader>m` / winbar "Open view" chip). The (misdiagnosed) markdown
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
- `notify.lua` — `nvim-notify` owns `vim.notify` (noice's notify routing is
  off). Toasts are short-lived (`timeout = 250` + the quick `fade` stage) and
  **one line**: `render = "compact"` folds the icon + title into the message
  line (`<icon> | <title>: <message>`) instead of the default renderer's
  separate header row. Only the header is folded; a multi-line message keeps
  its extra lines.
- `mini-animate.lua` — `mini.animate`: eases window open/close/resize (the AI
  column slides in) + a short cursor trail. **Scroll is disabled here** —
  that's `neoscroll`'s job (`smooth-scroll.lua`); don't enable both.
- `smooth-scroll.lua` — `neoscroll.nvim`, the **single** scroll owner (FA-17).
  It maps only `<PageUp>` / `<PageDown>`: `setup()` is deliberately never
  called, so neoscroll's default `<C-d>`/`<C-u>`/`<C-f>`/`zz`… set is never
  installed and those keys stay native. The step is a **window fraction**, not
  a line count — `STEP = 0.25`, and `STEP_BY_FILETYPE["neo-tree"] = 0.15`
  because a file list is scanned row by row — so a page scales with the split
  instead of assuming a height. A quarter window is half of `&scroll` (what the
  old `ctrl_d`/`ctrl_u` helpers travelled) and a quarter of `<S-Down>`/`<S-Up>`,
  Vim builtins for `CTRL-F`/`CTRL-B` that stay the long jump: measured on a
  55-row window, `<PageDown>` moves 14 lines where `ctrl_d` moved 28.
  The neo-tree step lives in a filetype table on the global map, **not** a
  buffer-local override — neo-tree binds nothing to these keys (its stock
  `<C-f>`/`<C-b>` scroll the *preview*), and a table lookup avoids racing this
  spec's own `VeryLazy` load.
  Two things that look like the step size but aren't: the cursor settling on
  window row 7 is `scrolloff = 6` (`core/options.lua`) — neoscroll pins the
  cursor to `scrolloff + 1` for the whole animation, so the first press off the
  top of a buffer moves it there once and every later press holds it; and
  `duration` stays at **10 ms** because neoscroll emits one `WinScrolled` per
  animation frame, which `colorizer` / `todo` / `markdown` / `indent` /
  `ui-touch` all debounce on.
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
