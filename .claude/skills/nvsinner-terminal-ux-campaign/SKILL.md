---
name: nvsinner-terminal-ux-campaign
description: >
  The decision-gated campaign for NvSinner's hardest live problem: fragility in
  the terminal/agent-UX stack (winbar activity spinner, disk auto-reload,
  focus bars, AI-column layout). Load when a terminal-UX bug is reported, when
  hardening or extending lua/core/ai-activity.lua, lua/core/ui-touch.lua,
  lua/core/autoreload.lua, or lua/plugins/terminal/toggleterm.lua, or when
  choosing the next improvement to agent busy/idle detection. Contains the
  baseline gate, the edge-case reproduction matrix, the ranked solution menu
  with proof obligations, and the fenced-off wrong paths. Do NOT load it for
  general debugging triage (nvsinner-debugging-playbook), for the settled
  war stories (nvsinner-failure-archaeology), or for platform theory
  (neovim-internals-reference).
---

# Terminal/agent-UX campaign

The four files under campaign: `lua/core/ai-activity.lua` (busy/idle
detector + winbar renderer), `lua/core/ui-touch.lua` (focus styling + terminal
bar), `lua/core/autoreload.lua` (disk-wins reload + AI-edit toast),
`lua/plugins/terminal/toggleterm.lua` (panel ids, layout, labels). Every past
fix here required empirical verification — do not skip gates.

## When NOT to use this skill

- Unknown symptom, unknown subsystem → `nvsinner-debugging-playbook` first.
- "Why is it built this way?" → `nvsinner-architecture-contract`.
- "Was X already tried?" → `nvsinner-failure-archaeology` (also fenced below).
- Designing a new probe for unsettled behavior → `nvsinner-empirical-verification`.

## Phase 0 — Baseline gate (run before touching anything)

```bash
make test                                              # expect: every block "Failed: 0, Errors: 0"
make test-file FILE=tests/core/ai_activity_spec.lua    # detector + real streaming terminal
make test-file FILE=tests/core/ui_touch_spec.lua       # bar highlights + baked buf number
make test-file FILE=tests/core/autoreload_spec.lua     # Post-event toast
.claude/skills/nvsinner-diagnostics-toolkit/scripts/boot-check.sh   # expect: "boot clean, no messages"
```

Verified 2026-07-02: full suite green (`Failed: 0, Errors: 0`), boot clean.
**If baseline fails → you are looking at a regression, not your new work; go to
`nvsinner-debugging-playbook` before proceeding.**

## Phase 1 — Edge-case reproduction matrix

Interactive checks need a real terminal running `nvim` (or `nvsinner`).
Headless cannot verify repaint (see `nvsinner-empirical-verification` recipe 5).
"Expected" values below are code-derived from the four files (constants
verified 2026-07-02); rendering expectations are marked [interactive].

