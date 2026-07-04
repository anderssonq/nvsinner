# CLAUDE.md

Guidance for Claude Code (and other agents) working in this repository.

## What this is

A personal Neovim configuration managed with **lazy.nvim**, extended into a
Cursor-like AI terminal IDE. Target editor: **Neovim 0.11+** (the LSP setup uses
the native `vim.lsp.config` / `vim.lsp.enable` API). There are no in-editor AI
plugins — AI is used by running a CLI agent (e.g. `claude`) in a terminal column.

It ships as the **NvSinner** distribution: it runs under its own
`NVIM_APPNAME=nvsinner` (config `~/.config/nvsinner`, isolated data/state/cache),
so it coexists with any other `~/.config/nvim`. The `nvsinner` launcher
(`bin/nvsinner`) and `install.sh` wire that up; see [NVSINNER.md](NVSINNER.md).
On the dev machine `~/.config/nvsinner` is a **symlink** to this repo
(`~/.config/nvim`), so both `nvim` and `nvsinner` load the same files.

## Installation (agent-executable)

These steps install the whole setup from scratch, written so an AI coding agent
can run them top-to-bottom. Commands target **macOS (Homebrew)**; Linux
equivalents are noted inline. Steps tagged **[manual]** need a human (interactive
auth or a GUI font selection) — surface those to the user instead of running them.

NvSinner runs under its own app name: either `export NVIM_APPNAME=nvsinner` for
the shell session (so the `nvim …` commands below load the nvsinner config) or
use the `nvsinner` launcher in place of `nvim`. The repo's `install.sh` automates
the whole flow (clone → launcher → plugin bootstrap).

### 1. System prerequisites

```bash
# macOS (Homebrew). Linux: swap brew for apt/dnf/pacman + cargo/npm equivalents.
brew install neovim ripgrep node   # neovim MUST be >= 0.11
```

The formatting/linting binaries (`stylua`, `prettier`, `eslint_d`) auto-install
via Mason on first boot (`mason-tool-installer`, see *LSP / formatting*), so no
manual `brew install stylua` / `npm i -g prettier eslint_d` is needed —
those remain valid manual fallbacks if the Mason install fails.

The config uses `vim.uv` and the native `vim.lsp` API, so it will NOT work below
0.11 — verify:

```bash
nvim --version | head -1   # expect: NVIM v0.11.x or newer
```

### 2. Install this config

```bash
# NvSinner installs under an isolated app name, so it does NOT clobber an
# existing ~/.config/nvim — clone straight into the nvsinner config dir.
git clone <THIS_REPO_URL> ~/.config/nvsinner
```

Then run it with `NVIM_APPNAME=nvsinner nvim` or the `nvsinner` launcher
(`bin/nvsinner`). `install.sh` automates this clone plus the launcher. (If you
are already running inside the cloned repo, skip the clone.)

### 3. Install plugins (lazy.nvim bootstraps itself)

```bash
nvim --headless "+Lazy! sync" +qa
```

Clones lazy.nvim and every plugin pinned in `lazy-lock.json`.

### 4. LSP servers via Mason (automatic)

`mason-lspconfig` auto-installs `lua_ls`, `ts_ls`, and `html` on first launch
(`ensure_installed` in `lsp-config.lua`) — no manual step needed. The only
optional manual install is `solargraph` (needs a Ruby toolchain; only if you
edit Ruby):

```bash
# Optional (needs Ruby):
nvim --headless "+MasonInstall solargraph" +qa
```

### 5. Install the bundled Nerd Font  [manual]

```bash
cp fonts/*.ttf ~/Library/Fonts/                              # macOS
# Linux: cp fonts/*.ttf ~/.local/share/fonts/ && fc-cache -f
```

Then set the terminal's font to **"FiraCode Nerd Font"** (GUI step).

### 6. Set up an AI CLI  [manual]

The AI workflow is a CLI agent in the terminal column (`<leader>j`). Install one,
e.g. Claude Code, then run it once to authenticate:

```bash
npm install -g @anthropic-ai/claude-code
claude   # complete the interactive login
```

Any other CLI (opencode, ollama, …) works — just type it in the AI column. The
config itself does NOT need `ANTHROPIC_API_KEY`; the CLI handles its own auth.

### 7. Validate

```bash
# Boot and surface any startup errors:
nvim --headless -c "lua vim.defer_fn(function() vim.cmd('messages'); vim.cmd('qa') end, 500)"
# Health check (LSP, treesitter, etc.):
nvim --headless "+checkhealth" +qa
```

Then open `nvim` and run `:Lazy` / `:Mason` to confirm everything installed.

## Layout

