# lua/plugins/navigation/ — navigation plugin notes

- `neo-tree.lua` — `<leader>e` toggles the tree (reveals the current file);
  it reads the persisted `tree_side` setting from `core/settings.lua` on each
  toggle, so the side changes live via `:NvSinnerMenu`. Folder colors come
  from the carbon folder packs (`M.folder_colors()` in `lua/core/carbon.lua`).
  The mouse-hover row wash on tree rows is native —
  `lua/core/neotree-hover.lua`, driven from ui-touch's `<MouseMove>` handler.
  `source_selector` puts **Files / Buffers / Git tabs in the tree's winbar**
  (that winbar is unowned: ui-touch's `SKIP_FT` lists `neo-tree`, filebadge
  only claims markdown). Tab colors are the carbon `NeoTreeTab*` groups in
  `colors/carbon.lua` — neo-tree defines those groups itself with hardcoded
  near-black hexes, so carbon must override them or the tabs ignore the
  theme; they carry both `fg` and `bg` so neo-tree's own
  `create_highlight_group` skips them. **`window.width` is 38 for the tabs'
  sake**: `tabs_layout = "equal"` splits the width into fixed thirds and
  `" 󰈚 Buffers "` truncates in a narrower third (measured: 38 renders all
  three labels whole) — narrowing the tree re-truncates the labels.
- **The Git tab is an ACTION tab, not a neo-tree source.** Clicking it (or
  reaching it with `<` / `>`) runs `<leader>gd`'s `open_diff()` — through the
  `_G.NvDiffview` seam published by `lua/plugins/git/diffview.lua` — so it keeps
  the one-diff-tab contract, and the tree stays on the source it was showing.
  It never scans git. Load-bearing details (pinned by
  `tests/plugins/neotree_spec.lua`, verified by a headless probe):
  - **Appended after the config merge, never listed in `setup()`.** neo-tree's
    merge drops every `source_selector.sources` entry that is not a loaded
    source (`neo-tree/setup/init.lua`). And `setup()` itself only *stores* the
    user config — the merge is deferred to `ensure_config()` — so `config()`
    forces `require("neo-tree").ensure_config()` and inserts into the returned
    `source_selector.sources`. Appending to the raw `.config` hits `nil` on a
    fresh boot. The selector re-reads that table on every winbar redraw.
  - **Both entry points are intercepted.** A tab click lands in the global
    `_G.___neotree_selector_click` (winbar `%@…@` regions only call globals);
    it is wrapped, decoding `index = id % (#sources + 1)` exactly as
    `neo-tree/ui/selector.lua` does, and every non-Git click goes to the
    original. `<` / `>` are remapped in `window.mappings` to `cycle_tab`, which
    mirrors upstream's wrap-around and delegates to
    `state.commands.prev_source/next_source` for real sources. Unwrapped, both
    would hand `nvsinner_git` to `neo-tree.command.execute`, which errors.
  - The Git tab is never "active": it opens a tab page, it is not a view of the
    tree. So `>` from Buffers always lands on Git (the diff) — `<` goes back.