| # | Case | Procedure | Expected | If broken instead |
|---|---|---|---|---|
| 1 | First-open winbar | Fresh nvim → `<leader>j` | Bar appears immediately with `AI · 1 ● idle` [interactive] | Bar missing on FIRST open only → the `TermOpen` re-run of `focus()` regressed (scratch→terminal transition, `ui-touch.lua` autocmd list) |
| 2 | All 3 layouts | (a) `<leader>t` only; (b) `<leader>j` only; (c) both | Every terminal window has a bar; horizontals bottom (20% height), AI column right (width 50), column full-height [interactive] | Column not full-height / horizontal beside column → `restore_layout()` ordering (columns must be forced `wincmd L` LAST) |
| 3 | Multi-session labels | `<leader>j`, `<leader>j2`, `<leader>t`, `<leader>t2` | Labels `AI · 1`, `AI · 2`, `term 1`, `term 2` (from `b:nv_term_label`, set in `on_panel_open`) | Wrong/missing label → `term.bufnr` nil at `on_panel_open`, or plain `:terminal` (no label is correct there) |
| 4 | Focus transitions | Cycle terminal ↔ code ↔ neo-tree ↔ dashboard | Terminals: bar brightens/dims, never disappears (no reflow). Code panes: glass bg + cursorline when focused. Neo-tree/dashboard/floats: untouched (`eligible()` skips `SKIP_FT` + floats) [interactive] | Special window restyled → its filetype missing from `SKIP_FT` in `ui-touch.lua` |
| 5 | Generic busy (non-AI) | `<leader>t`, run `sleep 1 && ls -R /usr/lib 2>/dev/null` | Bar shows `term 1 ⠹ working…` in the crimson `NvAiBusy` chip while output streams [interactive] | Never busy → `nv_ai_activity` TermOpen attach failed (probe: augroup autocmd count, diagnostics-toolkit §6) |
| 6 | Idle flip timing | After case 5's command ends, stop typing | Flips to `● idle` after ~1.2 s of quiet (`IDLE_MS = 1200`, checked every `POLL_MS = 120`) | Never flips → check `require("core.ai-activity")._timer` non-nil (GC pin) AND `._ticking` — the timer is busy-gated and idle-by-design when nothing is busy; it must be active while output streams |
| 7 | Toast dedup | Two rapid external writes to an open file: `echo a >> f; echo b >> f` from another terminal within 250 ms | ONE toast `🤖 AI · edited <name>` (250 ms dedup window in `notify_ai_edit`) | Double toast → dedup window shrunk or file-name key changed |
| 8 | Disk-wins conflict | Modify a buffer WITHOUT saving; externally overwrite the file; refocus | Buffer silently reloads to disk content; unsaved edits GONE — **by design** (`v:fcs_choice = "reload"`). Not a bug; do not "fix" without change control | Prompt W12 appears → the `FileChangedShell` handler regressed |
| 9 | Spinner with focus INSIDE terminal | Case 5 but stay in terminal-insert mode watching the bar | Spinner animates (the `nvim__redraw{winbar=true,flush=true}` path) [interactive] | Frozen while focused-in-terminal → someone replaced nvim__redraw with `:redrawstatus` (fenced, below) |
| 10 | Headless detector state | `make test-file FILE=tests/core/ai_activity_spec.lua` | Green: streaming terminal flips working→idle | The one edge headless CAN pin — keep this spec green above all |

Record every matrix run (date, Neovim version, pass/fail per row) in your PR
description (`nvsinner-docs-and-style` template).

## Phase 2 — Solution menu for remaining fragility (ranked)

The current detector is an **output heuristic**: any output = busy; 1.2 s
quiet = idle. It cannot distinguish "agent thinking silently" from "done", nor
"agent's own spinner repainting" from real work. Candidates, in order:

**S1 — OSC 133 prompt-marker detection (shell integration).** `TermRequest`
autocmd fires on OSC sequences from the terminal program — **verified available
on this machine's 0.12.3** (`vim.fn.exists('##TermRequest') == 1`). Semantic
"shell is at prompt" beats any quiet-timer. Proof obligations before adoption:
(a) probe which sequences the actual AI CLIs (claude, opencode) emit — they may
emit none without shell-integration config; (b) design fallback to the current
heuristic when no markers arrive; (c) regression spec sending synthetic OSC 133
via `chansend` to a scripted terminal. Accept when: matrix rows 5/6 pass AND a
"claude thinking silently > 1.2 s" session no longer shows a false `idle`.

**S2 — measured idle threshold.** Before ever tuning `IDLE_MS`, record real
output-cadence data: instrument `on_lines` timestamps (plain-table append —
fast-context safe) across a real agent session; the gap histogram tells you
whether 1200 ms sits in a gap-free zone. Obligation: data first, tune second;
predict the false-idle rate before changing the constant. Accept when: false
idle flips measurably drop without busy-lag exceeding ~2 s.

**S3 — process-tree busy detection.** Poll the terminal job's child processes
(`vim.bo[buf].channel` → `jobpid` → `ps -o state= -g <pid>`); "has a running
child" ≈ busy. Obligations: measure poll cost, prove macOS/Linux portability,
define behavior for TUI agents that idle *inside* one long-lived process (this
likely fails for claude — verify before building). Rank below S1/S2 for that
reason.

