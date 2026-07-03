---
name: nvsinner-testing-and-qa
description: >
  NvSinner's test suite and evidence standards. Load this when you are about to
  run the tests (make test / make test-file), write or modify a spec under
  tests/, decide what evidence a change needs before calling it "done", or when
  a spec fails and you need to triage it. Covers the plenary busted harness
  (tests/minimal_init.lua, PlenaryBustedDirectory sequential mode, failure
  rendering), the golden inventory of every spec and the hard-won behavior it
  pins, spec-writing conventions (real-Neovim-over-mocking, vim.wait, test
  seams, notify capture), a complete new-spec template, the acceptance evidence
  bar, and the suite's known gaps (no CI, shell scripts untested).
---

# NvSinner testing and QA

The test suite is this repo's **regression armor**. Most of what it pins was won
empirically — behaviors that looked fine, silently broke, and got fixed only
after real-PTY verification (frozen spinners, invisible winbar labels, toasts
that never fired). A green suite is what lets anyone refactor the terminal/agent
UX without re-losing those fights.

## When NOT to use this skill

| You are trying to... | Use instead |
|---|---|
| Classify a change / pass pre-merge gates / know the non-negotiable rules | `nvsinner-change-control` |
| Debug a live failure (broken editor, plugin error, weird rendering) | `nvsinner-debugging-playbook` |
| Design a new empirical experiment to verify Neovim behavior | `nvsinner-empirical-verification` |
| Run quick measurement/inspection one-liners (startup time, hl dumps, etc.) | `nvsinner-diagnostics-toolkit` |
| Install, bootstrap, or update the distro; lazy-lock.json mechanics | `nvsinner-build-and-run` |
| Understand why the architecture is shaped this way | `nvsinner-architecture-contract` |
| Look up the history behind a specific past failure | `nvsinner-failure-archaeology` |

## 1. Running the suite

```bash
# Whole suite (from the repo root):
make test

# One spec file:
make test-file FILE=tests/core/update_spec.lua
```

The Makefile targets expand to (verbatim from `Makefile`):

```
test:
	nvim --headless --noplugin -u tests/minimal_init.lua \
		-c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua', sequential = true }"

test-file:
	nvim --headless --noplugin -u tests/minimal_init.lua \
		-c "PlenaryBustedFile $(FILE)"
```

### What `tests/minimal_init.lua` actually does

Read it — it is 22 lines. In order:

1. Derives the repo root from its own script path
   (`debug.getinfo(1, "S").source` → parent of `tests/`), so the runner works
   from any cwd.
2. Prepends two entries to `runtimepath`: the repo root (so specs can
   `require("core.*")` and `dofile` plugin specs) and
   `stdpath("data") .. "/lazy/plenary.nvim"`. **plenary.nvim is not a test-only
   dependency you install** — it is already on disk as a telescope dependency,
   pinned in `lazy-lock.json`. Consequence: the plugin bootstrap
   (`nvim --headless "+Lazy! restore" +qa`, see `nvsinner-build-and-run`) must
   have run at least once on the machine or `PlenaryBusted*` won't exist.
3. Quiets the environment: `swapfile` off, `shadafile = "NONE"`, `more` off.
4. `vim.cmd("runtime plugin/plenary.vim")` to load the `:PlenaryBusted*`
   commands.

**No plugins load** (`--noplugin` + the minimal rtp), no user config runs, no
side effects: specs get raw Neovim plus this repo's `lua/` tree. That is why
plugin *behavior* can't be tested here — only what native Neovim plus
`lua/core/*` can do (which is a lot: real terminals, real autocmds, real
highlights).

### How `PlenaryBustedDirectory` runs

- It **spawns one fresh headless child Neovim per spec file**, each initialized
  with `tests/minimal_init.lua`. Output shows a `Scheduling:` line per file,
  then a `Testing:` block per file with per-test `Success ||` / `Fail ||` lines
  and a per-file `Success: / Failed : / Errors :` tally.
- `sequential = true` runs the files one at a time instead of in parallel jobs.
  Keep it: several specs open **real terminals with real timing**
  (`ai_activity_spec`, `ui_touch_spec`, `autoreload_spec` sleeps 1s for mtime);
  parallel children competing for the CPU would make the `vim.wait` budgets
  flaky.
- Fresh-child-per-file means specs cannot leak state into each other **across
  files**, but tests within one file share a Neovim instance — hence the
  restore-state conventions in section 3.

### How failures render

