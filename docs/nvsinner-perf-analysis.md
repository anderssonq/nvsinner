# NvSinner performance analysis

Evidence-based investigation of NvSinner's startup and runtime performance —
plugin loads, synchronous/asynchronous work, and UI painting — with a
prioritized, risk-ordered execution plan. Every claim cites a file and line
verified against the tree at the baseline commit below.

## 1. Scope & methodology

- **What was measured:** headless startup time (`nvim --headless
  --startuptime`, median of 10 runs via
  `.claude/skills/nvsinner-diagnostics-toolkit/scripts/startup-time.sh`),
  the per-module breakdown of one representative `--startuptime` log, the
  plugin census (`require("lazy").stats()`), the steady-state timer inventory
  (`uv_timer:is_active()` probes), and autocmd density on hot events
  (`nvim_get_autocmds`).
- **Variance caveat:** headless startup historically ranges ±2×
  (62–113 ms recorded before the `vim.loader` work); the first run after a
  code change is a cold outlier (bytecode cache rebuild). All comparisons use
  the **median of 10**, and a delta is only claimed when it exceeds run
  variance. A real TUI start differs from headless (UI attach, font, terminal
  I/O); one interactive `nvim --startuptime` data point is listed in the
  verification protocol as a user-run check.
- **Change-control gates:** every executed step must keep `make test` (32 spec
  files) green and `boot-check.sh` clean, is one concept per commit, and syncs
  its documentation in the same commit. `lazy-lock.json` is never touched
  (restore-not-sync doctrine).

## 2. Baseline

Captured 2026-07-15 on commit `074e0c1`, NVIM v0.12.3, Darwin arm64.

### 2.1 Startup (median of 10, headless)

| Run | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
|---|---|---|---|---|---|---|---|---|---|---|
| ms | 76.21 | 36.88 | 35.97 | 40.51 | 37.02 | 35.86 | 36.19 | 36.59 | 36.91 | 37.74 |

**Median 36.90 ms** (min 35.86, max 76.21 — run 1 is the cold-cache outlier).
This is already well under the pre-`vim.loader` 62–113 ms range.

### 2.2 Top entries of a representative run (self+sourced ms)

| ms | entry |
|---|---|
| 30.67 | sourcing `init.lua` (10.83 self) |
| 1.78 | `require('core.markdown')` |
| 1.64 | `require('vim.lsp')` (post-boot, lazy-triggered) |
| 1.53 | `require('vim.treesitter')` (pulled by core.markdown, see §3.3) |
| 1.20 | `require('lazy.view.commands')` |
| 1.19 | `require('vim.treesitter.languagetree')` (core.markdown chain) |
| 1.03 | `require('toggleterm')` |
| 1.02 | `require('lazy.manage')` |
| 0.96 | `require('vim.treesitter.query')` (core.markdown chain) |
| 0.82 | `require('core.options')` |

### 2.3 The eager core-require block

The 29 `require("core.*")` calls at `init.lua:24-52` span clock 7.57 ms →
16.0 ms ≈ **8.4 ms wall, ~7.6 ms self**. Two structural observations:

- The seven on-demand-only modal/command modules (`ai-complete` 0.46,
  `prompts` 0.28, `ai-ask` 0.26, `ia` 0.26, `help` 0.25, `menu` 0.23,
  `symbols` 0.22) sum to **≈2.0 ms** — the deferral ceiling.
- `core.markdown` alone accounts for ~1.8 ms plus the `vim.treesitter` /
  `languagetree` / `query` chain (~3.7 ms) pulled in by its crash-insurance
  `vim.treesitter.query.set` (`lua/core/markdown.lua:26-31`). That chain is
  deliberate (see §3.3) and not removable today.

### 2.4 Plugin census

`lazy.stats()`: **6 of 40 plugins loaded at boot**; everything else is
event/cmd/keys/ft-gated (see §3.2).

### 2.5 Steady-state wakeup inventory (zero terminals, idle editor)

| Source | Cadence | Active at boot? |
|---|---|---|
| `core.ai-activity` `M._timer` (`ai-activity.lua:213-214`) | 120 ms, forever | **true** |
| `core.autoreload` `M._timer` (`autoreload.lua:70-80`) | 1000 ms, forever | **true** |
| lualine statusline refresh (`lua/plugins/ui/lualine.lua:77`) | 100 ms (explicit override) | true once VeryLazy loads |

