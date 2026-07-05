# CLAUDE.md

Guidance for Claude Code (and other agents) working in this repository.

## What this is

A personal Neovim configuration managed with **lazy.nvim**, extended into a
Cursor-like AI terminal IDE. Target editor: **Neovim 0.11+** (hard requirement —
uses `vim.uv` and the native `vim.lsp.config` / `vim.lsp.enable` API). There are
no in-editor AI plugins — AI is used by running a CLI agent (e.g. `claude`) in a
toggleterm terminal column.

It ships as the **NvSinner** distribution: it runs under its own
`NVIM_APPNAME=nvsinner` (config `~/.config/nvsinner`, isolated
data/state/cache), so it coexists with any other `~/.config/nvim`. On the dev
machine `~/.config/nvsinner` is a **symlink** to this repo (`~/.config/nvim`),
so both `nvim` and `nvsinner` load the same files.

This repo is already installed and running. For a from-scratch install (system
prerequisites, plugin bootstrap, fonts, AI CLI) and the `install.sh` /
`uninstall.sh` anatomy, see [docs/installation.md](docs/installation.md).

## Layout

```
init.lua                     Bootstraps lazy.nvim, requires lua/core/*, imports the plugin folders
colors/carbon.lua            The "carbon" colorscheme (oxocarbon/IBM Carbon port, self-contained)
lua/core/options.lua         Leaders + core vim options (required FIRST, before lazy)
lua/core/settings.lua        Persistent :NvSinnerMenu settings (JSON in settings/) — seeds the carbon flags at boot (native)
lua/core/menu.lua            :NvSinnerMenu — Mason-style settings modal over core/settings (native)
lua/core/prompts.lua         :NvSinnerPrompts — prompt-library modal over settings/prompts.json → OS clipboard (native)
lua/core/help.lua            :NvSinnerHelp — command palette listing every NvSinner command; pick one to run it (native)
lua/core/symbols.lua         :NvSinnerSymbols / <leader>cs — LSP document-symbols modal; pick a symbol to jump to it (native)
lua/core/backdrop.lua        Dimming backdrop behind the NvSinner modals (full-screen winblend float, auto-closes with the modal) (native)
settings/prompts.json        The prompt library (committed, user-editable); settings/ also holds the gitignored :NvSinnerMenu cache
lua/core/carbon.lua          Carbon base16 role palette + accent packs — the ONE source of truth for every color
lua/core/keymaps.lua         Global keymaps: save/undo/redo, folds, split-resize, buffers
lua/core/autoreload.lua      AI-workflow: disk auto-reload + terminal auto-insert on focus
lua/core/ai-edits.lua        Underlines AI-written lines after a disk reload, until the user takes over (native)
lua/core/ui-touch.lua        Active-window border/glow + mouse-hover docs (native)
lua/core/filebadge.lua       Per-window winbar file badge: focus dot + filename; hosts the markdown "Open view" chip (native, replaces incline)
lua/core/ai-activity.lua     Agent/terminal activity spinner in the terminal winbar (native)
lua/core/ai-sessions.lua     AI session registry + send-to-AI bridge (native)
lua/core/ai-ask.lua          :NvSinnerAskAI + visual <leader>x — Ask-AI action modal over the selection (native)
lua/core/update.lua          :NvSinnerUpdate — git pull + Lazy restore + checkhealth (native)
lua/core/sync.lua            :NvSinnerSync — opt-in Lazy sync + Mason package updates (native)
lua/core/health.lua          Missing-externals detection: :checkhealth nvsinner + one-time first-run toast (native)
lua/core/image-open.lua      Open image files in macOS Quick Look + metadata placeholder (native)
lua/core/git-blame.lua       Inline git blame for the cursor line, async porcelain → eol virt_text (native, replaces git-blame.nvim)
lua/core/illuminate.lua      Symbol-occurrence underline: LSP document_highlight + visible-range fallback (native, replaces vim-illuminate)
lua/core/sessions.lua        :mksession sessions per cwd — :NvSinnerSession*, <leader>Sc/Sl/SQ (native, replaces persistence.nvim)
lua/core/indent.lua          Current-scope indent guide: decoration-provider overlay (native, replaces indentmini.nvim)
lua/core/colorizer.lua       #hex color chips on the visible range (native, replaces nvim-colorizer)
lua/core/todo.lua            TODO:/FIXME:… keyword chips on the visible range (native, replaces todo-comments.nvim)
lua/core/window-picker.lua   Letter-overlay window picker; serves require("window-picker") for neo-tree (native, replaces nvim-window-picker)
lua/nvsinner/health.lua      Thin provider so :checkhealth nvsinner resolves (delegates to core.health)
lua/plugins/<category>/<name>.lua   One plugin (or small related group) per file; each returns a lazy spec
```

