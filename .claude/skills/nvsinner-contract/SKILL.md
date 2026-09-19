---
name: nvsinner-contract
description: >
  The NvSinner contract in one place: the system map and where every
  configuration axis lives (options, leaders, tunable constants, the carbon
  palette, lazy-load triggers, terminal ids and widths, LSP server lists), the
  WHY behind each load-bearing design decision, the invariants that must always
  hold, and the gates every change must pass before it is "done". Load this
  BEFORE editing anything in this repo — especially init.lua, lua/core/,
  lua/plugins/, install.sh/uninstall.sh or lazy-lock.json — and whenever you
  add, remove or disable a plugin, change a keymap, change a color, add a
  tunable, or ask "where is X configured", "what is the current value of Y",
  "can I change X without breaking Y", "why was it built this way", "am I
  allowed to do this", or "what must never regress". Covers the init.lua boot
  order, the core-vs-plugins-vs-distro-shell layering, why AI is a CLI in a
  terminal column rather than an editor plugin, why core modules are
  zero-dependency native Lua, the NVIM_APPNAME isolation model, the pinned
  lazy-lock restore-not-sync policy, the disk-wins autoreload trade-off, the
  carbon palette single-source rule, why the terminal focus cue is a winbar,
  why treesitter is the only syntax-color source, the ai-activity busy/idle
  signal chain, and the project's known weak points. Do NOT load it to debug a
  live failure (nvsinner-debugging-playbook), to read the full story of a
  settled incident (nvsinner-failure-archaeology), or for install and setup
  questions (nvsinner-build-and-run).
---

# The NvSinner contract

NvSinner is a personal Neovim 0.12+ config (lazy.nvim) grown into a
distributable "AI-terminal IDE": AI means a CLI agent running in a toggleterm
column, not an in-editor plugin. The owner's ambitions, in priority order:
(a) the deepest AI-agent/terminal integration of any distro, (b) native-first
Neovim — zero-dependency core modules over plugins, (c) distro engineering
rigor. Every decision below serves one of those three.

**Root `CLAUDE.md` is the authoritative manifest.** If this file and CLAUDE.md
disagree, CLAUDE.md wins and this skill needs the fix.

## When NOT to use this skill

| You want… | Go to |
|---|---|
| To diagnose a live symptom (frozen spinner, crash, silent no-op) | `nvsinner-debugging-playbook` |
| The full story of a settled incident, and what was tried and rejected | `nvsinner-failure-archaeology` |
| Deep Neovim theory (fast contexts, winbar evaluation, terminal buffers) | `neovim-internals-reference` |
| Install / launch / update / uninstall | `nvsinner-build-and-run` |
| To run or write tests, or to know what evidence a change needs | `nvsinner-testing-and-qa` |
| To prove a Neovim behavior claim empirically | `nvsinner-empirical-verification` |
| Doc style, which doc is the record, commit/PR shape | `nvsinner-docs-and-style` |
| What to build next | `nvsinner-frontier` |

---

## 1. The map

### Three layers

| Layer | Where | Nature |
|---|---|---|
| **Core native modules** | `lua/core/*.lua` (39 files) | Zero-dependency Lua `require`d before lazy. Not plugin specs; only `vim.*` / `vim.uv`. The AI workflow, the modals, the native replacements for retired plugins, and the distro shell helpers all live here. |
| **Plugin specs** | `lua/plugins/<category>/<name>.lua` | One plugin per file, each returning a lazy spec. Six categories: `ui/ lsp/ git/ editor/ navigation/ terminal/`. Lazy-loaded wherever possible; only `theme.lua` and `toggleterm.lua` are deliberately eager. |
| **Distro shell** | `bin/nvsinner`, `install.sh`, `uninstall.sh`, `lua/nvsinner/` | Makes the config an installable, named distribution. `bin/nvsinner` is one line: `exec env NVIM_APPNAME=nvsinner nvim "$@"`. `lua/nvsinner/health.lua` exists only so `:checkhealth nvsinner` resolves; it delegates to `core.health`. `lua/nvsinner/init.lua` holds the single semver source of truth. |

### Boot sequence (`init.lua`, 88 lines — read it, it is the spine)