### 2.6 Autocmd density at boot (handlers per event)

CursorMoved 5 · CursorMovedI 5 · TextChanged 5 · TextChangedI 6 ·
WinScrolled 7 · InsertLeave 5 · BufWinEnter 6 · WinEnter 4 · ColorScheme 21.

### 2.7 Gates at baseline

`make test`: 32 spec files, 0 failed, 0 errors. `boot-check.sh`: clean.

### 2.8 Results (per executed step)

The steps were developed and gated one at a time (suite + boot-check green
after each), then squashed into a single commit on this branch.

| Step | Measured effect |
|---|---|
| Baseline (`074e0c1`) | 36.90 ms median · timers true/true · suite green |
| 1 — analysis doc | docs only; suite + boot-check green |
| 2 — remove lualine AI badge | per-100ms-eval pcall+require+`jobwait(0)`/session eliminated; no spec referenced the badge |
| 3 — rtp `disabled_plugins` | startup median 36.90 → 35.78 ms; `:Tutor` gone, netrw `:Explore` verified intact |
| 4 — drop 100ms refresh override | statusline wakeups 10/s → event-driven + 1 s fallback (pinned lualine default) |
| 5 — indent early-exit | column-only moves / duplicate events skip the synchronous scope recompute; new spec case pins the autocmd path |
| 6 — colorizer+todo debounce | edit/scroll bursts (3 modules × per-frame WinScrolled) coalesce to one rescan per 50 ms per module; new spec cases pin the coalescing |
| 7 — markdown debounce + off-guard | same coalescing; while the view is off (default) events cost one boolean — no call, no timer |
| 8 — ai-activity busy-gating | **wakeup inventory true/true → false/true**: the 120 ms timer is inactive at boot and whenever nothing is busy; real-PTY spec pins start-on-output + stop-after-idle |

**Final measurements (2026-07-15, all steps landed):**

- Startup median-of-10: **38.83 ms** (settled runs 35.47–41.43; one 58 ms
  cold outlier). Two consecutive batches medianed 46.6 and 38.8 — the first
  ran right after the 32-file test suite and shows ambient-load noise, which
  is why §1's variance caveat exists. Conclusion: startup is unchanged within
  run variance vs the 36.90 ms baseline (the campaign's wins are runtime
  wakeups, which are deterministic, not statistical).
- Steady-state wakeups with zero terminals: `ai-activity` timer **false**
  (was true), `autoreload` timer true (by design — pending item, §7),
  lualine on its event-driven default (was a 100 ms timer).
- Plugin census: 6/40 at boot (unchanged — no load-order changes).
- Autocmd counts per hot event are unchanged (the handlers remain
  registered); their per-event cost changed: CursorMoved's indent handler
  early-exits, and 4 of the 7 WinScrolled handlers are now debounced or
  boolean-gated.
- Gates: `make test` 32 files / 0 failed / 0 errors; `boot-check.sh` clean;
  `lazy-lock.json` untouched (`git log --stat` confirms no commit touches it).

## 3. Startup analysis

### 3.1 Already done — do not redo

Commit `074e0c1` landed the standard startup work: `vim.loader.enable()` as
the first statement (`init.lua:3`, covers every require below it), the four
remote-provider disables (`lua/core/options.lua:33-36`), and
`checker = { enabled = false }` (`init.lua:72`, no boot-time network check).

### 3.2 Plugin loading

Every active plugin spec has an explicit lazy trigger except two deliberate
cases: `lua/plugins/ui/theme.lua` (`lazy = false, priority = 1000` — colors
must exist before the UI draws) and `lua/plugins/terminal/toggleterm.lua`
(`lazy = false`, documented exception at `toggleterm.lua:4-9`; its keymaps are
closures over memoised panels). Eleven former plugins are `enabled = false`
stubs replaced by native `lua/core/` modules (zero load cost). At baseline the
boot loads 6/40 plugins; toggleterm's `require` costs ~1.0 ms (§2.2), which
does not justify the medium-risk `keys`-spec restructuring its own comment
defers ("if this ever shows up in startup profiles" — it barely does).

