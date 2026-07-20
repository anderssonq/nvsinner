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
