# lua/plugins/editor/ — text editing & syntax contracts

- `nvim-treesitter.lua` — **the spec pins `branch = "master"` on purpose.**
  Upstream flipped its default branch master → `main` (a full rewrite — no
  `nvim-treesitter.configs`, parser rebuilds failed to link on arm64, error
  flood; incident 2026-07-03, post-mortem FA-24 in
  `nvsinner-failure-archaeology`). Do NOT remove the pin. `:NvSinnerSync`'s
  branch-jump guard (`lua/core/sync.lua`) exists because of this incident;
  rollback recipe: `git restore lazy-lock.json` + `Lazy! restore`.
- **`lua/core/ts-compat.lua` is part of that pin.** The frozen `master` predates
  Neovim 0.12's query API, where a directive's `match[capture_id]` is a **list**
  of nodes; the plugin still reads it as one node, so `get_node_text(<list>)`
  threw `treesitter.lua:197: attempt to call method 'range'` on every markdown
  fence, HTML `<script type=…>` and bash heredoc. That was the real cause of the
  long-running "Neovim 0.12.x markdown crash" (FA-09) — not a Neovim bug. The
  shim re-registers the affected directives and is called from this spec's
  `config()` **after** `configs.setup{}`; registering earlier lets the plugin's
  own `add_directive` silently overwrite it. `highlight.enable` is therefore
  plain again — no markdown exclusion.
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
