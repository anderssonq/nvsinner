---
name: nvsinner-debugging-playbook
description: >
  Symptom-to-fix triage playbook for NvSinner's known failure modes. Load this
  when something in this repo is BROKEN or behaving strangely and you need to
  diagnose it: a plugin never loads, Neovim crashes on markdown, the terminal
  winbar spinner is frozen/empty/invisible, <leader>t opens the wrong panel,
  buffers don't reload after an AI CLI edit (or no 🤖 toast), <leader>t/<leader>j
  pause before acting, syntax colors flatten ~1s after opening a file, startup
  errors, hover-float errors, or failing tests. Do NOT load it to make planned
  changes (nvsinner-change-control), to learn the architecture
  (nvsinner-architecture-contract), or for install/setup problems on a fresh
  machine (nvsinner-build-and-run).
---

# NvSinner Debugging Playbook

Symptom → likely cause → discriminating experiment → fix, for this repo's
known failure modes. Every command below was run and verified in this repo on
2026-07-02 (Neovim 0.12.3, dev machine, `make test` green).

Run all commands from the repo root. On the dev machine `~/.config/nvim` IS
this repo, so a bare `nvim --headless …` loads this config; on a machine where
the repo lives only at `~/.config/nvsinner`, prefix commands with
`NVIM_APPNAME=nvsinner`.

## When NOT to use this skill

| You actually want to… | Go to |
|---|---|
| Classify / gate a change you're about to make | nvsinner-change-control |
| Read the full history of a settled investigation | nvsinner-failure-archaeology |
| Understand the design invariants behind a fix | nvsinner-architecture-contract |
| Neovim-internals theory (winbar eval, fast events, autocmd semantics) | neovim-internals-reference |
| Install/update/uninstall problems, PATH, launcher | nvsinner-build-and-run |
| Measurement/profiling tooling | nvsinner-diagnostics-toolkit |
| Write or extend tests | nvsinner-testing-and-qa |
| Plan work on the terminal/agent-UX stack | nvsinner-terminal-ux-campaign |
| Design an experiment to prove a hypothesis | nvsinner-empirical-verification |

## Jargon (defined once)

- **winbar** — a per-window one-line bar at the top of a window (`'winbar'`
  option). NvSinner uses it as the terminal "top bar" that hosts the activity
  spinner.
- **toggleterm id** — `toggleterm.nvim` keys each terminal by a numeric `id`;
  same id = same terminal. NvSinner reserves ids 1–9 for horizontal terminals
  and 100–108 for the AI columns.
- **lazy spec** — the table a file under `lua/plugins/<category>/` returns,
  telling lazy.nvim what to install and when to load it.
- **headless** — `nvim --headless`: no UI, scriptable, exits via `qa`.

## Master triage table