**S4 — event-driven idle (per-buffer uv timer reset on each on_lines).**
Replaces the 120 ms sweep with a timer restarted from the fast context.
Obligations: prove `uv_timer_start` from a fast event context is safe (probe
it — `uv.*` is generally fast-context legal, but verify restart-under-load), and
show CPU is actually lower than the current single 120 ms sweep before adding
complexity. Candidate only; the current sweep already skips idle redraws.
PARTIALLY LANDED (2026-07-15, perf campaign): the single sweep is now
**busy-gated** — `on_lines` starts `M._timer` from the fast context (the
`uv_timer:start`-in-fast-context obligation is proven by the real-PTY spec in
`tests/core/ai_activity_spec.lua`) and `tick()` stops it when nothing is busy,
so idle costs zero wakeups. The full per-buffer-timer variant remains a
candidate.

All candidates are **open/candidate status** — none is adopted. Promotion
routes through Phase 3.

## Fenced wrong paths (settled — do NOT retry)

Full stories with evidence: `nvsinner-failure-archaeology`.

- **changedtick polling** for terminal activity — rejected; `on_lines` is the
  push signal. (Note: the original "tick freezes" evidence did not reproduce on
  0.12.3 — see `nvsinner-empirical-verification` recipe 3 — but the design
  verdict stands: polling has no delivery contract.)
- **`g:statusline_winid` inside the winbar `%{}` expression** — absent there;
  the buffer number must stay baked into each window's string (`term_bar(win)`).
- **`:redrawstatus` for spinner repaint** — doesn't repaint the winbar when
  focus is inside a terminal; keep `nvim__redraw{winbar=true,flush=true}` with
  its `pcall` fallback (double-underscore = private API; the fallback is the
  safety net).
- **`vim.api` calls inside `on_lines`** — fast event context; E565/E5560
  (reproduced 2026-07-02). Plain Lua state + `uv.now()` only.
- **Hooking only `FileChangedShell`** — the common autoread case fires only
  `FileChangedShellPost` (reproduced 2026-07-02).
- **Unpinned uv timer handles** — GC kills the animation; keep `M._timer`.
- **fg == bg "invisible" bar styling** — `NvTermBarDim` needs a readable fg
  (`#7a7f8d`).
- **Low ids (1–9) for AI panels** — collides with `<leader>t` horizontals;
  AI panels keep `id = 99 + n`.

## Phase 3 — Validation and promotion protocol

Success is **measured, never judged by eye**:

1. New/changed behavior gets a spec (or extends one) in `tests/core/` — the
   pattern is a real terminal + `vim.wait` (`nvsinner-testing-and-qa`).
2. Full `make test` green; `boot-check.sh` clean; keymap-audit still
   `ALL KEYMAPS PRESENT`.
3. The Phase 1 matrix re-run and recorded (interactive rows included, with
   date + Neovim version).
4. Any new empirical finding gets a dated CLAUDE.md note + archaeology entry
   (`nvsinner-empirical-verification` §discipline).
5. Route the change through `nvsinner-change-control` gates including doc sync.
   Constants (`POLL_MS`, `IDLE_MS`, dedup window) also update
   `nvsinner-config-catalog`.

## Provenance and maintenance

Facts verified: 2026-07-02 at commit `a65af7f`, Neovim 0.12.3 — constants read
from the four campaign files; baseline suite run green; `TermRequest`
availability probed; fast-context and FileChangedShellPost findings reproduced
by probe. Rendering expectations marked [interactive] are code-derived and
must be confirmed in a real terminal on first campaign run.

Re-verification one-liners:

- Constants: `grep -n 'POLL_MS\|IDLE_MS' lua/core/ai-activity.lua && grep -n '250' lua/core/autoreload.lua && grep -n 'AI_WIDTH' lua/plugins/terminal/toggleterm.lua`
- Baseline: `make test` + `boot-check.sh`
- TermRequest still present: `nvim --headless -c "lua io.stdout:write(tostring(vim.fn.exists('##TermRequest'))..'\n')" -c qa!`
- Fences intact: `grep -n 'nvim__redraw\|M._timer\|FAST event' lua/core/ai-activity.lua`
