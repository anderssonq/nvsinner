---
name: nvsinner-debugging-playbook
description: >
  Symptom-to-fix triage for NvSinner's known failure modes. Load this when
  something in this repo is BROKEN or behaving strangely and you need to
  diagnose it: a plugin never loads, a treesitter "attempt to call method
  'range'" error, the terminal winbar spinner is frozen / empty / invisible,
  <leader>t opens the wrong panel, buffers don't reload after an AI CLI edit
  (or no toast appears), <leader>t / <leader>j pause before acting, syntax
  colors flatten about a second after opening a file, hover-float errors,
  startup errors, or failing tests. Do NOT load it to make planned changes or
  to look up a current value (nvsinner-contract), to read the full story of a
  settled incident (nvsinner-failure-archaeology), or for install and setup
  problems on a fresh machine (nvsinner-build-and-run).
---

# NvSinner debugging playbook

This skill is **triage**: match the symptom, run the discriminating probe, go
to the pointer. It deliberately does not retell the incidents — `FA-nn`
references resolve in `nvsinner-failure-archaeology`, which is the registry.

## Jargon (defined once)

- **winbar** — a per-window one-line bar at the top of a window. NvSinner uses
  it as the terminal "top bar" hosting the activity spinner.
- **toggleterm id** — toggleterm keys each terminal by a numeric `id`; same id
  = same terminal. Ids 1–9 are horizontal terminals, 100–108 the AI columns.
- **lazy spec** — the table a file under `lua/plugins/<category>/` returns.
- **headless** — `nvim --headless`: no UI, scriptable, exits via `qa`.

## Step 0 — is it your change, or was it already broken?

```bash
.claude/skills/nvsinner-testing-and-qa/scripts/boot-check.sh
make test
```
If the baseline fails you are looking at a regression, not at your new work.

## Master triage table

