---
name: nvsinner-architecture-contract
description: >
  The NvSinner architecture contract — the WHY behind every load-bearing design
  decision, the invariants that must always hold, and the known-weak points,
  stated plainly. Use when you need to understand the system before changing it:
  the init.lua boot order, the core-vs-plugins-vs-distro-shell layering, why AI
  is a CLI in a terminal column (not an editor plugin), why core modules are
  zero-dependency native Lua, the NVIM_APPNAME isolation model, the pinned
  lazy-lock restore-not-sync policy, the disk-wins autoreload trade-off, the
  single-accent glass palette and where each hex lives, why the terminal focus
  cue is a winbar and not a separator, why treesitter is the only syntax-color
  source, and how the ai-activity busy/idle signal chain works. Also use when
  asking "can I change X without breaking Y", "why was it built this way",
  "what must never regress", or "what are this config's weak spots".
---

# NvSinner architecture contract

NvSinner is a personal Neovim 0.11+ config (lazy.nvim) grown into a
distributable "AI-terminal IDE": AI means a CLI agent (e.g. `claude`) running in
a toggleterm column, not an in-editor plugin. The owner's stated ambitions, in
priority order: (a) the deepest AI-agent/terminal integration of any distro,
(b) native-first Neovim — zero-dependency core modules over plugins, (c) distro
engineering rigor (reproducible installs, health checks, tests). Every decision
below serves one of those three. `CLAUDE.md` is the authoritative manifest;
this skill explains the *why* and the *must-not-break*.

## When NOT to use this skill

| You want... | Go to |
|---|---|
| The rules as enforceable gates before a change ("am I allowed to...") | `nvsinner-change-control` |
| The war stories: what broke, how it was diagnosed, what was tried and rejected | `nvsinner-failure-archaeology` |
| Deep Neovim theory (fast event contexts, winbar evaluation, terminal buffer internals) | `neovim-internals-reference` |
| A per-file inventory of every plugin spec and its options | `nvsinner-config-catalog` |
| Install, launch, update, headless commands | `nvsinner-build-and-run` |
| Live debugging of a misbehaving instance | `nvsinner-debugging-playbook` / `nvsinner-diagnostics-toolkit` |
| Running or writing tests | `nvsinner-testing-and-qa` |
| Doc/style conventions for prose and Lua | `nvsinner-docs-and-style` |
| Fixing or evolving the terminal/agent UX (the hardest live problem) | `nvsinner-terminal-ux-campaign` |
| Roadmap / what to build next | `nvsinner-frontier` |
| How to empirically verify a Neovim behavior claim | `nvsinner-empirical-verification` |

---

## 1. System map

### Boot sequence (`init.lua`, 43 lines — read it, it is the spine)

1. **Bootstrap lazy.nvim** — clone `folke/lazy.nvim` into `stdpath("data")/lazy`
   if absent, prepend to `rtp`.
