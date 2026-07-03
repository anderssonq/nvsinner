---
name: nvsinner-change-control
description: >
  NvSinner's change-control doctrine: how to classify a change (plugin spec vs
  core module vs distro script vs docs), which owner-agent constraints apply,
  the project's non-negotiable rules with their rationale and incident history,
  and the exact validation gates + pre-merge checklist every change must pass.
  Load this BEFORE editing anything in this repo — especially before touching
  init.lua, lua/core/, lua/plugins/, install.sh/uninstall.sh, or lazy-lock.json,
  and whenever you are about to add/remove/disable a plugin, change a keymap,
  change a color, or declare a change "done". Do NOT load it for debugging a
  live failure (nvsinner-debugging-playbook), for understanding why the design
  is shaped this way (nvsinner-architecture-contract), for writing new tests
  (nvsinner-testing-and-qa), or for install/setup questions
  (nvsinner-build-and-run).
---

# NvSinner change control

This is the gatekeeping skill: what kind of change you are making, what you may
never do while making it, and what must pass before you call it done.
CLAUDE.md is the authoritative manifest — if this file and CLAUDE.md ever
disagree, CLAUDE.md wins and this skill needs the fix.

## When NOT to use this skill

| You are trying to… | Use instead |
|---|---|
| Diagnose a live symptom (frozen spinner, crash, silent no-op) | **nvsinner-debugging-playbook** |
| Read the full story behind a settled incident | **nvsinner-failure-archaeology** |
| Understand load-bearing design decisions / invariants | **nvsinner-architecture-contract** |
| Learn the Neovim internals a rule depends on (winbar eval, fast events, …) | **neovim-internals-reference** |
| Add or tune a config axis (option, keymap, tool) | **nvsinner-config-catalog** |
| Install, update, or uninstall the distro; env setup | **nvsinner-build-and-run** |
| Write or extend plenary specs | **nvsinner-testing-and-qa** |
| Match house doc style / know which doc is the record | **nvsinner-docs-and-style** |
| Work the terminal/agent-UX improvement campaign | **nvsinner-terminal-ux-campaign** |
| Prove a behavioral claim empirically before relying on it | **nvsinner-empirical-verification** |

## 1. Change classification

Every change falls into exactly one primary class. Classify first; the class
determines the owner constraints and which gates are mandatory.

| Class | Paths | Owner agent (`.claude/agents/`) | Notes |
|---|---|---|---|
| **Plugin spec** | `lua/plugins/ui/` | `nvim-ui.md` | Theme, chrome, notifications, animations, dashboard, which-key |
| | `lua/plugins/lsp/` | `nvim-lsp.md` | Servers, completion, formatting, diagnostics UI, neoconf |
| | `lua/plugins/git/` | `nvim-git.md` | gitsigns, git-blame, diffview |
| | `lua/plugins/editor/` | `nvim-editor.md` | autopairs, comment, surround, todo-comments, treesitter |
| | `lua/plugins/navigation/` | `nvim-navigation.md` | telescope, neo-tree, window-picker, leap |
| | `lua/plugins/terminal/` | `nvim-terminal.md` | toggleterm (AI columns + terminals), persistence |
| **Core module** | `lua/core/`, `lua/nvsinner/` (thin checkhealth shim), `init.lua`, `after/ftplugin/` | `nvim-core.md` (for `lua/core/`) | Native, zero-dep modules `require`d from `init.lua` — NOT lazy specs |
| **Distro script** | `install.sh`, `uninstall.sh`, `bin/nvsinner`, `Makefile`, `lazy-lock.json` | none — no owner agent | Highest blast radius: runs on strangers' machines |
| **Docs** | `CLAUDE.md`, `README.md`, `NVSINNER.md`, `TODO.md` | none | English only; see **nvsinner-docs-and-style** |

Rules of routing:

- **A change under `lua/X` follows that category's owner agent's constraints**
  even when you edit the file yourself instead of delegating. Read the matching
  `.claude/agents/nvim-*.md` before editing — each one carries hard
  constraints (e.g. `nvim-core.md` forbids switching the mouse-hover float to
  markdown) and its own validate-before-done commands.
