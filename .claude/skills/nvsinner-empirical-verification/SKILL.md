---
name: nvsinner-empirical-verification
description: >
  NvSinner's "prove it, don't just believe :help" discipline: runnable probe
  recipes for settling Neovim runtime-behavior questions, with worked examples
  re-run on this machine, plus the idea lifecycle (hunch → probe → recorded
  finding → regression spec → adopted change). Load BEFORE claiming any Neovim
  runtime behavior in code, docs, or review; when documentation and observation
  disagree; when designing an experiment to settle a behavior question; or when
  deciding whether an idea is proven enough to adopt. Do NOT load it to look up
  already-settled findings (nvsinner-failure-archaeology), for platform theory
  (neovim-internals-reference), or for routine measurement one-liners
  (nvsinner-diagnostics-toolkit).
---

# Empirical verification — the NvSinner method

Every load-bearing design decision in `lua/core/` exists because someone ran
the experiment instead of trusting intuition or `:help`. This skill is the
method. **Critical rule: recorded findings decay.** Two of this repo's own
"verified empirically" claims did not reproduce as recorded when re-probed on
Neovim 0.12.3 (2026-07-02) — see recipes 2 and 3. Re-run the probe on the
current Neovim before building on a recorded claim.

## When NOT to use this skill

- You want the settled finding, not the method → `nvsinner-failure-archaeology`.
- You want the platform rules behind a finding → `neovim-internals-reference`.
- You want a routine health/perf/keymap measurement → `nvsinner-diagnostics-toolkit`.
- You want spec-writing mechanics → `nvsinner-testing-and-qa`.

## The probe pattern

All recipes share one shape: a self-contained Lua file run as
`nvim --headless --clean -c "luafile <probe>.lua"`. Always use `--clean` so the
config under investigation cannot contaminate the result; register observers
FIRST, act second, `vim.wait()` for the state, print, `qa!`. Write probes to a
scratch dir, never into the repo.

## Recipe 1 — which autocmd events fire, in what order

**Use when:** behavior depends on event choice/ordering (the autoreload
subsystem lives or dies on this).

```lua
-- probe_fcs.lua
vim.opt.autoread = true
local fired = {}
for _, ev in ipairs({ "FileChangedShell", "FileChangedShellPost" }) do
  vim.api.nvim_create_autocmd(ev, { callback = function() table.insert(fired, ev) end })
end
local tmp = vim.fn.tempname()
vim.fn.writefile({ "original" }, tmp)
vim.cmd.edit(tmp)
vim.uv.sleep(1100)                       -- beat 1s mtime resolution
vim.fn.writefile({ "changed externally" }, tmp)
vim.cmd("checktime")
vim.wait(500, function() return #fired > 0 end)
print("EVENTS FIRED: " .. table.concat(fired, ", "))
print("BUFFER NOW: " .. vim.api.nvim_buf_get_lines(0, 0, 1, false)[1])
vim.cmd("qa!")
```

**Worked example (run 2026-07-02, Neovim 0.12.3):**

```
EVENTS FIRED: FileChangedShellPost
BUFFER NOW: changed externally 2
```

REPRODUCED as recorded: with `autoread` on and the buffer unmodified, the
silent reload fires **only** `FileChangedShellPost` — hooking only
`FileChangedShell` would miss the common AI-edit case. This is why
`lua/core/autoreload.lua` hooks both. Story: `nvsinner-failure-archaeology`.

## Recipe 2 — what is available during statusline/winbar evaluation

**Use when:** a `%{}`/`%!` expression renders empty or reads wrong state.

Probe: set the option to an expression that records `get(g:,
'statusline_winid', 'MISSING')` into a global, force evaluation with
`nvim__redraw{statusline=true, winbar=true, flush=true}`, print.

**Worked example (run 2026-07-02, Neovim 0.12.3, headless):**

- With `%{ProbeFn()}` **items**: `g:statusline_winid = 'MISSING'` for
  **statusline AND winbar**.
- With `%!ProbeFn()` **full-expressions**: `g:statusline_winid = 1000` (the
  real window id) for **statusline AND winbar**.

