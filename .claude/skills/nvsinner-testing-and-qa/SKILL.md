---
name: nvsinner-testing-and-qa
description: >
  NvSinner's test suite, measurement instruments and evidence standards. Load
  this when you are about to run the tests (make test / make test-file), write
  or modify a spec under tests/, decide what evidence a change needs before
  calling it "done", when a spec fails and you need to triage it, or when you
  need to VERIFY editor state instead of guessing — boot errors, startup time,
  keymap presence, palette drift. Covers the plenary busted harness
  (tests/minimal_init.lua, PlenaryBustedDirectory sequential mode, failure
  rendering), which specs pin hard-won behavior, spec-writing conventions
  (real-Neovim-over-mocking, vim.wait, test seams, notify capture), a complete
  new-spec template, the four shipped diagnostic scripts, the interactive QA
  matrix for terminal/agent UX, the acceptance evidence bar, what CI does and
  does not enforce, and the suite's known gaps. Do NOT load it for experiment
  DESIGN on unsettled Neovim behavior (nvsinner-empirical-verification) or for
  symptom-driven debugging flow (nvsinner-debugging-playbook).
---

# NvSinner testing and QA

The test suite is this repo's **regression armor**. Most of what it pins was
won empirically — behaviors that looked fine, silently broke, and got fixed
only after real-PTY verification (frozen spinners, invisible winbar labels,
toasts that never fired). A green suite is what lets anyone refactor the
terminal/agent UX without re-losing those fights.

## When NOT to use this skill

| You are trying to… | Use instead |
|---|---|
| Classify a change, pass the pre-merge gates, look up a current value | `nvsinner-contract` |
| Debug a live failure (broken editor, plugin error, weird rendering) | `nvsinner-debugging-playbook` |
| Design a new empirical experiment to verify Neovim behavior | `nvsinner-empirical-verification` |
| Install, bootstrap or update the distro; lazy-lock.json mechanics | `nvsinner-build-and-run` |
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
2026-09-19).

## 2. Spec inventory

**Do not keep a frozen table of specs and counts here** — the last one said
"8 spec files, 64 tests" long after the suite had grown past six times that.
Read the current shape instead:

```bash
find tests -name '*_spec.lua' | sort          # every spec
make test 2>&1 | sed 's/\x1b\[[0-9;]*m//g' \
  | awk '/^Success: /{s+=$2} /^Failed : /{f+=$3} /^Errors : /{e+=$3} \
         END{printf "tests=%d failed=%d errors=%d\n", s, f, e}'
```

Specs are discovered automatically: adding `tests/<area>/<name>_spec.lua` is
enough — do NOT edit `Makefile` or `tests/minimal_init.lua`.

### The specs worth knowing about before you refactor

Most specs assert the obvious. These pin something non-obvious that was **paid
for in debugging**; read the spec before changing the module it covers.

| Spec | Pins |
|---|---|
| `core/ai_activity_spec.lua` | The detector against a **real streaming terminal**: busy→idle transitions, the GC-pinned timer, and that `uv_timer:start` from a fast event context is legal. The single most load-bearing spec in the repo. |
| `core/ui_touch_spec.lua` | The winbar expression **bakes the buffer number in** (`g:statusline_winid` is absent during winbar evaluation), and `NvTermBarDim` keeps fg ≠ bg. |
| `core/autoreload_spec.lua` | **Both** `FileChangedShell` and `FileChangedShellPost` are registered, and the toast fires on a real external rewrite. The empirical finding: with `autoread` and an unmodified buffer, Neovim fires **only** the Post event — hooking the first alone would never toast the common AI-edit case. |
| `core/options_spec.lua` | Leaders are set, and `timeoutlen` is the calibrated value — leaders must exist before lazy reads any `keys` spec. |
| `core/keymaps_spec.lua` | Split-resize maps exist in **both** normal and terminal mode — `<C-,>` in `t` mode is how you resize the AI column from inside it. |
| `core/health_spec.lua` | Headless runs never consume the first-run marker. |
| `core/carbon_spec.lua` | The theme/accent/folder/slot resolution, including `vim.g` winning over the env. |
| `core/ts_compat_spec.lua` | The query-directive shim that makes the `branch = "master"` pin survivable on 0.12. |
| `plugins/tombstone_lock_spec.lua` | **A tombstoned plugin keeps its `lazy-lock.json` entry**, so flipping `enabled = true` lands on the tested commit instead of latest. This house rule is documented nowhere else in the repo. |
| `plugins/lsp_capabilities_spec.lua` | Semantic tokens stay nilled, and `<leader>zl` folding stays opt-in (`'foldmethod'` is exclusive, so `expr` makes `:fold` raise E350). |
| `plugins/plugin_specs_spec.lua` | Every file under `lua/plugins/**` loads and returns a valid lazy spec. Grows automatically with the plugin set. |

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