**Gap:** `lazy.setup` (`init.lua:54-73`) has **no
`performance.rtp.disabled_plugins`** block — the stock runtime plugins (gzip,
tarPlugin, zipPlugin, tohtml, tutor, rplugin, netrw, …) all source at boot.
This is the one standard lazy.nvim startup optimization not applied. Caveat:
`netrwPlugin` must stay — neo-tree is `cmd`/`keys`-lazy with no
`hijack_netrw` config, so netrw still owns `nvim <dir>`; disabling it is a
behavior change (documented as pending, §7). `gx` is safe either way
(`vim.ui.open` since 0.10). → **Executed as Step 3.**

### 3.3 Synchronous work at require time

- `core.settings` reads the settings JSON synchronously at boot
  (`settings.lua:58,71`) — required before the theme seeds; small file, on
  the critical path by design. **Keep.**
- `core.markdown` runs `vim.treesitter.query.set("markdown", "injections", …)`
  at require (`markdown.lua:26-31`), pulling the whole `vim.treesitter` Lua
  stack (~3.7 ms, §2.2). This is deliberate 0.12.x crash insurance (the
  markdown TS highlighter's nil-node crash on transient floats) and must be
  applied before any LanguageTree caches its injection query. **Keep;
  deletable only when upstream fixes the crash** (the module's own comment
  says so).
- `core.ai-activity` attaches to all buffers and **starts its 120 ms timer at
  require** (`ai-activity.lua:211-214`) — a runtime cost, analyzed in §4.
- `core.autoreload` starts its 1 s `checktime` timer at require
  (`autoreload.lua:70-80`) — analyzed in §4.
- The seven on-demand modal modules cost ≈2.0 ms total at boot (§2.3), far
  below the ~10-15 ms threshold that would justify restructuring `init.lua`
  into deferred command stubs. → **Documented as pending, not executed** (§7).

## 4. Runtime analysis (ranked)

1. **ai-activity 120 ms forever-timer** — `ai-activity.lua:213-214`; `tick()`
   (`:125-154`) runs every 120 ms for the whole session, with zero terminals
   and nothing busy: `vim.fn.mode()`, frame advance, state iteration. While
   busy it issues a full `nvim__redraw{statusline, winbar, flush}` per tick
   (`:149-153`). The winbar spinner it paints is **shared** by the vertical AI
   columns and the horizontal terminals (`:18-19`, attach on TermOpen
   `:193-198`). → **Executed as Step 8: gate the timer to run only while
   something is busy** (decision record in §5).
2. **lualine 100 ms statusline refresh + AI badge** — `lualine.lua:77` sets
   `refresh = { statusline = 100 }` purely to keep the `ai_badge` counts live
   (comment `:16-18`); each eval (`:19-43`) pcall-requires `core.ai-sessions`
   + `core.ai-activity` and runs `jobwait(…, 0)` per registered session
   (`ai-sessions.lua:71`). The installed lualine (`221ce6b`) defaults to
   event-driven refresh (WinEnter/BufEnter/CursorMoved/ModeChanged/…,
   16 ms coalescing) + a 1000 ms fallback — so with the badge gone the
   override is pure waste. → **Executed as Steps 2 and 4** (§5).
3. **indent.lua un-debounced synchronous scope recompute** — the autocmd at
   `indent.lua:129-137` calls `M.refresh` directly on every CursorMoved,
   CursorMovedI, TextChanged, TextChangedI, BufEnter, and WinScrolled;
   `refresh` (`:60-103`) runs `vim.fn.indent` + a visible-range membership
   walk on the main loop. Contrast the debounce discipline of `git-blame.lua`
   (350 ms) and `illuminate.lua` (120 ms), which only clear + arm on move. A
   trailing debounce would visibly lag the guide on `j`/`k`, so the fix is a
   same-position early-exit (identical win/line/viewport/changedtick → skip).
   → **Executed as Step 5.**
4. **autoreload 1 s `checktime` forever** — `autoreload.lua:70-80` re-stats
   every loaded buffer each second, plus the same on 6 focus events. This is
   the disk-wins AI workflow's backbone (the CLI edits files while focus never
   leaves Neovim), and gating it to "a terminal exists" would silently change
   the "another app edits the file while focus stays in nvim" case. →
   **Documented only, pending explicit approval** (§7).