⚠️ **Refines the recorded claim.** CLAUDE.md records "populated for
'statusline' evaluation but not for 'winbar'". On 0.12.3 the discriminator is
the evaluation FORM: `%!` sets it (both options), `%{}` items do not (either
option). The repo's winbar uses a `%{%v:lua...%}` item
(`term_bar(win)` in `lua/core/ui-touch.lua`), so the variable was genuinely
absent there — the design conclusion (bake the buffer number into each
window's string) remains correct and required. The recorded *mechanism* is
version- or form-imprecise; do not build anything new on `statusline_winid`
inside `%{}` items.

## Recipe 3 — terminal buffer behavior (streams, ticks, attachment)

**Use when:** anything involves detecting terminal output (the ai-activity
subsystem).

Probe: `jobstart({...}, { term = true })` in a hidden buffer, stream output,
sample `nvim_buf_get_changedtick` before/after, then `nvim_buf_attach` and
count `on_lines`.

**Worked example (run 2026-07-02, Neovim 0.12.3, headless, hidden buffer):**

```
HIDDEN+UNATTACHED: tick 2 -> 8 after 5 output lines (frozen=false)
```

⚠️ **Did NOT reproduce as recorded.** CLAUDE.md records that an unattached,
unrendered terminal buffer's changedtick "can sit frozen while output streams
(verified empirically)". On 0.12.3 headless the tick advanced. Possibilities:
the behavior changed upstream since the original probe, or the original
scenario differed (real TUI, different version). The **design decision stands
on its own**: `on_lines` is a push signal delivered per output chunk with no
polling loop, no cadence guessing, and a documented contract — still the right
mechanism for `lua/core/ai-activity.lua`. But do not cite "frozen changedtick"
as current fact without re-running this probe on the target version; flag the
CLAUDE.md sentence for a date-stamped caveat instead of deleting history.

The positive half — attach then stream, watch busy→idle — is pinned as a
regression spec: `tests/core/ai_activity_spec.lua` opens a real terminal and
`vim.wait`s for the state flip. That is the canonical "real behavior over
mocking" pattern (`nvsinner-testing-and-qa`).

## Recipe 4 — fast event context restrictions

**Use when:** writing any callback that might run in a *fast event context*
(`nvim_buf_attach` callbacks, `vim.uv` timer callbacks) — contexts where most
`vim.api`/`vim.fn` calls are forbidden.

Probe: inside `on_lines`, `pcall` a forbidden call and an allowed call, record
both.

**Worked example (run 2026-07-02, Neovim 0.12.3):**

```
vim.api in fast context -> ok=false err=E565: Not allowed to change text or change window | uv.now ok=true
```

REPRODUCED: mutating API calls fail inside `on_lines` (E565 here; E5560 is the
other error class you may see); `uv.now()` and plain Lua tables are safe. This
is why the `on_lines` callback in `lua/core/ai-activity.lua` touches ONLY the
plain `state` table and lets a scheduled timer do the redraw. Escape hatch:
`vim.schedule()`.

## Recipe 5 — rendering claims need a real TUI (the honest limit)

`--headless` has no compositor: winbar/statusline REPAINT, focus glow,
floating-window visuals, and spinner animation cannot be verified headlessly.
The repo's `:redrawstatus`-doesn't-repaint-the-winbar-in-terminal-mode finding
was made "in a real PTY render" and can only be re-checked interactively:

1. Open `nvim` in a real terminal. `:terminal`, run a long noisy command
   (`while true; do date; sleep 0.3; done`), stay in terminal-insert mode.
2. Watch the winbar: with `nvim__redraw{winbar=true,flush=true}` (current
   code) the braille spinner animates; to test the rejected path, temporarily
   make the `pcall` in `lua/core/ai-activity.lua` fail so it falls back to
   `redrawstatus!` and observe whether the bar freezes.
3. Record the observation with date + Neovim version before drawing
   conclusions.

Mark any such claim in docs as interactive-verified with its date. Do not
present a headless pass as proof of a rendering claim.

## Recipe 6 — object lifetime / GC hazards

The pinned-timer doctrine (`M._timer` in `lua/core/ai-activity.lua`): an
active-but-unreferenced `uv` timer handle can be garbage-collected and
silently stop. GC reproduction is **nondeterministic** — a probe forcing
`collectgarbage("collect")` may or may not kill the handle in a given run, so
this is doctrine, not a repeatable demo: **always keep a strong reference to
long-lived uv handles** (module table field). If you must probe it, loop
`collectgarbage()` + `vim.wait` and treat "timer ever stops" as confirmation;
treat "never stops" as inconclusive, not refutation.

## The discipline (idea lifecycle)

1. **Hypothesis predicts the observation before you run.** Write down what the
   probe will print if you're right AND if you're wrong. If both hypotheses
   predict the same output, the probe discriminates nothing — redesign it.
2. **One mechanism must explain ALL observations, including negatives.** The
   original activity-detector investigation qualified: the attach-based
   mechanism explained both why polling looked frozen and why the listener
   always fired. Recipe 3's re-probe shows why findings still carry dates.
3. **Record or it didn't happen.** A settled finding gets: a "verified
   empirically" note at the decision site (CLAUDE.md subsystem section, per
   `nvsinner-docs-and-style`) **with a date and Neovim version** (the missing
   version stamps are exactly what made recipes 2–3 ambiguous), an entry in
   `nvsinner-failure-archaeology` if an approach was rejected, and a
   regression spec if the behavior is load-bearing (`nvsinner-testing-and-qa`).
4. **Adoption routes through change control.** A proven finding becomes a code
   change only via the gates in `nvsinner-change-control`. A disproven idea
   becomes a documented rejection so nobody retries it.
5. Historically, every major finding here started as a *failing UI
   observation* (frozen spinner, empty bar, missing toast) that was then
   reduced to a controlled probe. When you see a weird symptom, resist
   patching at the symptom site; reduce first.

## Provenance and maintenance

Facts verified: 2026-07-02, Neovim 0.12.3 (`NVIM v0.12.3`), macOS, headless
probes with `--clean`; outputs quoted verbatim. Recipes 2 and 3 contradict or
refine CLAUDE.md's recorded claims — flagged above; re-probe before editing
either doc sentence.

Re-verification one-liners:

- Neovim version (findings are version-scoped): `nvim --version | head -1`
- Recipe 1 still holds: re-run the probe file (30 s)
- Fast-context doctrine intact in code: `grep -n 'FAST event' lua/core/ai-activity.lua`
- Timer still pinned: `grep -n 'M._timer' lua/core/ai-activity.lua`
- Winbar still baked per-window: `grep -n 'winbar(%d)' lua/core/ui-touch.lua`
