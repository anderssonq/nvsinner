---
name: nvsinner-failure-archaeology
description: >-
  The chronicle of every major NvSinner investigation, dead end, rejected
  approach, revert, and by-design trade-off — with evidence (commit SHAs,
  archived PR descriptions, code comments) and explicit "do not retry" notes.
  Load this BEFORE re-attempting any approach in this repo, whenever a fix idea
  feels obvious (obvious ideas here — changedtick polling, :redrawstatus,
  g:statusline_winid, re-enabling noice LSP hover, re-adding an in-editor AI
  plugin, "just use :Lazy sync" — were already tried and rejected), whenever
  you are investigating why something is configured strangely (a disabled
  plugin, a reserved terminal id 100+, a duplicated markdown disable, a
  fg-color on a "background" bar), and before deleting any workaround or
  "dead" code. Also load it when writing a post-mortem or when a test failure
  matches a symptom you can't explain.
---

# NvSinner Failure Archaeology

This is the project's institutional memory: every battle already fought, so
nobody fights it twice. Each entry follows **Symptom → Root cause → Evidence →
Resolution → Status**, plus what NOT to retry.

Two git histories exist (see FA-15): `main` starts fresh at `1ba89eb`
(2026-06-30); everything older lives on branch **`feat/nvsinner-distro`**.
Pre-split SHAs cited below (e.g. `220a897`, `26947f9`, `8f90d92`) resolve only
if that branch is fetched. Archived PR descriptions in `.tmp/*.md` are the
richest narrative source and are cited by filename.

**Status legend:**

| Status | Meaning |
|---|---|
| settled | Root-caused and fixed; the fix is the permanent design |
| workaround-pending-upstream | Deliberate patch around an external bug; remove only when upstream fixes it |
| by-design trade-off | A known cost accepted on purpose; do not "fix" it |
| disabled-not-deleted | Kept in-tree as a one-line revert |

## When NOT to use this skill

- **Making a change now and need the rules/checklist** → `nvsinner-change-control`.
- **Debugging a live failure step-by-step** → `nvsinner-debugging-playbook` (this skill tells you which paths are dead; that one tells you how to walk the live ones).
- **Why the architecture is shaped this way (positive design rationale)** → `nvsinner-architecture-contract`. This skill covers what was *rejected*; that one covers what was *chosen*.
- **Underlying Neovim theory** (fast event contexts, winbar vs statusline evaluation, terminal buffer internals) → `neovim-internals-reference`. Entries here state the empirical finding; the reference explains the mechanism.
- **Current/ongoing terminal-UX work** → `nvsinner-terminal-ux-campaign`. This skill is the settled past; that one is the active front.
- **How to reproduce a finding empirically** → `nvsinner-empirical-verification`.
- **What a plugin/option is set to today** → `nvsinner-config-catalog`.

## Index

| # | Entry | Area | Status |
|---|---|---|---|
| FA-01 | changedtick polling can't detect terminal output | ai-activity | settled |
| FA-02 | `g:statusline_winid` is empty during winbar evaluation | ai-activity / ui-touch | settled |
| FA-03 | `:redrawstatus` doesn't repaint the winbar from inside a terminal | ai-activity | settled |
| FA-04 | Hooking only `FileChangedShell` missed the common AI-edit case | autoreload | settled |
| FA-05 | Unpinned luv timer gets GC'd, spinner silently freezes | ai-activity | settled |
| FA-06 | `NvTermBarDim` fg==bg made the idle label invisible | ui-touch | settled |
| FA-07 | First-open terminal styled as a code pane (scratch-buffer caveat) | ui-touch | settled |
| FA-08 | Terminal id collision: AI panel claimed id 1 | toggleterm | settled |
| FA-09 | "0.12.x markdown-treesitter crash" — **misdiagnosed**; really nvim-treesitter's frozen master vs 0.12's list-valued `match[id]` | treesitter / floats | settled (fixed by `core/ts-compat`) |
| FA-10 | noice LSP hover/signature disabled | noice | workaround-pending-upstream |
| FA-11 | In-editor AI plugins removed (copilot, CopilotChat, avante, codecompanion) | AI architecture | settled |
| FA-12 | nvim-cursorline disabled (duplicated illuminate, fought ui-touch) | ui | disabled-not-deleted |
| FA-13 | Off-palette colors purged; single-accent doctrine | theme | settled |
| FA-14 | noice notify routing swallowed toast timeouts → 250ms overhaul | notifications | settled |
| FA-15 | Repo split: fresh `main`, history preserved on `feat/nvsinner-distro` | repo | settled |
| FA-16 | `--depth=1` installs broke updates → unshallow + restore-not-sync | install/update | settled |
| FA-17 | mini.animate scroll vs neoscroll: one owner for scroll | ui | settled |
| FA-18 | which-key silently dead: empty `config` suppressed `setup(opts)` | lazy.nvim | settled |
| FA-19 | eslint_d bogus "failed to decode json" diagnostic on every JS file | none-ls | settled |
| FA-20 | leap fork regression: auto-jump replaced label flow | navigation | settled |
| FA-21 | LSP: deprecated setup API, `ts_lsp` typo, semantic-token repaint | lsp | settled |
| FA-22 | AI column width: 30% proportional → fixed 50 columns | toggleterm | settled |
| FA-23 | Auto-reload: disk wins over unsaved buffer edits | autoreload | by-design trade-off |
| FA-24 | `:NvSinnerSync` jumped nvim-treesitter master → main (upstream default-branch flip) | install/update / treesitter | settled |
| FA-25 | "NvSinner feels slow": 1000 ms `timeoutlen` on the flagship prefix keys + a `jk` map delaying every `j` typed into the AI CLI | keymaps / terminal | settled |