Suppose you added a hypothetical native module `lua/core/example-guard.lua` that
(a) sets an option, (b) registers an autocmd in an augroup, (c) notifies via a
function with a `{ marker = ... }` test seam, and (d) flips an async state you
must wait for. Create `tests/core/example_guard_spec.lua` (do NOT edit
`Makefile` or `tests/minimal_init.lua` — discovery is automatic):

```lua
-- Tests for the idle guard (lua/core/example-guard.lua).

describe("core.example-guard", function()
	local guard = require("core.example-guard") -- module under test, top of describe

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
		local aus = vim.api.nvim_get_autocmds({ group = "example_guard", event = "CursorHold" })
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
make test-file FILE=tests/core/example_guard_spec.lua
make test
```

Finally, add a row to the spec table in `CLAUDE.md`'s **Tests** section
(formatting rules for that edit live in `nvsinner-docs-and-style`).

## 5. The evidence bar (acceptance discipline)

A change to this repo is not "done" when the code looks right. Minimum
evidence, in order (this is the testing slice — the full pre-merge gate list
lives in `nvsinner-contract` §5):

1. **Loadfile check** on every touched Lua file (syntax, no network):
   ```bash
   nvim --headless -c "lua assert(loadfile('lua/plugins/<category>/<file>.lua'))" -c "qa"
   ```
2. **Headless boot clean** — the config starts without startup errors:
   ```bash
   nvim --headless -c "lua vim.defer_fn(function() vim.cmd('messages'); vim.cmd('qa') end, 300)"
   ```
3. **Full `make test` green** — not just the spec for your module. Suite
   baseline is 303 passing (2026-07-28); any regression is your regression.
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

**What runs this bar for you, and what does not.** Items 2 and 3 are enforced
automatically: `.github/workflows/ci.yml` re-runs the headless boot check and
`make test` on every pull request and every push to `main`, on a clean machine
against the pinned lockfile — so a green PR is stronger evidence than "it
passed locally". The `.githooks/pre-push` hook — which you must opt into with
`git config core.hooksPath .githooks`; nothing wires it for you — catches
both plus `stylua --check` before the push even lands. Neither covers items 1,
4 and 5, nor formatting once someone passes `--no-verify`: those stay yours.
See §6 for what CI still misses.

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
   Are you on Neovim 0.12+?
4. **Never "fix" a failure by deleting or loosening the assertion** without
   reading the inventory row in section 2 — most assertions pin an incident.
5. Still stuck → `nvsinner-debugging-playbook`.

## 6. Instruments — measure, don't eyeball

Four tested scripts live in `.claude/skills/nvsinner-testing-and-qa/scripts/`.
All are read-only and run from the repo root.

| Script | Answers | Pass condition |
|---|---|---|
| `boot-check.sh` | Does the config boot without writing to the message log? | exit 0, `boot clean, no messages` |
| `keymap-audit.sh` | Do the load-bearing keymaps exist in a real instance? | exit 0, `ALL KEYMAPS PRESENT` |
| `palette-audit.sh` | Is there a hex in `lua/` that is not a carbon role? | exit 0, `palette clean` |
| `startup-time.sh` | How long is cold start, and what dominates it? | informational — report a median of 3, never one run |

`palette-audit.sh` **derives** its whitelist from `lua/core/carbon.lua` at run
time and skips Lua comments, so it cannot go stale the way its predecessor did
(that one froze on the kanagawa/glass palette and flagged every carbon role as
a violation). Literals that are deliberately not roles live in a short `allow`
list inside the script, each with a reason.