An assertion failure prints the test name, the assertion diff, and a stack
traceback with `file:line`, then counts into `Failed`; a Lua error (bad require,
nil index) counts into `Errors` instead. Verified by running a deliberately
failing spec:

```
Fail	||	deliberate failure fails on purpose
            .../fail_spec.lua:3: one is not two
            Expected objects to be equal.
            Passed in:  (number) 2
            Expected:   (number) 1
            stack traceback: ...
Success: 	0
Failed : 	1
Errors : 	0
Tests Failed. Exit: 1
```

Both `PlenaryBustedFile` and `PlenaryBustedDirectory` make **nvim exit with
code 1** on any failure, so `make test` fails properly in scripts (verified
2026-07-02).

### Current suite size (counted from a real run, 2026-07-02)

**8 spec files, 64 tests, 0 failed, 0 errors** on Neovim 0.12.3:

| File | Tests |
|---|---|
| `tests/core/options_spec.lua` | 4 |
| `tests/core/keymaps_spec.lua` | 4 |
| `tests/core/autoreload_spec.lua` | 3 |
| `tests/core/ui_touch_spec.lua` | 4 |
| `tests/core/ai_activity_spec.lua` | 6 |
| `tests/core/update_spec.lua` | 3 |
| `tests/core/health_spec.lua` | 5 |
| `tests/plugins/plugin_specs_spec.lua` | 35 (1 discovery + 1 generated per plugin file; grows automatically when plugin files are added) |

## 2. Spec inventory (golden inventory)

Each spec pins specific, mostly **empirically-won** behavior. Know what you are
protecting before you touch a module or "simplify" a test.

