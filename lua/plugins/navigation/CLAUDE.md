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
  `" 󰈚 Buffers "` truncates below 38 (measured) — narrowing the tree
  re-truncates the labels.
- **Click-to-open** — neo-tree's ONLY stock mouse binding is
  `["<2-LeftMouse>"] = "open"` (`neo-tree/defaults.lua`). A top-level
  `window.mappings` adds `<LeftRelease>` (single click opens a file / toggles a
  folder — `open` already routes directories to `toggle_node`) behind the
  persisted **`tree_click`** setting (`:NvSinnerMenu` → "Neo-tree click",
  default `single`). Notes that matter when editing this:
  - Mappings **merge** with the ~40 stock bindings; they are discarded only by
    `use_default_mappings = false`, which must never be set (pinned by
    `tests/plugins/neotree_spec.lua`).
  - `<LeftRelease>`, not `<LeftMouse>`: the press still positions the cursor,
    and the handler acts on the row it selected — the same split every
    NvSinner modal uses.
  - **`getmousepos().line` clamps to the last buffer line**, so a click on the
    empty space below the tree would open the last file. `clicked_line()`
    recovers the true row from `getwininfo()`'s `topline` + `winbar` offset and
    bails past the last node (and on the selector winbar, which owns its own
    `%@…@` click regions).
  - In `single` mode the `<2-LeftMouse>` map is a deliberate **no-op**: the
    second click of a reflexive double-click would re-collapse the folder the
    first click just expanded.
  - The handlers read the setting **live**, so switching applies on the next
    click without re-running neo-tree's `setup()` (its applier is a no-op).
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
- **The Git tab's blocking scan is NOT fixable from config** — it is the tab's
  content. `git_status/lib/items.lua` hard-calls the same sync `git.status`
  with `--untracked-files=all` on top of the default `--ignored=traditional`,
  which enumerates every ignored file and then *discards* it. Measured on the
  same repo: **73 ms** vs 14 ms for a plain `git status`, i.e. `--ignored` is a
  ~5× multiplier that scales with the ignored tree. Since it is only paid when
  you deliberately click "Git", it is left alone. **Do not "fix" this with
  `core.fsmonitor` / `core.untrackedCache`** — measured A/B on the same repo,
  fsmonitor made it *worse* (plain status 0.412 s vs 0.132 s per 10 calls;
  with `--ignored` 0.828 s vs 0.674 s): the daemon's IPC costs more than it
  saves at this scale and never helps `--ignored` enumeration. The real fix is
  upstream (neo-tree calling `git.status_async` for these two sources).
- `telescope.lua` — `<leader>f` find files (incl. hidden dotfiles),
  `<leader>sf` live grep, `<leader>fb` buffers, plus the `<leader>s*` pickers
  (diagnostics / keymaps / commands / resume / help / symbols / references).
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