---

## The terminal/agent-UX campaign (FA-01 … FA-07)

The hardest sustained problem in this repo: making a live "agent is working /
idle" spinner in the terminal winbar actually work. Four separate "obvious"
approaches failed for non-obvious Neovim-internals reasons, all verified
empirically. All landed together in commit `8f90d92` (branch
`feat/nvsinner-distro`); full narrative in
`.tmp/06-29-26_01_ai-activity-indicator-and-tests-PR-DESCRIPTION.md`.
Ongoing work in this area: see `nvsinner-terminal-ux-campaign`. Theory:
`neovim-internals-reference`.

### FA-01 — changedtick polling REJECTED for terminal activity detection

- **Symptom:** A poller watching `b:changedtick` on the AI terminal buffer sat
  frozen while the CLI visibly streamed output — the spinner never turned on.
- **Root cause:** Neovim does not materialise a terminal buffer's lines (and
  therefore does not bump its changedtick) unless something is attached to the
  buffer or the buffer is being rendered. Verified empirically during
  development — the tick can stay constant through arbitrary amounts of PTY
  output.
  > ⚠️ 2026-07-02 re-probe (Neovim 0.12.3, headless): the freeze did NOT
  > reproduce — the tick advanced on a hidden, unattached terminal. The
  > rejection of tick polling still stands (`on_lines` has a delivery
  > contract; polling doesn't), but the mechanism-claim is version-scoped.
  > See `nvsinner-empirical-verification` recipe 3.
- **Evidence:** `.tmp/06-29-26_01_...md` ("polling the tick silently stays
  frozen while output streams"); code comment `lua/core/ai-activity.lua:4-9`;
  commit `8f90d92`.
- **Resolution:** `nvim_buf_attach` with an `on_lines` callback, wired by a
  `TermOpen` autocmd. An attached listener is *always* notified. The callback
  runs in a fast event context, so it touches only a plain Lua `state` table
  and `uv.now()` — no `vim.*` API calls inside it
  (`lua/core/ai-activity.lua:83-91`).
- **Status:** settled.
- **Do not retry:** any changedtick-, timer-diff-, or `getbufline`-polling
  scheme for terminal activity. Attach or nothing.

### FA-02 — `vim.g.statusline_winid` REJECTED for winbar content

- **Symptom:** A shared winbar expression using `g:statusline_winid` to find
  "its" window rendered an **empty bar** in real use.
- **Root cause:** `g:statusline_winid` is populated during `'statusline'`
  evaluation but **not** during `'winbar'` evaluation. Verified empirically.
  > 2026-07-02 refinement (0.12.3 probe): the real discriminator is `%!` vs
  > `%{}` — `%{}` items see the variable in NEITHER option. Conclusion
  > unchanged. See `nvsinner-empirical-verification` recipe 2.
- **Evidence:** `.tmp/06-29-26_01_...md`; CLAUDE.md *Agent activity* ("verified");
  `term_bar(win)` at `lua/core/ui-touch.lua:83`; commit `8f90d92`.
- **Resolution:** `M.winbar(buf)` takes the buffer as an **argument**;
  `ui-touch.lua`'s `term_bar(win)` bakes the buffer number into each window's
  literal winbar string: `%{%v:lua.require'core.ai-activity'.winbar(<buf>)%}`.
- **Status:** settled.
- **Do not retry:** any "one shared winbar string that introspects its window"
  design via `g:statusline_winid`. Per-window strings with baked identifiers
  are the pattern.

### FA-03 — `:redrawstatus` REJECTED for spinner animation

- **Symptom:** Spinner looked frozen precisely in the main use case — when
  focus was *inside* the AI terminal watching the agent.
- **Root cause:** When focus is inside a terminal, `:redrawstatus` does not
  repaint the winbar. Verified in a real PTY render.
- **Evidence:** code comment `lua/core/ai-activity.lua:118-124`;
  `.tmp/06-29-26_01_...md`; commit `8f90d92`.
- **Resolution:** `vim.api.nvim__redraw({ statusline = true, winbar = true,
  flush = true })`, with a `pcall` fallback to `redrawstatus!` for older
  Neovim. Note `nvim__redraw` is a private (double-underscore) API — a known,
  accepted risk until a public equivalent exists (flagged in the PR's reviewer
  notes).
- **Status:** settled (watch future Neovim releases for a public replacement).
- **Do not retry:** "simplifying" the redraw back to `redrawstatus`/`redraw` —
  it passes casual testing (focus outside the terminal) and fails the real
  workflow.

### FA-04 — Hooking only `FileChangedShell` missed the common AI-edit case

- **Symptom:** The "🤖 AI · edited <file>" toast never fired for ordinary AI
  edits, only for conflict cases.
- **Root cause:** With `autoread` on and the buffer unmodified — the normal
  AI-edit scenario — Neovim reloads silently and fires **only**
  `FileChangedShellPost`, not `FileChangedShell`. Verified empirically.
- **Evidence:** CLAUDE.md *Auto-reload* ("verified empirically");
  `.tmp/06-29-26_01_...md`; `lua/core/autoreload.lua`; commit `8f90d92`.
- **Resolution:** Hook **both** events, with a per-file dedup window so one
  write can't double-toast. Originally 500ms (`8f90d92`); reduced to **250ms**
  in the toast overhaul (`01cb4bc`, see FA-14) — the live code is 250ms
  (`lua/core/autoreload.lua:27`). CLAUDE.md's Auto-reload prose still says
  500ms; the code is the ground truth here.
- **Status:** settled.
- **Do not retry:** dropping either hook. `FileChangedShell` alone misses the
  common case; `FileChangedShellPost` alone misses the conflict case; no dedup
  double-toasts.

### FA-05 — Luv timer GC hazard: spinner silently stops

- **Symptom class:** An active `vim.uv` timer whose handle is only a local
  variable can be garbage-collected by luv, silently stopping the animation.
- **Resolution:** The handle is pinned on the module table:
  `M._timer = assert(uv.new_timer())` (`lua/core/ai-activity.lua:142-143`).
- **Evidence:** `.tmp/06-29-26_01_...md` ("An unreferenced active `uv` timer
  can be GC'd and silently stop animating"); CLAUDE.md *Agent activity*;
  commit `8f90d92`.
- **Status:** settled.
- **Do not retry:** holding uv handles in function-local variables anywhere a
  handle must outlive its creating scope.

### FA-06 — `NvTermBarDim` fg==bg hid the idle label

- **Symptom:** The unfocused terminal bar looked like an empty black strip;
  the `● idle` / label text was invisible.
- **Root cause:** `NvTermBarDim` was defined with `fg == bg` (`#16161d` on
  `#16161d`) — the bar was meant to be a "subtle strip", but once it carried
  text, the text vanished.
- **Evidence:** `.tmp/06-29-26_01_...md`; fix visible at
  `lua/core/ui-touch.lua:22-23,36` (`BAR_DIM_FG = "#7a7f8d"`); regression test
  `tests/core/ui_touch_spec.lua` asserts `NvTermBarDim` fg ≠ bg; commit `8f90d92`.
- **Resolution:** fg set to muted palette `#7a7f8d`; the *busy* state
  additionally renders in the `NvAiBusy` crimson chip so it survives any dim bar.
- **Status:** settled.
- **Do not retry:** styling a text-bearing bar with fg==bg for "subtlety".

### FA-07 — First-open scratch-buffer caveat (toggleterm + BufWinEnter)

- **Symptom:** The very first open of a toggleterm window showed no terminal
  bar/spinner; it was styled like a code pane. Subsequent toggles were fine.
- **Root cause:** toggleterm fires `BufWinEnter` while its buffer is still a
  scratch buffer (`buftype == ""`), so `ui-touch.lua`'s `focus()` classified
  it as a code pane and skipped the terminal winbar. Only later does the
  buffer become `buftype == "terminal"`.
- **Evidence:** code comment `lua/core/ui-touch.lua:135-139`; CLAUDE.md
  *Touch / focus feedback* ("First-open caveat"); `.tmp/06-29-26_01_...md`;
  commit `8f90d92`.
- **Resolution:** `TermOpen` added to the focus autocmd's event list
  (`{ "WinEnter", "BufWinEnter", "TermOpen" }`) so `focus()` re-runs once the
  buffer is really a terminal.
- **Status:** settled.
- **Do not retry:** removing `TermOpen` from that list because it "looks
  redundant with BufWinEnter". It is not.

---

## Terminal plumbing and AI architecture (FA-08, FA-11, FA-22, FA-23)

### FA-08 — Terminal id collision: AI panel claimed id 1

- **Symptom:** Open the AI panel (`<leader>j`) first, then press the
  horizontal-terminal key — instead of opening a horizontal terminal, it just
  re-toggled (hid) the AI panel.
- **Root cause:** toggleterm auto-assigns ids; the AI panel opened first
  claimed id 1, which is exactly what the horizontal-terminal keymap's default
  `v:count1` targets.
- **Evidence:** commit `220a897` ("Fix terminal id collision…",
  branch `feat/nvsinner-distro`); live scheme in
  `lua/plugins/terminal/toggleterm.lua:58-62,77,129-130`.
- **Resolution:** AI panels use **reserved ids `99 + N`** (session 1 → 100 …
  session 9 → 108), disjoint from the horizontal terminals' ids 1–9. The id
  also drives the winbar label (`AI · <id-99>` vs `term <id>`). This scheme is
  a hard constraint documented in CLAUDE.md and the `nvim-terminal` subagent.
- **Status:** settled.
- **Do not retry:** letting any persistent panel auto-claim a toggleterm id,
  or "cleaning up" the 99+N offset.

### FA-11 — In-editor AI plugins REMOVED: AI-as-CLI architecture

- **Symptom:** `copilot.lua` threw an RPC auth error on startup ("Not
  authenticated: No access to GitHub Copilot found"); `avante.nvim` and
  `codecompanion.nvim` never worked at all (`ANTHROPIC_API_KEY` was never
  exported) while the same capability was already in daily use via the
  `claude` CLI in the toggleterm column. Dead weight: unbuildable `make`
  step, orphaned `Avante*` highlights, duplicate keymaps.
- **History:** CopilotChat era began with `ace5794` (":bookmark: chatcopilot
  added", 2025-08-30, on `feat/nvsinner-distro`; the dotfile history itself
  starts 2024-09-04 at `cb59fdf`). Everything AI-in-editor was removed in the
  cleanup commits `26947f9` / `b5b5971` (2026-06, same PR description
  committed twice): copilot.lua, copilot.vim (orphaned lock entry),
  CopilotChat.nvim, smoji.nvim, avante.nvim, codecompanion.nvim.
- **Evidence:** full narrative in the `26947f9`/`b5b5971` commit messages
  (they embed the PR description); CLAUDE.md *AI — terminal column*.
- **Resolution:** AI = a CLI agent in a persistent terminal column. The config
  never reads `ANTHROPIC_API_KEY`; auth is the CLI's problem. Supporting
  systems (auto-reload FA-23, activity spinner FA-01…07) exist *because* of
  this architecture.
- **Status:** settled — this is the project's identity, not a temporary state.
- **Do not retry:** proposing avante/codecompanion/copilot-chat or any
  in-editor AI plugin. `nvsinner-architecture-contract` owns the positive
  rationale; the history above is why the door closed.

### FA-22 — AI column width: 30% proportional → fixed 50 columns

- **Symptom:** On wide monitors, a 30%-of-screen AI column was excessively wide.
- **Resolution:** fixed `AI_WIDTH = 50` columns
  (`lua/plugins/terminal/toggleterm.lua:30,132`), landed with the tactile-UI
  layer, commit `2f7ec6c`. Resize on demand via `<C-,>` / `<C-.>`.
- **Status:** settled.

### FA-23 — Auto-reload: disk wins (by design)

- **Symptom (perceived):** unsaved in-Vim edits to a buffer the AI also wrote
  are silently discarded on reload.
- **Reality:** deliberate. `FileChangedShell` resolves to `"reload"` so the
  on-disk version always wins — chosen for the viewer-style workflow where
  editing happens in the AI pane. Documented as a trade-off from the start
  (`26947f9` commit message; CLAUDE.md *Auto-reload*).
- **Status:** by-design trade-off.
- **Do not "fix":** adding a W11/W12-style prompt would break the AI workflow
  this exists for. Any change here goes through `nvsinner-change-control`.

### FA-25 — "NvSinner feels slow": the 1000 ms prefix wait (2026-07-28)

- **Symptom:** the owner reported that `<leader>t` and `<leader>j` pause
  noticeably before the panel appears, and that the editor felt sluggish in
  general.
- **Diagnosis:** correct on both counts, and the second had a cause the first
  didn't. `timeoutlen` was **never set anywhere in the repo** — verified by a
  whole-tree grep returning only comments — so Neovim's **1000 ms** default
  governed every strict-prefix mapping. Four prefixes paid it: `<leader>t`
  (of `t2`…`t9`), `<leader>j` (of `j2`…`j9`, `jx`, `ja`, `jc`), `<leader>jx`
  (of `jx2`…`jx9`, stacking on `<leader>j`'s), and — previously undocumented,
  found during this investigation — **`<leader>f`** (of `<leader>fb`). That
  last one hid because the collision spans two ownership layers: `<leader>f`
  is a lazy `keys` stub in `lua/plugins/navigation/telescope.lua:24`,
  `<leader>fb` an eager map in `lua/core/keymaps.lua:83`.
  The diffuse "everything is slow" feeling traced to a fifth site nobody had
  connected to `timeoutlen`: `toggleterm.lua` mapped **`jk` in terminal
  mode**, making every literal `j` a prefix, so each `j` typed into the AI
  CLI was withheld a full second before reaching the program.
- **Fix:** `vim.opt.timeoutlen = 300` in `lua/core/options.lua`, overridable
  by a new persisted `key_timeout` setting (`lua/core/settings.lua` +
  a `:NvSinnerMenu` → "Key timeout" row cycling 200/250/300/400/500/1000), and
  the `t`-mode `jk` map deleted. Pinned by specs in `options_spec`,
  `settings_spec`, `menu_spec` and `keymaps_spec`.
- **Prior state of the record:** the delay was documented in eight places and
  classified *NOT A BUG*, which is why it survived so long. Re-reading those
  carefully was the unlock: the only fix ever **forbidden** was "removing the
  numbered maps". Lowering `timeoutlen` had never been tried, tested, or
  vetoed, and `nvsinner-architecture-contract` already listed the lag as a
  known **weak point** — an acknowledged cost, not a defended design.
- **Rejected:** (a) *removing or relocating the numbered maps* — still
  forbidden, it is the one veto that predates this work; (b) *a which-key
  `delay`/`triggers` tweak* — which-key only decides when the popup paints,
  it cannot change when the mapping fires, and editing that spec has its own
  history (FA-18); (c) *a per-mapping continuation reader* (`getchar` with a
  short custom wait, which would make the bare press truly instant while
  keeping every numbered map) — it works in principle but adds blocking,
  fragile input code to buy 300 ms over a one-line option.
- **Status:** settled.
- **Do not retry:** restoring Neovim's 1000 ms default, or re-adding a
  `t`-mode `jk` (or any other common typing character) as an escape — in
  terminal mode a prefix map costs one `timeoutlen` **per keystroke typed
  into the CLI**, which is the expensive case.

---

## The "Neovim 0.12.x markdown crash" cluster (FA-09, FA-10) — **misdiagnosed, now fixed**

### FA-09 — Markdown treesitter crash: a frozen plugin, not a Neovim bug

- **Symptom:** on Neovim 0.12.3, opening ANY markdown buffer threw
  `attempt to call method 'range' (a nil value)` from
  `runtime/treesitter.lua:197`. Also via telescope's file preview and via
  transient floats given `filetype=markdown` (first hit during the tactile-UI
  work — the mouse-hover float, commit `2f7ec6c`).
- **Root cause — CORRECTED 2026-08-31.** The original entry said "upstream
  Neovim 0.12.x regression — markdown parser/queries out of sync. Not our bug."
  **That was wrong.** Neovim 0.12 changed the treesitter handler contract to
  `fun(match: table<integer, TSNode[]>, …)`: `match[capture_id]` is a **list**
  of nodes. nvim-treesitter, pinned to the frozen `master` branch, still reads
  it as a single node, and its `query_predicates.lua:19` passes
  `{ force = true, all = false }` — on 0.12 `all` no longer exists and is
  silently ignored. Its `queries/markdown/injections.scm` calls
  `#set-lang-from-info-string!`, which then does `get_node_text(<list>)` and
  throws. Neovim's *own* markdown injections query uses no directive at all,
  which is why the crash vanished without the plugin on the runtimepath.
- **Blast radius was wider than markdown.** The same defect broke HTML
  `<script type=…>` (`#set-lang-from-mimetype!`) and bash heredoc
  (`#downcase!`) injections. Those never crashed loudly, they just silently
  stopped injecting — so nobody looked, and the label stayed on markdown.
- **How it was misdiagnosed, because this is the reusable lesson:**
  1. **The error string named a Neovim runtime file**
     (`runtime/lua/vim/treesitter.lua:197`), so the blame landed there. It was
     the *victim*, not the culprit — a plugin handed it a list.
  2. **"Rendering claims need a real TUI" was over-applied.** The crash lives
     inside `LanguageTree:parse(true)`, not in a repaint; it reproduces
     headless in one command. Believing it needed an interactive repro is why
     it went unprobed for months.
  3. **This entry contained its own disproof.** It recorded *"the crash does
     not occur on stable 0.11.x."* A Neovim runtime regression cannot be
     sensitive to which plugin is loaded — but a plugin whose `all = false` was
     still honoured on 0.11 can be. Nobody read the clue against the conclusion.
- **Evidence:** probes and verbatim outputs in `nvsinner-empirical-verification`
  Recipe 7 (2026-08-31, NVIM v0.12.3); `lua/core/ts-compat.lua`'s header;
  specs `tests/core/ts_compat_spec.lua` + `tests/plugins/treesitter_predicates_spec.lua`
  (the latter fails with the exact historical error when the shim is removed).
- **Resolution:** `lua/core/ts-compat.lua` re-registers the three directives any
  shipped query uses, with 0.12 semantics, called from nvim-treesitter's spec
  `config()` **after** `configs.setup{}` (registering earlier lets the plugin
  overwrite the shim — verified). All four workarounds were then removed:
  `after/ftplugin/markdown.lua` (deleted), `highlight.disable`, telescope's
  `preview.treesitter.disable`, and `core/markdown.lua`'s injection-query patch.
- **Status: settled (fixed).** Markdown, HTML and bash injections work. The pin
  stays: `branch = "master"` + the shim are now a pair — see the CLAUDE.md
  non-negotiable.
- **Do not retry:** re-adding any of the four workarounds; "fixing" this by
  migrating to nvim-treesitter `main` (needs the tree-sitter CLI on PATH and
  re-enters FA-24's parser-build surface — to fix a handful of lines); or
  removing the shim while the `master` pin stands.

### FA-10 — noice LSP hover/signature OFF (same crash class)

- **Symptom-if-reverted:** enabling noice's LSP hover/signature/markdown paths
  routes LSP markdown through the treesitter markdown highlighter in transient
  floats → the FA-09 crash.
- **Resolution:** `lsp = { hover = { enabled = false }, signature =
  { enabled = false } }` and no overrides of the `vim.lsp` markdown helpers
  (`lua/plugins/ui/noice.lua:32-37`). `K` keeps the native handler;
  mouse-hover docs stay in `ui-touch.lua` as plain text. Landed with the
  restructure (`b0cf66f`; narrative in
  `.tmp/06-28-26_01_nvim-config-restructure-PR-DESCRIPTION.md`).
- **Status: the stated reason is VOID** (FA-09 is fixed), but the flags are
  still off. Re-enabling them is a UX change to a different subsystem —
  bordered noice floats replacing the native handler, different scrolling,
  `override` of the `vim.lsp` markdown helpers — and it deletes a CLAUDE.md
  non-negotiable, so it needs its own evidence rather than a drive-by flip.
- **Do not retry:** flipping them "because FA-09 is fixed" without actually
  testing the noice float path. Same for giving `ui-touch`'s hover float
  `filetype = "markdown"`."

---

## UI doctrine formed by failure (FA-12, FA-13, FA-17)

### FA-12 — nvim-cursorline disabled, not deleted

- **Symptom:** double highlighting — nvim-cursorline's cursorword duplicated
  `vim-illuminate`, and its cursorline fought `ui-touch.lua`'s focus-aware
  `CursorLine`.
- **Resolution:** `enabled = false` in `lua/plugins/ui/cursorline.lua:9`,
  kept in-tree as a one-line revert (per the disable-don't-delete convention).
  Landed in the restructure (`b0cf66f`; `.tmp/06-28-26_01_...md`).
- **Status:** disabled-not-deleted.
- **Do not retry:** re-enabling it while illuminate + ui-touch both exist, or
  deleting the file (it documents the decision).

### FA-13 — Off-palette colors purged: the single-accent doctrine

- **Symptom:** plugin default themes leaked foreign colors into the
  monochrome glass UI — incline's old blue badge, barbecue's tokyonight
  defaults.
- **Resolution:** both were explicitly recolored to the glass palette
  (bg `#0a0a0f`, glass `#111118`, FG `#c5c9d5`, muted `#7a7f8d`) with exactly
  **one** accent, kanagawa dragonRed `#c4746e`. The restructure PR's reviewer
  notes state this was enforced as a hard constraint across all seven
  subagent prompts (`.tmp/06-28-26_01_...md`; commit `b0cf66f`; CLAUDE.md
  *UI chrome — one palette, one accent*).
- **Status:** settled — doctrine, not preference.
- **Do not retry:** accepting any new plugin's default colors. Theme it or
  don't add it. Palette specifics: `nvsinner-config-catalog`.

### FA-17 — mini.animate scroll vs neoscroll: one owner per animation

- **Symptom-if-enabled:** both plugins animating scroll fight over scroll
  events (double-animation).
- **Resolution:** `scroll = { enable = false }` in
  `lua/plugins/ui/mini-animate.lua:14-15`; neoscroll
  (`lua/plugins/ui/smooth-scroll.lua`) is the sole scroll owner; mini.animate
  keeps window open/close/resize + cursor trail. (`b0cf66f`;
  `.tmp/06-28-26_01_...md`.)
- **Status:** settled.
- **Do not retry:** enabling mini.animate's scroll, or adding a third
  scroll-animation plugin.

---

## Notifications (FA-14)

### FA-14 — noice's notify routing swallowed toast timeouts → 250ms overhaul

- **Symptom:** every toast lingered ~1s+ longer than intended; per-call
  `{ timeout = ... }` options had no effect; toasts carried a fixed timestamp
  badge.
- **Root cause (two-part):** (1) noice's notification-routing interceptor sat
  between `vim.notify` and nvim-notify and silently ignored the per-call
  `timeout` field; (2) nvim-notify's default `"fade_in_slide_out"` stage added
  ~750ms of animation on top of the visibility window.
- **Evidence:** `.tmp/06-30-26_01_main-PR-DESCRIPTION.md` §"250ms toast
  overhaul"; commits `01cb4bc` + `3cb061d` (branch `feat/nvsinner-distro`);
  live config `lua/plugins/ui/noice.lua:24-31` (`notify = { enabled =
  false }`) and `lua/plugins/ui/notify.lua` (`timeout = 250`, `stages =
  "fade"`).
- **Resolution:** disable noice's notify routing entirely (noice keeps only
  cmdline + popupmenu); nvim-notify owns `vim.notify` with a global 250ms
  timeout + `"fade"`; every call site passes `{ timeout = 250 }` explicitly;
  autoreload's dedup window matched down to 250ms (see FA-04).
- **Status:** settled.
- **Do not retry:** re-enabling `notify` in noice's setup — it was "the only
  clean fix" per the PR; tweaking nvim-notify timeouts while noice intercepts
  is a no-op.

---

## Distro and repo history (FA-15, FA-16, FA-24)

### FA-15 — Repo split: fresh `main`, old history on `feat/nvsinner-distro`

- **What happened:** NvSinner was split out of the personal dotfile repo
  (`anderssonq/ander-nvim-lazy`, per NVSINNER.md item 4) into
  `anderssonq/nvsinner` with a **fresh history**: `main` begins at `1ba89eb`
  "Initial commit: NvSinner Neovim distro" (2026-06-30). The full pre-split
  history (back to `cb59fdf`, 2024-09-04) is preserved on branch
  `feat/nvsinner-distro`. The two histories are **disjoint** —
  `git merge-base main feat/nvsinner-distro` is empty (verified).
- **Consequences for you:** `git log main` / `git blame` cannot see anything
  before 2026-06-30. To dig into any pre-split SHA cited in this skill
  (`220a897`, `26947f9`/`b5b5971`, `2f7ec6c`, `b0cf66f`, `8f90d92`,
  `01cb4bc`, `3cb061d`, `ace5794`), use `git log feat/nvsinner-distro` or
  `git show <sha>` with that branch fetched. Never merge or rebase the two
  histories together.
- **Evidence:** `git branch -a`, disjoint merge-base, NVSINNER.md items 4/Status,
  TODO.md Done list.
- **Status:** settled.

### FA-16 — `--depth=1` legacy → unshallow-on-update; restore-not-sync doctrine

- **Symptom:** older `install.sh` cloned with `--depth=1` and *skipped* an
  existing clone on re-run — so existing installs had no way to pull new
  config code, and shallow clones broke history-based updates.
- **Resolution (commit `c818b8b` on `main`, "Add self-update path"):**
  - `install.sh` now `git pull`s an existing clone, first running
    `git fetch --unshallow` on old shallow installs (`install.sh:31-37`);
    fresh clones are full-depth (`install.sh:44`).
  - New `:NvSinnerUpdate` (`lua/core/update.lua`): async `git pull --ff-only`
    → `Lazy restore` → `:checkhealth` → restart reminder; no-ops with a
    warning when the config dir isn't a git clone (dev symlink / manual copy).
  - **Restore-not-sync doctrine:** both install and update run
    `Lazy! restore` against the committed `lazy-lock.json` so the plugin set
    reproduces the tested pins; `:Lazy sync` is the *opt-in* float-to-latest
    path (`install.sh:78-82`; CLAUDE.md *Updater*).
- **Evidence:** commit `c818b8b` message; `install.sh`; TODO.md Done;
  `tests/core/update_spec.lua`.
- **Status:** settled.
- **Do not retry:** `--depth=1` in install paths, or swapping `restore` back
  to `sync` in install/update flows. Install mechanics:
  `nvsinner-build-and-run`.

### FA-24 — `:NvSinnerSync` jumped nvim-treesitter to the `main` rewrite (2026-07-03)

- **Symptom:** running the new `:NvSinnerSync` (the opt-in float path,
  `lua/core/sync.lua`) produced a cascade of ERROR notifications:
  `nvim-treesitter[markdown/markdown_inline]: Failed to execute the following
  command`, `ld: symbol(s) not found for architecture arm64`
  (`_tree_sitter_…_external_scanner_*`), `clang: error: linker command failed`.
- **Root cause (two layers):**
  1. The nvim-treesitter spec had **no `branch` pin**, so lazy follows the
     upstream **default branch** — and upstream flipped it from `master`
     (frozen) to `main`, a **full rewrite**: no `nvim-treesitter.configs`
     module (the spec's `config` would error on the next restart) and a new
     install pipeline that recompiles every parser from source on the machine.
  2. The `build = ":TSUpdate"` rebuild of the markdown pair then failed at
     link on arm64, and every failed pipeline step (compile, `mv -f …-tmp…`)
     fired its own error notification — the flood.
  `restore` never exposes this (it checks out the pinned commit); only
  `sync` re-resolves the default branch. The running session kept working on
  the old in-memory modules, masking the breakage until restart.
- **Resolution:**
  - Rolled back: `git restore lazy-lock.json` + `Lazy! restore` in BOTH app
    instances (`nvim` and `nvsinner` data dirs) — treesitter back to the
    pinned master commit, `configs.lua` present, compiled parsers intact.
  - Pinned `branch = "master"` in `lua/plugins/editor/nvim-treesitter.lua`
    with the incident note; migrating to `main` is a deliberate config
    rewrite, not a version bump.
  - `:NvSinnerSync` grew a **branch-jump guard**: it snapshots the lockfile's
    per-plugin `branch` before syncing, diffs it after (`M.branch_jumps`,
    pure test seam), and WARNs naming every jump plus the rollback recipe.
- **Evidence:** `lazy-lock.json` diff (`"nvim-treesitter": master → main`);
  absence of `lua/nvim-treesitter/configs.lua` on the `main` checkout;
  `tests/core/sync_spec.lua` (branch-jump cases).
- **Status:** settled.
- **Do not retry:** unpinning nvim-treesitter's `branch` while the spec uses
  `nvim-treesitter.configs`, or removing the branch-jump guard from
  `core/sync.lua`. When migrating to the `main` rewrite on purpose, rewrite
  the spec's config for the new API in the same change.

---

## The great cleanup's smaller bugs (FA-18 … FA-21)

All from commits `26947f9` / `b5b5971` ("Neovim config cleanup", 2026-06,
branch `feat/nvsinner-distro`) — the commit messages embed the full PR
description with root causes.

### FA-18 — which-key silently dead: empty `config` suppressed `setup(opts)`

- **Symptom:** which-key's popup never appeared; no error anywhere.
- **Root cause:** the spec had both `opts = {...}` **and** an empty
  `config = function() end`. lazy.nvim only auto-calls `setup(opts)` when no
  custom `config` is defined — the empty function silently suppressed setup.
- **Resolution:** remove the empty `config`. (`26947f9`.)
- **Status:** settled.
- **Do not retry / general lesson:** never leave a stub `config = function()
  end` in a lazy spec alongside `opts` — it is not a no-op, it is a kill
  switch. Spec rules: `nvsinner-change-control`.

### FA-19 — eslint_d bogus "failed to decode json" diagnostic

- **Symptom:** a fake diagnostic on the first character of every JS file:
  `failed to decode json`.
- **Root cause:** `eslint_d` prints a *plain-text* error when a project has
  no ESLint config; none-ls piped that into `vim.json.decode()` and surfaced
  the parse failure as a diagnostic.
- **Resolution:** guard the `eslint_d` source behind a `root_has_file`
  condition (`.eslintrc*`, `eslint.config.{js,mjs,cjs,ts}`) in
  `lua/plugins/lsp/none-ls.lua`. (`26947f9`.)
- **Status:** settled.
- **Do not retry:** wiring any linter source unconditionally when its binary
  errors in plain text on unconfigured projects.

### FA-20 — leap fork regression: auto-jump replaced the label flow

- **Symptom:** leap auto-jumped to the nearest match instead of always
  labeling targets; `case_sensitive` option errored.
- **Root cause:** the installed fork (`codeberg.org/andyg/leap.nvim`) removed
  `case_sensitive` (now driven by `vim_opts['go.ignorecase']`) and ships a
  non-empty `safe_labels` default that enables auto-jump.
- **Resolution:** `safe_labels = ""` restores the classic "type 2 chars →
  pick a label" flow; the deprecated option was migrated.
  (`26947f9`; `lua/plugins/navigation/leap.lua`.)
- **Status:** settled.
- **Do not retry:** trusting an upstream fork's defaults after a pin bump —
  re-verify `safe_labels` behavior if leap is ever updated.

### FA-21 — LSP modernization: deprecated API, `ts_lsp` typo, semantic-token repaint

- **Symptoms:** (a) the TypeScript server config was never applied — a typo
  (`ts_lsp` instead of `ts_ls`); (b) the config used the deprecated
  `require("lspconfig").<server>.setup()` pattern; (c) later, LSP semantic
  tokens (`@lsp.*`) repainted buffers ~1s after open, flattening the
  Treesitter palette.
- **Resolution:** migrate to the Neovim 0.11 native API —
  `vim.lsp.config("*", { capabilities })` + `vim.lsp.enable({...})`
  (`26947f9`); the `"*"` config's `on_attach` nils
  `client.server_capabilities.semanticTokensProvider`
  (`lua/plugins/lsp/lsp-config.lua:57`) so Treesitter stays the single source
  of syntax color (`b0cf66f`). Load-order corollary: mason-lspconfig runs
  with `automatic_enable = false` (`lsp-config.lua:28`) because auto-enabling
  could start a server *before* the `"*"` config lands and bring the `@lsp.*`
  repaint back (`.tmp/06-30-26_01_...md` — includes the regression check:
  open a `.lua` file, watch whether highlights shift ~1s after open).
- **Status:** settled.
- **Do not retry:** `lspconfig.<server>.setup()`, removing
  `automatic_enable = false`, or removing the semanticTokensProvider nil
  without deciding you *want* semantic highlighting (CLAUDE.md documents that
  as the one legitimate reason).

---

## Provenance and maintenance

**Sources:** archived PR descriptions in `.tmp/*.md` (richest narratives);
commit messages on `main` and `feat/nvsinner-distro` (the cleanup and
spinner commits embed full PR write-ups); CLAUDE.md subsystem prose (where an
entry rests *only* on CLAUDE.md, the entry says "CLAUDE.md" in its Evidence
line — e.g. parts of FA-05's GC rationale); and direct code reads of the cited
files. FA-15's disjoint-history claim was verified by an empty
`git merge-base`.

**Facts verified: 2026-07-02** (dev machine: NVIM v0.12.3; `make test` green
per `.tmp/07-02-26_01_...md`).

**Keymap-timeout facts re-verified: 2026-07-28** — `timeoutlen = 300` set in
`lua/core/options.lua`, retunable via `key_timeout` in `lua/core/settings.lua`,
and no `t`-mode `jk` map in `lua/plugins/terminal/toggleterm.lua`. Every other
claim on this page still carries the 2026-07-02 date.

Re-verification one-liners (run from the repo root):

- Histories still disjoint: `git merge-base main feat/nvsinner-distro || echo disjoint`
- Pre-split SHAs reachable: `git log --oneline feat/nvsinner-distro | head`
- FA-01/03/05 code intact: `grep -n 'nvim_buf_attach\|nvim__redraw\|M._timer' lua/core/ai-activity.lua`
- FA-02/06/07 code intact: `grep -n 'term_bar\|BAR_DIM_FG\|TermOpen' lua/core/ui-touch.lua`
- FA-04/14 dedup + timeout: `grep -n '250' lua/core/autoreload.lua lua/plugins/ui/notify.lua`
- FA-08 reserved ids: `grep -n '99 + n\|id = n' lua/plugins/terminal/toggleterm.lua`
- FA-09 stays fixed (the shim is the guard): `make test-file FILE=tests/plugins/treesitter_predicates_spec.lua`; the shim is wired: `grep -n 'ts-compat' lua/plugins/editor/nvim-treesitter.lua`
- FA-10/17: `grep -n 'enabled = false' lua/plugins/ui/noice.lua lua/plugins/ui/mini-animate.lua lua/plugins/ui/cursorline.lua`
- FA-16 doctrine: `grep -n 'unshallow\|Lazy! restore' install.sh`
- FA-21 guards: `grep -n 'semanticTokensProvider\|automatic_enable' lua/plugins/lsp/lsp-config.lua`
- FA-25 timeout + no t-mode `jk`: `nvim --headless -c 'lua print(vim.o.timeoutlen, "jk=" .. vim.fn.maparg("jk", "t"))' -c qa` (expect `300  jk=`)
