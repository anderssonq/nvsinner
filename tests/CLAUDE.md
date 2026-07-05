# tests/ — plenary busted suite

A [plenary](https://github.com/nvim-lua/plenary.nvim) busted suite (plenary is
already present as a telescope dependency — no extra install). Run it with the
`Makefile`:

```bash
make test                                   # whole suite
make test-file FILE=tests/core/options_spec.lua   # one file
```

Each spec runs in a fresh headless Neovim via `tests/minimal_init.lua`, which
puts this config + plenary on the runtimepath (no plugins loaded, no side
effects). Deeper QA doctrine (evidence bar, new-spec template) lives in the
`nvsinner-testing-and-qa` skill.

## Spec inventory

| Spec | Covers |
|------|--------|
| `tests/core/options_spec.lua` | leaders + core editor options |
| `tests/core/carbon_spec.lua` | carbon role tables (dark/light), the background/transparency flags (`vim.g` + env), and `:colorscheme carbon` honoring both (opaque vs transparent surfaces) |
| `tests/core/keymaps_spec.lua` | global keymaps exist (save/undo/redo, resize in n+t, buffer picker), the full `<leader>x*` NvSinner shortcut namespace routed to its commands, + the resize step applied behaviorally (+20 cols) |
| `tests/core/settings_spec.lua` | settings defaults, JSON save/load roundtrip + corrupt-file fallback, vim.g seeding precedence, the quiet notify filter, and the carbon accent/folder packs + single-role color slots |
| `tests/core/menu_spec.lua` | `:NvSinnerMenu` command, the modal float rendering every row, and move/cycle writing through to core/settings |
| `tests/core/prompts_spec.lua` | `:NvSinnerPrompts` command, JSON loading (array/string content, corrupt-file fallback), the modal listing title+description rows, copy() returning the prompt + closing, and the shipped library carrying 11 valid entries |
| `tests/core/help_spec.lua` | `:NvSinnerHelp` command, refresh() discovering NvSinner* commands (self excluded, late registrations included) + the checkhealth extra, the modal listing rows, section rule headers + items landing on their refresh()-computed lines, the strtrans desc sanitizer (no mangled bytes ever render), the solid NvMenuNormal surface + backdrop pairing/teardown, and run() executing + auto-closing |
| `tests/core/autoreload_spec.lua` | `autoread`, the FileChangedShell**Post** autocmds, and the edit toast firing on an external change |
| `tests/core/ai_edits_spec.lua` | the NvAiEdit accent-wash group (bg-only, blended — never the raw accent), a real external rewrite washing exactly the changed/added lines after the autoread reload, clear() re-baselining the snapshot, the armed take-over autocmds wiping the marks, and special buffers being skipped |
| `tests/core/ui_touch_spec.lua` | focus/term-bar highlights, `NvTermBarDim` fg≠bg, mouse/fillchars, and the per-window winbar baking the buffer number |
| `tests/core/ai_activity_spec.lua` | `winbar(buf)` idle/label/invalid, a real streaming terminal flipping working→idle, `status()` for untracked buffers, and the awaiting state (`_on_osc` on `133;B`/`133;C`/OSC 9, output clearing it, the `NvAiAwait` chip) |
| `tests/core/ai_sessions_spec.lua` | registry register/unregister + sessions() snapshot, target() MRU semantics (open > live job, current-terminal override), send() into a real terminal job, bracketed-paste payload wrapping, the no-session opener fallback + warn, `@path` mention + diagnostics formatting, and the `<leader>as/ab/ad/ja` maps |
| `tests/core/ai_ask_spec.lua` | build() headers (fix/refactor/explain, one-line range collapse, custom question), visual-mode capture via the `<leader>x` map (ctx + back to normal mode), the modal rendering the four actions, run() sending into a real terminal, the vim.ui.input custom flow (cancel sends nothing), the >1-session vim.ui.select branch hitting send_to(), send_to() dead-entry fallback, double_click() (word capture + modal, active-selection reuse, silent bail in special buffers/whitespace), and the maps + :NvSinnerAskAI existing |
| `tests/core/symbols_spec.lua` | `:NvSinnerSymbols` command + `<leader>cs`/`<leader>xo` maps, `_flatten()` on both LSP shapes (nested DocumentSymbol children indented, flat SymbolInformation, position-less entries skipped), the `nvsinner_symbols` float (nofile, non-modifiable, cursorline), run() jumping the source window to the picked symbol, and the no-LSP-client warn path |
| `tests/core/backdrop_spec.lua` | `attach()` opening the full-screen non-focusable dim float below the modal (zindex, winblend 60, no focus steal), the WinClosed teardown, the invalid-window guard, and `NvMenuBackdrop` carrying the carbon `backdrop` role |
| `tests/core/update_spec.lua` | `:NvSinnerUpdate` command exists, `is_git_repo` detection, and the not-a-git-clone warning path |
| `tests/core/sync_spec.lua` | `:NvSinnerSync` command exists, `outdated()` version comparison (stale/fresh/no-receipt/throwing lookup), `branch_jumps()` lockfile diffing (jump detection, added/removed ignored), and the mason-unavailable warning path |
| `tests/core/health_spec.lua` | `check_tools` present/absent detection, the first-run toast (warn-once via marker, silent when nothing missing), and `:checkhealth nvsinner` running |
| `tests/core/image_open_spec.lua` | `BufReadCmd` replaces an image with the placeholder, `buftype=nofile` write-guard, `<cr>`/`gO` buffer maps, and no headless auto-preview |
| `tests/plugins/plugin_specs_spec.lua` | every `lua/plugins/**/*.lua` loads and returns a valid lazy spec |

## Conventions for new specs

Name them `*_spec.lua`, require the module under test at the top of the
`describe` block (plenary busted has **no** `setup`/`finally`; use
`before_each` / restore state inline), and prefer real Neovim behaviour (open a
terminal, `vim.wait` for the state) over mocking.