- **Click-to-open** — neo-tree's ONLY stock mouse binding is
  `["<2-LeftMouse>"] = "open"` (`neo-tree/defaults.lua`). A top-level
  `window.mappings` adds `<LeftRelease>` (single click opens a file / toggles a
  folder — `open` already routes directories to `toggle_node`) behind the
  persisted **`tree_click`** setting (`:NvSinnerMenu` → "Explorer click",
  default `single`). That setting covers **every explorer**: diffview's file
  panels read the same key (`lua/plugins/git/CLAUDE.md`), so one knob decides
  what a click costs everywhere. Notes that matter when editing this:
  - Mappings **merge** with the ~40 stock bindings; they are discarded only by
    `use_default_mappings = false`, which must never be set (pinned by
    `tests/plugins/neotree_spec.lua`).
  - `<LeftRelease>`, not `<LeftMouse>`: the press still positions the cursor,
    and the handler acts on the row it selected — the same split every
    NvSinner modal uses.
  - **`getmousepos().line` clamps to the last buffer line**, so a click on the
    empty space below the tree would open the last file.
    `core.mouse.clicked_line()` (shared with diffview's panels) recovers the
    true row from `getwininfo()`'s `topline` + `winbar` offset and bails past
    the last node (and on the selector winbar, which owns its own `%@…@` click
    regions).
  - In `single` mode the `<2-LeftMouse>` map is a deliberate **no-op**: the
    second click of a reflexive double-click would re-collapse the folder the
    first click just expanded.
  - The handlers read the setting **live**, so switching applies on the next
    click without re-running neo-tree's `setup()` (its applier is a no-op).
- **Click, never drag-select** — sweeping the pointer across tree rows used to
  paint a Visual selection over the filenames, which is meaningless in an
  explorer and swallowed the next click. A `FileType neo-tree` autocmd
  (augroup `nvsinner_neotree_mouse`) hands each tree buffer to
  `core.mouse.lock_selection()`, which locks the six selection-starting mouse
  gestures (`<LeftDrag>`, `<2-`/`<3-`/`<4-LeftDrag>`, `<3-`/`<4-LeftMouse>`).
  Points that are load-bearing:
  - **An autocmd, not `window.mappings`.** The locks must be **expr** maps (to
    let a resize-drag fall through), and `'mouse'` is a global-only option, so
    buffer-local maps are the only lever available at all.
  - **`<LeftRelease>` must stay a plain consuming callback.** Vim finalises a
    mouse selection on the RELEASE, from the remembered press position — so an
    expr/fall-through `<LeftRelease>` would re-enter Visual mode even with every
    drag gesture locked. Verified by probe; pinned by `neotree_spec.lua`.
  - **Visual mode itself is untouched**: neo-tree binds real visual commands
    (copy/cut/delete over a multi-row selection). Only the MOUSE path is cut.
  - `<2-LeftMouse>` is deliberately NOT in the lock list — both explorers
    already claim it, so mouse word-select can never fire.
- **The Buffers tab does NOT show git symbols, on purpose.** neo-tree's buffers
  source subscribes a `BEFORE_RENDER` handler that calls the **synchronous**
  `git.status` (`vim.fn.system`, `neo-tree/git/init.lua:251`) on *every render*
  — and `git_status_async` does **not** cover it: only the filesystem source
  reads that option. That subscription lives in an
  `elseif config.before_render` branch, so defining `buffers.before_render`
  (a no-op) is what stops it being registered at all.
  Measured on a synthetic 24k-file repo with a 24k-file ignored `node_modules`:
  the call cost **~64 ms per render** before, none after. Files keeps its git
  state (that source uses the genuinely async path).
- **The `git_status` source tab is REMOVED — do not re-add it** (the Git tab
  above is the action tab, which is a different thing). Its scan is the tab's content
  and is NOT fixable from config: `git_status/lib/items.lua` hard-calls the
  same sync `git.status` with `--untracked-files=all` on top of the default
  `--ignored=traditional`, which enumerates every ignored file and then
  *discards* it. Measured on the same repo as above: **73 ms** vs 14 ms for a
  plain `git status`, i.e. `--ignored` is a ~5× multiplier that scales with
  the ignored tree. Diffview already owns git (`<leader>gd` etc., see
  `lua/plugins/git/CLAUDE.md`), so the tab was pure cost — it is dropped from
  `source_selector.sources` (the `git_status` source itself stays in
  neo-tree's defaults, so a deliberate `:Neotree source=git_status` still
  works if ever needed). **Do not "fix" the scan with
  `core.fsmonitor` / `core.untrackedCache`** — measured A/B on the same repo,
  fsmonitor made it *worse* (plain status 0.412 s vs 0.132 s per 10 calls;
  with `--ignored` 0.828 s vs 0.674 s): the daemon's IPC costs more than it
  saves at this scale and never helps `--ignored` enumeration. The real fix is
  upstream (neo-tree calling `git.status_async` for these two sources).
- `telescope.lua` — `<leader>f` find files (incl. hidden dotfiles),
  `<leader>sf` live grep, `<leader>fb` buffers, plus the `<leader>s*` pickers
  (diagnostics / keymaps / commands / resume / help / symbols / references).
  `<leader>ld` / `<leader>lt` peek at the LSP definition / type definition in
  the picker with preview instead of jumping (`gd` / `grt` still jump).
  Search pickers use `layout_strategy = "flex"`: horizontal at 100+ columns
  (42% results / 58% preview), vertical below that, with the prompt and best
  matches at the top in both shapes. Results stay on the solid `blend` surface
  and preview on darker `shade`, even in transparent mode. Pickers with a real
  preview get `core.backdrop`; preview-less pickers do not.
  telescope-ui-select skins `vim.ui.select` (used by the `<leader>ja`/`jc`
  AI session pickers). The spec's `init` shims `vim.ui.select` so the FIRST
  call of a session lazy-loads telescope and re-dispatches — without it, a
  select fired before telescope loaded fell back to Neovim's builtin
  numbered prompt (rendered inconsistently by noice popup/cmdline).
- `leap.lua` — `s` / `S` / `gs` motions.
- `nvim-window-picker.lua` — **disabled** (`enabled = false`): replaced by
  the native letter-overlay picker in `lua/core/window-picker.lua`, which
  serves `require("window-picker")` via `package.preload` so neo-tree's
  open-with (`w`) works unchanged (the shim defers to the real plugin if the
  stub is re-enabled). Kept as a one-line revert.
