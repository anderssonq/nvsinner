# lua/plugins/editor/ — text editing & syntax contracts

- `nvim-treesitter.lua` — **the spec pins `branch = "master"` on purpose.**
  Upstream flipped its default branch master → `main` (a full rewrite — no
  `nvim-treesitter.configs`, parser rebuilds failed to link on arm64, error
  flood; incident 2026-07-03, post-mortem FA-24 in
  `nvsinner-failure-archaeology`). Do NOT remove the pin. `:NvSinnerSync`'s
  branch-jump guard (`lua/core/sync.lua`) exists because of this incident;
  rollback recipe: `git restore lazy-lock.json` + `Lazy! restore`.
- Treesitter is the single source of syntax colour — LSP semantic tokens are
  disabled in `lua/plugins/lsp/lsp-config.lua` (see that folder's CLAUDE.md).
- `comment.lua` — `Comment.nvim` is **disabled** (`enabled = false`):
  Neovim's builtin commenting (0.10+) covers it — `gcc` toggles the current
  line, `gc{motion}` / visual `gc` toggle a region, commentstring-aware via
  treesitter. Kept as a one-line revert.
- `todocomment.lua` — `todo-comments.nvim` is **disabled** (`enabled =
  false`): replaced by the native keyword-chip module in `lua/core/todo.lua`
  (visible-range `TODO:`/`FIXME:`… scan → carbon accent chips; drops a
  plenary consumer). Kept as a one-line revert.
- `autopairs.lua`, `surround.lua` — standard lazy-loaded editing plugins; no
  special contracts beyond the repo conventions.