| # | Symptom | Likely cause | Discriminating experiment | Fix / pointer |
|---|---------|--------------|---------------------------|---------------|
| 1 | A plugin never loads | New category folder missing its `{ import = … }` line in `init.lua` (import does NOT recurse); or lazy trigger (`event`/`cmd`/`keys`/`ft`) never fires | Headless plugin-list probe: is it even in the spec? | Add the import line / fix the trigger (§1) |
| 2 | `attempt to call method 'range'` from a markdown/HTML/bash buffer | The `core/ts-compat` shim is missing or ran before nvim-treesitter (its `add_directive` then overwrites it) | `make test-file FILE=tests/plugins/treesitter_predicates_spec.lua` | Ensure `config()` calls `require("core.ts-compat").apply()` AFTER `configs.setup{}`; story: FA-09 |
| 3a | Terminal spinner frozen while agent works | Redraw path regressed to `:redrawstatus` (doesn't repaint winbar from inside a terminal), or the `M._timer` handle got GC'd | Check `tick()` in `lua/core/ai-activity.lua` uses `nvim__redraw{winbar=true,flush=true}` | §3; theory: neovim-internals-reference |
| 3b | Terminal winbar renders empty | Expression reads `vim.g.statusline_winid` (never set during winbar eval) instead of the baked-in bufnr | `:lua print(vim.wo.winbar)` — must contain `winbar(<bufnr>)` | §3 |
| 3c | Bar label invisible when terminal unfocused | `NvTermBarDim` has `fg == bg` | Inspect the highlight; fg must be `#7a7f8d`-ish, not the bg | §3 |
| 4 | `<leader>t` opens/toggles the AI column instead of a horizontal terminal | toggleterm id collision — AI panel claimed a low id (1–9) | List all terminal ids; AI panels must be ≥100 | §4; full story: nvsinner-failure-archaeology |
| 5 | Buffer didn't reload after the AI CLI edited it / no 🤖 toast | Autoreload chain broken (autoread off, autocmds gone, timer dead) — OR the file simply isn't open in a buffer (by design) | Real external-write test (§5); run `tests/core/autoreload_spec.lua` | §5 |
| 6 | Bare `<leader>t`, `<leader>j` or `<leader>f` pauses before acting | `timeoutlen` prefix wait — `<leader>t` is a prefix of `<leader>t2`…`t9` (same for `j`, `jx`, and `f`/`fb`) | `:set timeoutlen?` — must be 300, not 1000; press the prefix then a digit immediately: instant | NOT A BUG (§6) — but if it's ~1s, the setting regressed |
| 7 | Syntax colors flatten/change ~1s after opening a file | LSP semantic tokens (`@lsp.*`) repainting over Treesitter — the `on_attach` nil was removed, or a server started before the `"*"` config | Check `semanticTokensProvider` on attached clients (§7) | §7; full story: nvsinner-failure-archaeology |
| 8 | Startup errors / config won't boot | Lua error in a core module or plugin spec | Headless boot probe + per-file `loadfile` check | §8 |
| 9 | Errors from hover/doc floats | Something re-enabled a markdown-treesitter float path (noice LSP hover, or `filetype=markdown` on the ui-touch float) | Grep the three guard sites (§9) | §9 — keep them OFF on 0.12.x |
| 10 | Tests fail | Plenary missing (plugins not installed), or a real regression | `make test-file FILE=<one spec>` to isolate | §10; conventions: nvsinner-testing-and-qa |

---

## §1 A plugin never loads

**Background.** `init.lua` imports each category folder explicitly —
`plugins.ui`, `plugins.lsp`, `plugins.git`, `plugins.editor`,
`plugins.navigation`, `plugins.terminal` — because **lazy.nvim's `import` does
not recurse into subfolders**. A file in a brand-new category folder without a
matching `{ import = "plugins.<category>" }` line silently never loads.

**Step 1 — is it in the spec at all?**

```bash
nvim --headless -c "lua vim.defer_fn(function() local names={} for _,p in pairs(require('lazy').plugins()) do table.insert(names, p.name) end table.sort(names) print(table.concat(names, ' ')) vim.cmd('qa') end, 800)"
```

Expected: one line listing ~47 plugin names (`Comment.nvim LuaSnip … which-key.nvim window-picker`).
- **Name absent** → import problem. Check the spec file's folder against the
  `{ import = … }` lines in `init.lua` (lines 32–37). New folder ⇒ add the line.
  Also confirm the file returns a spec table (see §8 `loadfile` check) — a file
  that errors on load is dropped.
- **Name present but features missing** → trigger problem, step 2.

**Step 2 — in spec but not loaded (lazy trigger never fires):**

```bash
nvim --headless -c "lua vim.defer_fn(function() local p = require('lazy.core.config').plugins['toggleterm.nvim'] print(('spec=%s loaded=%s'):format(tostring(p ~= nil), tostring(p and p._.loaded ~= nil))) vim.cmd('qa') end, 800)"
```

Expected for an eagerly-configured plugin: `spec=true loaded=true`. For a
lazy plugin at startup, `loaded=false` is normal — the question is whether its
`event`/`cmd`/`keys`/`ft` ever fires. Interactively, `:Lazy` shows loaded
plugins at the top and, per plugin, which handler will load it. Common repo
traps: `enabled = false` left in the spec (the documented disable convention —
check first), and keymaps defined only inside `config = function()` of a plugin
that itself never loads.

## §2 Neovim crashes opening a markdown file (0.12.x)

**Signature:** `attempt to call method 'range' (a nil value)` from the runtime
`treesitter.lua` (≈line 197). Cause: on Neovim 0.12.x the bundled markdown
treesitter highlighter calls `node:range()` on a nil node. The workaround has
**three parts**; all must be intact:

| File | Guard |
|------|-------|
| `lua/plugins/editor/nvim-treesitter.lua` | `highlight.disable = { "markdown", "markdown_inline" }` |
| `lua/plugins/navigation/telescope.lua` | `defaults.preview.treesitter.disable = { "markdown", "markdown_inline" }` |
| `after/ftplugin/markdown.lua` | `pcall(vim.treesitter.stop, 0)` + `vim.bo.syntax = "markdown"` (overrides the 0.12 runtime ftplugin that unconditionally calls `vim.treesitter.start()`) |

Related guards that keep markdown-treesitter out of transient floats: noice LSP
hover/signature off (§9).

**Confirm intact (one command):**

```bash
grep -n "markdown" lua/plugins/editor/nvim-treesitter.lua lua/plugins/navigation/telescope.lua after/ftplugin/markdown.lua
```

**Prove no crash + regex fallback active:**

```bash
nvim --headless README.md -c "lua vim.defer_fn(function() print(('md-open OK syntax=%s ts-active=%s'):format(vim.bo.syntax, tostring(vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()] ~= nil))) vim.cmd('qa') end, 700)"
```

Expected output: `md-open OK syntax=markdown ts-active=false`. If `ts-active=true`
on 0.12.x, one of the three guards is gone. The parsers themselves stay in
`ensure_installed` on purpose (markdown + markdown_inline are a pair). Remove
the workaround only per the upstream-fix condition — see nvsinner-change-control
before touching it; full investigation: nvsinner-failure-archaeology.

## §3 Terminal winbar spinner frozen / empty / invisible

Three **distinct** root causes, all settled empirically (deep campaign:
nvsinner-terminal-ux-campaign; theory: neovim-internals-reference). Ownership:
`lua/core/ai-activity.lua` renders the content; `lua/core/ui-touch.lua` owns
the bar + highlights.

**3a — spinner frozen while the agent streams output.**
- Cause 1: redraw path. `:redrawstatus` does NOT repaint the winbar when focus
  is inside a terminal (the usual case). The `tick()` function must call
  `vim.api.nvim__redraw({ statusline = true, winbar = true, flush = true })`
  (with a `pcall` fallback). Check:
  ```bash
  grep -n "nvim__redraw" lua/core/ai-activity.lua
  ```
  Expected: one hit inside `tick()`.
- Cause 2: timer GC. The luv timer must be stored on the module
  (`M._timer = assert(uv.new_timer())`) — an unreferenced active handle can be
  garbage-collected and the spinner silently stops. Check:
  ```bash
  grep -n "M._timer" lua/core/ai-activity.lua
  ```
- Cause 3 (never reintroduce): busy detection must be `nvim_buf_attach`
  `on_lines`, not `b:changedtick` polling — terminal buffers don't bump the
  tick unless attached/rendered. The `on_lines` callback runs in a fast event
  context: plain Lua table writes + `uv.now()` only, no `vim.*` API.

**3b — winbar renders empty.**
Cause: `vim.g.statusline_winid` is populated for `'statusline'` evaluation but
NOT for `'winbar'` evaluation, so any expression relying on it returns "".
(2026-07-02 refinement: `%{}` items see it in neither option — see
`nvsinner-empirical-verification` recipe 2; guidance unchanged.)
The fix in place: `term_bar(win)` in `lua/core/ui-touch.lua` bakes the buffer
number into each window's winbar string. Discriminating experiment (inside a
running nvsinner, focus the terminal window):

