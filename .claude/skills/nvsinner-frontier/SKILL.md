---
name: nvsinner-frontier
description: >
  NvSinner's external positioning and research frontier: what is genuinely
  novel here versus standard practice, the discipline for public claims (what
  must be measured before it may be stated), and the open problems where this
  project can advance the state of the art — each with concrete first steps and
  a falsifiable milestone. Also holds the ranked solution menu for the hardest
  live problem, agent busy/idle detection. Load when planning new features or
  direction, when choosing the next improvement to the terminal/agent UX, or
  when writing public-facing text (README pitch, release notes, comparisons to
  NvChad/LazyVim/AstroNvim/Cursor). Do NOT load it for current values or the
  rules of changing them (nvsinner-contract), for docs mechanics
  (nvsinner-docs-and-style), or to debug a live failure
  (nvsinner-debugging-playbook).
---

# NvSinner frontier — positioning and open problems

The owner's definition of "beyond state of the art", all three at once:
(a) the deepest AI-agent/terminal integration of any Neovim distro; (b)
native-first — prove how much IDE polish zero-dependency core modules can
deliver instead of plugins; (c) distro-engineering rigor NvChad/LazyVim don't
hold themselves to.

## When NOT to use this skill

- Whether a change is allowed, or what the system IS today → `nvsinner-contract`.
- A live symptom → `nvsinner-debugging-playbook`.
- Was it already tried? → `nvsinner-failure-archaeology`.
- Designing a probe for unsettled behavior → `nvsinner-empirical-verification`.

## 1. Positioning (honesty first)

Repo-side facts are verified. **Every comparative cell about other distros is
"believed, unverified"** — check their current repos before publishing.

| Axis | NvSinner (verified in-repo) | Other distros (believed, unverified) |
|---|---|---|
| AI integration | CLI-agent-in-terminal with a native busy/idle/awaiting winbar spinner, per-session labels, an agent cockpit, disk-wins autoreload + edit toast | Most ship an in-editor AI plugin or nothing; no known distro ships terminal-agent activity awareness |
| Native vs plugins | 39 zero-dep core modules carry focus UX, activity, autoreload, the modals, updater and health — and have replaced 9 plugins outright | Chrome is typically all plugins |
| Test suite | plenary busted suite over core behavior including a real streaming-terminal spec | Distro configs rarely have behavioral test suites |
| Update reproducibility | committed `lazy-lock.json` + `restore`-not-`sync` on install AND update; tombstones keep their lockfile entry | Lockfile committed varies; update flows often float to latest |
| Install isolation | `NVIM_APPNAME=nvsinner`, four XDG dirs, symlink-safe uninstaller | NvChad/LazyVim conventionally install INTO `~/.config/nvim` |

## 2. Genuinely novel vs standard (label correctly in public text)

**Plausibly novel** (no known equivalent; verify before claiming "first"):
the native terminal-agent activity detector (`nvim_buf_attach` → fast-context
state → uv timer → `nvim__redraw` winbar chip), its OSC-133 "awaiting input"
refinement, and the pairing with per-session labels, the cockpit and the
disk-wins/toast loop — i.e. the editor as a *viewer cockpit* for CLI agents.

**Standard practice** (never claim as novel): lazy.nvim category structure,
Mason `ensure_installed`, monochrome theming, toggleterm side columns, alpha
dashboards, plenary tests *as a technique*.

**Differentiating discipline**: the empirical-verification culture with
regression specs for editor arcana, and restore-not-sync as a hard rule.

## 3. Claim discipline

No public claim without a dated re-measurement.

| Claim | Re-measure before repeating |
|---|---|
| README's cold-start number | median of 3 × `.claude/skills/nvsinner-testing-and-qa/scripts/startup-time.sh`; a real TUI start differs from headless, and the README number must be re-stated in the same commit that changes it |
| "N of M plugins load at startup" | `:Lazy` shows loaded/total; the eager set is whatever carries an explicit `lazy = false` |
| "coexists with any ~/.config/nvim" | verified by design (`NVIM_APPNAME`) — see `nvsinner-build-and-run` |

Comparative statements ("only distro that…", "unlike NvChad…") require a dated
check of the competitor's current repo, recorded in the PR that adds the claim.

## 4. Open frontier problems

Each: why SOTA fails → NvSinner's asset → first steps in this repo →
falsifiable milestone. All are **open**; none is promised.

### F1 — Semantic agent-state awareness (beyond output heuristics)
- **Gap:** most busy indicators infer from output alone and cannot tell
  "waiting for MY input" from "thinking" from "done".
- **Partially shipped.** `ai-activity.lua` has a third state (`awaiting`) and
  `M._on_osc` handles OSC 133 B/C plus OSC 9 / OSC 777 notifications. Its
  documented honest limit: it only lights up for emitters, and a CLI that emits
  nothing falls back to the quiet-timer heuristic, which stays the primary
  signal.
- **What remains:** probe what the actual AI CLIs emit (unverified for claude),
  and drive the false-idle rate down for silent thinking.
- **Result when:** a scripted session distinguishes working / awaiting-input /
  idle with zero false "idle" during a long silent think, pinned by a spec.

### F2 — Edit attribution and agent-diff UX
- **Gap:** the toast names the file; nobody shows *which agent session* changed
  *what*, reviewable without leaving the editor.
- **Asset:** per-session labels, the cockpit, gitsigns + diffview integrated.
- **First steps:** correlate toast events with the busy session at write time
  (the state is already in `ai-activity.lua`); extend the toast with the
  session label; add a "diff last AI edit" keymap driving diffview against the
  pre-reload buffer content.
