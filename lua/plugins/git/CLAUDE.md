# lua/plugins/git/ — git plugin ownership rules

- `git-blame.lua` — `git-blame.nvim` is **disabled** (`enabled = false`):
  replaced by the native inline blame in `lua/core/git-blame.lua` (async
  `git blame --porcelain` of the buffer contents → eol virtual text,
  `:NvSinnerBlameToggle`). Kept as a one-line revert. Inline blame is still
  that module's job — the gitsigns rule below is unchanged.
- `gitsigns.lua` — `gitsigns.nvim`: sign-column markers for added / changed /
  deleted lines vs. the git index (a thin `▎` bar), lazy-loaded on
  `BufReadPre` / `BufNewFile`. Hunk keymaps live in its `on_attach`: `]h` /
  `[h` navigate, `<leader>hp` preview, `<leader>hs` / `<leader>hr` stage /
  reset hunk, `<leader>hS` / `<leader>hR` stage / reset buffer, `<leader>hb`
  blame popup. Keep the **inline** blame as `core/git-blame.lua`'s job and
  the **popup** blame as gitsigns' — don't enable gitsigns
  `current_line_blame` (it would double up).
- `diffview.lua` — `diffview.nvim`: a full side-by-side `git diff` viewer
  (file panel + two versions of the file). Lazy-loaded on its `Diffview*`
  commands and keymaps: `<leader>gd` open working-tree-vs-index, `<leader>gh`
  current-file history, `<leader>gH` whole-repo history, `<leader>gq` close.
  `enhanced_diff_hl` is on for word-level highlights; everything else is left
  at defaults (intentionally minimal — just "see the differences"). The
  `<leader>g` git namespace is otherwise free; gitsigns owns the per-hunk
  `<leader>h*` maps.