```vim
:lua print(vim.wo.winbar)
```

Expected: `%{%v:lua.require'core.ai-activity'.winbar(<bufnr>)%}` with a literal
number. `M.winbar(buf)` must keep taking the buffer as an argument.
Also: `M.winbar` returns "" for an invalid buf — covered by
`tests/core/ai_activity_spec.lua`.

**3c — label invisible on an unfocused terminal.**
Cause: `NvTermBarDim` once had `fg == bg` (hid the idle label entirely).
Current contract: fg `#7a7f8d` on bg `#16161d`; the busy state is wrapped in
the `NvAiBusy` chip (fg `#0a0a0f` on accent `#c4746e`) so it reads even on the
dim bar. Check:

```vim
:lua print(vim.inspect(vim.api.nvim_get_hl(0, { name = "NvTermBarDim" })))
```

Expected: distinct `fg` and `bg` values. `tests/core/ui_touch_spec.lua`
asserts fg ≠ bg.

**Related first-open caveat:** a toggleterm window fires `BufWinEnter` while
its buffer is still `buftype ""`, so `ui-touch`'s focus autocmd includes
`TermOpen` to re-style once the buffer becomes a terminal. If the bar is
missing only on the very first open, check that `TermOpen` is still in the
autocmd event list in `lua/core/ui-touch.lua`.