2. **`require("core.options")` FIRST.** It sets `vim.g.mapleader = " "` and
   `vim.g.maplocalleader = "\\"`. This must happen before `lazy.setup` because
   lazy evaluates plugin `keys` specs against the *current* leader; a leader set
   after lazy would leave every `<leader>...` plugin keymap bound to the default
   `\`. This ordering is the single most fragile line in the boot.
3. **Then the rest of `lua/core/`, in order:** `keymaps` (global maps),
   `autoreload` (disk-sync for the AI workflow), `ui-touch` (focus glow +
   terminal winbar + mouse hover), `ai-activity` (busy/idle spinner state +
   timer), `update` (`:NvSinnerUpdate`), `health` (`:checkhealth nvsinner` +
   first-run toast). These are plain `require`s — they run *now*, before any
   plugin, and register autocmds/timers immediately.
4. **`lazy.setup` with six explicit imports:** `plugins.ui`, `plugins.lsp`,
   `plugins.git`, `plugins.editor`, `plugins.navigation`, `plugins.terminal`.
   lazy.nvim's `import` does **not** recurse into subfolders, so each category
   folder needs its own line. A new category folder without an import line
   silently never loads — no error, the plugins just don't exist.

### The three layers

| Layer | Where | Nature |
|---|---|---|
| **Core native modules** | `lua/core/*.lua` (7 files) | Zero-dependency Lua required before lazy. Not plugin specs. They use only `vim.*` / `vim.uv`. This is the AI-workflow heart: autoreload, ui-touch, ai-activity, update, health. |
| **Plugin specs** | `lua/plugins/<category>/<name>.lua` | One plugin (or small group) per file, each returning a lazy spec. Six categories: `ui/`, `lsp/`, `git/`, `editor/`, `navigation/`, `terminal/`. Lazy-loaded via `event`/`cmd`/`keys`/`ft` wherever possible; only the theme is `lazy = false, priority = 1000`. |
| **Distro shell** | `bin/nvsinner`, `install.sh`, `uninstall.sh`, `lua/nvsinner/health.lua` | Makes the config an installable, named distribution. `bin/nvsinner` is a one-liner: `exec env NVIM_APPNAME=nvsinner nvim "$@"`. `lua/nvsinner/health.lua` exists only so Neovim's module-path discovery (`lua/<name>/health.lua` → `:checkhealth <name>`) resolves; it delegates to `core.health.report()`. |

Tests (`tests/`, plenary busted via `make test`) cover every core module plus a
"every plugin spec loads and is a valid lazy spec" sweep. See
`nvsinner-testing-and-qa`.

---

## 2. Load-bearing decisions (each with its WHY)

### AI as a CLI in a terminal column — no in-editor AI plugins
avante and codecompanion were removed; there is no `lua/plugins/ai.lua`.
Rationale: the CLI agent (Claude Code, opencode, ollama, anything) is the
better product — it handles its own auth/billing (the config never reads
`ANTHROPIC_API_KEY`), its own model routing, its own tools — and a terminal
column is agent-agnostic where an editor plugin locks you to one vendor's API.
The editor's job shrinks to three native supports: show the agent's activity
(`lua/core/ai-activity.lua`), reload what it writes (`lua/core/autoreload.lua`),
and make the column feel first-class (`lua/core/ui-touch.lua`,
`lua/plugins/terminal/toggleterm.lua`). This is ambition (a) implemented via
ambition (b).

### Native-first core modules (zero dependencies on purpose)
`ui-touch`, `ai-activity`, `autoreload`, `update`, `health` use no plugin —
only `vim.api`, `vim.uv`, autocmds, and winbar/statusline expressions. Why:
they must exist before lazy loads anything (they wire `TermOpen`/`WinEnter`
autocmds that must catch the *first* terminal), they must never break because a
plugin update changed an API, and they are the differentiating layer — the part
worth owning outright. The cost is accepted: more code to maintain and manual
duplication of things plugins would centralize (see palette weak point).

### NVIM_APPNAME isolation
NvSinner runs as `NVIM_APPNAME=nvsinner`: config `~/.config/nvsinner`, own
data/state/cache dirs. Why: it can be installed on any machine without
clobbering an existing `~/.config/nvim`, and uninstall is a clean rm of four
XDG dirs. On the dev machine `~/.config/nvsinner` is a **symlink** to this repo
(`~/.config/nvim`), so `nvim` and `nvsinner` load the same files. Consequences
that shape other code: `uninstall.sh` must unlink, never follow, that symlink;
`core/update.lua` must no-op (with a warning) when the config dir has no
`.git`, because the symlinked dev dir and a manual copy both can't `git pull`.

### Pinned `lazy-lock.json` + restore-not-sync
`install.sh` and `:NvSinnerUpdate` both run `Lazy! restore` /
`require("lazy").restore()`, never `sync`. Why: `restore` checks every plugin
out to the commit pinned in the committed `lazy-lock.json`, so every install
and update reproduces the plugin set the distro was actually tested with.
`:Lazy sync` is the deliberate opt-in "float to latest" path. This is ambition
(c): the lockfile is the tested artifact, not a byproduct.

### Disk-wins autoreload (the viewer-style trade-off)
`lua/core/autoreload.lua`: `autoread` + `FileChangedShell` forcing
`v:fcs_choice = "reload"` + `checktime` on focus events + a 1s `vim.uv` timer
(the timer exists because terminal mode has no `CursorHold`, so without it the
code pane wouldn't refresh while you sit in the AI column). Why disk wins:
in the intended workflow the *agent* is the editor and Neovim is the viewer;
a W11/W12 prompt on every agent write would make the workflow unusable. The
cost is real and accepted: unsaved in-Vim edits to a file the agent rewrites
are silently discarded. A toast (`FileChangedShell` **and**
`FileChangedShellPost`, 250ms per-file dedup) names each externally-edited
file. Why both events: with `autoread` on and the buffer unmodified — the
common case — Neovim reloads silently and fires *only* the Post event
(verified empirically; the story is in `nvsinner-failure-archaeology`).

### Single-accent glass palette
One dark monochrome surface, one color accent. Base: kanagawa "dragon"
(`lua/plugins/ui/theme.lua`). The hexes, each verified in source on 2026-07-02:

| Role | Hex | Defined in |
|---|---|---|
| Editor bg (near-black) | `#0a0a0f` | `theme.lua` (`BG`), `ui-touch.lua` (`BG`), `ai-activity.lua` (NvAiBusy chip fg) |
| Glass surface (floats, focused pane) | `#111118` | `theme.lua` (`GLASS`), `ui-touch.lua` (`GLASS`), `noice.lua` |
| Float borders | `#333345` | `theme.lua` (`BORDER`), `noice.lua` |
| Primary FG | `#c5c9d5` | `theme.lua` (`FG`), `noice.lua`, `incline.lua`, `barbacue.lua` |
| Muted FG | `#7a7f8d` | `ui-touch.lua` (`BAR_DIM_FG`), `incline.lua` / `barbacue.lua` (`MUTED`) |
| Accent — kanagawa dragonRed, the lone color | `#c4746e` | `ai-activity.lua` (`NvAiBusy` bg), `noice.lua`, `dashboard.lua`, `barbacue.lua`, `incline.lua` (each as `CRIMSON`) |
| Dim terminal bar (unfocused) | `#16161d` | `ui-touch.lua` (`BAR_DIM`) |
| Dim separator | `#2a2a38` | `ui-touch.lua` (`SEP_DIM`) |
| Focused code-pane separator | `#5b5b70` | `ui-touch.lua` (`SEP_ACTIVE`) |
| Focused terminal bar + separator | `#80949e` | `ui-touch.lua` (`SEP_TERM`) |
| Focused cursorline wash | `#15151c` | `ui-touch.lua` (`CURSORLINE`) |

**Labeled divergence:** `CLAUDE.md` documents `NvTermFocusBar` /
`NvTermFocusSeparator` as `#c4746e`; the code (`lua/core/ui-touch.lua:21`,
`SEP_TERM`) has shipped `#80949e` since the initial commit (`git log -S`
confirms `#c4746e` never appeared in that file). The code is ground truth; the
doc value is stale. Same class of drift: `CLAUDE.md` says the autoreload toast
dedup is 500ms, `lua/core/autoreload.lua:27` implements 250ms. Both are
evidence for the "manual palette/doc sync" weak point below.

Why one accent: the whole UI (incline, barbecue, noice, dashboard, the busy
chip) reads as one instrument panel, and any crimson pixel means exactly one
thing — "active / attention". Off-palette plugin defaults (the old incline
blue, barbecue's tokyonight colors) were removed for this reason; do not
reintroduce them.

### Winbar as the terminal focus cue (not a separator)
The focused terminal gets a full-width top bar (`winbar`, `NvTermFocusBar`)
plus a brighter separator; unfocused terminals keep the bar but dim
(`NvTermBarDim`). Why a bar: a 1px split line was too faint on the near-black
bg to signal focus. Why always-present: adding/removing a winbar changes window
height and reflows the terminal's scrollback; keeping it permanent and only
changing its highlight means zero reflow. Why `NvTermBarDim` has a readable fg
(`#7a7f8d`, not fg==bg): the bar now carries live content (the activity label)
that must stay legible when unfocused. Applied via `WinEnter`/`WinLeave`
(+ `BufWinEnter`, + `TermOpen` for the first-open scratch-buffer case) setting
per-window `winhighlight`/`winbar` in `lua/core/ui-touch.lua`, with an
`eligible()` guard skipping floats and special filetypes (neo-tree, telescope,
dashboard, lazy, mason, ...) so their own `winhighlight` is untouched.

### Treesitter as the single syntax-color source
`lua/plugins/lsp/lsp-config.lua`: the `vim.lsp.config("*")` `on_attach` nils
`client.server_capabilities.semanticTokensProvider`. Why: without it, ~1s after
a file opens the LSP's semantic tokens (`@lsp.*` groups) repaint the buffer on
top of treesitter and flatten the palette. Two supporting decisions hang off
this: (1) the config uses the Neovim 0.11 native API (`vim.lsp.config` +
`vim.lsp.enable`), never `require("lspconfig").<server>.setup()` (deprecated);
(2) `mason-lspconfig` runs with `automatic_enable = false` so it can never
start a server *before* the `"*"` config lands — enable order is part of the
contract, not a style choice.

### The ai-activity signal chain (architecture view)
The question "is the agent working or idle?" is answered by output flow, not
process inspection — CLI-agnostic by design. The chain
(`lua/core/ai-activity.lua` + `lua/core/ui-touch.lua`):

```
TermOpen autocmd
  → nvim_buf_attach(buf).on_lines            -- fires on every output chunk
    → plain Lua state table only              -- fast event context: no vim.* API
      (state[buf].busy = true, .last = uv.now())
  → vim.uv timer, 120ms (POLL_MS)             -- animates spinner, flips busy→idle
      after 1200ms quiet (IDLE_MS); handle kept on M._timer so luv can't GC it
    → nvim__redraw{statusline,winbar,flush}   -- NOT :redrawstatus (doesn't repaint
      (pcall, fallback redrawstatus!)            the winbar from inside a terminal)
  → rendered by the per-window winbar expression that ui-touch.lua builds:
      %{%v:lua.require'core.ai-activity'.winbar(<buf>)%}
      -- buffer number BAKED IN: g:statusline_winid is not set during
      -- winbar evaluation, so the expression must be told its buffer
```

Why each link is what it is: `on_lines` because polling `b:changedtick` on a
terminal buffer is unreliable (Neovim doesn't materialize terminal lines — or
bump the tick — unless something is attached or the buffer is rendered);
timer-side redraws because the fast-context callback may not call `vim.*`;
`nvim__redraw` because `:redrawstatus` skips the winbar when focus is inside a
terminal. Each rejected alternative was disproven in a real render — the
methodology lives in `nvsinner-empirical-verification`, the stories in
`nvsinner-failure-archaeology`, the underlying Neovim mechanics in
`neovim-internals-reference`. The busy state renders as an accent chip
(`NvAiBusy`, `#c4746e` bg) so it reads even on a dim unfocused bar; toggleterm
tags each buffer with `b:nv_term_label` (`AI · <n>` for ids 100+, `term <n>`
for 1–9) which `winbar()` prefixes.

---

## 3. Invariants (must always hold)

| # | Invariant | Where enforced / verified | Breaks if violated |
|---|---|---|---|
| 1 | Leaders are set before any lazy `keys` spec is read (`core.options` is the first require in `init.lua`) | `init.lua:20`, `lua/core/options.lua:6-7`; `tests/core/options_spec.lua` | Every `<leader>` plugin keymap binds to `\` |
| 2 | Every `lua/plugins/<category>/` folder has a matching `{ import = "plugins.<category>" }` in `init.lua` (six today) | `init.lua:32-37` | New category's plugins silently never load |
| 3 | Palette hexes stay identical across every `ColorScheme`-reapplied group: `theme.lua` `apply_glass_highlights`, `ui-touch.lua` `apply_hl`, `noice.lua` `glass_hl`, `ai-activity.lua` `NvAiBusy`, plus incline/barbacue/dashboard constants | Manual sync only — no test | Mismatched surfaces; the "one panel, one accent" read dies (already drifted doc-side, see §2) |
| 4 | toggleterm ids: AI panels reserve 100–108 (`id = 99 + n`); horizontals use 1–9 | `lua/plugins/terminal/toggleterm.lua:76,130` | An AI panel claims id 1 and `<leader>t` re-toggles the AI column instead of opening a terminal |
| 5 | The `on_lines` callback touches only the plain Lua `state` table + `uv.now()` — never `vim.*` API (fast event context) | `lua/core/ai-activity.lua:83-95` | Errors or corruption inside libuv callbacks |
| 6 | The terminal winbar expression bakes the buffer number in (`winbar(<buf>)`); never rely on `vim.g.statusline_winid` in winbar code | `lua/core/ui-touch.lua:83-85`, `lua/core/ai-activity.lua:58`; `tests/core/ui_touch_spec.lua` | Bar renders empty in real use |
| 7 | Markdown treesitter highlighting stays OFF in transient floats while on 0.12.x: ui-touch hover is plain text, noice `lsp.hover/signature` disabled, noice `lsp.override = {}` | `lua/core/ui-touch.lua:176-179`, `lua/plugins/ui/noice.lua:32-39` | "attempt to call method 'range'" crash on hover |
| 8 | Headless runs never consume the health first-run marker (`setup()` bails when `#vim.api.nvim_list_uis() == 0`) | `lua/core/health.lua:159-162`; `tests/core/health_spec.lua` | Installer/tests eat the greeting; user's first launch is silent about missing tools |
| 9 | `uninstall.sh` unlinks (`rm -f`) a symlinked config dir, never follows into its target | `uninstall.sh:80-83` | Uninstalling on the dev machine deletes the source repo |
| 10 | `NvTermBarDim` fg ≠ bg (readable muted text on the dim bar) | `lua/core/ui-touch.lua:36`; `tests/core/ui_touch_spec.lua` | Idle/working label invisible on unfocused terminals |
| 11 | The ai-activity timer handle stays referenced on the module (`M._timer`) | `lua/core/ai-activity.lua:142` | luv GCs the handle; spinner silently freezes |
| 12 | Semantic tokens stay nilled in the `"*"` `on_attach`, and `mason-lspconfig` keeps `automatic_enable = false` | `lua/plugins/lsp/lsp-config.lua:28,56-58` | `@lsp.*` repaint returns ~1s after open |
| 13 | Install/update paths use `Lazy restore` against the committed `lazy-lock.json`, never `sync` | `install.sh:82`, `lua/core/update.lua:29` | Installs float to untested plugin versions |

Rules-as-gates form of these (what a reviewer should block) lives in
`nvsinner-change-control`.

---

## 4. Known weak points (plainly)

- **Disk-wins can destroy work.** Unsaved in-Vim edits to any buffer the agent
  rewrites are discarded with no undo prompt — by design, but there is no
  guard, no "buffer was modified" escalation, nothing. The toast tells you
  *after* the fact.
- **Palette duplication is manual sync, and it has already drifted.** At least
  seven files hard-code hexes; nothing tests them against each other. The
  doc-side drift is live today: `CLAUDE.md` says the terminal focus bar is
  `#c4746e` while the code has always shipped `#80949e`, and it says the toast
  dedup is 500ms while the code says 250ms.
- **The busy/idle detector is an output heuristic.** Any terminal output =
  busy; 1.2s of quiet = idle. It cannot distinguish an agent genuinely working
  from the agent's own cosmetic spinner redraws (both stream output), and it
  goes "idle" during any >1.2s silent compute pause. `IDLE_MS = 1200` is a
  guess, not a measured constant. This is the core of the owner's stated
  hardest live problem — terminal/agent-UX fragility.
- **`timeoutlen` lag on the two flagship keys.** Bare `<leader>t` and
  `<leader>j` are prefixes of `<leader>t2..9` / `<leader>j2..9`, so each waits
  one `timeoutlen` before acting. The most-used bindings in the config are the
  slowest to respond.
- **0.12.x compatibility is reactive.** The config targets 0.11+ but is only
  exercised on the dev machine's 0.12.3. The markdown-treesitter crash was
  patched around in three files after it bit; there is no version matrix and
  nothing will catch the next such regression before a user does.
- **No CI at all.** `make test` passes today (2026-07-02) but only when someone
  runs it; CI is an open item in `TODO.md`, alongside Mason-managed formatters
  and versioned releases.
- **Layout determinism depends on a repair function.** `restore_layout()` in
  `toggleterm.lua` re-asserts the bottom/right split geometry after every panel
  open because toggleterm's own split placement is order-dependent — a
  workaround, not a fix.

What to *do* about the terminal/agent-UX items is `nvsinner-terminal-ux-campaign`'s
territory; the broader remediation roadmap (CI, version matrix, palette
single-sourcing) belongs to `nvsinner-frontier`.

---

## Provenance and maintenance

Facts verified: 2026-07-02 — every claim above checked against the working
tree at commit `a65af7f` (clean status) by direct file read; hexes, ids, and
timings quoted from source lines, not from docs.

Re-verification one-liners (run from the repo root):

- Boot order + six imports: `grep -n 'require("core\.\|import = ' init.lua`
- Leaders first: `head -8 lua/core/options.lua`
- Palette table: `grep -rn '#[0-9a-f]\{6\}' lua/core/ui-touch.lua lua/core/ai-activity.lua lua/plugins/ui/theme.lua lua/plugins/ui/noice.lua lua/plugins/ui/incline.lua lua/plugins/ui/barbacue.lua`
- Reserved terminal ids: `grep -n 'id = ' lua/plugins/terminal/toggleterm.lua`
- Signal-chain constants + fast-context rule: `grep -n 'POLL_MS\|IDLE_MS\|on_lines\|nvim__redraw\|M._timer' lua/core/ai-activity.lua`
- Winbar bakes buf: `grep -n 'winbar(%d)' lua/core/ui-touch.lua` (pattern: `grep -n "winbar(" lua/core/ui-touch.lua`)
- Semantic tokens nilled + no auto-enable: `grep -n 'semanticTokensProvider\|automatic_enable' lua/plugins/lsp/lsp-config.lua`
- restore-not-sync: `grep -n 'restore' install.sh lua/core/update.lua`
- Headless health guard: `grep -n 'nvim_list_uis' lua/core/health.lua`
- Symlink-safe uninstall: `grep -n 'rm -f\|rm -rf' uninstall.sh`
- Suite still green: `make test`