`init.lua` requires the `lua/core/*` modules (options first, so the leaders are
set before lazy reads any `keys` spec) and then calls `lazy.setup`.

Plugin specs are grouped into **category subfolders** under `lua/plugins/`:

| Folder | What lives there |
|--------|------------------|
| `ui/` | theme, statusline/chrome, notifications, animations, cursor/symbol highlighting, which-key |
| `lsp/` | language servers, completion, formatting, diagnostics UI, neoconf |
| `git/` | diffview, git-blame, gitsigns |
| `editor/` | text editing & syntax: autopairs, comment, surround, todo-comments, treesitter |
| `navigation/` | telescope, neo-tree, window-picker, leap |
| `terminal/` | toggleterm (AI columns + terminals), persistence (sessions) |

**lazy.nvim's `import` does NOT recurse into subfolders**, so `init.lua` imports
each category explicitly: one `{ import = "plugins.<category>" }` per folder
above. **When you add a new category folder, add a matching `{ import = ... }`
line to `init.lua`** or its files will silently never load.

## Conventions (follow these when editing)

- **All Lua, no Vimscript** (the one `vim.cmd([[ ... ]])` options block in
  `core/options.lua` is the only exception and should not grow).
- **Comments in English.**
- **All markdown files (.md) in English** — including README, CLAUDE.md,
  NVSINNER.md, etc. This keeps documentation accessible and maintains a single
  language standard across the project.
- **One plugin per file** in the appropriate `lua/plugins/<category>/` folder,
  returning either a spec table or a list of spec tables. New files in an
  existing category folder are picked up automatically; a brand-new category
  folder needs its own `{ import = "plugins.<category>" }` line in `init.lua`
  (see *Layout*).
- **Lazy-load** new plugins via `event` / `cmd` / `keys` / `ft` whenever
  possible (keep startup cost ~zero). Things that must theme the UI at startup
  use `lazy = false, priority = 1000` (see `theme.lua`).