**Regression suite for all three:**

```bash
make test-file FILE=tests/core/ai_activity_spec.lua
make test-file FILE=tests/core/ui_touch_spec.lua
```

Expected: `Failed : 0`, `Errors : 0`.

## §4 `<leader>t` opens the AI column instead of a horizontal terminal

**History:** toggleterm memoises terminals by numeric id. Before the fix
(commit `220a897` on branch `feat/nvsinner-distro`, "Fix terminal id
collision"), an AI panel opened first claimed id 1, so `<leader>t` just
re-toggled that panel. **The contract now:** horizontal terminals use ids 1–9;
AI panels use reserved ids `99 + N` (session 1 → 100 … session 9 → 108), set in
`get_ai_panel` in `lua/plugins/terminal/toggleterm.lua`.

**Inspect live terminal ids** (inside a running nvsinner, after opening some
panels):

```vim
:lua for _,t in pairs(require("toggleterm.terminal").get_all(true)) do print(t.id, t.direction, vim.b[t.bufnr].nv_term_label) end
```

Expected shape: `1 horizontal term 1` for `<leader>t`, `100 vertical AI · 1`
for `<leader>j`. Any `vertical` terminal with an id < 100 means the reserved-id
scheme was broken (check `id = 99 + n` and `id = n` in
`lua/plugins/terminal/toggleterm.lua`). Note the labels (`term N` / `AI · N`)
are set by `on_panel_open`, which only runs for the keymap-created Terminal
objects — a bare `:ToggleTerm` shows `nil`, which is expected, not a bug.

If instead the *layout* is wrong (horizontal terminal landing as a vertical
split beside the AI column), that's `restore_layout()` in the same file —
it forces horizontals to the bottom (`wincmd J`) then columns to the right
(`wincmd L`), columns last so they win the right edge.

## §5 Buffer didn't reload after the AI CLI edited a file / no 🤖 toast

**The chain** (`lua/core/autoreload.lua`, all native):
1. `vim.opt.autoread = true`.
2. `FileChangedShell` autocmd → `v:fcs_choice = "reload"` (conflict case) + toast.
3. `FileChangedShellPost` autocmd → toast. **Required**: with autoread on and
   the buffer unmodified (the common case) Neovim reloads silently and fires
   *only* the Post event, never `FileChangedShell` (verified empirically).
4. `checktime` on `FocusGained/BufEnter/WinEnter/TermLeave/CursorHold/CursorHoldI`
   **plus** a 1s `vim.uv` timer (needed because there is no CursorHold in
   terminal mode — this is what makes reload work while you sit in the AI pane).
5. A per-file dedup (250 ms in the code; CLAUDE.md's prose says 500 ms — the
   code is ground truth; flag via nvsinner-docs-and-style) prevents the two
   events double-toasting one write. Toast text: `edited <file>` with title
   `🤖 AI`.

**Before debugging, rule out by-design behavior:**
- **Only loaded buffers fire** — a file you don't have open never toasts. Not a bug.
- **Disk wins** — unsaved in-Vim edits to a buffer the AI rewrites are
  DISCARDED by design (viewer-style workflow; edit in the AI pane). "My edits
  vanished" is the documented trade-off, not a bug.

**Real external-write test (interactive, ~5s):** open any file in nvsinner,
then from another shell:

```bash
sh -c 'sleep 1; echo "// external edit" >> /path/to/that/open/file'
```

Within ~1s (the timer tick) the buffer should show the new line and a
`🤖 AI · edited <file>` toast should appear — without touching Neovim.
(The `sleep 1` guarantees a later mtime, same trick the spec uses.)

**Automated check:**

```bash
make test-file FILE=tests/core/autoreload_spec.lua
```

Expected: 3 successes, 0 failed (asserts autoread, both autocmds in group
`auto_reload_on_disk_change`, and the toast firing on a real external rewrite).
If the autocmds are missing, confirm `require("core.autoreload")` is still in
`init.lua`.

## §6 Bare `<leader>t` / `<leader>j` / `<leader>f` pauses before acting — NOT A BUG (but check the value)

When a mapping is a strict prefix of a longer one, Neovim waits one
`timeoutlen` for a possible continuation before running the bare mapping;
which-key shows its menu during the wait. Four prefixes in this config pay it:

| Prefix | Continuations |
|---|---|
| `<leader>t` | `<leader>t2`…`t9` |
| `<leader>j` | `<leader>j2`…`j9`, `jx`, `ja`, `jc` |
| `<leader>jx` | `<leader>jx2`…`jx9` (stacks on `<leader>j`'s own wait) |
| `<leader>f` | `<leader>fb` — note the split ownership: `<leader>f` is a lazy `keys` stub in `lua/plugins/navigation/telescope.lua`, `<leader>fb` an eager map in `lua/core/keymaps.lua` |

`timeoutlen` **is** set now — `lua/core/options.lua` puts it at **300 ms**, and
`lua/core/settings.lua`'s `key_timeout` (the `:NvSinnerMenu` → "Key timeout"
row) can retune it per user. Neovim's unset default is 1000 ms, which is what
made the flagship keys feel broken.

**Triage:** if the pause is back to ~1 s, `:set timeoutlen?` — something dropped
the option, not the keymaps. If `<leader>t3` keeps opening terminal 1, the value
is too low for how fast that user types: raise it from the menu, don't touch code.

Pressing a digit immediately after the prefix skips the wait entirely.

**Still forbidden:** do not "fix" this by removing the numbered maps (see
nvsinner-change-control). Lowering `timeoutlen` was the sanctioned fix and is
already applied — see FA-25 in nvsinner-failure-archaeology.

**Related, same root cause:** there is deliberately no `jk` map in terminal
mode. It made every literal `j` typed into an AI CLI a prefix, so the keystroke
was withheld one `timeoutlen` before reaching the program. `<esc>` is the
terminal-normal-mode escape. If someone reports "typing in the AI column drops
or delays characters", check `maparg("jk", "t")` first.

## §7 Syntax colors flatten/change ~1s after opening a file

**Cause:** an LSP server attaches ~1s after the buffer opens and its semantic
tokens (`@lsp.*` highlights) repaint over Treesitter, flattening the palette.
**The contract** (in `lua/plugins/lsp/lsp-config.lua`): Treesitter is the
single source of syntax colour —

- `vim.lsp.config("*", { … on_attach = function(client) client.server_capabilities.semanticTokensProvider = nil end })`
- `mason-lspconfig` has `automatic_enable = false` **on purpose**: servers are
  enabled by *our* `vim.lsp.enable` calls (core includes `vtsls` + `vue_ls`;
  optional toolchains are executable-gated) only after the `"*"` config lands.
  If mason-lspconfig auto-enables, a server
  can start before the on_attach nil and the repaint comes back.

**Discriminating experiments** (in a buffer with an attached server):

```vim
:lua for _,c in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do print(c.name, "semanticTokens:", c.server_capabilities.semanticTokensProvider ~= nil) end
```

Expected: `semanticTokens: false` for every client. Also `:Inspect` on a
recolored token: if it lists `@lsp.*` captures, semantic tokens are live again.

**Fix:** restore the `on_attach` nil in the `"*"` config and/or
`automatic_enable = false`; make sure nothing calls the deprecated
`require("lspconfig").<server>.setup()` (forbidden per CLAUDE.md).
Full story: nvsinner-failure-archaeology.

## §8 Startup errors / config won't boot

**Step 1 — boot probe** (surfaces startup errors, silent when clean):

```bash
nvim --headless -c "lua vim.defer_fn(function() vim.cmd('messages'); vim.cmd('qa') end, 500)"
```

Expected on a healthy config: **no output**, exit 0. Any Lua traceback printed
names the failing module.

**Step 2 — syntax-check the suspect file** (no plugins, no network):

```bash
nvim --headless -c "lua assert(loadfile('lua/plugins/<category>/<file>.lua'))" -c "qa"
```

Expected: no output, exit 0. A syntax error prints the file:line. This only
catches parse errors — runtime errors inside `config = function()` need step 1
or 3. Run it over every plugin spec at once with the suite's
`tests/plugins/plugin_specs_spec.lua` (`make test-file FILE=tests/plugins/plugin_specs_spec.lua`),
which also validates each file returns a proper lazy spec.

**Step 3 — bisect by disabling.** The sanctioned disable switch is
`enabled = false` in a plugin's spec (never delete the file to test). Halve the
suspects: add `enabled = false` to a category's plugins, re-run the boot probe,
narrow down. For core modules (`lua/core/*.lua`), comment out one `require`
line in `init.lua` at a time — but remember `core.options` must always stay
first (leaders before lazy). Revert every bisect edit when done.

## §9 Errors from hover/doc floats

**Why things are the way they are:** the misdiagnosed "0.12.x markdown-treesitter crash" (§2, FA-09)
also fires inside transient floats that highlight markdown. Three deliberate
guards exist; an error from a hover float almost always means one was undone:

| Guard | File | Check |
|---|---|---|
| noice LSP hover + signature disabled, `override = {}` empty | `lua/plugins/ui/noice.lua` | `grep -n "hover\|signature\|override" lua/plugins/ui/noice.lua` |
| ui-touch mouse-hover float rendered as PLAIN TEXT (filetype deliberately not `markdown`) | `lua/core/ui-touch.lua` (`open_float`) | `grep -n "markdown" lua/core/ui-touch.lua` — should only be the explanatory comment |
| `K` keeps the native `vim.lsp.buf.hover` handler | `lua/plugins/lsp/lsp-config.lua` | `grep -n '"K"' lua/plugins/lsp/lsp-config.lua` |

Do **not** enable noice's LSP markdown paths on 0.12.x — CLAUDE.md forbids it.
If the mouse-hover float itself errors, note `request_hover` is already wrapped
in `pcall` (errors close the float silently), so a visible error points at a
different float owner — check `:messages` for the source.

## §10 Tests fail

```bash
make test                                        # whole suite
make test-file FILE=tests/core/options_spec.lua  # one spec (verified: 4 successes)
```

Mechanics (brief — conventions and spec-writing live in nvsinner-testing-and-qa):
each spec runs in a fresh headless child via `tests/minimal_init.lua`, which
prepends this repo and `<stdpath data>/lazy/plenary.nvim` to the runtimepath —
**no plugins load**. Two failure classes to separate first:

- **Harness failure** (`PlenaryBusted… not an editor command`, or plenary
  require errors): plenary isn't installed at `stdpath("data")/lazy/plenary.nvim`.
  Fix: `nvim --headless "+Lazy! restore" +qa` (restore, not sync — pinned
  lockfile; see nvsinner-build-and-run).
- **Real spec failure**: isolate with `make test-file`, read the assert. The
  suite passes as of 2026-07-02, so any failure is caused by a local change —
  diff against the invariants in §3/§5/§7 before "fixing" the test
  (evidence bar: nvsinner-empirical-verification).

---

## Provenance and maintenance

**Facts verified: 2026-07-02** — by direct file reads of `init.lua`,
`lua/core/{ai-activity,ui-touch,autoreload,options,keymaps}.lua`,
`lua/plugins/{editor/nvim-treesitter,navigation/telescope,ui/noice,lsp/lsp-config,terminal/toggleterm}.lua`,
`after/ftplugin/markdown.lua`, `Makefile`, `tests/minimal_init.lua`,
`tests/core/autoreload_spec.lua`, plus live runs of every probe printed above
(Neovim 0.12.3, `make test` green).

**Keymap-timeout facts re-verified: 2026-07-28** — `timeoutlen = 300` set in
`lua/core/options.lua`, retunable via `key_timeout` in `lua/core/settings.lua`,
and no `t`-mode `jk` map in `lua/plugins/terminal/toggleterm.lua`. Every other
claim on this page still carries the 2026-07-02 date.

Re-verify before trusting, if this file is older than the last commit touching
the named module:

| Claim | One-line re-check |
|---|---|
| Category import lines in init.lua | `grep -n "import = \"plugins\." init.lua` |
| 3-part markdown workaround intact | `grep -n "markdown" lua/plugins/editor/nvim-treesitter.lua lua/plugins/navigation/telescope.lua after/ftplugin/markdown.lua` |
| Markdown opens crash-free, TS off | `nvim --headless README.md -c "lua vim.defer_fn(function() print(vim.bo.syntax, vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()] == nil and 'ts-off' or 'TS-ON') vim.cmd('qa') end, 700)"` |
| Spinner redraw + timer + on_lines | `grep -n "nvim__redraw\|M._timer\|on_lines" lua/core/ai-activity.lua` |
| Winbar bakes bufnr (no statusline_winid) | `grep -n "statusline_winid\|term_bar" lua/core/ui-touch.lua` |
| NvTermBarDim fg ≠ bg | `make test-file FILE=tests/core/ui_touch_spec.lua` |
| Reserved AI ids 99+N | `grep -n "99 + n\|id = n" lua/plugins/terminal/toggleterm.lua` |
| Autoreload chain + 250ms dedup | `grep -n "autoread\|FileChangedShellPost\|250\|1000" lua/core/autoreload.lua` |
| timeoutlen set to 300ms (NOT unset — unset means 1000) | `nvim --headless -c 'lua print(vim.o.timeoutlen)' -c qa` (expect `300`); source: `grep -n "timeoutlen" lua/core/options.lua lua/core/settings.lua` |
| No `jk` map in terminal mode | `nvim --headless -c 'lua print(vim.fn.maparg("jk", "t"))' -c qa` (expect empty) |
| Semantic tokens nilled + automatic_enable=false | `grep -n "semanticTokensProvider\|automatic_enable" lua/plugins/lsp/lsp-config.lua` |
| noice LSP hover/signature off | `grep -n "enabled = false" lua/plugins/ui/noice.lua` |
| Suite green | `make test` |
| Still on 0.12.x (workarounds needed) | `nvim --version \| head -1` |