1. **Bootstrap lazy.nvim** into `stdpath("data")/lazy`, prepend to `rtp`.
2. **`require("core.options")` FIRST** (`init.lua:24`). It sets `mapleader` and
   `maplocalleader`; lazy resolves `keys =` specs against the leaders at setup
   time, so a later require binds every `<leader>` plugin map to `\`. This is
   the single most fragile line in the boot.
3. **`require("core.settings")` third** — it seeds the carbon feature flags
   *before* the theme spec reads them.
4. **Then the other 30 core modules**, in the order `init.lua:24-57` lists.
   They are plain `require`s: they run now, before any plugin, and register
   autocmds and timers immediately.
5. **`lazy.setup` with six explicit imports** (`init.lua:63-68`).

Two core modules are NOT required from `init.lua`: `statusmark` (loaded by
`lualine.lua`) and `ts-compat` (called from the nvim-treesitter spec's
`config()`). `mouse` is a pure library, required on demand.

### Where every configuration axis lives

Values drift; the file does not. **Read the value, don't trust a copy** — each
row below is the place to look, and where a one-liner can regenerate the whole
table, that command *is* the documentation.

| Axis | Where | How to read it now |
|---|---|---|
| Leaders, core vim options, `timeoutlen`, `pumblend` | `lua/core/options.lua` | `grep -nE 'mapleader\|timeoutlen\|pumblend' lua/core/options.lua` |
| The one allowed `vim.cmd([[…]])` block | `lua/core/options.lua` | `grep -c 'vim.cmd' lua/core/options.lua` — expect 1 |
| Tunable constants per core module | top-of-file `local UPPER_CASE` | `grep -rnE '^local [A-Z_]+ =' lua/core/` |
| The carbon palette: roles, 10 themes, accent packs, folder packs, slots | `lua/core/carbon.lua` | `grep -nE '^M\.[a-z_]+ =\|^function M\.' lua/core/carbon.lua` |
| Persisted user settings (`:NvSinnerMenu`) | `lua/core/settings.lua` | `grep -n 'defaults\|M.get' lua/core/settings.lua` |
| Lazy-load triggers for every spec | each spec | `grep -nE 'event\s*=\|cmd\s*=\|keys\s*=\|ft\s*=\|lazy\s*=\|enabled\s*=' lua/plugins/*/*.lua` |
| Which specs are tombstones | each spec | `grep -lE '^\s{0,2}enabled = false' lua/plugins/*/*.lua` |
| Terminal ids, AI column width, layout repair | `lua/plugins/terminal/toggleterm.lua` | `grep -nE 'AI_WIDTH\|99 \+ n\|0\.20\|persist_mode' …` |
| LSP servers, capability surgery | `lua/plugins/lsp/lsp-config.lua` | `grep -nE 'ensure_installed\|vim.lsp.enable\|semanticTokensProvider\|automatic_enable' …` |
| Probed external tools | `lua/core/health.lua` | `grep -n 'name = ' lua/core/health.lua` |
| The distro version | `lua/nvsinner/init.lua` | one line, `version = "X.Y.Z"` |
| Every keybinding | `README.md` §Full keybindings reference | that table is the single source; don't fork it |

The handful of values worth stating because they are *calibrated*, not
arbitrary — re-read them before quoting:

- `timeoutlen = 300` (not Neovim's 1000). `<leader>t`, `<leader>j`,
  `<leader>jx` and `<leader>f` are strict prefixes of longer maps, so each
  waits this long before firing; 300 ms is the calibrated value (FA-25), and
  it is retunable at runtime via `settings.key_timeout` / `:NvSinnerMenu`.
- `POLL_MS = 120` / `IDLE_MS = 1200` in `ai-activity.lua`. `IDLE_MS` is a
  guess, not a measured constant — see *Known weak points*.
- `AI_WIDTH = 50` columns, fixed rather than percentual.
- `splitright` is load-bearing: it is why the AI column opens on the right.

---

## 2. Load-bearing decisions (each with its WHY)

### AI as a CLI in a terminal column — no in-editor AI plugin
avante and codecompanion were removed; there is no `lua/plugins/ai.lua`. The
CLI agent handles its own auth and billing (the config never reads
`ANTHROPIC_API_KEY`), its own model routing, its own tools — and a terminal
column is agent-agnostic where an editor plugin locks you to one vendor. The
editor's job shrinks to native supports: show the agent's activity
(`ai-activity`), reload what it writes (`autoreload`), make the column
first-class (`ui-touch`, `toggleterm`), and carry context in
(`ai-sessions`, `ai-ask`). Story: FA-11.

The one exception is `lua/core/ai-complete.lua`'s opt-in inline completion —
still not a plugin: native Lua, `curl` to **OpenCode Zen only**, reading
`$OPENCODE_API_KEY` from the env at request time, never a stored key.

### Native-first core modules (zero dependencies on purpose)
Core modules use no plugin — only `vim.api`, `vim.uv`, autocmds and
statusline/winbar expressions. Why: they must exist before lazy loads anything
(they wire `TermOpen`/`WinEnter` autocmds that must catch the *first*
terminal), they must never break because a plugin changed an API, and they are
the differentiating layer. The cost is accepted: more code to maintain. Nine
plugins have since been replaced by core modules outright, each keeping its
spec as a tombstone.

### NVIM_APPNAME isolation
NvSinner runs as `NVIM_APPNAME=nvsinner`: config `~/.config/nvsinner`, its own
data/state/cache. It installs on any machine without clobbering an existing
`~/.config/nvim`, and uninstall is a clean rm of four XDG dirs. On the dev
machine `~/.config/nvsinner` is a **symlink** to this repo. Consequences that
shape other code: `uninstall.sh` must unlink, never follow, that symlink;
`core/update.lua` must no-op with a warning when the config dir has no `.git`.

### Pinned `lazy-lock.json` + restore-not-sync
`install.sh` and `:NvSinnerUpdate` both run `Lazy! restore`, never `sync`.
`restore` checks every plugin out to the commit pinned in the committed
lockfile, so every install and update reproduces the tested plugin set.
`:NvSinnerSync` is the one deliberate opt-in "float to latest" path, and it
rewrites the lockfile — retest and commit it. The lockfile is the tested
artifact, not a byproduct.

A tombstoned plugin **keeps its lockfile entry**, so flipping `enabled = true`
lands on the tested commit rather than whatever is latest. Pinned by
`tests/plugins/tombstone_lock_spec.lua`.

### Disk-wins autoreload (the viewer-style trade-off)
`autoreload.lua`: `autoread` + `FileChangedShell` forcing
`v:fcs_choice = "reload"` + `checktime` on focus events + a 1s `vim.uv` timer
(terminal mode has no `CursorHold`, so without the timer the code pane wouldn't
refresh while you sit in the AI column). Why disk wins: in the intended
workflow the *agent* is the editor and Neovim is the viewer; a W11/W12 prompt
on every agent write would make it unusable. The cost is real and accepted:
unsaved in-Vim edits to a file the agent rewrites are silently discarded. A
toast fires on `FileChangedShell` **and** `FileChangedShellPost` because with
`autoread` on and the buffer unmodified — the common case — Neovim reloads
silently and fires only the Post event (verified empirically).

### Carbon palette — one role table, semantic accents
The theme is **carbon**, a native oxocarbon / IBM Carbon port; it replaced the
kanagawa-dragon "glass" theme on **2026-07-03**. One base16 role table defined
ONCE in `lua/core/carbon.lua`; `colors/carbon.lua` is the colorscheme, and
every consumer requires the module and references roles. Raw hexes never
appear in consumers.

Accents are semantic — blue = identity/active, magenta = modified/attention,
pink = the busy chip, light blue = focused terminal bar — so the whole UI reads
as one instrument panel and each colored pixel means exactly one thing.
Off-palette plugin defaults (incline's blue, barbecue's tokyonight colors) were
removed for this reason.

**Do not quote hex values in docs.** There are 10 themes × 4 accent packs; a
literal is right for at most one of them, and hardcoded hexes in prose are what
produced the 2026-07 documentation drift. `grep` the role out of
`lua/core/carbon.lua`, or run
`.claude/skills/nvsinner-testing-and-qa/scripts/palette-audit.sh`, which
derives the whitelist from that file and so cannot go stale.

### Winbar as the terminal focus cue (not a separator)
The focused terminal gets a full-width `winbar` plus a brighter separator;
unfocused terminals keep the bar but dim. Why a bar: a 1px split line was too
faint on the near-black bg. Why always present: adding or removing a winbar
changes window height and reflows the terminal's scrollback, so it stays
permanent and only the highlight changes — zero reflow. Why the dim bar keeps
a readable fg (fg ≠ bg): it carries live content (the activity label) that must
stay legible when unfocused. Story: FA-06.

### Treesitter as the single syntax-color source
The `vim.lsp.config("*")` `on_attach` nils
`client.server_capabilities.semanticTokensProvider`. Without it, ~1s after a
file opens the LSP's semantic tokens (`@lsp.*`) repaint the buffer on top of
treesitter and flatten the palette. Two supporting decisions hang off this:
the config uses the native `vim.lsp.config` / `vim.lsp.enable` API (0.11+),
never `require("lspconfig").<server>.setup()`; and `mason-lspconfig` runs with
`automatic_enable = false` so it can never start a server *before* the `"*"`
config lands. Enable order is part of the contract, not a style choice.

### The nvim-treesitter pin and its compensating control
The spec pins `branch = "master"`: `main` is a full rewrite needing the
tree-sitter CLI (FA-24). That pin freezes a plugin predating Neovim 0.12's
query API, so `lua/core/ts-compat.lua` re-registers its query directives for
0.12's list-valued `match[id]`. **The pin and the shim are one unit — remove
one and you must remove the other.**

This also retired the old "0.12 markdown crash" workarounds. There is no
`after/ftplugin/markdown.lua` and no markdown highlight disable; the crash was
this frozen master, not Neovim. noice's LSP hover/signature stay off *pending
their own evaluation*, which is a different reason — don't restate the crash
as their justification.

### The ai-activity signal chain
"Is the agent working or idle?" is answered by **output flow**, not process
inspection — CLI-agnostic by design.

```
TermOpen → nvim_buf_attach(buf).on_lines     -- fires on every output chunk
  → plain Lua state table only                -- fast event context: no vim.* API
  → vim.uv timer (POLL_MS)                    -- animates, flips busy→idle after
      IDLE_MS of quiet; handle pinned on M._timer so luv can't GC it.
      Busy-gated: on_lines starts it, tick() stops it once nothing is busy.
  → nvim__redraw{statusline,winbar,flush}     -- NOT :redrawstatus
  → per-window winbar expression built by ui-touch.lua:
      %{%v:lua.require'core.ai-activity'.winbar(<buf>)%}
      -- buffer number BAKED IN: g:statusline_winid is not set during
      -- winbar evaluation, so the expression must be told its buffer