- Cross-category changes (e.g. a palette change touching both
  `lua/plugins/ui/theme.lua` and `lua/core/ui-touch.lua`) must satisfy BOTH
  owners' constraints; the agent files explicitly tell the editor to flag
  cross-category effects.
- `init.lua` changes are almost always a side effect of another class (new
  core `require`, new category import). Treat them as part of that change and
  gate accordingly.
- Distro scripts and docs have no owner agent; the gates in section 3 and the
  conventions in CLAUDE.md are the whole discipline. Do not invent additional
  unwritten rules.

## 2. Non-negotiables

Each rule below exists because something broke. One-line incident here;
full stories live in **nvsinner-failure-archaeology**.

### Load order & structure

1. **`core/options.lua` is required FIRST in `init.lua`, before `lazy.setup`.**
   Rationale: it sets `<leader>` (Space) and `<localleader>` (`\`); lazy.nvim
   resolves `keys =` specs against the leaders at setup time, so a later
   require would bind every leader keymap to the default backslash leader.
   Current order (verified in `init.lua`): options → keymaps → autoreload →
   ui-touch → ai-activity → update → health → `lazy.setup`.
2. **One plugin per file** in `lua/plugins/<category>/`, returning a lazy spec
   (or list of specs). Enforced by test:
   `tests/plugins/plugin_specs_spec.lua` loads every `lua/plugins/**/*.lua`
   and validates the return shape.
3. **lazy.nvim's `import` does NOT recurse into subfolders.** A new category
   folder needs its own `{ import = "plugins.<category>" }` line in
   `init.lua`, or every file in it silently never loads — no error, the
   plugins just don't exist. Existing imports: `plugins.ui`, `plugins.lsp`,
   `plugins.git`, `plugins.editor`, `plugins.navigation`, `plugins.terminal`.
4. **All Lua, no Vimscript.** The single `vim.cmd([[ ... ]])` block in
   `lua/core/options.lua` (line 10) is the only exception and **must not
   grow**.
5. **English-only comments and English-only markdown** (README, CLAUDE.md,
   NVSINNER.md, everything `.md`). Single language standard, per CLAUDE.md.
6. **Disable plugins with `enabled = false`; do not delete the file.** Keeps a
   one-line revert. Live example: `lua/plugins/ui/cursorline.lua` is kept
   disabled because it duplicated illuminate and fought ui-touch.

### Lazy-loading & startup

7. **Lazy-load by default** — every new plugin gets `event` / `cmd` / `keys` /
   `ft`. The only sanctioned exception is `lazy = false, priority = 1000` for
   things that must theme the UI at startup (see `lua/plugins/ui/theme.lua`).
   Rationale: startup cost stays ~zero and the dashboard is instant.

### Palette & UI chrome

8. **One palette, one accent — never introduce off-palette colors.** The
   palette: bg `#0a0a0f`, glass `#111118`, FG `#c5c9d5`, muted `#7a7f8d`,
   single accent kanagawa dragonRed `#c4746e`. Incident: incline shipped its
   default blue and barbecue its tokyonight defaults; both were explicitly
   recolored out (`.tmp/06-28-26_01_nvim-config-restructure-PR-DESCRIPTION.md`).
9. **The palette is duplicated in `lua/plugins/ui/theme.lua` and
   `lua/core/ui-touch.lua` (`apply_hl()`), and the two copies must stay in
   sync.** Both re-apply on `ColorScheme` so lazy-loaded plugins can't clobber
   them. Any palette edit is by definition a cross-category change (rule in
   section 1).
10. **Treesitter is the single source of syntax color.** The `"*"` LSP
    config's `on_attach` in `lua/plugins/lsp/lsp-config.lua` nils
    `client.server_capabilities.semanticTokensProvider`; removing that line
    lets `@lsp.*` semantic tokens repaint the buffer ~1s after open and
    flatten the treesitter palette. Related ordering rule:
    `mason-lspconfig` runs with `automatic_enable = false` on purpose — the
    config enables servers itself via `vim.lsp.enable` *after* the `"*"`
    config (with that `on_attach`) lands, otherwise a server can attach before
    the nil and the repaint comes back.

### LSP & 0.12.x hazards

11. **Never reintroduce `require("lspconfig").<server>.setup()`.** Deprecated;
    this config uses the Neovim 0.11 native API only:
    `vim.lsp.config("*", …)` + `vim.lsp.enable({ "ts_ls", "solargraph",
    "html", "lua_ls" })` (verified in `lua/plugins/lsp/lsp-config.lua`).
12. **Do not enable noice's LSP hover/signature (markdown) paths.**
    `lua/plugins/ui/noice.lua` sets `hover = { enabled = false }` and
    `signature = { enabled = false }` because the markdown treesitter
    highlighter crashes transient floats on Neovim 0.12.x — the same crash
    that forced the live 3-file workaround (`after/ftplugin/markdown.lua` +
    treesitter/telescope disables). `ui-touch.lua`'s mouse hover renders
    plain text for the same reason. Removing the workaround is gated on the
    upstream fix — one-liner in **nvsinner-failure-archaeology**.

### Single-owner subsystems (no doubling up)

13. **Scroll animation belongs to neoscroll** (`lua/plugins/ui/smooth-scroll.lua`).
    `lua/plugins/ui/mini-animate.lua` keeps `scroll = { enable = false }`;
    enabling both double-animates every scroll.
14. **Inline blame belongs to git-blame.nvim; popup blame to gitsigns.** Do
    not enable gitsigns' `current_line_blame` — it would duplicate the
    always-on inline blame.

### Distro discipline

15. **Update/install paths use `Lazy! restore` against the committed
    `lazy-lock.json`, NOT `Lazy! sync`.** Both `:NvSinnerUpdate`
    (`lua/core/update.lua`, `require("lazy").restore()`) and `install.sh`
    (`+Lazy! restore`) pin every plugin to the tested commit; `:Lazy sync` is
    the developer's opt-in "float to latest" path. If you intentionally bump
    plugins, run sync locally, retest, and commit the new `lazy-lock.json`.
16. **AI panels keep reserved toggleterm ids 100+** (session N → `id = 99 + N`
    in `lua/plugins/terminal/toggleterm.lua`); horizontal terminals own ids
    1–9. Incident (commit `220a897`): the AI panel auto-claimed id 1 on first
    open, so the horizontal-terminal keymap just re-toggled the AI panel
    instead of opening a terminal.

If a task appears to require breaking any rule above, stop and surface the
conflict to the user instead of routing around it. The written rules in
CLAUDE.md are the complete discipline set — do not invent new ones, and do not
drop these.

## 3. Gates — what "done" requires

Run from the repo root. All commands below were executed and verified passing
on 2026-07-02.

**Gate 1 — syntax check every edited Lua file** (fast, no network):

```bash
nvim --headless -c "lua assert(loadfile('lua/plugins/<category>/<file>.lua'))" -c "qa"
# core files identically: lua/core/<file>.lua
```

Silence = pass; a Lua syntax error prints and aborts.

**Gate 2 — headless boot, surface startup errors:**

```bash
nvim --headless -c "lua vim.defer_fn(function() vim.cmd('messages'); vim.cmd('qa') end, 300)"
```

Output must contain no `E`-errors / stack traces. (CLAUDE.md's install docs use
a 500ms defer for cold boots; 300ms is the documented validating-changes form.)

**Gate 3 — plugin install/build** (only when the plugin set changed):

```bash
nvim --headless "+Lazy! sync" +qa    # adding/bumping plugins: installs + rewrites lazy-lock.json
```

Adding a plugin means `lazy-lock.json` changes — commit it, since restore-based
updates (non-negotiable 15) reproduce exactly what's in the lockfile.

**Gate 4 — test suite** (mandatory for core-module and behavioral changes):

```bash
make test                                          # whole suite (passes: 0 failed, 0 errors)
make test-file FILE=tests/core/options_spec.lua    # one spec during iteration
```

If you changed behavior that a spec covers (see the spec table in CLAUDE.md
*Tests*), the spec must be updated in the same change; new user-visible
behavior in `lua/core/` gets a new spec. Conventions and evidence standards:
**nvsinner-testing-and-qa**.

**Gate 5 — doc sync.** CLAUDE.md is the manifest: any new/changed keymap,
subsystem behavior, convention, or tool requirement must be reflected there
(and keymaps also in README.md's "Full keybindings reference"). New plugin →
README plugin table. Style and the full doc-sync checklist:
**nvsinner-docs-and-style**.

Interactive spot-checks when relevant: `:Lazy`, `:Mason`,
`:checkhealth nvsinner`. Install/update flow details (install.sh anatomy,
`:NvSinnerUpdate`, uninstall traps): **nvsinner-build-and-run**.

## 4. Pre-merge checklist

| # | Check | How |
|---|---|---|
| 1 | Change classified; owner-agent file read (`.claude/agents/nvim-*.md`) | Section 1 table |
| 2 | New category folder? → `{ import = "plugins.<category>" }` added to `init.lua` | Non-negotiable 3 |
| 3 | New core module? → `require`d from `init.lua` AFTER `core.options` | Non-negotiable 1 |
| 4 | New plugin lazy-loaded (`event`/`cmd`/`keys`/`ft`) or justified `lazy=false, priority=1000` | Non-negotiable 7 |
| 5 | No off-palette colors; palette edits mirrored in theme.lua AND ui-touch.lua | Non-negotiables 8–9 |
| 6 | No forbidden reintroductions: lspconfig `.setup()`, noice LSP md, mini.animate scroll, gitsigns line blame, semantic tokens | Non-negotiables 10–14 |
| 7 | Disabled plugins kept with `enabled = false`, not deleted | Non-negotiable 6 |
| 8 | Terminal ids: AI 100+, horizontals 1–9 untouched | Non-negotiable 16 |
| 9 | All comments and all markdown in English; Lua only | Non-negotiables 4–5 |
| 10 | Gate 1: `loadfile` check on every edited Lua file | Section 3 |
| 11 | Gate 2: headless boot clean | Section 3 |
| 12 | Gate 3: `Lazy! sync` run + `lazy-lock.json` committed (only if plugin set changed) | Section 3 |
| 13 | Gate 4: `make test` green; specs updated/added for behavior changes | Section 3 |
| 14 | Gate 5: CLAUDE.md synced; README keymap/plugin tables synced | Section 3 |
| 15 | Cross-category effects flagged (palette, keymaps, init.lua) | Section 1 |

## Provenance and maintenance

**Facts verified: 2026-07-02** — by direct file inspection, `git show`, and by
running Gates 1, 2, and 4 in this repo (all passed; `make test`: 0 failed,
0 errors).

Re-verification one-liners for anything that may drift:

- Core require order + category imports: `sed -n '18,43p' init.lua`
- Owner-agent roster: `ls .claude/agents/`
- Semantic tokens nil / automatic_enable / native enable list: `grep -n "semanticTokensProvider\|automatic_enable\|vim.lsp.enable" lua/plugins/lsp/lsp-config.lua`
- Noice hover/signature still off: `grep -n "enabled = false" lua/plugins/ui/noice.lua`
- mini.animate scroll still off: `grep -n "scroll" lua/plugins/ui/mini-animate.lua`
- Palette copies in sync: `grep -n "#0a0a0f\|#111118\|#c4746e\|#7a7f8d" lua/plugins/ui/theme.lua lua/core/ui-touch.lua`
- Reserved AI ids: `grep -n "99 + n\|id = n" lua/plugins/terminal/toggleterm.lua`
- Update uses restore: `grep -n "restore" lua/core/update.lua install.sh`
- Single vim.cmd exception: `grep -c "vim.cmd" lua/core/options.lua` (expect 1)
- 0.12.x markdown workaround still present (remove rule 12's caveat when upstream fixes): `ls after/ftplugin/markdown.lua`
- Id-collision incident: `git show 220a897 --stat`
- Suite still green: `make test`
