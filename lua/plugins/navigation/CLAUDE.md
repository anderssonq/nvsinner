# lua/plugins/navigation/ — navigation plugin notes

- `neo-tree.lua` — `<leader>e` toggles the tree (reveals the current file);
  it reads the persisted `tree_side` setting from `core/settings.lua` on each
  toggle, so the side changes live via `:NvSinnerMenu`. Folder colors come
  from the carbon folder packs (`M.folder_colors()` in `lua/core/carbon.lua`).
  The mouse-hover row wash on tree rows is native —
  `lua/core/neotree-hover.lua`, driven from ui-touch's `<MouseMove>` handler.
- `telescope.lua` — `<leader>f` find files (incl. hidden dotfiles),
  `<leader>sf` live grep, `<leader>fb` buffers, plus the `<leader>s*` pickers
  (diagnostics / keymaps / commands / resume / help / symbols / references).
  telescope-ui-select skins `vim.ui.select` (used by the `<leader>ja` AI
  session picker).
- `leap.lua` — `s` / `S` / `gs` motions.
- `nvim-window-picker.lua` — **disabled** (`enabled = false`): replaced by
  the native letter-overlay picker in `lua/core/window-picker.lua`, which
  serves `require("window-picker")` via `package.preload` so neo-tree's
  open-with (`w`) works unchanged (the shim defers to the real plugin if the
  stub is re-enabled). Kept as a one-line revert.
