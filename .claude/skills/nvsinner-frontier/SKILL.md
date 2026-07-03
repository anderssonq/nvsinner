---
name: nvsinner-frontier
description: >
  NvSinner's external positioning and research frontier: what is genuinely
  novel here vs standard practice, the discipline for public claims (what must
  be measured before it may be stated), and the open problems where this
  project can advance the state of the art with concrete first steps and
  falsifiable milestones. Load when planning new features or direction, writing
  public-facing text (README pitch, release notes, comparisons to
  NvChad/LazyVim/AstroNvim/Cursor), or picking the next high-leverage project.
  Do NOT load it to execute terminal-UX work (nvsinner-terminal-ux-campaign),
  for current values (nvsinner-config-catalog), or for the docs mechanics
  (nvsinner-docs-and-style).
---

# NvSinner frontier — positioning and open problems

The owner's definition of "beyond state of the art" for this project, all
three at once: (a) the deepest AI-agent/terminal integration of any Neovim
distro — beat Cursor at its own game inside a terminal; (b) native-first —
prove how much IDE polish zero-dependency core modules can deliver instead of
plugins; (c) distro-engineering rigor NvChad/LazyVim don't hold themselves to.

## When NOT to use this skill

- Executing the hardening work → `nvsinner-terminal-ux-campaign`.
- Whether a change is allowed → `nvsinner-change-control`.
- What the system IS today → `nvsinner-architecture-contract`.

## 1. Positioning (honesty first)

Repo-side facts below are verified; **every comparative cell about other
distros is "believed, unverified (as of 2026-07-02)"** — verify against their
current repos before publishing any comparison.

| Axis | NvSinner (verified in-repo) | Other distros (believed, unverified) |
|---|---|---|
| AI integration | CLI-agent-in-terminal with native busy/idle winbar spinner, per-session labels, disk-wins autoreload + edit toast | Most ship an in-editor AI plugin or nothing; no known distro ships terminal-agent activity awareness |
| Native vs plugins | 7 zero-dep core modules (`lua/core/`, `lua/nvsinner/health.lua`) carry focus UX, activity, autoreload, updater, health | Chrome is typically all plugins |
| Test suite | plenary busted suite over core behavior incl. a real streaming-terminal spec (`make test`, green 2026-07-02) | Distro configs rarely have behavioral test suites |
| Update reproducibility | committed `lazy-lock.json` + `restore`-not-`sync` on install AND update | Lockfile committed varies; update flows often float to latest |
| Install isolation | `NVIM_APPNAME=nvsinner`, four XDG dirs, symlink-safe uninstaller | NvChad/LazyVim conventionally install INTO `~/.config/nvim` |
| Health | `:checkhealth nvsinner` + one-time first-run toast | checkhealth providers exist in some (e.g. LazyVim); first-run toast less common |

## 2. Genuinely novel vs standard (label correctly in public text)

**Plausibly novel** (no known equivalent; verify before claiming "first"):
the native terminal-agent activity detector (`lua/core/ai-activity.lua`:
`nvim_buf_attach` → fast-context state → uv timer → `nvim__redraw` winbar
chip) and its pairing with per-session labels + the disk-wins/toast loop —
i.e. the editor is a *viewer cockpit* for CLI agents.

**Standard practice** (never claim as novel): lazy.nvim category structure,
Mason `ensure_installed`, glassmorphism/monochrome theming, toggleterm
side columns, alpha dashboards, plenary tests *as a technique*.

**Differentiating discipline** (novel-ish as a standard, not a mechanism):
empirical-verification culture with regression specs for editor arcana
(`nvsinner-empirical-verification`), and restore-not-sync update
reproducibility as a hard rule.

## 3. Claim discipline

No public claim without a dated re-measurement. Current README claims and
their re-verification:

| Claim (README.md) | Status | Re-measure before repeating |
|---|---|---|
| "cold start ≈ 60 ms" | ⚠️ 2026-07-02 headless measurements ranged 62–113 ms (±2× run variance) | median of 3 × `.claude/skills/nvsinner-diagnostics-toolkit/scripts/startup-time.sh`; note that a real TUI start differs from headless |
| "only ~12 of 42 plugins load at startup" | unverified count | `nvim` → `:Lazy` shows loaded/total; or count `lazy = false` + no-trigger specs in `nvsinner-config-catalog` §4 (none-ls, leap, toggleterm, theme, dashboard are the startup set + deps) |
| "coexists with any ~/.config/nvim" | verified by design (`NVIM_APPNAME`) | `nvsinner-build-and-run` §3 |

Rule: comparative statements ("only distro that…", "unlike NvChad…") require a
dated check of the competitor's current repo, recorded in the PR that adds the
claim.

## 4. Open frontier problems

Each: why SOTA fails → NvSinner's asset → first three steps IN THIS REPO →
falsifiable milestone. All are **open**; none is promised.

### F1 — Semantic agent-state awareness (beyond output heuristics)
- **Gap:** every known busy indicator (including ours) infers from output;
  none knows "agent is waiting for MY input" vs "thinking" vs "done".