| # | Symptom | Likely cause | Discriminating probe | Go to |
|---|---|---|---|---|
| 1 | A plugin never loads | A new category folder is missing its `{ import = … }` line in `init.lua` (import does **not** recurse); or its lazy trigger never fires | §A | `nvsinner-contract` invariant 3 |
| 2 | `attempt to call method 'range'` from a markdown/HTML/bash buffer | `core/ts-compat` is missing, or ran *before* nvim-treesitter — whose `add_directive` then overwrites it | `make test-file FILE=tests/plugins/treesitter_predicates_spec.lua` | FA-09 / FA-24. `config()` must call `require("core.ts-compat").apply()` AFTER `configs.setup{}` |
| 3a | Spinner frozen while the agent works | The redraw path regressed to `:redrawstatus` (which doesn't repaint a winbar from inside a terminal), or the `M._timer` handle was GC'd | `grep -n 'nvim__redraw\|M._timer' lua/core/ai-activity.lua` | FA-01, FA-05 |
| 3b | Terminal winbar renders empty | The expression reads `vim.g.statusline_winid` (never set during winbar evaluation) instead of the baked-in bufnr | `:lua print(vim.wo.winbar)` — must contain `winbar(<bufnr>)` | FA-02 |
| 3c | Bar label invisible when the terminal is unfocused | `NvTermBarDim` has `fg == bg` | `:lua vim.print(vim.api.nvim_get_hl(0, { name = "NvTermBarDim" }))` | FA-06 |
| 4 | `<leader>t` toggles the AI column instead of a horizontal terminal | toggleterm id collision — an AI panel claimed a low id | §B | FA-08 |
| 5 | Buffer didn't reload after the CLI edited it, or no toast | The autoreload chain broke — **or** the file simply isn't open in a buffer, which is by design | §C | FA-04, FA-23 |
| 6 | Bare `<leader>t` / `<leader>j` / `<leader>f` pauses before acting | `timeoutlen` prefix wait | `:set timeoutlen?` — expect 300, not 1000 | **Not a bug** (§D) unless the value regressed. FA-25 |
| 7 | Syntax colors flatten ~1s after opening a file | LSP semantic tokens repainting over treesitter: the `on_attach` nil was removed, or a server started before the `"*"` config | §E | `nvsinner-contract` invariant 10 |
| 8 | Startup errors / config won't boot | Lua error in a core module or a plugin spec | `boot-check.sh`, then `loadfile` per edited file | §F |
| 9 | Errors from hover or doc floats | Something re-enabled a markdown-treesitter float path | `grep -n 'hover\|signature' lua/plugins/ui/noice.lua` | Keep them off — *pending evaluation*, not because of the old crash |
| 10 | Tests fail | Plenary missing (plugins not installed), or a real regression | `make test-file FILE=<one spec>` | `nvsinner-testing-and-qa` |

---

## §A A plugin never loads

Is it in the spec at all?

```bash
nvim --headless -c "lua vim.defer_fn(function() local n={} for _,p in pairs(require('lazy').plugins()) do n[#n+1]=p.name end table.sort(n) print(#n..': '..table.concat(n,' ')) vim.cmd('qa') end, 800)"
```

- **Name absent** → an import problem. Compare the spec file's folder against
  the `{ import = … }` lines in `init.lua`; a new folder needs its own line.
  Also confirm the file returns a spec table — a file that errors on load is
  dropped silently.
- **Name present, features missing** → a trigger problem. For a lazy plugin,
  `loaded=false` at startup is normal; the question is whether its
  `event`/`cmd`/`keys`/`ft` ever fires. `:Lazy` shows which handler will load
  it.
- **Check `enabled = false` first.** Eleven specs are deliberate tombstones.

## §B Terminal id collision

Inside a running instance, after opening some panels:

```vim
:lua for _,t in pairs(require("toggleterm.terminal").get_all(true)) do print(t.id, t.direction, vim.b[t.bufnr].nv_term_label) end
```

Expect `1 horizontal term 1` and `100 vertical AI · 1`. Any **vertical**
terminal with an id below 100 means the reserved-id scheme broke — check
`id = 99 + n`. A bare `:ToggleTerm` shows a `nil` label, which is expected:
labels are set by `on_panel_open`, which only runs for keymap-created panels.

If instead the *layout* is wrong (a horizontal terminal landing beside the AI
column), that is `restore_layout()` — horizontals `wincmd J`, then columns
`wincmd L` last so they win the right edge.

## §C Autoreload didn't fire

**Rule out by-design behavior first:**
- Only loaded buffers fire. A file you don't have open never toasts.
- **Disk wins.** Unsaved in-Vim edits to a buffer the agent rewrites are
  discarded. That is the documented trade-off, not a bug.

The chain lives in `lua/core/autoreload.lua`: `autoread`, a
`FileChangedShell` handler setting `v:fcs_choice = "reload"`, a
`FileChangedShellPost` handler, `checktime` on focus events, and a 1s `vim.uv`
timer (there is no `CursorHold` in terminal mode, so the timer is what makes
reload work while you sit in the AI column). Both events are needed: with
`autoread` on and the buffer unmodified — the common case — Neovim reloads
silently and fires **only** the Post event (FA-23).

Real external-write test: open a file, then from another shell

```bash
sh -c 'sleep 1; echo "// external edit" >> /path/to/that/open/file'
```

Within ~1s the buffer should update and a toast should appear. The `sleep 1`
guarantees a later mtime — the same trick the spec uses.

```bash
make test-file FILE=tests/core/autoreload_spec.lua
```

## §D The prefix wait is not a bug

When a mapping is a strict prefix of a longer one, Neovim waits one
`timeoutlen` before running the bare mapping. Four prefixes pay it:
`<leader>t` (of `t2…t9`), `<leader>j` (of `j2…j9`, `jx`, `ja`, `jc`),
`<leader>jx` (which stacks on `<leader>j`'s wait), and `<leader>f` (of
`<leader>fb` — note the split ownership: `<leader>f` is a lazy `keys` stub in
the telescope spec, `<leader>fb` an eager map in `lua/core/keymaps.lua`).

The wait is **300 ms**, not Neovim's 1000 ms default, and is retunable at
runtime via `:NvSinnerMenu` → "Key timeout". Pressing the prefix then a digit
immediately is instant. If you measure ~1s, the setting regressed. FA-25.

## §E Semantic tokens repainting

```bash
grep -n 'semanticTokensProvider\|automatic_enable' lua/plugins/lsp/lsp-config.lua
```

Both must be present: the `"*"` `on_attach` nils the capability, and
`mason-lspconfig` keeps `automatic_enable = false` so no server can attach
before that config lands. Live check, with a server attached:

```vim
:lua for _,c in pairs(vim.lsp.get_clients()) do print(c.name, tostring(c.server_capabilities.semanticTokensProvider)) end
```

Every client must print `nil`.

## §F Startup errors

```bash
.claude/skills/nvsinner-testing-and-qa/scripts/boot-check.sh
nvim --headless -c "lua assert(loadfile('lua/<the file you edited>.lua'))" -c "qa"
```

The boot check exits non-zero and prints the message log when anything was
written to it. A `loadfile` check is silent on success.

## Instruments

All four live in `.claude/skills/nvsinner-testing-and-qa/scripts/`:
`boot-check.sh` (startup clean), `keymap-audit.sh` (load-bearing maps present),
`palette-audit.sh` (no off-palette hexes, whitelist derived from
`lua/core/carbon.lua`), `startup-time.sh` (cold-start total + slowest entries).

## Provenance and maintenance

**Facts verified: 2026-09-19.** This skill was cut from 451 lines to triage
plus probes: the long-form incident narratives it carried were a second telling
of `nvsinner-failure-archaeology`, and its §2 documented a three-part markdown
workaround (`after/ftplugin/markdown.lua` and two highlight disables) that no
longer exists — the crash was nvim-treesitter's frozen master, and
`lua/core/ts-compat.lua` fixed it.

Re-verification: every probe above is runnable as written; run the ones for
the rows you touch.
