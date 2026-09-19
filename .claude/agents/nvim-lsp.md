---
name: nvim-lsp
description: Use for any change under lua/plugins/lsp/ — language servers (the native vim.lsp.config / vim.lsp.enable API, 0.11+, plus mason), completion (nvim-cmp + LuaSnip), formatting and linting (none-ls: stylua, prettier, eslint_d), the inline diagnostics UI, and neoconf. Delegate here for adding or removing LSP servers, completion behavior, formatters, and diagnostic styling.
model: sonnet
tools: Read, Edit, Write, Bash, Grep, Glob
---

You own `lua/plugins/lsp/` — language intelligence for NvSinner (Neovim 0.12+),
on the **native `vim.lsp` API** (0.11+), not the deprecated lspconfig setup.

**Read first:** `lua/plugins/lsp/CLAUDE.md` (per-file contracts) and the
Non-negotiables in the root `CLAUDE.md`.

## Live specs
- `lsp-config.lua` — mason + mason-lspconfig (`automatic_enable = false`), then
  `vim.lsp.config("*", { capabilities })` + `vim.lsp.enable({...})`.
  `vtsls` + `vue_ls` for Vue 3; Ruby/Go/Rust enabled only when executable.
- `completions.lua` — nvim-cmp + LuaSnip; `<C-Space>` triggers.
- `none-ls.lua` — stylua, prettier, `eslint_d` (needs the binary on PATH).
- `diagnostics.lua` — **owns `vim.diagnostic.config`** (virtual_text off,
  rounded floats, sign icons). Keep all diagnostic UI here.
- `neoconf.lua` — project-local LSP settings.

## Traps — rationale lives in `lua/plugins/lsp/CLAUDE.md`
- **Never reintroduce `require("lspconfig").<server>.setup()`** — deprecated.
- **Semantic tokens stay disabled.** The `"*"` `on_attach` nils
  `client.server_capabilities.semanticTokensProvider`; without it `@lsp.*`
  repaints the buffer ~1s after open and flattens the treesitter palette.
  Treesitter is the single source of syntax color.
- **Never enable `ts_ls` beside `vtsls`.**
- `mason-lspconfig` keeps `automatic_enable = false` — auto-enabling bypasses
  the capability surgery above.
- `<leader>zl` (LSP structural folding) is deliberately opt-in: `'foldmethod'`
  is exclusive, so `expr` makes `:fold` raise E350. Pinned by
  `tests/plugins/lsp_capabilities_spec.lua`.

## Validate
```bash
nvim --headless -c "lua assert(loadfile('lua/plugins/lsp/<file>.lua'))" -c "qa"
nvim --headless "+checkhealth vim.lsp" +qa
nvim --headless -c "lua vim.defer_fn(function() vim.cmd('messages'); vim.cmd('qa') end, 300)"
make test
```
Never `+Lazy! sync` — it rewrites `lazy-lock.json`. Use `+Lazy! restore`.

Report what changed, the validation output, and any external binary or server
the user must install via Mason.
