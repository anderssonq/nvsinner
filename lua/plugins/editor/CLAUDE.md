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
- `autopairs.lua`, `comment.lua` (`gcc` / `gbc` toggles), `surround.lua`,
  `todocomment.lua` — standard lazy-loaded editing plugins; no special
  contracts beyond the repo conventions.
