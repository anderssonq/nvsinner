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
brew install neovim ripgrep node stylua   # neovim MUST be >= 0.11
npm install -g prettier eslint_d           # JS/TS formatter + linter (need node)
```

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
lua/core/options.lua         Leaders + core vim options (required FIRST, before lazy)
lua/core/keymaps.lua         Global keymaps: save/undo/redo, folds, split-resize, buffers
lua/core/autoreload.lua      AI-workflow: disk auto-reload + terminal auto-insert on focus
lua/core/ui-touch.lua        Active-window border/glow + mouse-hover docs (native)
lua/core/ai-activity.lua     Agent/terminal activity spinner in the terminal winbar (native)
lua/core/update.lua          :NvSinnerUpdate — git pull + Lazy restore + checkhealth (native)
lua/core/health.lua          Missing-externals detection: :checkhealth nvsinner + one-time first-run toast (native)
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
  (Claude Code) — inside the toggleterm "AI column" on the right (see *Terminals*).
- The CLI handles its own auth/billing; the config does **not** read
  `ANTHROPIC_API_KEY`. Buffers auto-reload when the CLI edits files on disk (see
  *Auto-reload*).

### Theme — `lua/plugins/ui/theme.lua`
- Active colorscheme: **kanagawa "dragon"**, dark monochrome glassmorphism.
- Background `#0a0a0f`; floats use glass `#111118` with `#333345` borders. Glass
  highlights are re-applied via a `ColorScheme` autocmd so they survive
  lazy-loaded plugins.