| Spec | Module covered | Hard-won behaviors it pins |
|---|---|---|
| `tests/core/options_spec.lua` | `lua/core/options.lua` | Space/`\` leaders set; 2-space expandtab; number/relativenumber/termguicolors; splitbelow/right + mouse. Leaders matter: they must be set before lazy reads any `keys` spec. |
| `tests/core/keymaps_spec.lua` | `lua/core/keymaps.lua` | Save/undo/redo maps; `<leader>fb`; split-resize maps exist in **both normal and terminal mode** (`<C-,>` in `t` mode is how you resize the AI column from inside it); the four `_G.Increase/DecreaseWidth/Height` helpers are global. |
| `tests/core/autoreload_spec.lua` | `lua/core/autoreload.lua` | `autoread` on; **both** `FileChangedShell` and `FileChangedShellPost` registered in the `auto_reload_on_disk_change` augroup; the edit toast actually fires when an OPEN file is rewritten externally. Pins the empirical finding that with `autoread` + unmodified buffer Neovim fires **only `FileChangedShellPost`** — hooking only `FileChangedShell` would never toast the common AI-edit case. |
| `tests/core/ui_touch_spec.lua` | `lua/core/ui-touch.lua` | Focus/terminal-bar highlight groups exist; **`NvTermBarDim` fg ≠ bg** (the original fg == bg made the idle label invisible on unfocused bars); `mousemoveevent` + fillchars; a real `:terminal` window's winbar **bakes its own buffer number** into `...ai-activity'.winbar(<buf>)` — because `g:statusline_winid` is populated for `'statusline'` but NOT `'winbar'` evaluation. |
| `tests/core/ai_activity_spec.lua` | `lua/core/ai-activity.lua` | Timer handle pinned on `M._timer` (unreferenced active luv handles get GC'd and the spinner silently dies); `NvAiBusy` chip defined with a bg; `winbar(buf)` empty for nil/invalid, idle-without-chip for quiet buffers, `b:nv_term_label` prefix; and the crown jewel: a **real streaming terminal** flips `working` → `idle` — which only works because the signal is `nvim_buf_attach on_lines`, not changedtick polling (terminal ticks freeze when nothing is attached). |
| `tests/core/update_spec.lua` | `lua/core/update.lua` | `:NvSinnerUpdate` command exists; `is_git_repo` detects a `.git` **directory** (worktree `.git` files also accepted per the module); the **not-a-git-clone path warns exactly once and does not pull** (dev-machine symlink / manual-copy installs). Happy path (pull + restore) is deliberately NOT exercised — network + plugins-on-rtp, see the spec header comment. |
| `tests/core/health_spec.lua` | `lua/core/health.lua` + `lua/nvsinner/health.lua` | `check_tools` present/absent per tool (via a swapped `M.tools` table); first-run toast **warns exactly once** then the marker silences it; marker written **even when nothing is missing** (greet-once, never nags); silent when all tools present; the `:checkhealth nvsinner` provider resolves and its report actually renders. |
| `tests/plugins/plugin_specs_spec.lua` | every `lua/plugins/**/*.lua` | Each file `dofile`s without error and returns a structurally valid lazy.nvim spec (string-headed table, dir/url/name/import spec, or list thereof). Catches syntax errors and "returned nothing" bugs in every plugin file without loading any plugin. |

One-liner on plugins: `lazy-lock.json` is the pinned **golden plugin set** — the
suite is only known-green against those commits, and install/update use
`Lazy! restore` (not `sync`) to reproduce it. Details live in
`nvsinner-build-and-run`.

## 3. Conventions for new specs

Every rule below is verified against the existing specs — copy their patterns,
not generic busted lore.

1. **Name it `*_spec.lua`** under `tests/core/` (native modules) or
   `tests/plugins/` (spec-shape checks). `PlenaryBustedDirectory tests/` picks
   it up automatically — no registry to edit.

2. **Require the module under test at the top of the `describe` block** (or
   file top). `ui_touch_spec`, `autoreload_spec`, `keymaps_spec`,
   `options_spec` all do `require("core.x")` as the first line inside
   `describe`; `ai_activity_spec`, `update_spec`, `health_spec` bind it to a
   local at the top. Either is fine; the point is the module's side effects
   (autocmds, highlights, commands) land once, before any `it`.

3. **Plenary busted has NO `setup`/`teardown`/`finally`.** It supports
   `describe`/`it`/`pending`/`before_each`/`after_each` and luassert. Use
   `after_each` for restores that must survive a failing test —
   `health_spec.lua` restores the swapped `health.tools` that way — or restore
   inline **before asserting**. The suite's literal idiom, appearing in
   `autoreload_spec`, `update_spec`, and `health_spec`:

   ```lua
   vim.notify = orig -- restore BEFORE asserting (so a failure can't leak it)
   ```

   A failed assertion throws immediately; anything after it never runs. Restore
   first, assert last.

4. **Capture notifications by swapping `vim.notify`**, never by mocking a
   framework:

   ```lua
   local captured = {}
   local orig = vim.notify
   vim.notify = function(msg, level, opts)
     captured[#captured + 1] = { msg = msg, level = level, title = opts and opts.title }
   end
   -- ... trigger the behavior ...
   vim.notify = orig
   -- ... assert on captured ...
   ```

5. **Prefer REAL Neovim behavior over mocking.** The suite opens real
   terminals, writes real files, fires real autocmds, and `vim.wait`s for
   observable state. The canonical pattern, verbatim from
   `tests/core/ai_activity_spec.lua`:

   ```lua
   vim.cmd([[terminal sh -c 'for i in $(seq 1 30); do echo line $i; sleep 0.1; done']])
   local buf = vim.api.nvim_get_current_buf()
   assert.are.equal("terminal", vim.bo[buf].buftype)

   local became_busy = vim.wait(3000, function()
     return ai.winbar(buf):find("working") ~= nil
   end, 50)
   assert.is_true(became_busy, "winbar should report working while output streams")
   ```

   `vim.wait(budget_ms, predicate, poll_ms)` pumps the event loop while
   polling — this is how you test async/timer/autocmd behavior without sleeps.
   Give generous budgets (the suite uses 3000–5000ms for terminal state, 500ms
   for autocmd application) so a loaded machine doesn't flake.

6. **Test seams: an optional `opts` table that overrides one prod value.** Two
   existing examples to imitate:
   - `lua/core/update.lua` → `M.update({ dir = ... })` — annotated
     `---@param opts? { dir?: string } test seam: override the config dir to pull.`
   - `lua/core/health.lua` → `M.first_run_notify({ marker = ... })` plus
     `M.tools` exposed on the module table ("Exposed on M so tests can swap it
     for a deterministic set").

   To add one without polluting prod code: take `opts?` as the last parameter,
   default every field to the production value
   (`local dir = (opts and opts.dir) or vim.fn.stdpath("config")`), annotate it
   `test seam`, and never branch on "am I in a test". Production callers pass
   nothing; the seam is invisible to them.

7. **Clean up what you create, inline.** Buffers:
   `vim.api.nvim_buf_delete(buf, { force = true })` or `vim.cmd("bwipeout!")`.
   Temp paths: `vim.fn.tempname()` to create, `os.remove(path)` /
   `vim.fn.delete(dir, "rf")` to remove. Tests in the same file share one
   Neovim instance — a leftover terminal buffer or hijacked global breaks the
   tests after yours.

## 4. How to add a spec — worked template

Suppose you added a hypothetical native module `lua/core/idle-guard.lua` that
(a) sets an option, (b) registers an autocmd in an augroup, (c) notifies via a
function with a `{ marker = ... }` test seam, and (d) flips an async state you
must wait for. Create `tests/core/idle_guard_spec.lua` (do NOT edit
`Makefile` or `tests/minimal_init.lua` — discovery is automatic):

```lua
-- Tests for the idle guard (lua/core/idle-guard.lua).

describe("core.idle-guard", function()
	local guard = require("core.idle-guard") -- module under test, top of describe

	-- If a test swaps module state (tables, config), restore it in after_each so
	-- a mid-test failure can't poison later tests (see health_spec.lua).
	local orig_config = guard.config
	after_each(function()
		guard.config = orig_config
	end)

	it("sets the option it owns", function()
		assert.is_true(vim.o.autoread) -- assert observable Neovim state, not internals
	end)

	it("registers its autocmd in its augroup", function()
		local aus = vim.api.nvim_get_autocmds({ group = "idle_guard", event = "CursorHold" })
		assert.is_true(#aus > 0)
	end)

	it("notifies once via the marker seam, then stays quiet", function()
		local marker = vim.fn.tempname() -- fresh path per run; never stdpath("state")

		local notes = {}
		local orig = vim.notify
		vim.notify = function(msg, level)
			notes[#notes + 1] = { msg = msg, level = level }
		end

		guard.warn_once({ marker = marker })
		guard.warn_once({ marker = marker }) -- marker exists now → no-op

		vim.notify = orig -- restore BEFORE asserting (so a failure can't leak it)
		vim.fn.delete(marker)

		assert.are.equal(1, #notes, "should notify exactly once")
		assert.matches("idle%-guard", notes[1].msg) -- luassert matches() takes a Lua pattern
	end)

	it("flips state on real terminal activity", function()
		-- Real behavior, not a mock: open a terminal that streams, wait for state.
		vim.cmd([[terminal sh -c 'for i in $(seq 1 10); do echo tick; sleep 0.1; done']])
		local buf = vim.api.nvim_get_current_buf()
		assert.are.equal("terminal", vim.bo[buf].buftype)

		local became_active = vim.wait(3000, function()
			return guard.is_active(buf)
		end, 50)
		assert.is_true(became_active, "should turn active while output streams")

		local went_idle = vim.wait(5000, function()
			return not guard.is_active(buf)
		end, 100)
		assert.is_true(went_idle, "should settle back to idle after output stops")

		vim.api.nvim_buf_delete(buf, { force = true }) -- clean up the terminal
	end)
end)
```

Run it alone first, then the whole suite (your spec must not break its
neighbors — shared instance within a file, real timing across files):

```bash
make test-file FILE=tests/core/idle_guard_spec.lua
make test
```

Finally, add a row to the spec table in `CLAUDE.md`'s **Tests** section
(formatting rules for that edit live in `nvsinner-docs-and-style`).

## 5. The evidence bar (acceptance discipline)

A change to this repo is not "done" when the code looks right. Minimum
evidence, in order (this is the testing slice — the full pre-merge gate list
lives in `nvsinner-change-control`):

1. **Loadfile check** on every touched Lua file (syntax, no network):
   ```bash
   nvim --headless -c "lua assert(loadfile('lua/plugins/<category>/<file>.lua'))" -c "qa"
   ```
2. **Headless boot clean** — the config starts without startup errors:
   ```bash
   nvim --headless -c "lua vim.defer_fn(function() vim.cmd('messages'); vim.cmd('qa') end, 300)"
   ```
3. **Full `make test` green** — not just the spec for your module. Suite
   baseline is 64/64; any regression is your regression.
4. **New or changed behavior gets a spec.** If you added a user-visible
   behavior to `lua/core/*` and no `it` block would fail if it broke, the
   change is unfinished. Plugin additions are covered structurally by
   `plugin_specs_spec` for free, but core behavior needs its own test.
5. **Empirically-discovered Neovim behavior gets BOTH a CLAUDE.md note AND a
   regression spec.** This is the house rule that keeps hard-won knowledge from
   evaporating. Existing precedents — imitate them:
   - Terminal `changedtick` freezes without an attached listener →
     CLAUDE.md *Agent activity* ("Signal: `nvim_buf_attach` `on_lines`, NOT
     changedtick polling") + the streaming-terminal test in
     `ai_activity_spec.lua`.
   - `g:statusline_winid` empty during `'winbar'` evaluation → CLAUDE.md
     *Agent activity* + the baked-buffer-number test in `ui_touch_spec.lua`.
   - Silent reload fires only `FileChangedShellPost` → CLAUDE.md *Auto-reload*
     + the toast test in `autoreload_spec.lua`.

   (Designing the experiment that *establishes* such a fact is
   `nvsinner-empirical-verification`'s territory; your job here is to encode
   the result.)

### When a spec fails — triage order

1. **Reproduce in isolation**: `make test-file FILE=<the failing spec>`. If it
   passes alone but fails in the full run, suspect timing/load (real terminals
   + `vim.wait` budgets) or cross-test state within the file.
2. **Read the `Fail ||` block**: `Failed` = assertion (behavior changed —
   decide: regression in your change, or intentional change that needs the spec
   updated *and* CLAUDE.md re-synced). `Errors` = Lua error (require path, nil
   index, missing plenary).
3. **Check the harness before the code**: is plenary at
   `stdpath("data")/lazy/plenary.nvim`? Did you run tests from the repo root?
   Are you on Neovim 0.11+?
4. **Never "fix" a failure by deleting or loosening the assertion** without
   reading the inventory row in section 2 — most assertions pin an incident.
5. Still stuck → `nvsinner-debugging-playbook`.

## 6. Known gaps — plainly

- **No CI.** An open `TODO.md` item ("CI that boots the config headless + runs
  `make test` on push"). Today the suite runs only on dev machines, only when
  someone remembers. Treat "make test passed locally" as the strongest evidence
  that currently exists.
- **Not covered by the suite:**
  - **Visual rendering** — highlights are asserted as *defined* (group exists,
    fg ≠ bg), never as *looking right* on screen. Theme regressions that keep
    the groups defined pass silently.
  - **Real PTY winbar repaint** — the `nvim__redraw{winbar=true}` fix (spinner
    frozen while focused inside a terminal) was verified manually in a real PTY
    and is documented in CLAUDE.md, but headless children can't assert screen
    repaints. The *state* flip is tested; the *paint* is not.
  - **`install.sh` / `uninstall.sh`** — zero automated coverage of the shell
    scripts (clone/update, launcher, PATH hint, XDG dir removal, the
    symlink-unlink-don't-follow safety property).
  - **Cross-platform** — everything is verified on macOS (dev machine, Neovim
    0.12.3). Linux paths in the scripts and docs are untested.
  - **Plugin runtime behavior** — `plugin_specs_spec` proves specs load and are
    well-shaped; it does not start plugins (`--noplugin` harness). Whether
    telescope actually greps is out of scope.
  - **`update.lua` happy path** — pull + `Lazy restore` needs network and
    plugins on the rtp; only the guard/warning path is tested (spec header says
    so explicitly).
  - **`health.setup()` interactive path** — the `User VeryLazy` + 800ms-defer
    first-run wiring bails in headless (`#nvim_list_uis() == 0`), so only
    `first_run_notify` itself is testable; the autocmd timing is not.
- Ambitions to close these (CI, script tests, screenshot/PTY harnesses) belong
  in `nvsinner-frontier` — do not bolt them onto the suite ad hoc.

## Provenance and maintenance

**Facts verified: 2026-07-02** by direct inspection of `Makefile`,
`tests/minimal_init.lua`, all 8 spec files, `lua/core/update.lua`,
`lua/core/health.lua`, `TODO.md`, and CLAUDE.md, plus live runs of `make test`
(64/64 green on Neovim 0.12.3), `make test-file FILE=tests/core/update_spec.lua`,
and a deliberately failing spec (confirmed `Fail ||` rendering + nvim exit
code 1 in both file and directory modes).

Re-verify with:

```bash
make test                                            # expect 8 files, 64 total, 0 Failed/Errors
make test-file FILE=tests/core/options_spec.lua      # single-file path still works
ls tests/core tests/plugins                          # spec inventory unchanged?
grep -n "sequential" Makefile                        # sequential mode still on
grep -rn "test seam" lua/core/                       # seams: update.lua {dir}, health.lua {marker}
```

If a spec file is added/removed or its pinned behaviors change, update the
inventory table (section 2) AND the spec table in CLAUDE.md's Tests section in
the same change.