```

Why each link: `on_lines` because polling `b:changedtick` on a terminal buffer
is unreliable; timer-side redraws because the fast-context callback may not
call `vim.*`; `nvim__redraw` because `:redrawstatus` skips the winbar when
focus is inside a terminal. Each rejected alternative was disproven in a real
render — see FA-01…FA-07 and `nvsinner-empirical-verification`. There are three
states, not two: busy, idle, and **awaiting input**.

---

## 3. Invariants (must always hold)

Line numbers drift; the greps in §1 don't. Verify, don't trust the column.

| # | Invariant | Breaks if violated |
|---|---|---|
| 1 | `core.options` is the first require in `init.lua`, before `lazy.setup` | Every `<leader>` plugin keymap binds to `\` |
| 2 | `core.settings` is required before the theme spec reads the carbon flags | The theme boots on defaults, then flips |
| 3 | Every `lua/plugins/<category>/` folder has a matching `{ import = … }` in `init.lua` | That category's plugins silently never load — no error |
| 4 | Every color consumer references `lua/core/carbon.lua` roles; no literal hexes outside it and the dashboard ramp | An inline hex forks the palette and is wrong for 9 of the 10 themes |
| 5 | toggleterm ids: AI panels reserve `99 + n` (100–108); horizontals use 1–9 | An AI panel claims id 1 and `<leader>t` re-toggles the AI column (FA-08) |
| 6 | The `on_lines` callback touches only the plain Lua state table + `uv.now()` — never `vim.*` | Errors or corruption inside libuv callbacks |
| 7 | The terminal winbar expression bakes the buffer number in; winbar code never relies on `vim.g.statusline_winid` | Bar renders empty in real use (FA-02) |
| 8 | The ai-activity timer handle stays referenced on `M._timer` | luv GCs it; the spinner silently freezes (FA-05) |
| 9 | `NvTermBarDim` fg ≠ bg | The idle/working label is invisible on unfocused terminals (FA-06) |
| 10 | Semantic tokens stay nilled in the `"*"` `on_attach`, and `mason-lspconfig` keeps `automatic_enable = false` | `@lsp.*` repaint returns ~1s after open |
| 11 | The nvim-treesitter `branch = "master"` pin and `core/ts-compat.lua` are added and removed together | Query directives break on 0.12 (FA-24) |
| 12 | Install/update paths use `Lazy restore` against the committed lockfile, never `sync` | Installs float to untested plugin versions |
| 13 | A tombstoned plugin keeps its `lazy-lock.json` entry | Re-enabling it lands on an untested commit |
| 14 | toggleterm keeps `persist_mode = false` | One `<Esc>` makes every later focus of that column need an `i` |
| 15 | Headless runs never consume the health first-run marker (`setup()` bails when there are no UIs) | Installer and tests eat the greeting |
| 16 | `uninstall.sh` unlinks a symlinked config dir, never follows into its target | Uninstalling on the dev machine deletes the source repo |

---

## 4. Change classification

Classify first; the class determines the owner constraints and the gates.

| Class | Paths | Owner agent |
|---|---|---|
| **Plugin spec** | `lua/plugins/<category>/` | `.claude/agents/nvim-<category>.md` |
| **Core module** | `lua/core/`, `lua/nvsinner/`, `init.lua` | `nvim-core.md` |
| **Release** | `lua/nvsinner/init.lua` version line, `NVSINNER.md` | `nvim-release.md` |
| **Distro script** | `install.sh`, `uninstall.sh`, `bin/nvsinner`, `Makefile`, `lazy-lock.json` | none — highest blast radius, runs on strangers' machines |
| **Docs** | every `.md` | none — English only; see `nvsinner-docs-and-style` |

- A change under `lua/X` follows that category owner's constraints **even when
  you edit it yourself** instead of delegating. Read the agent file first.
- Cross-category changes (a palette change touching both a UI spec and a core
  module) must satisfy BOTH owners' constraints.
- `init.lua` changes are almost always a side effect of another class (a new
  core require, a new category import). Gate them as part of that change.
- If a task appears to require breaking a rule here, **stop and surface the
  conflict** instead of routing around it. Do not invent new rules either —
  CLAUDE.md is the complete discipline set.

---

## 5. Gates — what "done" requires

**Gate 1 — syntax check every edited Lua file** (fast, no network):
```bash
nvim --headless -c "lua assert(loadfile('lua/<path>.lua'))" -c "qa"
```
Silence = pass.

**Gate 2 — headless boot, surface startup errors:**
```bash
.claude/skills/nvsinner-testing-and-qa/scripts/boot-check.sh
```

**Gate 3 — plugin set changed?** Install with `+Lazy! restore`. Only
`:NvSinnerSync` (or a deliberate local `Lazy sync`) may float to latest, and
then you retest and commit the new `lazy-lock.json`. **Never put `Lazy! sync`
in a validation step** — it rewrites the lockfile as a side effect of checking.

**Gate 4 — test suite** (mandatory for core-module and behavioral changes):
```bash
make test
make test-file FILE=tests/core/options_spec.lua
```
Behavior a spec covers must be updated in the same change; new user-visible
behavior in `lua/core/` gets a new spec.

**Gate 5 — doc sync.** CLAUDE.md is the manifest: any new or changed keymap,
subsystem behavior, convention or tool requirement is reflected there, and
keymaps also in README.md's "Full keybindings reference".

**Gate 6 — formatting:** `stylua --check lua/ tests/`.

**What runs without you.** `.github/workflows/ci.yml` re-runs Gate 2 and Gate 4
on every PR and every push to `main`, on a clean machine against the pinned
lockfile. `.githooks/pre-push` runs `stylua --check` + `make test` locally —
but **only if you opted in with `git config core.hooksPath .githooks`**.
Nothing wires it for you; `install.sh` does not. So: CI never checks
formatting, CI is `ubuntu-latest` × `{v0.12.0, stable}` with no macOS and no
nightly, and CI symlinks the checkout to `~/.config/nvim`, so the
`NVIM_APPNAME=nvsinner` path is never exercised.

### Pre-merge checklist

| # | Check |
|---|---|
| 1 | Change classified; owner-agent file read |
| 2 | New category folder → `{ import = … }` added to `init.lua` |
| 3 | New core module → `require`d from `init.lua` in the right position |
| 4 | New plugin lazy-loaded, or `lazy = false` justified inline |
| 5 | No literal hexes; `palette-audit.sh` clean |
| 6 | No forbidden reintroductions: lspconfig `.setup()`, noice LSP markdown, mini.animate scroll, gitsigns line blame, semantic tokens, terminal-mode `jk`, a second diff exit key |
| 7 | Disabled plugins kept with `enabled = false` **and** their lockfile entry |
| 8 | Terminal ids: AI 100+, horizontals 1–9 untouched |
| 9 | All comments and all markdown in English; Lua only |
| 10 | Gates 1, 2, 4, 6 run and green |
| 11 | Gate 5: CLAUDE.md and README tables synced |
| 12 | Cross-category effects flagged |

---

## 6. Known weak points (plainly)

- **Disk-wins can destroy work.** Unsaved in-Vim edits to any buffer the agent
  rewrites are discarded with no undo prompt — by design, but there is no
  guard and no "buffer was modified" escalation. The toast tells you after.
- **The busy/idle detector is an output heuristic.** Any terminal output =
  busy; `IDLE_MS` of quiet = idle. It cannot distinguish real work from the
  agent's own cosmetic spinner redraws, and it goes idle during any silent
  compute pause longer than the threshold. `IDLE_MS = 1200` is a guess. This is
  the owner's stated hardest live problem.
- **`timeoutlen` lag is mitigated, not eliminated.** Keeping 9 numbered
  terminals and 9 AI sessions on two prefixes means the bare press can never be
  instant, only fast. The residual trade-off is the user's to set: too low and
  `<leader>t3` opens terminal 1. See FA-25.
- **Doc drift is the live failure mode.** Code-side palette duplication was
  retired in 2026-07 — every consumer pulls roles — but doc-side sync stayed
  manual and **did** drift: 12 of 13 skills carried `Facts verified:
  2026-07-02`, one day before the carbon migration, and quoted dead hexes for
  months. The structural answer is in §1: state where a value lives and how to
  read it, never a frozen copy.
- **Nightly and macOS are unexercised.** CI runs the declared floor and current
  stable on ubuntu only, and nightly is exactly where the crash class lives.
- **Layout determinism depends on a repair function.** `restore_layout()` in
  `toggleterm.lua` re-asserts the split geometry after every panel open because
  toggleterm's own placement is order-dependent — a workaround, not a fix.

---

## Provenance and maintenance

**Facts verified: 2026-09-19**, against the working tree by direct file read.
This skill replaces `nvsinner-architecture-contract`, `nvsinner-change-control`
and `nvsinner-config-catalog`, which stated the same facts three times and
drifted independently.

It deliberately holds **no** frozen value tables. Every axis in §1 carries the
command that regenerates it; the palette has `palette-audit.sh`. When you find
a fact here that a command could have produced, replace the fact with the
command.

Re-verification:
```bash
grep -nE 'require\("core\.|import = ' init.lua      # boot order + imports
grep -c 'vim.cmd' lua/core/options.lua              # expect 1
.claude/skills/nvsinner-testing-and-qa/scripts/palette-audit.sh
.claude/skills/nvsinner-testing-and-qa/scripts/boot-check.sh
grep -n 'restore' install.sh lua/core/update.lua    # never `sync`
grep -n 'persist_mode' lua/plugins/terminal/toggleterm.lua
make test
```