### Touch / focus feedback — `lua/core/ui-touch.lua` (+ `lua/plugins/ui/illuminate.lua`)
- Native module `lua/core/ui-touch.lua` (required from `init.lua`) makes focus
  and the mouse feel tactile, layered on the glass theme:
  - **Active-window border + glow** — the focused window/terminal gets a glass
    `Normal` (`NvFocusNormal` `#111118`) plus an accent separator and a subtle
    `CursorLine`; everything else stays on the base `#0a0a0f` with a tenue
    `WinSeparator` `#2a2a38`. **Focused terminals** (AI column / horizontal
    terminal) additionally get a **full-width top bar** (a `winbar`, `WinBar:`
    `NvTermFocusBar` `#80949e`) plus a brighter separator (`NvTermFocusSeparator`
    `#80949e`) — a 1px split line
    was too faint on the near-black bg, so the bar
    carries the focus cue. The bar is **always present** (dim `NvTermBarDim`
    `#16161d` when unfocused, bright when focused) so the terminal never reflows;
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
    an accent **chip** (`NvAiBusy`, crimson) so it stays visible even when the
    terminal is unfocused; for that the unfocused bar `NvTermBarDim` now carries a
    readable muted `fg` (`#7a7f8d`) instead of `fg == bg` (which hid the label).
    See *Agent activity* below for the detector.
  - **Mouse hover** — `mousemoveevent` is on; a debounced `<MouseMove>` handler
    shows the LSP doc (or the line's diagnostics as fallback) for the symbol
    under the *pointer* in a `relative="mouse"` float, no `<K>` needed. The float
    is non-focusable and torn down on cursor move / mode / layout change.
  - Highlights live in an `apply_hl()` re-applied on `ColorScheme` (mirrors
    `theme.lua`). Keep this palette in sync with `theme.lua`.
- `illuminate.lua` — `vim-illuminate`: highlights every occurrence of the symbol
  under the cursor (the "actionable text" cue) via LSP → treesitter → regex, with
  a glass underline (`IlluminatedWordText/Read/Write`). Lazy-loaded on
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
  render empty in real use. Busy is wrapped in `%#NvAiBusy#…%*` (a crimson chip,
  `apply_hl` re-applied on `ColorScheme`) so it shows even on an unfocused/dim bar;
  idle is plain and inherits the focus-aware WinBar highlight. Tunables (`POLL_MS`,
  `IDLE_MS`, `SPINNER`, labels) live at the top of the file.
- **Per-terminal label** — `M.winbar(buf)` also prefixes a buffer var
  `b:nv_term_label` if present (e.g. `AI · 3 ⠹ working…`). `toggleterm.lua`
  sets it in `on_panel_open` from the term id: AI panels use the reserved ids
  100+ (`AI · <id-99>`), the `<leader>t` horizontals use 1–9 (`term <id>`). Plain
  `:terminal` buffers have no label and just show the spinner.
- **First-open caveat (handled in `ui-touch.lua`)** — a toggleterm window fires
  `BufWinEnter` while its buffer is still a scratch (`buftype ""`), so `ui-touch`'s
  `focus()` would style it as a code pane and skip the terminal winbar; the
  `TermOpen` trigger added to `ui-touch`'s focus autocmd re-applies focus once the
  buffer is a `terminal`, so the bar + spinner show on the very first open.

### UI chrome — one palette, one accent
Everything below is themed to the glass palette (bg `#0a0a0f`, glass `#111118`,
FG `#c5c9d5`, muted `#7a7f8d`) with **one** colour accent: kanagawa dragonRed
`#c4746e` (the same accent `dashboard.lua` / `ui-touch.lua` use). When editing
these, do **not** reintroduce off-palette colours (the old incline blue / the old
barbecue tokyonight defaults were removed for exactly this reason).
- `incline.lua` — per-window filename badge (top-right). Active window glows in
  crimson on a glass lift; others stay muted on base. The filetype icon keeps its
  own colour as *foreground* only (no coloured block) to stay monochrome.
- `barbacue.lua` — `barbecue` breadcrumb winbar (path > LSP symbols) on code
  windows, recolored: muted dirname/separators, FG basename, soft `#9aa0b4`
  symbol icons, crimson reserved for the `modified` marker. Pairs with the
  terminal winbar so every window has a consistent top bar.
- `noice.lua` — `noice.nvim`: centered floating `:` cmdline (`command_palette`
  preset), messages routed through `nvim-notify`, glass-themed popups
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
- AI panels → **multiple persistent vertical columns on the right**, each an
  independent AI session for any AI CLI; toggling hides without killing the
  process. Session 1 is triggered by `<leader>j`, `<M-J>` (iTerm2 sends this
  from Cmd+Opt+J via "Send Escape Sequence" = `J`), or `<D-M-j>` (GUI Neovim).
  Sessions 2–9 are toggled by `<leader>j2` … `<leader>j9`.
- Panels are created **lazily and memoised by session number** (`get_ai_panel`),
  so a session only spawns a shell the first time you open it.
- Each panel gets a reserved `id = 99 + N` (session 1 → 100, … session 9 → 108),
  kept clear of the low ids 1–9 that the horizontal terminals use. Without
  reserved ids, opening an AI panel first would claim id 1 and `<leader>t` would just
  re-toggle that panel instead of opening a horizontal terminal.
- `<leader>j` is also a prefix of `<leader>j2`…, so a bare `<leader>j` waits one
  `timeoutlen` (which-key shows the menu) before falling back to session 1;
  press a digit right after `<leader>j` to jump straight to that session.
- Resize via the global split-resize keymaps in `core/keymaps.lua`: `<C-,>` /
  `<C-.>` (width ±20%, use for the vertical AI panel) and `<C-;>` / `<C-'>`
  (height ±5%, use for the horizontal terminal). Both work from terminal mode.

See [NVSINNER.md](NVSINNER.md) for the plan to package this config as an
installable, separately-named Neovim distro ("NvSinner").

### Auto-reload — `lua/core/autoreload.lua`
- When the AI CLI edits a file from the terminal column, the on-disk version is
  reloaded into the buffer automatically (no W11/W12 prompt). Done via
  `autoread` + a `FileChangedShell` handler that sets `v:fcs_choice = "reload"`,
  plus `checktime` on focus/window-enter events and a 1s `vim.uv` timer.
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
| `<leader>f` / `<leader>sf` / `<leader>fb` | Telescope find files / live grep / buffers |
| `<leader>e` | Toggle Neo-tree (reveals the current file in the tree) |
| `<C-Space>` (insert) | nvim-cmp trigger completion |
| `<leader>t` / `<leader>t2` … `<leader>t9` | Horizontal terminals 1–9 (independent) |
| `<leader>j` / `<M-J>` / `<D-M-j>` | Toggle AI session 1 (terminal column) |
| `<leader>j2` … `<leader>j9` | Toggle AI sessions 2–9 (independent columns) |
| `]h` / `[h` | Next / previous git hunk (gitsigns) |
| `<leader>hp` / `<leader>hs` / `<leader>hr` / `<leader>hb` | Hunk: preview / stage / reset / blame line |
| `<leader>gd` / `<leader>gh` / `<leader>gH` / `<leader>gq` | Diffview: open diff / file history / repo history / close |
| `s` / `S` / `gs` | leap forward / backward / cross-window |
| `K` / `gd` / `<leader>lf` / `<leader>ca` | LSP hover / definition / format / code action |
| `<leader>SQ` / `<leader>Sc` / `<leader>Sl` | Session: quit no-save / restore cwd / restore last |
| `gcc` / `gbc` | Toggle line / block comment |
| `<C-y>` / `<C-u>` / `<C-r>` | Save / undo / redo (with notifications) |
| `<C-,>` `<C-.>` `<C-;>` `<C-'>` | Resize splits: width ±20% / height ±5% (also work in terminal mode, e.g. to resize the AI chat) |

## External requirements

Neovim **0.11+** (hard requirement — uses `vim.uv` and the native `vim.lsp`
API), `git`, `ripgrep` (live grep), `node` (for `prettier` / `eslint_d`), a Nerd
Font, and for linting/formatting: `stylua`, `prettier`, `eslint_d`. For AI,
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
| `tests/core/keymaps_spec.lua` | global keymaps exist (save/undo/redo, resize in n+t, buffer picker) + resize helpers |
| `tests/core/autoreload_spec.lua` | `autoread`, the FileChangedShell**Post** autocmds, and the edit toast firing on an external change |
| `tests/core/ui_touch_spec.lua` | focus/term-bar highlights, `NvTermBarDim` fg≠bg, mouse/fillchars, and the per-window winbar baking the buffer number |
| `tests/core/ai_activity_spec.lua` | `winbar(buf)` idle/label/invalid + a real streaming terminal flipping working→idle |
| `tests/core/update_spec.lua` | `:NvSinnerUpdate` command exists, `is_git_repo` detection, and the not-a-git-clone warning path |
| `tests/core/health_spec.lua` | `check_tools` present/absent detection, the first-run toast (warn-once via marker, silent when nothing missing), and `:checkhealth nvsinner` running |
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
those before trusting a value under active development. Authoring this
library surfaced two doc/code mismatches in this very file, corrected above:
the AI-edit toast dedup is **250ms** (Auto-reload section) and the
focused-terminal bar/separator color is **`#80949e`**, not kanagawa dragonRed
(Touch / focus feedback section) — dragonRed `#c4746e` remains the lone
*accent* color, used for the `NvAiBusy` busy chip and UI highlights, not the
terminal bar itself.
