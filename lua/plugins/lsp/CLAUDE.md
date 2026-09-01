# lua/plugins/lsp/ — LSP / completion / formatting contracts

- **Neovim 0.12 native capabilities** (all builtin, no plugin): an `LspAttach`
  autocmd enables `vim.lsp.linked_editing_range` on clients advertising
  `textDocument/linkedEditingRange` (rename an HTML/JSX tag, its pair follows);
  `:NvSinnerDiagnosticsWorkspace` wraps `vim.lsp.buf.workspace_diagnostics()`,
  which reaches files Trouble cannot (it only sees loaded buffers), and is named
  `NvSinner*` so `:NvSinnerHelp` discovers it for free; `<leader>zl` toggles
  `vim.lsp.foldexpr` folding **per window**. Folding is a toggle and not a
  default because `'foldmethod'` is exclusive — `expr` makes `:fold` raise E350,
  silently breaking `<leader>zf`. `vim.lsp.document_color` was evaluated and NOT
  adopted: its default `style = "background"` is the same treatment
  `lua/core/colorizer.lua` already applies to hex literals, so the two would
  decorate the same range; its complementary value (CSS vars, `rgb()`, named
  colors) needs a rendering decision first.
- `lsp-config.lua` — `mason` + `mason-lspconfig`, then the **Neovim 0.11
  native API**: `vim.lsp.config("*", { capabilities })` +
  `vim.lsp.enable({...})`. Enabled servers: `ts_ls`, `solargraph`, `html`,
  `lua_ls`, `pyright`, `gopls`, `rust_analyzer`, `bashls`, `jsonls`, `yamlls`,
  `cssls`. Do **not** reintroduce `require("lspconfig").<server>.setup()`
  (deprecated).
  - `mason-lspconfig` carries `ensure_installed = { "lua_ls", "ts_ls", "html",
    "pyright", "bashls", "jsonls", "yamlls", "cssls" }` — all node-standalone,
    so a fresh NvSinner install auto-installs them on first boot (it's
    `event = "VeryLazy"` + depends on `mason.nvim` so the install fires even
    on the dashboard). `automatic_enable = false` on purpose: **we** enable
    servers via `vim.lsp.enable` *after* the `"*"` config lands — otherwise
    mason-lspconfig could start a server before `on_attach` nils semantic
    tokens (below) and the `@lsp.*` repaint would come back. The
    toolchain-gated servers — solargraph (Ruby), gopls (Go), rust_analyzer
    (Rust) — are left out of `ensure_installed` but stay in `vim.lsp.enable`
    (harmless if not installed; they light up once the toolchain + server
    exist).
  - **LSP keymaps are global on purpose** (not LspAttach/buffer-local): the
    `vim.lsp.buf.*` calls no-op safely without a client and global maps keep
    which-key listings stable. `<leader>rn` = rename. The Neovim 0.11
    **builtins are documented, not remapped**: `grn` rename, `grr` references,
    `gri` implementation, `gO` document symbols, `]d`/`[d` diagnostics.
- **Treesitter is the single source of syntax colour.** The `"*"` config's
  `on_attach` nils `client.server_capabilities.semanticTokensProvider`, so LSP
  semantic tokens (`@lsp.*`) never repaint the buffer ~1s after open and
  flatten the Treesitter palette. Remove that line if you ever want semantic
  highlighting.
- `trouble.lua` — `trouble.nvim`: workspace diagnostics / symbols / quickfix
  panel on the `<leader>x*` namespace (`xx` diagnostics, `xX` buffer-only,
  `xs` symbols, `xl` loclist, `xq` qflist), lazy on `cmd`/`keys`. It only
  *lists* diagnostics — `diagnostics.lua` keeps owning
  `vim.diagnostic.config`.
- `completions.lua` — `nvim-cmp` + LuaSnip. `<C-Space>` triggers completion.
- `none-ls.lua` — `none-ls` + `none-ls-extras`; sources: `stylua`, `prettier`,
  `shfmt`, `eslint_d` (eslint_d comes from none-ls-extras and needs the binary
  on PATH).
- `mason-tools.lua` — `mason-tool-installer.nvim` auto-installs the none-ls
  binaries (`stylua`, `prettier`, `eslint_d`, `shfmt`) via Mason on first boot
  (`event = "VeryLazy"`, same trigger as mason-lspconfig, so it fires even on
  the dashboard). `auto_update = false` on purpose — package updates stay the
  opt-in `:NvSinnerSync` path. `:MasonToolsInstall` retries a failed install;
  `core/health.lua`'s hints point at it, with brew/npm as manual fallbacks.
- `diagnostics.lua` — `tiny-inline-diagnostic.nvim`: rounded inline bubble for
  the cursor-line diagnostic. Owns `vim.diagnostic.config` (sets
  `virtual_text = false`, rounded floats, sign icons) — keep diagnostic UI
  config here, not scattered across `lsp-config.lua`.
