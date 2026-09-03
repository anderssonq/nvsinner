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
- **Snippet placeholder navigation lives in `completions.lua`.** Expanding a
  snippet used to trap you on the first placeholder: Neovim 0.11+ ships default
  `<Tab>`/`<S-Tab>` jump maps, but they are guarded on `vim.snippet.active()`,
  and `snippet.expand` hands the body to **LuaSnip** — so the builtin maps fall
  through to a literal Tab and nothing else was bound. The fix is two maps:
  select-mode `<Tab>` (the one that actually fires — a placeholder is *selected*
  after an expand) and `{i,s}` `<S-Tab>` for backwards. Insert-mode `<Tab>` is
  deliberately NOT mapped here: it is arbitrated in `lua/core/ai-complete.lua`,
  and mapping it here would silently replace that chain. If expansion ever moves
  to `vim.snippet.expand`, these maps become dead weight — `tests/plugins/
  snippet_jump_spec.lua` asserts `vim.snippet.active()` is false and will flip.
- `lsp-config.lua` — `mason` + `mason-lspconfig`, then the **Neovim 0.11
  native API**: `vim.lsp.config("*", { capabilities })` +
  `vim.lsp.enable({...})`. Core servers: `vtsls`, `vue_ls`, `html`, `lua_ls`,
  `pyright`, `bashls`, `jsonls`, `yamlls`, `cssls`; `solargraph`, `gopls`, and
  `rust_analyzer` are executable-gated optional servers. Do **not** reintroduce
  `require("lspconfig").<server>.setup()` (deprecated).
  - Vue 3 uses language-tools hybrid mode: `vue_ls` owns HTML/CSS in the SFC;
    `vtsls`, configured with Mason's `@vue/typescript-plugin`, owns JS/TS and
    includes the `vue` filetype. Never enable `ts_ls` beside `vtsls` — that
    duplicates the TypeScript client.
  - `mason-lspconfig` carries `ensure_installed = { "lua_ls", "vtsls",
    "vue_ls", "html", "pyright", "bashls", "jsonls", "yamlls", "cssls" }`,
    so a fresh NvSinner install auto-installs them on first boot (it's
    `event = "VeryLazy"` + depends on `mason.nvim` so the install fires even
    on the dashboard). `automatic_enable = false` on purpose: **we** enable
    servers via `vim.lsp.enable` *after* the `"*"` config lands — otherwise
    mason-lspconfig could start a server before `on_attach` nils semantic
    tokens (below) and the `@lsp.*` repaint would come back. The
    toolchain-gated servers — solargraph (Ruby), gopls (Go), rust_analyzer
    (Rust) — are left out of `ensure_installed` and enabled individually only
    when `vim.fn.executable` sees their command. Installing one requires a
    restart before it becomes active.
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