5. **Visible-range rescan trio, un-debounced** — `colorizer.lua:82-91`,
   `todo.lua:79-88`, `markdown.lua:234-243` each wipe their whole namespace
   (`nvim_buf_clear_namespace(buf, ns, 0, -1)`; e.g. `colorizer.lua:64`) and
   re-scan the visible range on every BufWinEnter, TextChanged, TextChangedI,
   InsertLeave, and WinScrolled — three full rescans per scroll tick, and
   neoscroll emits WinScrolled per animation frame. The markdown callback also
   fires while the reading view is **off** (the default; `refresh` no-ops
   internally but the autocmd fires). → **Executed as Steps 6-7: 50 ms
   per-buffer debounce on the edit/scroll events, first-paint events stay
   immediate; markdown gains an `M.on` guard first in the callback.**
6. **mini.animate cursor trail** (`mini-animate.lua:16-19`, redraws per cursor
   move) and **satellite `current_only = false`** (`scrollbar.lua:12`,
   repaints the bar in all windows on scroll/diagnostic/git events) —
   user-visible UX features. → **Documented as optional user toggles only**
   (§7); changing defaults is scope creep.
7. **ui-touch `<MouseMove>` handler** — `ui-touch.lua:279-282` runs the
   neo-tree hover wash synchronously per mouse-move event before the 200 ms
   LSP-hover debounce; the common case is a cached-position early-return
   (`neotree-hover.lua:63`). Cheap; **documented only**.
8. **ColorScheme fan-out** — 21 handlers (§2.6) including two full plugin
   `setup()` re-runs (`lualine.lua:90`, `barbacue.lua:78`). Only fires on a
   live theme switch from `:NvSinnerMenu`; rare by construction.
   **Documented only.**

## 5. The "horizontal UI" requirement — decision record

The feature spec asked to analyze and, if safe, remove "el UI horizontal de
nvsinner (el proceso que pinta el working y la cola de demanda de recursos)"
while preserving "el UI vertical del chat con la IA" intact.

**Finding:** no single component matches that description. There is no
literal "resource-demand queue" anywhere in the code (the only queue mentions
are prose comments, e.g. `ai-sessions.lua:18` "no queued auto-flush"), and
the "working…" painter (`ai-activity.lua`, `LABEL_BUSY` at `:29`) is shared
infrastructure explicitly serving both the vertical AI columns and the
horizontal `<leader>t` terminals (`:18-19`). The candidates were:

| Candidate | Paints "working"? | Queue-like? | Horizontal-exclusive? |
|---|---|---|---|
| lualine AI cockpit badge (`lualine.lua:19-43,83`) | yes ("N working") | yes (session-demand summary) | it *is* the horizontal statusline |
| ai-activity winbar spinner (`ai-activity.lua`) | yes (the chip) | its 120 ms poll/redraw loop | **no — shared with the vertical column** |
| `<leader>t` horizontal terminals (`toggleterm.lua:88-117`) | no | no | yes |

**User decision (recorded 2026-07-15):** the "horizontal UI" refers to the
**lualine AI cockpit badge** and the **ai-activity working painter**, resolved
as:

- **Badge: removed** (Step 2). It was the horizontal element that literally
  painted "N working" plus the queue-of-sessions-demanding-resources summary.
  Its removal does not touch the vertical column: `M.status()` /
  `M.sessions()` stay as the public cockpit API used by the `<leader>ja`
  picker and the tests.
- **Spinner: optimized, NOT removed** (Step 8). Full removal was **rejected**
  because `ai-activity.lua` also renders the vertical AI column's winbar
  status via ui-touch's `term_bar` (`ui-touch.lua:89-91`), and the spec's
  hard requirement preserves the vertical chat UI intact. The optimization
  gates the 120 ms timer to run only while a terminal is actually busy —
  user-visible behavior with terminals in use is identical; at idle (and with
  zero terminals) the process that "paints the working" stops waking up
  entirely.
- The `<leader>t` horizontal terminals themselves are **untouched** — the
  user did not select them.

## 6. Prioritized execution plan (lowest → highest risk)

One concept per commit; each step's gate must pass before the commit lands.