- `<leader>` is **Space**, `<localleader>` is `\`.
- To disable a plugin without deleting it, add `enabled = false` to its spec.

## Non-negotiables (one line each — full rationale in the nested CLAUDE.md files)

- **lazy.nvim `import` does not recurse** — every new `lua/plugins/` category
  folder needs its own import line in `init.lua`.
- **Updates use `Lazy restore`, never `sync`** — `lazy-lock.json` is the tested
  set; `:NvSinnerSync` is the only opt-in "float to latest" path and rewrites
  the lockfile (retest + commit it).
- **nvim-treesitter pins `branch = "master"`** — upstream's `main` is a full
  rewrite; do not remove the pin (incident FA-24; see
  `lua/plugins/editor/CLAUDE.md`).
- **Never reintroduce `require("lspconfig").<server>.setup()`** — this config
  uses the Neovim 0.11 native `vim.lsp.config` / `vim.lsp.enable` API.
- **LSP semantic tokens stay disabled** — treesitter is the single source of
  syntax colour (`on_attach` nils `semanticTokensProvider`).
- **noice's LSP hover/signature stay off** — the markdown TS highlighter
  crashes on 0.12.x transient floats; `K` keeps the native handler.
- **Never hardcode hex colors** — every color is a role from
  `lua/core/carbon.lua` (the single palette source of truth).
- **No in-editor AI plugin** — AI is a CLI in the toggleterm column; the config
  never reads `ANTHROPIC_API_KEY`.
- **The send-to-AI bridge never auto-submits** — payloads land in the CLI input
  for review (no trailing `\r`).
- **Auto-reload means disk wins** — unsaved in-Vim edits to a buffer the AI
  changes are discarded (intended viewer-style workflow).
- **Don't enable gitsigns `current_line_blame`** — inline blame is
  git-blame.nvim's job; gitsigns owns the popup.
- **mini.animate scroll stays off** — smooth scrolling is neoscroll's job;
  never enable both.

## Key subsystems — where the full contracts live

Detailed per-subsystem docs sit in nested CLAUDE.md files, loaded automatically
when you work under that directory. Read them before editing there:

| Area | Contract file |
|------|---------------|
| Native core modules (AI bridge/ask, carbon theme, settings/menu, prompts, help, symbols/backdrop, ui-touch, filebadge, ai-activity, autoreload/ai-edits, update/sync/health, image-open) | `lua/core/CLAUDE.md` |
| UI chrome (theme.lua, lualine, incline, barbecue, render-markdown, noice, mini.animate, scrollbar, which-key, illuminate, cursorline) | `lua/plugins/ui/CLAUDE.md` |
| LSP / completion / formatting / diagnostics | `lua/plugins/lsp/CLAUDE.md` |
| Terminals: toggleterm AI columns, CLI picker, reserved ids, persistence | `lua/plugins/terminal/CLAUDE.md` |
| Git: gitsigns / git-blame / diffview ownership | `lua/plugins/git/CLAUDE.md` |
| Editor plugins + the treesitter branch pin | `lua/plugins/editor/CLAUDE.md` |
| Navigation: telescope, neo-tree (`tree_side`), leap | `lua/plugins/navigation/CLAUDE.md` |
| Colorscheme file | `colors/CLAUDE.md` |
| Test suite: spec inventory + conventions | `tests/CLAUDE.md` |
| Installation runbook + install/uninstall scripts | `docs/installation.md` |

AI summary (details in `lua/core/CLAUDE.md` + `lua/plugins/terminal/CLAUDE.md`):
there is no in-editor AI plugin — a CLI agent runs in a persistent vertical
toggleterm column (`<leader>j`, sessions 2–9 via `<leader>j2`…); editor context
is piped in via the send-to-AI bridge (`<leader>as`/`ab`/`ad`, visual
`<leader>x` Ask-AI modal) and buffers auto-reload when the CLI edits files on
disk.

## Keymaps

The full keybindings reference lives in **README.md §Full keybindings
reference** — check it before adding a map. Leader namespaces (leader = Space):

- `a` ai (send-to-AI bridge) · `c` code · `g` git (diffview) · `h` hunks
  (gitsigns) · `j` ai sessions (toggleterm columns) · `l` lsp · `s` search
  (telescope) · `S` session (persistence) · `t` terminals · `x` trouble +
  NvSinner shortcuts (normal) / Ask-AI modal (visual)
- `<leader>t` and `<leader>j` are prefixes of their numbered variants, so a
  bare press waits one `timeoutlen` before falling back to terminal/session 1.
- Neovim 0.11 builtins are documented, not remapped: `grn` / `grr` / `gri` /
  `gO` / `]d` / `[d`.

## Validating changes

```bash
# Syntax-check a single file (no network):
nvim --headless -c "lua assert(loadfile('lua/plugins/<category>/<file>.lua'))" -c "qa"

# Install/build plugins:
nvim --headless "+Lazy! sync" +qa

# Boot config and surface startup errors:
nvim --headless -c "lua vim.defer_fn(function() vim.cmd('messages'); vim.cmd('qa') end, 300)"
```

Also useful interactively: `:Lazy`, `:checkhealth`, `:Mason`.

## Tests

```bash
make test                                   # whole suite
make test-file FILE=tests/core/options_spec.lua   # one file
```

Each spec runs in a fresh headless Neovim via `tests/minimal_init.lua` (no
plugins loaded, no side effects). The spec inventory and conventions for new
specs live in `tests/CLAUDE.md`.

## Skill library (`.claude/skills/`)

Ground-truth-verified runbooks (debugging playbook, failure archaeology,
architecture contract, Neovim-internals reference, testing/QA, docs/style, …)
that auto-load from their trigger-rich descriptions — nothing needs to be
invoked by name, and each skill self-describes. Each ends with a **Provenance
and maintenance** section (`Facts verified: <date>` + re-verification
commands) — facts drift, re-run those before trusting a value under active
development. Note: the skills were authored against the previous
kanagawa-dragon "glass" palette; the theme is now **carbon**, so any specific
hex a skill quotes is historical — current values live in
`lua/core/carbon.lua`.

See [NVSINNER.md](NVSINNER.md) for the original distro-packaging plan,
[docs/installation.md](docs/installation.md) for setup, and
[docs/native-roadmap.md](docs/native-roadmap.md) for the plugin→native
migration analysis and its wave plan (which plugins stay, which go native,
and why).