- **Asset:** `ai-activity.lua` already owns the attach/render pipeline;
  `TermRequest` is available (verified 0.12.3); tests can drive scripted PTYs.
- **First steps:** (1) probe what OSC sequences claude/opencode emit
  (campaign S1 obligation); (2) prototype a `TermRequest` listener recording
  sequences per session; (3) add a third winbar state (`awaiting input`) behind
  the existing render path.
- **Result when:** a scripted session shows the bar distinguishing
  working/awaiting-input/idle with zero false "idle" during a >1.2 s silent
  think, pinned by a spec.

### F2 — Edit attribution and agent-diff UX
- **Gap:** today the toast names the file (`autoreload.lua`); nobody shows
  *which agent session* changed *what*, reviewable without leaving the editor.
- **Asset:** per-session labels (`b:nv_term_label`), gitsigns + diffview
  already integrated.
- **First steps:** (1) correlate toast events with the busy session(s) at
  write time (state already in `ai-activity.lua`); (2) extend the toast with
  the session label; (3) add a "diff last AI edit" keymap driving diffview
  against the pre-reload buffer content.
- **Result when:** an AI edit produces a toast naming session + file, and one
  keymap opens the exact hunk diff; spec pins the correlation logic.

### F3 — Multi-agent orchestration cockpit
- **Gap:** 9 AI columns exist but there is no aggregate view; SOTA (Cursor
  et al.) is single-agent-centric.
- **Asset:** per-buffer busy state for ALL sessions already lives in one
  `state` table.
- **First steps:** (1) expose an `M.sessions()` summary from `ai-activity.lua`;
  (2) render an aggregate widget (lualine component or incline badge — palette
  rules apply); (3) a which-key-visible picker jumping to the busiest session.
- **Result when:** with 3 sessions running, one glance shows each session's
  state without visiting it; spec pins `M.sessions()`.

### F4 — Native-first expansion
- **Gap:** distro chrome is plugin-heavy everywhere; unclear how far native
  modules can go.
- **Asset:** ui-touch/ai-activity prove the pattern (zero-dep, ColorScheme
  re-apply, spec-covered).
- **Honest candidates** (survey of `lua/plugins/`): indent guides
  (identmini is tiny; native `listchars`/extmarks could replace),
  cursor-word illumination (illuminate → `vim.lsp.buf.document_highlight` +
  treesitter fallback), the scrollbar (satellite → decoration provider) —
  each only if the native version stays smaller than the plugin it replaces.
  NOT candidates: telescope, treesitter, cmp, gitsigns (too deep).
- **Result when:** one plugin is replaced by a ≤150-line core module with
  specs and no palette/startup regression, and the plugin spec is kept as
  `enabled = false` for revert.

### F5 — Distro-engineering rigor (CI, releases, script tests)
- **Gap:** TODO.md items — no CI, no versioned releases; install.sh/
  uninstall.sh untested (`nvsinner-testing-and-qa` known gaps).
- **Asset:** the suite is already headless-runnable (`make test`);
  scripts are POSIX bash.
- **First steps:** (1) GitHub Actions workflow: matrix {macOS, ubuntu} ×
  {0.11.x, 0.12.x, nightly} running `make test` + `boot-check.sh`; (2) bats or
  bash-based tests for install.sh/uninstall.sh against a sandboxed
  `$HOME`/`$XDG_*`; (3) tag `v0.1.0` + release notes template
  (`nvsinner-docs-and-style`).
- **Result when:** a green CI badge on a tagged release, with the 0.12.x
  markdown workaround exercised by the matrix (it should FAIL loudly when
  upstream fixes land and the workaround can be retired).

## 5. Proof-before-claim table

| Ambition | May be claimed publicly when |
|---|---|
| "Deepest AI-terminal integration" | F1 or F2 shipped + a dated feature-matrix check against ≥3 named distros |
| "Beat Cursor in-terminal" | A written task-level comparison (agent visibility, edit review, multi-session) with dates and versions |
| "Native-first" | F4's first replacement shipped; count of native modules vs chrome plugins published with the counting rule |
| "Distro rigor" | F5's CI badge is green on a tagged release |
| "≈60 ms startup" | Median-of-3 re-measure documented in the same commit that states it |

## Provenance and maintenance

Facts verified: 2026-07-02 at commit `a65af7f` — repo-side rows of §1, the
startup measurements (62–113 ms headless), `TermRequest` availability, suite
green, TODO.md open items. All statements about other distros/Cursor are
**believed, unverified (as of 2026-07-02)** — no web verification was
performed; verify before publishing.

Re-verification one-liners:

- TODO still open: `cat TODO.md`
- Startup claim: median of 3 × `scripts/startup-time.sh` (diagnostics-toolkit)
- Suite: `make test`
- Competitor claims: check the NvChad / LazyVim / AstroNvim repos' READMEs and
  date-stamp what you find.