| # | Step | Risk | Files | Gate |
|---|---|---|---|---|
| 1 | This analysis document | none | `docs/nvsinner-perf-analysis.md` | suite + boot-check green |
| 2 | Remove the lualine AI cockpit badge | low | `lualine.lua`, README, ui+core CLAUDE.md | suite green; no `ai_badge` reference left |
| 3 | `performance.rtp.disabled_plugins` (keep netrw) | low | `init.lua` | suite + boot-check; startup median re-run |
| 4 | Drop the 100 ms statusline refresh override | low | `lualine.lua` | suite green; mode chip stays live (event-driven default) |
| 5 | Indent-scope same-position early-exit | low-med | `indent.lua`, spec, core CLAUDE.md | targeted + full suite |
| 6 | Debounce colorizer + todo rescans (50 ms) | low-med | `colorizer.lua`, `todo.lua`, specs, docs | targeted + full suite |
| 7 | Debounce markdown rescan + off-guard | low-med | `markdown.lua`, spec, docs | targeted + full suite |
| 8 | Gate the ai-activity timer (busy-gated) | med | `ai-activity.lua`, spec, docs, skills | targeted + full suite; boot probe shows timer inactive |
| 9 | Record final results | none | this document | final probes re-run |

Step 8 design (the riskiest change): keep the `M._timer` handle created at
require (`ai-activity.lua:213` — GC anchor, pinned by the spec); remove the
unconditional `:start`; start via `ensure_ticking()` from the `on_lines`
fast-event callback (luv timer ops are fast-context legal; the restriction is
`vim.api`/`vim.fn`); stop at the end of `tick()` when nothing is busy — the
idle-flip tick performs its final redraw first, then stops. `awaiting` needs
no ticks (`_on_osc` self-redraws, `:187`). Fallback if the fast-context start
misbehaves in the real-PTY spec: start in `attach()` (normal autocmd context)
and stop when the state table empties.

## 7. Documented-only / pending items (NOT executed)

| Item | Status | Why |
|---|---|---|
| Disable `netrwPlugin` | pending approval | Would change `nvim <dir>` behavior; needs a neo-tree `hijack_netrw` decision first. |
| Gate the autoreload 1 s `checktime` timer | pending approval | Disk-wins semantics are a non-negotiable; gating to "terminal exists" changes external-edit detection when no terminal is open. Trade-off must be accepted explicitly. |
| Defer the 7 on-demand core modules | rejected by measurement | ≈2.0 ms total at boot (§2.3) — under any reasonable threshold; `init.lua` churn is not worth it while `vim.loader` is active. |
| toggleterm `keys`-spec restructuring | rejected by measurement | ~1.0 ms require cost (§2.2); its own comment defers this until it shows in profiles. |
| mini.animate cursor trail / satellite `current_only` | optional user toggles | User-visible UX; flip `enabled = false` / `current_only = true` per taste. |
| Auxiliary agent / spec markdown | pending approval | Spec requirement 7: no auxiliary agents or spec documents are created without explicit approval. None was needed for this work. |

## 8. Verification protocol

- **Per commit (headless):** `make test` plus the step's targeted
  `make test-file`; `boot-check.sh` clean; startup median-of-10 re-run for
  startup-affecting steps; the timer/wakeup probes for runtime steps. `git
  status` must never show `lazy-lock.json` modified.
- **Test/build/lint commands discovered** (spec verification item 3): this
  repo has no `package.json`/CI; the harness is `make test` /
  `make test-file FILE=…` (plenary busted, `tests/minimal_init.lua`), plus the
  diagnostics scripts under
  `.claude/skills/nvsinner-diagnostics-toolkit/scripts/` and
  `stylua` (via none-ls) for Lua formatting.
- **Final (headless):** full suite + boot-check + startup / lazy census /
  wakeup / autocmd probes re-run and recorded in §2.8.
- **Interactive smoke checklist (user-run):**
  1. `<leader>j` AI column: spinner animates while the CLI works, flips to
     `● idle` ~1.2 s after quiet, `◆ needs input` still appears for OSC
     emitters.
  2. `<leader>t` terminal: a long command animates the spinner, flips idle.
  3. Hide/reopen the column mid-work (`<M-J>`): state survives; multiple
     sessions animate independently.
  4. Statusline: no `AI:` badge; mode chip recolors instantly on mode change.
  5. Markdown reading view repaints within ~50 ms of a scroll stopping.
  6. `#hex` and `TODO:` chips paint on open and follow scroll + edits.
  7. Indent guide follows `j`/`k` with no lag.
  8. AI CLI edits an open file → buffer reloads + `🤖 AI · edited` toast.
  9. `nvim .` still opens netrw.
  10. `:messages` clean after an interactive boot; optionally one TUI
      `nvim --startuptime /tmp/nvsinner-tui.log +q` reference number.