```
init.lua                     Bootstraps lazy.nvim, requires lua/core/*, imports the plugin folders
colors/carbon.lua            The "carbon" colorscheme (oxocarbon/IBM Carbon port, self-contained)
lua/core/options.lua         Leaders + core vim options (required FIRST, before lazy)
lua/core/settings.lua        Persistent :NvSinnerMenu settings (JSON in settings/) — seeds the carbon flags at boot (native)
lua/core/menu.lua            :NvSinnerMenu — Mason-style settings modal over core/settings (native)
lua/core/prompts.lua         :NvSinnerPrompts — prompt-library modal over settings/prompts.json → OS clipboard (native)
lua/core/help.lua            :NvSinnerHelp — command palette listing every NvSinner command; pick one to run it (native)
settings/prompts.json        The prompt library (committed, user-editable); settings/ also holds the gitignored :NvSinnerMenu cache
lua/core/carbon.lua          Carbon base16 role palette + accent packs — the ONE source of truth for every color
lua/core/keymaps.lua         Global keymaps: save/undo/redo, folds, split-resize, buffers
lua/core/autoreload.lua      AI-workflow: disk auto-reload + terminal auto-insert on focus
lua/core/ui-touch.lua        Active-window border/glow + mouse-hover docs (native)
lua/core/ai-activity.lua     Agent/terminal activity spinner in the terminal winbar (native)
lua/core/update.lua          :NvSinnerUpdate — git pull + Lazy restore + checkhealth (native)
lua/core/sync.lua            :NvSinnerSync — opt-in Lazy sync + Mason package updates (native)
lua/core/health.lua          Missing-externals detection: :checkhealth nvsinner + one-time first-run toast (native)
lua/core/image-open.lua      Open image files in macOS Quick Look + metadata placeholder (native)
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
  returning either a spec table or a list of spec tables. New files in an existing
  category folder are picked up automatically; a brand-new category folder needs
  its own `{ import = "plugins.<category>" }` line in `init.lua` (see *Layout*).
- **Lazy-load** new plugins via `event` / `cmd` / `keys` / `ft` whenever possible
  (keep startup cost ~zero). Things that must theme the UI at startup use
  `lazy = false, priority = 1000` (see `theme.lua`).
- `<leader>` is **Space**, `<localleader>` is `\`.
- To disable a plugin without deleting it, add `enabled = false` to its spec.

## Key subsystems

### AI — terminal column (no in-editor AI plugins)
- avante and codecompanion were **removed**. There is no in-editor AI plugin and
  no `lua/plugins/ai.lua`. AI is used by running a CLI agent — e.g. `claude`
  (Claude Code) — inside the toggleterm "AI column" (see *Terminals*).
- **First-open CLI picker** — the first time an AI session is toggled, a picker
  opens *in the column's own space* (a full-height side split, not a float)
  listing `claude` / `kiro-cli` / `opencode` (not-installed ones are marked and
  refuse selection with a warning) plus **"plain terminal — no AI"**. The choice
  becomes the toggleterm `cmd` (nil → default shell); picking plain terminal
  titles the column's winbar `term` (like the horizontals) instead of `AI · N`
  via the `__nv_label` override read by `on_panel_open`. Keyboard (`j`/`k`,
  `<CR>`, `1`-`4`, `q`/`<Esc>`) + mouse (click a row); styled with the NvMenu*
  groups from `core/menu.lua`.
- The CLI handles its own auth/billing; the config does **not** read
  `ANTHROPIC_API_KEY`. Buffers auto-reload when the CLI edits files on disk (see
  *Auto-reload*).

### Theme — carbon (oxocarbon / IBM Carbon port)
- Active colorscheme: **carbon**, a self-contained port of oxocarbon.nvim
  (Nyoom Engineering, inspired by the IBM Carbon Design System) — industrial
  grayscale core, blue-forward accents, color only where it carries meaning.
  No external theme plugin; the design doctrine is documented in
  `lua/core/carbon.lua` itself.
- **Three files, one palette:** `lua/core/carbon.lua` holds the base16 role
  palette (`base00`…`base15`, `blend`, `lift`; dark + light variants) and is the
  SINGLE source of truth — the colorscheme, the core modules, and every UI
  chrome spec `require` it; raw hexes never appear in consumers.
  `colors/carbon.lua` is the real colorscheme (`:colorscheme carbon`) applying
  the full highlight→role mapping (editor UI, syntax, treesitter, diagnostics,
  diff washes, markdown, telescope/cmp/notify/neo-tree, terminal ANSI).
  `lua/plugins/ui/theme.lua` is a local virtual lazy spec (`lazy = false,
  priority = 1000`) whose only job is applying it at startup.
- Key roles (dark): bg `base00 #161616`, panels `base01 #262626`, body text
  `base04 #d0d0d0` (never pure white), comments `base03 #525252` italic, floats
  recessed on `blend #131313` with **invisible borders**, focused-pane lift
  `lift #1c1c1c`. Identity accent: `base09 #78a9ff` (blue); attention/modified:
  `base10 #ee5396` (magenta); busy chip: `base12 #ff7eb6` (pink); focused
  terminal bar: `base11 #33b1ff` (carbon's terminal-mode accent).
- Chrome highlights are re-applied via `ColorScheme` autocmds so they survive
  colorscheme reloads and lazy-loaded plugins.
- **Feature flags** (resolved by `core/carbon.lua`; `vim.g` wins over env,
  which wins over the persisted `:NvSinnerMenu` value seeded by
  `core/settings.lua`): `vim.g.nvsinner_background` / `$NVSINNER_BACKGROUND`
  (`"dark"` default, `"light"` boots the light variant),
  `vim.g.nvsinner_transparent` / `$NVSINNER_TRANSPARENT` (drops every
  full-surface bg — editor, floats, panels — while chips/bars stay solid for
  legibility; `ui-touch.lua` also drops its focus lift and dim-bar strip in
  transparent mode), `vim.g.nvsinner_accent` / `$NVSINNER_ACCENT` (accent
  pack, below), `vim.g.nvsinner_folder` / `$NVSINNER_FOLDER` (neo-tree
  folder color pack, below), and the four single-role slot flags
  `vim.g.nvsinner_notif|variables|strings|functions` /
  `$NVSINNER_NOTIF|VARIABLES|STRINGS|FUNCTIONS` (below). Documented for users
  in README's *Theme options (carbon)*, which also carries the glass→carbon
  migration steps.
- **Accent packs** — `M.accents` in `core/carbon.lua` defines four selectable
  identity accents (`blue` default / `magenta` / `green` / `purple`, IBM
  Carbon tones). A pack overrides ONLY the identity text-accent pair (`base09`
  and its pale companion `base15`) in `M.colors()`; gray surfaces
  (`base00`/`base01`/`base02`, `blend`, `lift`) never change. Because every
  consumer re-resolves `M.colors()` on `ColorScheme`, switching the accent is
  just `vim.g.nvsinner_accent = <pack>` + `:colorscheme carbon` (which is what
  `core/settings.lua` does).
- **Single-role color slots** — `M.slots` / `M.slot_choices` in
  `core/carbon.lua` generalize the pack idea to element classes that take ONE
  color: `notif` (the NotifyINFO* toast accent — WARN/ERROR keep their
  semantic colors), `variables` (Identifier + `@variable*`/`@parameter`/
  `@field`), `strings` (String/Character), `functions` (Function + the whole
  `@function*`/`@method` family). Choices are role names (`accent` follows
  the accent pack, plus teal/aqua/magenta/pink/green/purple/plain);
  `"default"` makes `M.slot_color()` return nil and the colorscheme keep its
  stock per-group roles (functions stock is a deliberate MIX of roles, which
  is why stock can't be expressed as a single choice). Flags:
  `vim.g.nvsinner_<slot>` / `$NVSINNER_<SLOT>`, persisted via `:NvSinnerMenu`.
- **Folder color packs** — `M.folders` in `core/carbon.lua` maps a pack name
  (`accent` default / `teal` / `aqua` / `pink` / `green` / `purple` / `gray`)
  to a **role-name pair** `{ name, icon }` (roles, not hexes — so one table
  serves both variants and every accent pack). `M.folder_colors()` resolves
  the pair through `M.colors()`; `colors/carbon.lua` reads it for
  `NeoTreeDirectoryName` / `NeoTreeDirectoryIcon` on every apply. The stock
  `accent` pack reproduces the original look (name `base09` — follows the
  accent pack — icon pink `base12`); the others paint name + icon in one
  fixed accent, `gray` gives a monochrome tree. Like accents, only text
  accents change — never surfaces.

### Settings & menu — `lua/core/settings.lua` + `lua/core/menu.lua` (native, required from `init.lua`)
- `core/settings.lua` persists user choices as JSON in the distro's
  **`settings/` folder** (`stdpath("config")/settings/nvsinner-settings.json`,
  gitignored — next to the committed `settings/prompts.json`, so all
  user-tweakable state sits in one place; a pre-`settings/` cache under
  `stdpath("data")` is migrated on first load) and applies them:
  `background` / `transparent` / `accent` / `folder` / `notif` / `variables` /
  `strings` / `functions` (carbon flags), `tree_side` (neo-tree
  position), `ai_side` (AI/vertical terminal column side), `quiet` (mute
  INFO-level `vim.notify`; WARN/ERROR always pass). **Required right after
  `core.options` in `init.lua`** so it can seed the carbon `vim.g` flags before
  lazy applies the theme — and it only seeds a flag when neither `vim.g` nor
  the env var is set, preserving the documented `vim.g` > env precedence.
  Every `M.set` persists, applies live (theme changes re-run
  `:colorscheme carbon`), and fires `User NvSinnerSetting`
  (`data = { key, value }`) so lazy specs react without eager requires:
  `toggleterm.lua` re-asserts its layout on `ai_side`, neo-tree reads
  `tree_side` on each `<leader>e`. The quiet wrapper is installed on
  `User VeryLazy` (after noice replaces `vim.notify`) and wraps/unwraps the
  *current* notify. `M.load({ file = … })` / `M.setup({ file = … })` are test
  seams (mirror `update.lua` / `health.lua`).
- `core/menu.lua` defines **`:NvSinnerMenu`** — a Mason-style floating modal
  over the eleven settings. Keyboard: `j`/`k` (or arrows) move, `h`/`l` /
  `<CR>` / `<Space>` cycle a value, `1`-`9` jump (rows past 9 via j/k or
  mouse), `q`/`<Esc>` close. Mouse:
  hovering moves the selection onto the row under the pointer (`<MouseMove>`,
  same feel as the dashboard menu — the buffer-local map also shadows
  ui-touch's LSP-hover handler over the modal) and a click cycles the row
  (`<LeftRelease>` + `getmousepos`). The AI CLI picker carries the same
  hover/click behavior. Every change
  applies live and persists via `settings.set`. Rendering uses exact byte
  spans (the `▸` marker is multi-byte) with extmarks in the `nvsinner_menu`
  namespace; highlights are the fg-only `NvMenu*` groups (carbon roles,
  re-applied on `ColorScheme`; `NvMenuSel` keeps a solid `base01` wash on
  purpose, chips stay legible in transparent mode). The NvMenu* groups are
  shared with toggleterm's AI CLI picker so both read as one component. There
  is deliberately NO WinLeave auto-close: changing "AI column side" makes
  toggleterm jump windows to re-assert the layout, which would tear the modal
  down mid-interaction.

### Prompt library — `lua/core/prompts.lua` + `settings/prompts.json` (native, required from `init.lua`)
- **`:NvSinnerPrompts`** (also `<leader>p`) — a Mason-style floating modal over
  the prompt library in `settings/prompts.json`: each entry shows its **title**
  plus a muted **description** row; picking one copies the full prompt to the
  **OS clipboard** (`+` and `*` registers, `pcall`-guarded for headless) with a
  `📋` toast and closes — the pm.sh/fzf flow (pick → clipboard → paste into the
  AI column's CLI). Keyboard mirrors `:NvSinnerMenu`: `j`/`k` (or arrows) move,
  `<CR>`/`<Space>`/`l` copy, `1`-`9` jump, **`e` opens the JSON for editing**,
  `q`/`<Esc>` close. Mouse: hover moves the selection, click copies. Styled
  with the same `NvMenu*` groups (re-declared locally so the module stands
  alone; identical values, so double-applying is harmless).
- **The library is plain JSON, edited by hand** (`e` in the modal or open the
  file): `{ "prompts": [ { title, description, content } ] }` where `content`
  is a string **or an array of lines** (arrays are easier to hand-edit). The
  file is re-read on every open, so edits show up without a restart; invalid
  entries are skipped and a missing/corrupt file degrades to an in-modal
  "No prompts found — press e" hint, never an error. `M.load({ file = … })` is
  the test seam (mirrors `core/settings.lua`).
- `settings/prompts.json` is **committed** (it ships the five default prompts:
  PR description, strict code review, feature plan, bug fix, tests-from-pattern
  — all with `[PLACEHOLDER]` slots to fill after pasting); the
  `:NvSinnerMenu` cache next to it is **gitignored**.

### Command palette — `lua/core/help.lua` (native, required from `init.lua`)
- **`:NvSinnerHelp`** — a Mason-style floating modal listing the distro's own
  commands (title + muted description); selecting one (keyboard `<CR>`/
  `<Space>`/`l`, or a mouse click) **runs it and auto-closes** the modal, so it
  doubles as the discoverability entry point for the `:NvSinner*` surface.
  Navigation mirrors the other modals: `j`/`k` (or arrows) move, `1`-`9` jump,
  hover moves the selection, `q`/`<Esc>` close. Same `NvMenu*` styling.
- **The list is self-maintaining**: `M.refresh()` (re-run on every open) scans
  `nvim_get_commands()` for names starting with `NvSinner` (excluding itself)
  — for Lua commands the returned `definition` field carries the registered
  `desc` (verified empirically), which becomes the description; a `DESCS`
  table overrides it where a keymap hint helps, and `EXTRAS` appends
  non-command entry points (`:checkhealth nvsinner`). A future `:NvSinnerFoo`
  shows up automatically with its `desc`.
- `M.run()` closes **before** executing on purpose: the target may open its own
  modal (`:NvSinnerMenu`, `:NvSinnerPrompts`) or window (`:checkhealth`) and
  must not land inside this float. It returns the command name (test seam).

### Touch / focus feedback — `lua/core/ui-touch.lua` (+ `lua/plugins/ui/illuminate.lua`)
- Native module `lua/core/ui-touch.lua` (required from `init.lua`) makes focus
  and the mouse feel tactile, layered on the carbon theme (roles pulled from
  `lua/core/carbon.lua`):
  - **Active-window border + glow** — the focused window/terminal gets a lifted
    `Normal` (`NvFocusNormal` on `lift #1c1c1c`) plus an accent separator and a
    subtle `CursorLine` (`base01`); everything else stays on `base00 #161616`
    with a near-invisible `WinSeparator` (`base01`). **Focused terminals** (AI
    column / horizontal terminal) additionally get a **full-width top bar** (a
    `winbar`, `WinBar:` `NvTermFocusBar` on `base11 #33b1ff` — carbon's
    terminal-mode accent, dark text on a solid chip) plus a matching brighter
    separator (`NvTermFocusSeparator`) — a 1px split line
    was too faint on the near-black bg, so the bar
    carries the focus cue. The bar is **always present** (dim `NvTermBarDim`
    `base01` when unfocused, bright when focused) so the terminal never reflows;
    it just brightens. This works in all three terminal layouts (horizontal-only,
    vertical-only, both). Toggled via `WinEnter`/`WinLeave` autocmds setting
    per-window `winhighlight` (and `winbar` for terminals). Special
    windows (neo-tree, telescope, dashboard, floats) are skipped by an `eligible()`
    guard so their own `winhighlight` is left intact.
  - **Agent / terminal activity spinner** — the terminal top bar is no longer an
    empty strip: its `winbar` is a live expression
    `%{%v:lua.require'core.ai-activity'.winbar(<buf>)%}` built per-window by
    `term_bar(win)` in `ui-touch.lua` (the buffer number is baked in — see
    *Agent activity* for why), so the bar shows a braille spinner + `working…` while the
    terminal is producing output and `● idle` when it goes quiet. Busy is drawn in
    an accent **chip** (`NvAiBusy`, carbon pink `base12`) so it stays visible even
    when the terminal is unfocused; for that the unfocused bar `NvTermBarDim`
    carries a readable muted `fg` (`base03`) instead of `fg == bg` (which hid the
    label).
    See *Agent activity* below for the detector.
  - **Mouse hover** — `mousemoveevent` is on; a debounced `<MouseMove>` handler
    shows the LSP doc (or the line's diagnostics as fallback) for the symbol
    under the *pointer* in a `relative="mouse"` float, no `<K>` needed. The float
    is non-focusable and torn down on cursor move / mode / layout change.
  - Highlights live in an `apply_hl()` re-applied on `ColorScheme`. All values
    are roles from `lua/core/carbon.lua` — never hardcode a hex here.
- `illuminate.lua` — `vim-illuminate`: highlights every occurrence of the symbol
  under the cursor (the "actionable text" cue) via LSP → treesitter → regex, with
  a panel-gray underline (`IlluminatedWordText/Read/Write`). Lazy-loaded on
  `BufReadPost`/`BufNewFile`; defaults map `<a-n>`/`<a-p>` to next/prev reference.
- `cursorline.lua` — `nvim-cursorline` is **disabled** (`enabled = false`): its
  cursorword duplicated `illuminate` and its cursorline fought `ui-touch`. Kept
  as a one-line revert.

### Agent activity — `lua/core/ai-activity.lua` (native, required from `init.lua`)
- Detects whether the program in a terminal — an AI CLI (`claude`, `kiro`,
  `opencode`, …) or any command — is **working vs. idle**, and renders it as a
  spinner in the terminal `winbar` (the content side of `ui-touch.lua`'s bar; see
  *Touch / focus feedback*). Generic on purpose: vertical AI columns AND the
  horizontal `<leader>t` terminals light up (a long build shows `working…`).
- **Signal: `nvim_buf_attach` `on_lines`, NOT changedtick polling.** A `TermOpen`
  autocmd attaches an output listener to each terminal buffer; every chunk of
  output (including an agent's own "thinking" spinner) marks that buffer busy and
  stamps `uv.now()`. Polling `b:changedtick` was tried and **rejected**: Neovim
  doesn't materialise a terminal buffer's lines (so doesn't bump the tick) unless
  something is attached or the buffer is rendered — verified empirically — so the
  tick can sit frozen while output streams. An attached listener is always
  notified. The `on_lines` callback runs in a **fast event context**: it touches
  only the plain Lua `state` table (and `uv.now()`); no `vim.*` API calls there.
- A light `vim.uv` timer (`POLL_MS` 120ms) animates the spinner and flips a
  buffer back to idle after `IDLE_MS` (1.2s) of quiet, redrawing only while
  something is busy or a state just changed (no idle redraws). The timer handle is
  stored on the module table (`M._timer`) so luv won't GC the unreferenced active
  handle and silently stop the spinner.
- **Redraw: `nvim__redraw{ winbar = true, flush = true }`, NOT `:redrawstatus`.**
  When focus is INSIDE a terminal (the usual case while watching an agent),
  `:redrawstatus` does NOT repaint the winbar, so the spinner looked frozen —
  verified in a real PTY render. `nvim__redraw` re-evaluates + flushes the winbar
  in terminal mode too (with a `pcall` fallback to `redrawstatus!`).
- **`M.winbar(buf)` takes its buffer as an ARGUMENT** — `ui-touch.lua` bakes the
  buffer number into each window's string (`…winbar(<buf>)`). It must NOT use
  `vim.g.statusline_winid`: that global is populated for 'statusline' evaluation
  but **not** for 'winbar' evaluation (verified), so relying on it made the bar
  render empty in real use. Busy is wrapped in `%#NvAiBusy#…%*` (a carbon-pink
  `base12` chip,
  `apply_hl` re-applied on `ColorScheme`) so it shows even on an unfocused/dim bar;
  idle is plain and inherits the focus-aware WinBar highlight. Tunables (`POLL_MS`,
  `IDLE_MS`, `SPINNER`, labels) live at the top of the file.
- **Per-terminal label** — `M.winbar(buf)` also prefixes a buffer var
  `b:nv_term_label` if present (e.g. `AI · 3 ⠹ working…`). `toggleterm.lua`
  sets it in `on_panel_open` from the term id: AI panels use the reserved ids
  100+ (`AI · <id-99>`), the `<leader>t` horizontals use 1–9 (`term <id>`);
  an AI column opened as a *plain terminal* (CLI picker) carries the
  `__nv_label` override and is titled `term` instead. Plain `:terminal`
  buffers have no label and just show the spinner.
- **First-open caveat (handled in `ui-touch.lua`)** — a toggleterm window fires
  `BufWinEnter` while its buffer is still a scratch (`buftype ""`), so `ui-touch`'s
  `focus()` would style it as a code pane and skip the terminal winbar; the
  `TermOpen` trigger added to `ui-touch`'s focus autocmd re-applies focus once the
  buffer is a `terminal`, so the bar + spinner show on the very first open.

### UI chrome — one palette, meaningful accents
Everything below pulls carbon roles from `lua/core/carbon.lua` (bg `base00`,
panels `base01`/`base02`, body `base04`, muted `base03`, floats on `blend`) with
accents used **semantically**: `base09` blue = identity/active, `base10` magenta
= modified/attention, `base12` pink = busy, `base11` light blue = terminal focus.
When editing these, do **not** hardcode hexes or introduce off-palette colours
(the old incline blue / the old barbecue tokyonight defaults were removed for
exactly this reason) — reference a role.
- `lualine.lua` — statusline with the carbon **mode→accent** map:
  the mode block is a solid accent chip with dark `base00` text (normal `base09`,
  insert `base12`, visual `base14`, replace `base08`, command `base13`, terminal
  `base11`); all other sections stay `base04` on `base00`.
- `incline.lua` — per-window filename badge (top-right). Active window is marked
  with a `base09` blue dot on a `base02` chip; others stay muted on `base01`.
  Modified dot is `base10`. The filetype icon keeps its own colour as
  *foreground* only (no coloured block) to stay gray-dominant.
- `barbacue.lua` — `barbecue` breadcrumb winbar (path > LSP symbols) on code
  windows, recolored: muted dirname/separators, `base04` basename, soft `base09`
  symbol icons, `base10` reserved for the `modified` marker. Pairs with the
  terminal winbar so every window has a consistent top bar. **markdown is in
  `exclude_filetypes`** so it doesn't fight `render-markdown.lua`'s "Open view"
  button for the same winbar line.
- `render-markdown.lua` — `render-markdown.nvim` gated behind an **"Open view"**
  reading-view toggle. The button is a **centered, clickable** winbar chip
  (`NvMdBtn`, accent-blue `base09` on `blend`) on every markdown window (a `%=…%@…@…%X…%=` click region
  driving `_G.NvMdReader.click`); `<leader>m` toggles the same thing. Starts OFF
  (`enabled = false`) and renders only when opted in. **0.12.x crash fix:** the
  spec's `init` overrides the markdown `injections` query to keep only the
  `markdown_inline` injection and drop the code-fence language directive that
  hits the `node:range` nil-node crash — set at STARTUP because a buffer's
  markdown LanguageTree caches its injection query at construction (setting it
  later from `config()` is too late). Nothing else consumes the markdown TS tree,
  so the blast radius is exactly render-markdown.
- `noice.lua` — `noice.nvim`: centered floating `:` cmdline (`command_palette`
  preset), messages routed through `nvim-notify`, carbon-recessed popups on
  `blend` with invisible borders
  (`NoiceCmdlinePopup*` re-applied on `ColorScheme`). **LSP hover/signature are
  off on purpose** — the markdown treesitter highlighter crashes on Neovim
  0.12.x transient floats (same reason `ui-touch.lua` renders hover as plain
  text); `K` keeps the native handler. Do not enable noice's lsp markdown paths.
- `mini-animate.lua` — `mini.animate`: eases window open/close/resize (the AI
  column slides in) + a short cursor trail. **Scroll is disabled here** — that's
  `neoscroll`'s job (`smooth-scroll.lua`); don't enable both.
- `diagnostics.lua` — `tiny-inline-diagnostic.nvim`: rounded inline bubble for
  the cursor-line diagnostic. Owns `vim.diagnostic.config` (sets
  `virtual_text = false`, rounded floats, sign icons) — keep diagnostic UI config
  here, not scattered across `lsp-config.lua`.
- `scrollbar.lua` — `satellite.nvim`: slim decoration-based right-edge scrollbar
  overlaying git hunks / diagnostics / search / cursor. Excludes neo-tree,
  toggleterm, telescope, dashboard, etc.

### LSP / formatting
- `lsp-config.lua` — `mason` + `mason-lspconfig`, then the **Neovim 0.11 native
  API**: `vim.lsp.config("*", { capabilities })` + `vim.lsp.enable({...})`.
  Servers: `ts_ls`, `solargraph`, `html`, `lua_ls`. Do **not** reintroduce
  `require("lspconfig").<server>.setup()` (deprecated).
  - `mason-lspconfig` carries `ensure_installed = { "lua_ls", "ts_ls", "html" }`
    so a fresh NvSinner install auto-installs those on first boot (it's `event =
    "VeryLazy"` + depends on `mason.nvim` so the install fires even on the
    dashboard). `automatic_enable = false` on purpose: **we** enable servers via
    `vim.lsp.enable` *after* the `"*"` config lands — otherwise mason-lspconfig
    could start a server before `on_attach` nils semantic tokens (below) and the
    `@lsp.*` repaint would come back. solargraph is left out of `ensure_installed`
    (needs Ruby) but stays in `vim.lsp.enable` (harmless if not installed).
- **Treesitter is the single source of syntax colour.** The `"*"` config's
  `on_attach` nils `client.server_capabilities.semanticTokensProvider`, so LSP
  semantic tokens (`@lsp.*`) never repaint the buffer ~1s after open and flatten
  the Treesitter palette. Remove that line if you ever want semantic highlighting.
- `completions.lua` — `nvim-cmp` + LuaSnip. `<C-Space>` triggers completion.
- `none-ls.lua` — `none-ls` + `none-ls-extras`; sources: `stylua`, `prettier`,
  `eslint_d` (eslint_d comes from none-ls-extras and needs the binary on PATH).
- `mason-tools.lua` — `mason-tool-installer.nvim` auto-installs the none-ls
  binaries (`stylua`, `prettier`, `eslint_d`) via Mason on first boot
  (`event = "VeryLazy"`, same trigger as mason-lspconfig, so it fires even on
  the dashboard). `auto_update = false` on purpose — package updates stay the
  opt-in `:NvSinnerSync` path. `:MasonToolsInstall` retries a failed install;
  `core/health.lua`'s hints point at it, with brew/npm as manual fallbacks.

### Git
- `git-blame.lua` — `git-blame.nvim`: always-on inline blame as virtual text
  (author / date / sha of the current line), lazy-loaded on `VeryLazy`.
- `gitsigns.lua` — `gitsigns.nvim`: sign-column markers for added / changed /
  deleted lines vs. the git index (a thin `▎` bar), lazy-loaded on `BufReadPre` /
  `BufNewFile`. Hunk keymaps live in its `on_attach`: `]h` / `[h` navigate,
  `<leader>hp` preview, `<leader>hs` / `<leader>hr` stage / reset hunk,
  `<leader>hS` / `<leader>hR` stage / reset buffer, `<leader>hb` blame popup.
  Keep the **inline** blame as git-blame.nvim's job and the **popup** blame as
  gitsigns' — don't enable gitsigns `current_line_blame` (it would double up).
- `diffview.lua` — `diffview.nvim`: a full side-by-side `git diff` viewer (file
  panel + two versions of the file). Lazy-loaded on its `Diffview*` commands and
  keymaps: `<leader>gd` open working-tree-vs-index, `<leader>gh` current-file
  history, `<leader>gH` whole-repo history, `<leader>gq` close. `enhanced_diff_hl`
  is on for word-level highlights; everything else is left at defaults
  (intentionally minimal — just "see the differences"). The `<leader>g` git
  namespace is otherwise free; gitsigns owns the per-hunk `<leader>h*` maps.

### Terminals — `lua/plugins/terminal/toggleterm.lua`
- `<leader>t` → horizontal terminal 1 (forced `direction=horizontal`), sized to
  20% of `vim.o.lines`. `<leader>t2` … `<leader>t9` toggle additional independent
  horizontal terminals (ids 2–9), each via `exe "<N>ToggleTerm direction=horizontal"`.
  `<leader>t` is a prefix of `<leader>t2`…, so a bare `<leader>t` waits one
  `timeoutlen` (which-key shows the menu) before falling back to terminal 1.
  (Moved off `<C-t>` to avoid a Ctrl+T conflict.)
- AI panels → **multiple persistent vertical columns** (right by default; side
  configurable via `:NvSinnerMenu`'s `ai_side` — `restore_layout()` forces
  `wincmd L`/`wincmd H` accordingly and a `User NvSinnerSetting` autocmd
  re-asserts it live), each an independent AI session for any AI CLI; toggling
  hides without killing the process. Session 1 is triggered by `<leader>j`,
  `<M-J>` (iTerm2 sends this from Cmd+Opt+J via "Send Escape Sequence" = `J`),
  or `<D-M-j>` (GUI Neovim). Sessions 2–9 are toggled by `<leader>j2` …
  `<leader>j9`.
- Panels are created **lazily and memoised by session number**
  (`create_ai_panel`), so a session only spawns its process the first time you
  open it — and that first open shows the **CLI picker** (see *AI* above):
  the chosen CLI becomes the terminal's `cmd`, "plain terminal" runs the shell
  with a `term` winbar title.
- Each panel gets a reserved `id = 99 + N` (session 1 → 100, … session 9 → 108),
  kept clear of the low ids 1–9 that the horizontal terminals use. Without
  reserved ids, opening an AI panel first would claim id 1 and `<leader>t` would just
  re-toggle that panel instead of opening a horizontal terminal.
- `<leader>j` is also a prefix of `<leader>j2`…, so a bare `<leader>j` waits one
  `timeoutlen` (which-key shows the menu) before falling back to session 1;
  press a digit right after `<leader>j` to jump straight to that session.
- Resize via the global split-resize keymaps in `core/keymaps.lua`: `<C-,>` /
  `<C-.>` (width ±20 columns, use for the vertical AI panel) and `<C-;>` /
  `<C-'>` (height ±5 rows, use for the horizontal terminal). Both work from
  terminal mode. (The steps are absolute — Vim silently ignores a trailing `%`
  on `:resize`, so the old "±20%" wording was never percentual.)

See [NVSINNER.md](NVSINNER.md) for the plan to package this config as an
installable, separately-named Neovim distro ("NvSinner").

### Auto-reload — `lua/core/autoreload.lua`
- When the AI CLI edits a file from the terminal column, the on-disk version is
  reloaded into the buffer automatically (no W11/W12 prompt). Done via
  `autoread` + a `FileChangedShell` handler that sets `v:fcs_choice = "reload"`,
  plus `checktime` on focus/window-enter events and a 1s `vim.uv` timer. The
  timer handle is anchored on the module table (`M._timer`) — an unreferenced
  active luv timer can be GC-reaped and silently stop the poll (same guard as
  `ai-activity.lua`).
- Trade-off: **disk wins** — unsaved in-Vim edits to a buffer the AI changes are
  discarded. Intended for the viewer-style workflow (edit in the AI pane).
- **Edit toast** — a small `vim.notify` (`🤖 AI · edited <file>`) names the file an
  external process just wrote. Hooked on **both** `FileChangedShell` (the conflict
  case) **and** `FileChangedShellPost`: with `autoread` on and the buffer
  unmodified — the common case — Neovim reloads silently and fires *only*
  `FileChangedShellPost`, NOT `FileChangedShell` (verified empirically), so the
  Post event is required to catch the usual AI edit. A 250ms per-file dedup keeps
  the two events from double-toasting one write. Only loaded buffers fire either,
  so you're notified for files you actually have open.

### Updater — `lua/core/update.lua` (native, required from `init.lua`)
- Defines the `:NvSinnerUpdate` command (à la `:NvChadUpdate` / `:AstroUpdate`):
  `git -C <config> pull --ff-only` (async via `vim.system`) → `require("lazy").restore()`
  → `:checkhealth`, then a toast reminding you to **restart** (the pull rewrites
  the Lua files on disk but the running Neovim keeps the old modules loaded).
- **`restore`, not `sync`** — updates check every plugin out to the commit pinned
  in the committed `lazy-lock.json`, so installs/updates reproduce the tested
  plugin set instead of floating to latest (`:Lazy sync` is the opt-in "float"
  path). `install.sh` uses `Lazy! restore` for the same reason.
- **No-op-with-warning when the config dir isn't a git clone** (`is_git_repo`
  checks for a `.git` dir OR file): the dev machine's `~/.config/nvsinner` is a
  symlink to this repo and a manual copy has no remote — neither can `git pull`.
  `M.update({ dir = … })` takes an optional dir override purely as a test seam.
- `install.sh` mirrors this out-of-editor: on an existing clone it `git pull`s
  (unshallowing old `--depth=1` installs) instead of skipping; fresh clones are
  full-depth so `git pull` / `:NvSinnerUpdate` update cleanly.

### Plugin/Mason sync — `lua/core/sync.lua` (native, required from `init.lua`)
- Defines **`:NvSinnerSync`** — the explicit **opt-in "float" path** that
  non-negotiable `restore`-doctrine reserves for developers: `require("lazy").sync()`
  (install missing + update to latest + clean removed — **rewrites
  `lazy-lock.json`**, so retest and commit it) followed by a **Mason package
  update** phase. It never replaces `:NvSinnerUpdate`, which stays pinned to
  the lockfile; install/update paths are untouched.
- **Chaining via `User LazySync`, not a runner** — lazy's `sync()` returns
  nothing (unlike `restore()`, which returns a waitable runner — verified in
  `lazy/manage/init.lua`); it fires the `User LazySync` autocmd when the whole
  clean+install+update pipeline settles, so the Mason phase hooks that event
  with a one-shot autocmd.
- **Mason phase** (mason 2.x API, verified against the installed plugin):
  loads `mason.nvim` via `require("lazy").load` (it's `cmd = "Mason"` lazy),
  `registry.refresh(cb)` (async; a failed refresh just falls back to cached
  specs), then `M.outdated()` compares `pkg:get_installed_version()` vs
  `pkg:get_latest_version()` per installed package (both pcall-guarded —
  `get_latest_version` throws on a malformed purl; a nil installed version /
  missing receipt is skipped) and `pkg:install(nil, cb)` updates the stale
  ones, with one summary toast (or an ERROR listing failures). When
  mason/lazy aren't on the rtp (tests, bare boot) it warns and skips instead
  of erroring. `M.outdated(pkgs)` is the pure test seam.
- **Branch-jump guard** — a spec without a `branch` pin follows the *upstream
  default* branch, and sync re-resolves it, so an upstream default-branch flip
  silently swaps the plugin for whatever lives there. Incident 2026-07-03:
  nvim-treesitter flipped master → `main` (a full rewrite — no
  `nvim-treesitter.configs`, parser rebuilds failed to link on arm64, error
  flood); rolled back via `git restore lazy-lock.json` + `Lazy! restore`, and
  the spec now pins `branch = "master"`. Sync snapshots the lockfile's
  per-plugin `branch` before running and diffs it after (`M.branch_jumps`,
  the second pure test seam), WARN-ing about every jump with the rollback
  recipe. Full post-mortem: FA-24 in `nvsinner-failure-archaeology`.

### Health check — `lua/core/health.lua` (native, required from `init.lua`)
- Surfaces missing external tools (ripgrep, node, stylua, prettier, eslint_d, a
  Nerd Font) so features fail *loudly* instead of silently no-op-ing. **One tool
  table (`M.tools`), two entry points:**
  - **`:checkhealth nvsinner`** — `lua/nvsinner/health.lua` is a thin provider
    (`{ check = … }`) that Neovim discovers by module path (`lua/<name>/health.lua`
    → checkhealth name `<name>`); it delegates to `core.health.report()`, which
    walks `check_tools({ with_version = true })` and emits `vim.health.ok/warn`
    with an install hint per missing tool. It shows in the full `:checkhealth`
    (and the one `:NvSinnerUpdate` runs) under "nvsinner" too.
  - **First-run toast** — `M.setup()` (called at require time) registers a
    `User VeryLazy` autocmd that, after an 800ms defer (so nvim-notify is ready),
    runs `M.first_run_notify()`: if any tool is missing it fires a one-time
    `vim.notify` pointing at `:checkhealth nvsinner`. A marker file under
    `stdpath("state")` makes it **greet once** (written even when nothing's
    missing, so it never nags). `M.first_run_notify({ marker = … })` takes a
    marker override as a test seam (mirrors `update.lua`'s `{ dir = … }`).
- **Headless never consumes the first run** — `setup()` bails when
  `#vim.api.nvim_list_uis() == 0`, so the installer's headless `Lazy! restore`
  and the test harness don't write the marker or toast; the user's first
  *interactive* launch gets the greeting.
- **Nerd Font is info-only** — it's a terminal/GUI font setting that can't be
  probed from inside Neovim, so it's reported as `vim.health.info` and left OUT
  of the missing-count that drives the toast. Tool checks use `vim.fn.executable`
  (fast, no subprocess); versions shell out only for `:checkhealth`.

### Image viewer — `lua/core/image-open.lua` (native, required from `init.lua`)
- Opening an image file shows it instead of dumping binary bytes. iTerm2 (this
  config's terminal) uses its own inline-image escapes, **not** the Kitty
  graphics protocol that in-buffer image plugins need, so the image is popped
  into **macOS Quick Look** (`qlmanage -p`, async/non-blocking) and the buffer
  shows a small placeholder (icon, filename, `sips` dimensions, size).
- **`BufReadCmd` takes over the read** for the image extensions (`png`, `jpg`,
  `webp`, `svg`, …, both cases) and sets `buftype = "nofile"` so `:w` can never
  overwrite the image with the placeholder text. Setting `filetype` last fires
  the `nvsinner_image` `FileType` autocmd, which binds `<cr>` (reopen Quick Look)
  and `gO` (open in Preview.app).
- **Auto-preview is interactive-only** — it bails when `#nvim_list_uis() == 0`
  (headless/tests) and skips **floating** windows (`win_config.relative ~= ""`),
  so telescope's preview doesn't spawn a Quick Look storm; a `b:` flag makes it
  pop once per buffer.

### Install / uninstall scripts — `install.sh`, `uninstall.sh`
- `install.sh`: clone-or-update → `nvsinner` launcher (`~/.local/bin`) → headless
  `Lazy! restore`. If `~/.local/bin` isn't on PATH it **prints** the exact
  `export PATH` line (naming the likely rc: `.zshrc` / `.bash_profile` on macOS /
  `.bashrc` on Linux / fish's `config.fish` with `fish_add_path`) — it never
  edits the user's shell files.
- `uninstall.sh`: removes the four `nvsinner` XDG dirs (config/data/state/cache,
  each respecting `XDG_*_HOME`) + the `~/.local/bin/nvsinner` launcher. Lists what
  it'll remove, then **confirms** — prompts on a TTY, requires `--yes`/`-y` when
  piped (`curl | bash` has no TTY). A **symlinked** config dir (dev machine) is
  `rm -f`'d (unlink only) — never followed into its target; real dirs are
  `rm -rf`'d. `~/.config/nvim` is untouched (different app name).

## Keymap reference (leader = Space)

| Keys | Action |
|------|--------|
| `<leader>f` / `<leader>sf` / `<leader>fb` | Telescope find files (incl. hidden dotfiles) / live grep / buffers |
| `<leader>e` | Toggle Neo-tree (reveals the current file; side from `:NvSinnerMenu`) |
| `:NvSinnerMenu` | Settings modal: theme, transparency, accent pack, folder/notif/syntax colors, panel sides, notifications |
| `<leader>p` / `:NvSinnerPrompts` | Prompt library modal — pick a reusable AI prompt, copy it to the clipboard (`e` edits `settings/prompts.json`) |
| `:NvSinnerHelp` | Command palette — every NvSinner command with its description; pick one to run it (auto-closes) |
| `:NvSinnerSync` | Opt-in float: `:Lazy sync` (rewrites `lazy-lock.json`) + update outdated Mason packages (`:NvSinnerUpdate` stays the pinned path) |
| `<leader>m` | Markdown "Open view" — toggle the render-markdown reading view (also the clickable winbar button) |
| `<cr>` / `gO` (in an image buffer) | Reopen image in Quick Look / open in Preview.app |
| `<C-Space>` (insert) | nvim-cmp trigger completion |
| `<leader>t` / `<leader>t2` … `<leader>t9` | Horizontal terminals 1–9 (independent) |
| `<leader>j` / `<M-J>` / `<D-M-j>` | Toggle AI session 1 (terminal column; first open asks which CLI) |
| `<leader>j2` … `<leader>j9` | Toggle AI sessions 2–9 (independent columns) |
| `]h` / `[h` | Next / previous git hunk (gitsigns) |
| `<leader>hp` / `<leader>hs` / `<leader>hr` / `<leader>hb` | Hunk: preview / stage / reset / blame line |
| `<leader>gd` / `<leader>gh` / `<leader>gH` / `<leader>gq` | Diffview: open diff / file history / repo history / close |
| `s` / `S` / `gs` | leap forward / backward / cross-window |
| `K` / `gd` / `<leader>lf` / `<leader>ca` | LSP hover / definition / format / code action |
| `<leader>SQ` / `<leader>Sc` / `<leader>Sl` | Session: quit no-save / restore cwd / restore last |
| `gcc` / `gbc` | Toggle line / block comment |
| `<C-y>` / `<C-u>` / `<C-r>` | Save / undo / redo (with notifications) |
| `<C-,>` `<C-.>` `<C-;>` `<C-'>` | Resize splits: width ±20 cols / height ±5 rows (also work in terminal mode, e.g. to resize the AI chat) |

## External requirements

Neovim **0.11+** (hard requirement — uses `vim.uv` and the native `vim.lsp`
API), `git`, `ripgrep` (live grep), `node` (for `prettier` / `eslint_d`), a Nerd
Font, and for linting/formatting: `stylua`, `prettier`, `eslint_d`
(auto-installed via Mason on first boot — see `mason-tools.lua`). For AI,
install a CLI agent such as Claude Code (`claude`). See *Installation* above for
exact commands.

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

A [plenary](https://github.com/nvim-lua/plenary.nvim) busted suite lives in
`tests/` (plenary is already present as a telescope dependency — no extra
install). Run it with the `Makefile`:

```bash
make test                                   # whole suite
make test-file FILE=tests/core/options_spec.lua   # one file
```

Each spec runs in a fresh headless Neovim via `tests/minimal_init.lua`, which puts
this config + plenary on the runtimepath (no plugins loaded, no side effects).

| Spec | Covers |
|------|--------|
| `tests/core/options_spec.lua` | leaders + core editor options |
| `tests/core/carbon_spec.lua` | carbon role tables (dark/light), the background/transparency flags (`vim.g` + env), and `:colorscheme carbon` honoring both (opaque vs transparent surfaces) |
| `tests/core/keymaps_spec.lua` | global keymaps exist (save/undo/redo, resize in n+t, buffer picker) + the resize step applied behaviorally (+20 cols) |
| `tests/core/settings_spec.lua` | settings defaults, JSON save/load roundtrip + corrupt-file fallback, vim.g seeding precedence, the quiet notify filter, and the carbon accent/folder packs + single-role color slots |
| `tests/core/menu_spec.lua` | `:NvSinnerMenu` command, the modal float rendering every row, and move/cycle writing through to core/settings |
| `tests/core/prompts_spec.lua` | `:NvSinnerPrompts` command, JSON loading (array/string content, corrupt-file fallback), the modal listing title+description rows, and copy() returning the prompt + closing |
| `tests/core/help_spec.lua` | `:NvSinnerHelp` command, refresh() discovering NvSinner* commands (self excluded, late registrations included) + the checkhealth extra, the modal listing rows, and run() executing + auto-closing |
| `tests/core/autoreload_spec.lua` | `autoread`, the FileChangedShell**Post** autocmds, and the edit toast firing on an external change |
| `tests/core/ui_touch_spec.lua` | focus/term-bar highlights, `NvTermBarDim` fg≠bg, mouse/fillchars, and the per-window winbar baking the buffer number |
| `tests/core/ai_activity_spec.lua` | `winbar(buf)` idle/label/invalid + a real streaming terminal flipping working→idle |
| `tests/core/update_spec.lua` | `:NvSinnerUpdate` command exists, `is_git_repo` detection, and the not-a-git-clone warning path |
| `tests/core/sync_spec.lua` | `:NvSinnerSync` command exists, `outdated()` version comparison (stale/fresh/no-receipt/throwing lookup), `branch_jumps()` lockfile diffing (jump detection, added/removed ignored), and the mason-unavailable warning path |
| `tests/core/health_spec.lua` | `check_tools` present/absent detection, the first-run toast (warn-once via marker, silent when nothing missing), and `:checkhealth nvsinner` running |
| `tests/core/image_open_spec.lua` | `BufReadCmd` replaces an image with the placeholder, `buftype=nofile` write-guard, `<cr>`/`gO` buffer maps, and no headless auto-preview |
| `tests/plugins/plugin_specs_spec.lua` | every `lua/plugins/**/*.lua` loads and returns a valid lazy spec |

Conventions for new specs: name them `*_spec.lua`, require the module under test
at the top of the `describe` block (plenary busted has **no** `setup`/`finally`;
use `before_each` / restore state inline), and prefer real Neovim behaviour
(open a terminal, `vim.wait` for the state) over mocking.
```

## Skill library (`.claude/skills/`)

Ground-truth-verified runbooks that let a **Sonnet-class agent with zero repo
history** debug, extend, validate, and advance NvSinner at the standard this
file sets — without re-deriving context each session. Claude Code auto-loads
the matching skill from its trigger-rich `description`; nothing here needs to
be invoked by name. Skills are self-contained (no dependency on this file at
runtime) but must never contradict it — this file remains the authoritative
manifest.

| Skill | Covers |
|------|--------|
| `nvsinner-change-control` | Change classification, the project's non-negotiables with rationale + incident pointers, validation gates, pre-merge checklist |
| `nvsinner-debugging-playbook` | Symptom→triage table for known failure modes, with discriminating experiments |
| `nvsinner-failure-archaeology` | Chronicle of settled investigations, dead ends, and by-design trade-offs — "do not retry" fences |
| `nvsinner-architecture-contract` | Boot sequence, load-bearing design decisions with WHY, invariants, weak points stated plainly |
| `neovim-internals-reference` | The Neovim-internals theory pack (fast event contexts, winbar evaluation, terminal buffers, redraw machinery) as applied here |
| `nvsinner-config-catalog` | Every config axis — tunables, triggers, palette hexes, terminal ids — with current values and how-to-add checklists |
| `nvsinner-build-and-run` | Environment from scratch, install/update/uninstall anatomy, first-boot behavior, known traps |
| `nvsinner-diagnostics-toolkit` | Measurement over eyeballing — ships tested scripts: boot-check, startup-time, keymap-audit, palette-audit |
| `nvsinner-testing-and-qa` | The plenary suite, spec conventions, evidence-bar discipline for calling a change "done" |
| `nvsinner-docs-and-style` | Docs-of-record map, house style, doc-sync checklist, commit/PR templates |
| `nvsinner-terminal-ux-campaign` | Decision-gated campaign for the terminal/agent-UX stack: reproduction matrix, ranked solution menu, fenced wrong paths |
| `nvsinner-empirical-verification` | "Prove it, don't just believe `:help`" — runnable probe recipes + the idea lifecycle |
| `nvsinner-frontier` | Honest positioning vs. other distros, claim discipline, falsifiable open research problems |

Each skill ends with a **Provenance and maintenance** section (`Facts
verified: <date>` + one-line re-verification commands) — facts drift, re-run
those before trusting a value under active development. Note: the skills were
authored against the previous kanagawa-dragon "glass" palette; the theme is now
**carbon** (see *Theme* above), so any specific hex a skill quotes
(bg `#0a0a0f`, glass `#111118`, dragonRed `#c4746e`, terminal bar `#80949e`, …)
is historical — current values live in `lua/core/carbon.lua`, and this file
remains the authoritative manifest.