Startup numbers carry ±2× run variance on a loaded machine. Any public
startup claim needs a median re-measured in the same commit that states it.

## 7. Interactive QA matrix (terminal/agent UX)

Headless cannot verify repaint. These rows need a real terminal running
`nvim` or `nvsinner`; record date, Neovim version and pass/fail per row in the
PR when you touch `ai-activity`, `ui-touch`, `autoreload` or `toggleterm`.

| # | Case | Expected | If broken |
|---|---|---|---|
| 1 | Fresh instance → `<leader>j` | The bar appears immediately on first open | The `TermOpen` re-run of `focus()` regressed (scratch→terminal transition) |
| 2 | (a) `<leader>t` only; (b) `<leader>j` only; (c) both | Every terminal window has a bar; horizontals at the bottom, AI column full-height on the right | `restore_layout()` ordering — columns must be forced `wincmd L` LAST |
| 3 | `<leader>j`, `<leader>j2`, `<leader>t`, `<leader>t2` | Labels `AI · 1`, `AI · 2`, `term 1`, `term 2` | `term.bufnr` nil at `on_panel_open`. A bare `:ToggleTerm` showing no label is correct |
| 4 | Cycle terminal ↔ code ↔ neo-tree ↔ dashboard | Terminal bars brighten/dim but never disappear (no reflow); neo-tree/dashboard/floats untouched | A special window got restyled → its filetype is missing from `SKIP_FT` |
| 5 | `<leader>t`, then a command that streams output for a while | The bar shows the spinner and `working…` in the busy chip | The `TermOpen` attach failed |
| 6 | Let case 5 finish, stop typing | Flips to `idle` after the quiet threshold | Check `_timer` non-nil (GC pin) and `_ticking` — the timer is busy-gated and idle-by-design when nothing is busy |
| 7 | Two rapid external writes to one open file | ONE toast | The dedup window or the file-name key changed |
| 8 | Modify a buffer without saving, overwrite the file externally, refocus | Buffer reloads; unsaved edits gone — **by design** | A `W12` prompt means the `FileChangedShell` handler regressed |
| 9 | Case 5 while staying in terminal-insert mode | The spinner animates | Someone replaced `nvim__redraw` with `:redrawstatus` |

## 8. Known gaps — plainly

- **CI does not check formatting.** `stylua --check` runs only in
  `.githooks/pre-push`, which is **opt-in** (`git config core.hooksPath
  .githooks` — nothing wires it for you, and `install.sh` does not) and
  skippable with `--no-verify`. Formatting drift can reach `main`.
- **One platform, no nightly.** CI is `ubuntu-latest` × `{v0.12.0, stable}`.
  macOS is the dev platform and hosts `image-open.lua`'s `qlmanage`/`sips`
  path; nightly is where the crash class lives. Neither is exercised.
- **The `NVIM_APPNAME` path is never tested.** CI symlinks the checkout to
  `~/.config/nvim`, so the distro's own launch mode is untested in CI.
- **`install.sh` and `uninstall.sh` have zero automated coverage** — the
  highest-blast-radius scripts in the repo, since they run on other people's
  machines.
- **Headless cannot verify rendering.** Anything about what a bar *looks* like
  needs §7's interactive matrix.

## Provenance and maintenance

**Facts verified: 2026-09-19** — suite run green on this machine:
**512 tests, 0 failed, 0 errors** across 50 spec files. The previous version of
this skill claimed "8 spec files, 64 tests" and credited `install.sh` with
wiring the pre-push hook, which it does not do.

This skill absorbed `nvsinner-diagnostics-toolkit` (its scripts now live under
`scripts/` here) and the interactive QA matrix from
`nvsinner-terminal-ux-campaign`.

Re-verification:
```bash
make test
find tests -name '*_spec.lua' | wc -l
for s in boot-check keymap-audit palette-audit; do \
  .claude/skills/nvsinner-testing-and-qa/scripts/$s.sh >/dev/null && echo "$s OK"; done
grep -n 'hooksPath\|githooks' install.sh || echo "install.sh wires no hook (correct)"
sed -n '1,40p' .github/workflows/ci.yml
```