- **Result when:** an AI edit produces a toast naming session + file, and one
  keymap opens the exact hunk diff; a spec pins the correlation.

### F3 — Native-first expansion
- **Gap:** distro chrome is plugin-heavy everywhere; unclear how far native
  modules can go.
- **Shipped 9 times already** — filebadge, illuminate, colorizer, indent, todo,
  window-picker, markdown, git-blame and sessions each replaced a plugin, and
  each plugin spec survives as a tombstone. The milestone this section
  originally set has been met nine times over.
- **Remaining honest candidate:** the scrollbar (satellite → decoration
  provider). **Not candidates:** telescope, treesitter, cmp, gitsigns.
- **Result when:** the replacement stays smaller than the plugin it replaces,
  with specs and no palette or startup regression.

### F4 — Distro-engineering rigor (CI depth, script tests)
- **Shipped:** CI (`.github/workflows/ci.yml` — boot check + `make test` on
  every PR and push to `main`) and versioned releases with a remote update
  check.
- **Gaps that remain:** CI is `ubuntu-latest` × `{v0.12.0, stable}` — one
  platform, no macOS (the dev platform, and where `image-open.lua`'s
  `qlmanage`/`sips` path lives), no nightly (precisely where the crash class
  lives). `stylua --check` is not a CI step, only a local opt-in hook. CI
  symlinks the checkout to `~/.config/nvim`, so the `NVIM_APPNAME` path is
  never exercised. `install.sh` / `uninstall.sh` have zero automated coverage.
- **First steps:** widen the matrix to {macOS, ubuntu} × {v0.12.0, stable,
  nightly}; add a `stylua --check` step; bats-style tests for the install
  scripts against a sandboxed `$HOME`/`$XDG_*`.
- **Result when:** the widened matrix and a formatting step are green on a
  tagged release, with the badge in the README.

## 5. The busy/idle solution menu (ranked, for F1)

The detector is an output heuristic: any output = busy, `IDLE_MS` of quiet =
idle. It cannot distinguish "thinking silently" from "done", nor the agent's
own spinner repaints from real work.

**S1 — OSC prompt-marker detection. LANDED** (`M._on_osc`). Semantic "shell is
at prompt" beats any quiet-timer where it is available. The fallback design
obligation was met: no markers → the heuristic still runs.

**S2 — measured idle threshold.** Before ever tuning `IDLE_MS`, record real
output-cadence data: instrument `on_lines` timestamps (plain-table append —
fast-context safe) across a real agent session; the gap histogram tells you
whether the current value sits in a gap-free zone. **Obligation: data first,
tune second** — predict the false-idle rate before changing the constant.
Accept when false idle flips measurably drop without busy-lag exceeding ~2 s.

**S3 — process-tree busy detection.** Poll the terminal job's child processes
(`vim.bo[buf].channel` → `jobpid` → `ps`). Obligations: measure poll cost,
prove macOS/Linux portability, and define behavior for TUI agents that idle
*inside* one long-lived process — which likely breaks this for claude. Verify
that before building; it is ranked last for that reason.

**S4 — event-driven idle (per-buffer timer reset from `on_lines`).**
**PARTIALLY LANDED** (2026-07-15): the single sweep is now busy-gated —
`on_lines` starts `M._timer` from the fast context (that obligation is proven
by the real-PTY spec) and `tick()` stops it when nothing is busy, so idle costs
zero wakeups. The full per-buffer-timer variant remains a candidate, and must
show lower CPU than the current sweep before adding complexity.

**Promotion protocol:** new behavior gets a spec; `make test` green;
`boot-check.sh` clean; the interactive QA matrix in `nvsinner-testing-and-qa`
re-run and recorded with date + Neovim version; any new empirical finding gets
a dated note plus an archaeology entry.

## 6. Proof-before-claim table

| Ambition | May be claimed publicly when |
|---|---|
| "Deepest AI-terminal integration" | F1 or F2 shipped + a dated feature-matrix check against ≥3 named distros |
| "Beat Cursor in-terminal" | A written task-level comparison (agent visibility, edit review, multi-session) with dates and versions |
| "Native-first" | The count of native modules vs chrome plugins published with the counting rule (9 replacements already justify the claim; publish the rule, not just the number) |
| "Distro rigor" | F4's widened matrix is green on a tagged release, with the badge in the README. CI exists but is one OS × two Neovims and skips formatting — that is not yet "rigor" in public |
| Any startup number | Median-of-3 re-measure documented in the same commit that states it |

## Provenance and maintenance

**Facts verified: 2026-09-19** — repo-side rows of §1, the shipped status of
S1/S4 and F3's nine replacements, and the CI matrix, all by direct file read.
All statements about other distros and Cursor remain **believed, unverified** —
no web verification was performed; verify before publishing.

This skill absorbed `nvsinner-terminal-ux-campaign`'s solution menu (§5). That
skill's interactive reproduction matrix moved to `nvsinner-testing-and-qa`; its
"fenced wrong paths" were already a third copy of FA-01…FA-08 and now live only
in `nvsinner-failure-archaeology`.

Re-verification:
```bash
cat TODO.md
grep -n '_on_osc\|LABEL_AWAIT\|_ticking' lua/core/ai-activity.lua   # F1/S1/S4 status
grep -lE '^\s{0,2}enabled = false' lua/plugins/*/*.lua              # F3 replacements
sed -n '1,40p' .github/workflows/ci.yml                             # F4 matrix
make test
```
