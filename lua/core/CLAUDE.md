# lua/core/ — native module contracts

Deep per-subsystem docs for every native (non-plugin) module in this directory.
The root CLAUDE.md carries the one-line non-negotiables; this file carries the
full behavior and the WHY. Neovim-internals theory (fast event contexts, winbar
evaluation, terminal buffers, redraw machinery) lives in the
`neovim-internals-reference` skill.

## AI — send-to-AI bridge & Ask-AI modal (no in-editor AI plugins)

avante and codecompanion were **removed**. There is no in-editor AI plugin and
no `lua/plugins/ai.lua`. AI is used by running a CLI agent — e.g. `claude`
(Claude Code) — inside the toggleterm "AI column" (panel/picker details in
`lua/plugins/terminal/CLAUDE.md`). The CLI handles its own auth/billing; the
config does **not** read `ANTHROPIC_API_KEY`. Buffers auto-reload when the CLI
edits files on disk (see *Auto-reload* below).

### Send-to-AI bridge — `ai-sessions.lua` (required from `init.lua`)
- Pipes editor context straight into an AI column's terminal job via
  `chansend()`: `<leader>as` (visual mode) sends the selection, `<leader>ab`
  sends a claude-style `@path ` mention for the current buffer (cwd-relative,
  trailing space), `<leader>ad` sends the current line's diagnostics with a
  `Fix this diagnostic in <file>:` header. Multi-line payloads are
  **bracketed-paste wrapped** (`\27[200~ … \27[201~`) so a TUI CLI receives ONE
  editable block instead of submitting each line; the bridge **never
  auto-submits** (no trailing `\r`) — text lands in the CLI input for review.
- Targeting: the terminal you are inside > the most-recently-used session with
  an open column > MRU with a live (hidden) job; with none, it calls the
  injected opener to open session 1 and warns you to resend once the CLI is up
  (no queued auto-flush — CLI startup timing makes it flaky).
- `toggleterm.lua` pushes sessions in (`register` on create, `touch` on open +
  a `TermEnter` autocmd, `unregister` on exit, `set_opener` for the fallback);
  the registry is core-native on purpose so the lualine badge, the `<leader>ja`
  picker, and the tests reach it without loading toggleterm. `M.send_to(e,
  text, opts)` sends to an EXPLICIT session entry (registry entry or
  `sessions()` row; job_id read live from `e.term`) — `M.send` is now a thin
  auto-target wrapper over it. `M._reset()` / `M._payload()` are test seams.

### Ask-AI modal — `ai-ask.lua` (required from `init.lua`)
- The IDE-style "select → ask" flow: visual `<leader>x` (free — trouble's
  `<leader>x*` maps are normal-mode only) opens a help.lua-style modal with
  **Fix / Refactor / Explain / Ask custom question**. Capture ordering is
  load-bearing: selection (`sessions.selection_text()`), line range, and
  cwd-relative path are read FIRST (getregion is only valid in visual mode),
  then visual mode is left synchronously (`nvim_feedkeys(<Esc>, "nx")`, same
  dance as `<leader>as`), THEN the modal opens. Picking builds a header +
  location + code payload (`Fix this code in lua/core/foo.lua:10-25:` …;
  custom question becomes the header via `vim.ui.input`) and dispatches
  through the bridge — never auto-submitted. With >1 registered session a
  `vim.ui.select` (same label formula as `<leader>ja`) asks which; with 0,
  `send()`'s opener fallback applies. `:NvSinnerAskAI` reruns on the last
  selection (`'<`/`'>` marks).
- **Double-click** also opens it: a global `<2-LeftMouse>` map (n+x) selects
  the word under the pointer (`normal! viw` — a superset of the default
  double-click word-select) or uses the active visual selection, then runs the
  same capture→Esc→open flow. It bails silently in floats, non-file buftypes,
  unnamed buffers, and on whitespace-only words; buffer-local `<2-LeftMouse>`
  maps (neo-tree, …) win over it. `M.double_click()` is public because mouse
  events can't be synthesized headless. Ctx lives in module state (vim.ui.*
  callbacks are async), cleared after dispatch/cancel. `M.build(key, ctx,
  question)` / `M._reset()` / `M._ctx()` are the test seams; NvMenu* styling
  re-declared locally like the other modals.

## Inline AI completion — `ai-complete.lua` (required from `init.lua`)

The **one deliberate exception** to "no in-editor AI / never read an API key".
Copilot-style ghost-text code completion, served by an OpenAI-compatible
chat/completions endpoint (OpenCode Zen "Go" plan → `glm-5.2` by default). It is
a NATIVE module (no plugin) and is distinct from the agentic AI terminal column:
that column stays for "building big things", this completes code inline in the
buffer you're editing.

- **Fast, non-reasoning model on purpose** — the default is `glm-5.2`, NOT a
  reasoning model. Reasoning models (e.g. `deepseek-v4-flash`, the original
  default) spend the `max_tokens` budget on `reasoning_content` and return an
  **empty** `content`, so `M._extract` got nil → `kind = "empty"` → the feature
  silently produced no ghost at all. `M.model()` resolves with precedence
  **`$OPENCODE_MODEL` (launch override) > persisted `settings.ai_model` (the
  `:NvSinnerIA` picker) > `M.DEFAULT_MODEL` (`glm-5.2`)** — measured the fastest
  OpenCode Zen model (~2s) that returns clean, code-only content with zero
  reasoning; `M.MAX_TOKENS` is 512 for headroom. `M.RECOMMENDED` = { glm-5.2,
  glm-5, minimax-m2.7 } (the verified-clean set the picker marks ✓); avoid
  `kimi-k2.5` (narrates prose) and `minimax-m3` (emits `<think>` inside
  `content`). `M.fetch_models(on_done)` fetches the live Go-plan catalogue (`GET
  {base}/models`, cached; nil without a key → picker uses `M.FALLBACK_MODELS`).
  Never read `reasoning_content` as the completion — it's the model's prose.
- **Manual trigger only** — insert-mode `<C-l>` (or `:NvSinnerComplete`) requests
  a suggestion at the cursor; cost is bounded by explicit triggers, which keeps
  the OpenCode Zen Go plan's usage caps predictable, so there is no
  type-ahead/debounced request path on purpose. `<C-l>` instead of the original
  `<C-g>`, which was terminal-fragile (a stray `Ctrl-Shift-G` inserts a literal
  "G"); `<C-l>` has no insert-mode default. `<Tab>` accepts (see cmp coexistence
  below), `<C-]>` dismisses; any cursor move / edit / `InsertLeave` also clears
  the ghost.
- **The API key is env-only** — read from `$OPENCODE_API_KEY` via `vim.env` at
  request time, NEVER hardcoded, persisted, or written to `settings/`. With no
  key the feature is a quiet no-op after a single WARN. `$OPENCODE_MODEL`,
  `$OPENCODE_ENDPOINT`, and `$OPENCODE_FALLBACK_MODEL` override the defaults.
- **FIM context (minuet-ai / Copilot shape)** — `_build_context` sends the WHOLE
  file around the cursor as prefix + suffix, not a fixed line window. It fits the
  combined text into `M.CONTEXT_WINDOW` chars (16000) split by `M.CONTEXT_RATIO`
  (0.75 → prefix 3:1 over suffix, since what precedes the cursor matters more),
  char-based (`strchars`/`strcharpart`, multibyte-safe), keeping the prefix's
  tail and suffix's head when it overflows. Most files fit whole, so imports at
  the top are always included (the earlier 60-line window dropped them once the
  cursor was far below). The prompt (`_build_messages`) wraps this as
  `Language` / `File` (relative path) / `<PREFIX>…<CURSOR>…<SUFFIX>`. Input size
  barely affects latency here (verified: a 3.6k-token prompt is as fast as a
  70-token one — output generation dominates), so the big window is free.
- **Zero plugin dependency** — the HTTP call is `curl` via `vim.system` (same
  shape as `git-blame.lua` / `image-open.lua`), body on stdin so the prompt
  never appears in argv (the key still does, via the `-H "Authorization:
  Bearer …"` flag — visible to `ps` on this process only, same as any curl
  invocation with an inline auth header). `M._request(payload, on_done)` is
  the ONLY function that touches the network and is called **by table
  field**, so tests swap it — the suite never makes a real request.
  `M._classify(res)` turns a curl result into
  `{ ok, status, kind, text }` (`kind ∈ ok|timeout|curl|auth|rate|http|parse|
  empty|killed`), splitting the HTTP status off the `-w "\n%{http_code}"` tail.
- **Loading spinner** — while a request is in flight, a tiny non-focusable float
  in the top-right corner (where nvim-notify toasts sit) shows an animated
  braille spinner + `AI completion…` (`NvAiLoading`, a carbon `base09` blue chip,
  distinct from ai-activity's pink terminal-busy chip), so the ~2–4s wait isn't a
  dead pause. Opened with `enter = false` + `noautocmd` so it never fires
  `InsertLeave`/`BufLeave` — the invalidate autocmd listens for those and would
  cancel the very request being awaited. Animated by a `vim.uv` timer whose
  handle lives on the durable `M._spin` (module table), stopped on every terminal
  outcome (`dispatch`), on any invalidate (cursor move / edit), on
  `set_enabled(false)`, and in `_reset`; a 429-with-fallback keeps it spinning
  through the retry. Seams: `M._loading_start/_loading_stop/_loading_active`.
- **Ghost paint discipline** — `render()` repaints via
  `nvim__redraw{ win, valid = false, flush = true }` (pcall — private API —
  with a `redraw!` fallback) immediately AND once more on the next main-loop
  tick (nvim-cmp's `misc.redraw(true)` shape). Probed on 0.12.3: insert mode
  repaints scheduled virtual text on its own (copilot.lua/minuet force no
  redraw at all), but a single flush inside the same K_EVENT can be held back
  by the TUI layer (iTerm2 + `'termsync'`/DEC 2026 synchronized output) until
  the next keystroke — the next-tick flush releases it. Actual painting (not
  just extmark existence) is pinned by a real-grid PTY spec.
- **Superseded results are dropped** — a generation counter plus `M._job:kill`
  on the next trigger / `CursorMovedI` / `TextChangedI` / `InsertLeave` (same
  discipline as `git-blame.lua`), so ghost text never paints under a moved
  cursor. Accept is **anchor-guarded**: it injects text only if the cursor still
  sits exactly where the suggestion was requested (`nvim_buf_set_text`).
- **Errors never fail silently, and honour `quiet`** — feature-affecting
  failures use WARN (which passes the quiet filter); an empty completion is a
  normal, silent outcome. A 401/403 warns about the key and enters a short
  cooldown; a 429/usage-limit retries once with `$OPENCODE_FALLBACK_MODEL` if
  set, otherwise warns and pauses ~5 min (`M._cooldown_until`, a timestamp
  compare — no timer). Missing curl / no key warn once.
- **Ghost-text accept yields to nvim-cmp** — `completions.lua` uses
  `cmp.mapping.preset.insert`, which does NOT map `<Tab>`, so overloading it is
  safe: the `<Tab>` map is an expr that returns `<Cmd>…accept()<CR>` (so the
  buffer edit runs outside expr textlock) and accepts ONLY when a suggestion is
  pending AND `cmp.visible()` is false; otherwise it falls through to a literal
  Tab.
- **On/off is one persisted setting** — `ai_complete` in `settings.lua` (default
  `true`; the menu row cycles it), applied via `M.set_enabled(v)`. `M.toggle()`
  / `:NvSinnerCompleteToggle` flip it live and persist. `NvAiGhost` is a carbon
  `base03` italic group re-applied on `ColorScheme`. Seams: `M._ns`,
  `M._pending()`, `M._cooldown_active()`, `M._reset()`, and the pure
  `M._build_context/_build_messages/_build_payload/_extract/_classify`. Spec:
  `tests/core/ai_complete_spec.lua`.

## Theme — carbon (oxocarbon / IBM Carbon port)

- Active colorscheme: **carbon**, a self-contained port of oxocarbon.nvim
  (Nyoom Engineering, inspired by the IBM Carbon Design System) — industrial
  grayscale core, blue-forward accents, color only where it carries meaning.
  No external theme plugin; the design doctrine is documented in `carbon.lua`
  itself.
- **Three files, one palette:** `lua/core/carbon.lua` holds the base16 role
  palette (`base00`…`base15`, `blend`, `lift`; one role table per background
  theme, below) and is the SINGLE source of truth — the colorscheme, the core
  modules, and every UI chrome spec `require` it; raw hexes never appear in
  consumers.
  `colors/carbon.lua` is the real colorscheme (`:colorscheme carbon`) applying
  the full highlight→role mapping (editor UI, syntax, treesitter, diagnostics,
  diff washes, markdown, telescope/cmp/notify/neo-tree, terminal ANSI).
  `lua/plugins/ui/theme.lua` is a local virtual lazy spec (`lazy = false,
  priority = 1000`) whose only job is applying it at startup.
- Key roles (dark): bg `base00 #161616`, panels `base01 #262626`, body text
  `base04 #d0d0d0` (never pure white), comments `base03 #525252` italic, floats
  recessed on `blend #131313` with **invisible borders**, focused-pane lift
  `lift #1c1c1c`. The NvSinner modals (`:NvSinnerMenu`/`Help`/`Prompts`/
  `Symbols`/AskAI) sit on the darker `shade #0d0d0d` surface
  (`NvMenuNormal`/`NvMenuBorder`, solid on purpose — like `NvMenuSel`, the
  contrast survives transparent mode) and dim the editor behind them via
  `backdrop.lua` (a full-screen non-focusable `backdrop`-black float at
  `winblend` 60, one zindex layer below the modal, torn down by a `WinClosed`
  autocmd on the modal window). Identity accent: `base09 #78a9ff` (blue);
  attention/modified: `base10 #ee5396` (magenta); busy chip: `base12 #ff7eb6`
  (pink); focused terminal bar: `base11 #33b1ff` (carbon's terminal-mode
  accent).
- Chrome highlights are re-applied via `ColorScheme` autocmds so they survive
  colorscheme reloads and lazy-loaded plugins.
- **Background themes** — `M.themes` / `M.theme_names` in `carbon.lua` name
  seven full role tables selectable from `:NvSinnerMenu` "Background theme":
  `carbon` (the reference dark, `M.dark`), `moon` (the light variant,
  `M.light`), and five ORIGINAL palettes inspired by well-known schemes —
  `onedusk` (One Dark Pro), `mocha` (Catppuccin Mocha), `kyoto` (Tokyo
  Night), `fjord` (Nord), `monolith` (Monokai). Each registry entry maps the
  name to its role table (`palette`) and its `vim.o.background` `variant`
  (only `moon` is light); each palette fills the EXACT role set of `M.dark`
  (pinned by `tests/core/carbon_spec.lua`) with carbon's role semantics —
  base09 identity, base10 attention, base12 busy — so every consumer works
  unchanged. `M.theme()` resolves the flag (`vim.g.nvsinner_theme` /
  `$NVSINNER_THEME`, unknown → `"carbon"`; the legacy
  `nvsinner_background`/`$NVSINNER_BACKGROUND` flag still maps
  light→`moon` when no theme flag is set), `M.colors()` selects the palette
  from it, and `M.background()` returns the active theme's variant (what
  `theme.lua` boots `vim.o.background` with). Switching is live:
  `settings.set("theme", …)` → flag + `:colorscheme carbon` → every
  ColorScheme consumer retints. Accent packs overlay by the theme's
  dark/light variant, so `blue` (the empty pack) shows each theme's own
  signature accent and the other packs apply their generic overrides.
- **Feature flags** (resolved by `carbon.lua`; `vim.g` wins over env, which
  wins over the persisted `:NvSinnerMenu` value seeded by `settings.lua`):
  `vim.g.nvsinner_theme` / `$NVSINNER_THEME` (background theme, above;
  `"carbon"` default), `vim.g.nvsinner_transparent` /
  `$NVSINNER_TRANSPARENT` (drops every full-surface bg — editor, floats,
  panels — while chips/bars stay solid for legibility; `ui-touch.lua` also
  drops its focus lift and dim-bar strip in transparent mode),
  `vim.g.nvsinner_accent` / `$NVSINNER_ACCENT` (accent pack, below),
  `vim.g.nvsinner_folder` / `$NVSINNER_FOLDER` (neo-tree folder color pack,
  below), and the four single-role slot flags
  `vim.g.nvsinner_notif|variables|strings|functions` /
  `$NVSINNER_NOTIF|VARIABLES|STRINGS|FUNCTIONS` (below). Documented for users
  in README's *Theme options (carbon)*, which also carries the glass→carbon
  migration steps.
- **Accent packs** — `M.accents` in `carbon.lua` defines four selectable
  identity accents (`blue` default / `magenta` / `green` / `purple`, IBM
  Carbon tones). A pack overrides ONLY the identity text-accent pair (`base09`
  and its pale companion `base15`) in `M.colors()`; gray surfaces
  (`base00`/`base01`/`base02`, `blend`, `lift`) never change. Because every
  consumer re-resolves `M.colors()` on `ColorScheme`, switching the accent is
  just `vim.g.nvsinner_accent = <pack>` + `:colorscheme carbon` (which is what
  `settings.lua` does).
- **Single-role color slots** — `M.slots` / `M.slot_choices` in `carbon.lua`
  generalize the pack idea to element classes that take ONE color: `notif`
  (the NotifyINFO* toast accent — WARN/ERROR keep their semantic colors),
  `variables` (Identifier + `@variable*`/`@parameter`/`@field`), `strings`
  (String/Character), `functions` (Function + the whole
  `@function*`/`@method` family). Choices are role names (`accent` follows
  the accent pack, plus teal/aqua/magenta/pink/green/purple/plain);
  `"default"` makes `M.slot_color()` return nil and the colorscheme keep its
  stock per-group roles (functions stock is a deliberate MIX of roles, which
  is why stock can't be expressed as a single choice). Flags:
  `vim.g.nvsinner_<slot>` / `$NVSINNER_<SLOT>`, persisted via `:NvSinnerMenu`.
- **Folder color packs** — `M.folders` in `carbon.lua` maps a pack name
  (`accent` default / `teal` / `aqua` / `pink` / `green` / `purple` / `gray`)
  to a **role-name pair** `{ name, icon }` (roles, not hexes — so one table
  serves both variants and every accent pack). `M.folder_colors()` resolves
  the pair through `M.colors()`; `colors/carbon.lua` reads it for
  `NeoTreeDirectoryName` / `NeoTreeDirectoryIcon` on every apply. The stock
  `accent` pack reproduces the original look (name `base09` — follows the
  accent pack — icon pink `base12`); the others paint name + icon in one
  fixed accent, `gray` gives a monochrome tree. Like accents, only text
  accents change — never surfaces.

## Settings & menu — `settings.lua` + `menu.lua` (required from `init.lua`)

- `settings.lua` persists user choices as JSON in the distro's **`settings/`
  folder** (`stdpath("config")/settings/nvsinner-settings.json`, gitignored —
  next to the committed `settings/prompts.json`, so all user-tweakable state
  sits in one place; a pre-`settings/` cache under `stdpath("data")` is
  migrated on first load) and applies them: `theme` (background theme; a
  legacy persisted `background` key migrates to `moon`/`carbon` on load) /
  `transparent` / `accent` / `folder` / `notif` / `variables` / `strings` /
  `functions` (carbon flags), `tree_side` (neo-tree position), `ai_side` (AI/vertical
  terminal column side), `quiet` (mute INFO-level `vim.notify`; WARN/ERROR
  always pass). **Required right after `core.options` in `init.lua`** so it
  can seed the carbon `vim.g` flags before lazy applies the theme — and it
  only seeds a flag when neither `vim.g` nor the env var is set, preserving
  the documented `vim.g` > env precedence. Every `M.set` persists, applies
  live (theme changes re-run `:colorscheme carbon`), and fires
  `User NvSinnerSetting` (`data = { key, value }`) so lazy specs react without
  eager requires: `toggleterm.lua` re-asserts its layout on `ai_side`,
  neo-tree reads `tree_side` on each `<leader>e`. The quiet wrapper is
  installed on `User VeryLazy` (after noice replaces `vim.notify`) and
  wraps/unwraps the *current* notify. `M.load({ file = … })` /
  `M.setup({ file = … })` are test seams (mirror `update.lua` / `health.lua`).
- `menu.lua` defines **`:NvSinnerMenu`** — a Mason-style floating modal over
  the eleven settings. Keyboard: `j`/`k` (or arrows) move, `h`/`l` / `<CR>` /
  `<Space>` cycle a value, `1`-`9` jump (rows past 9 via j/k or mouse),
  `q`/`<Esc>` close. Mouse: hovering moves the selection onto the row under
  the pointer (`<MouseMove>`, same feel as the dashboard menu — the
  buffer-local map also shadows ui-touch's LSP-hover handler over the modal)
  and a click cycles the row (`<LeftRelease>` + `getmousepos`). The AI CLI
  picker carries the same hover/click behavior. Every change applies live and
  persists via `settings.set`. Rendering uses exact byte spans (the `▸` marker
  is multi-byte) with extmarks in the `nvsinner_menu` namespace; highlights
  are the fg-only `NvMenu*` groups (carbon roles, re-applied on `ColorScheme`;
  `NvMenuSel` keeps a solid `base01` wash on purpose, chips stay legible in
  transparent mode). The NvMenu* groups are shared with toggleterm's AI CLI
  picker so both read as one component. There is deliberately NO WinLeave
  auto-close: changing "AI column side" makes toggleterm jump windows to
  re-assert the layout, which would tear the modal down mid-interaction.

## Prompt library — `prompts.lua` + `settings/prompts.json`

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
  the test seam (mirrors `settings.lua`).
- `settings/prompts.json` is **committed** (it ships eleven default prompts:
  PR description, strict code review, feature plan, bug fix,
  tests-from-pattern, commit message, refactor, explain code, docstrings,
  security review, git conflict resolution — all with `[PLACEHOLDER]` slots to
  fill after pasting); the `:NvSinnerMenu` cache next to it is **gitignored**.
  Only entries 1–9 get digit shortcuts; 10–11 are reached via `j`/`k` or mouse.

## Command palette — `help.lua` (required from `init.lua`)

- **`:NvSinnerHelp`** — a Mason-style floating modal listing the distro's own
  commands (title + muted description), **grouped into sections** (ai / editor /
  settings / maintenance / other — `SECTION_OF` maps each command, unknowns land
  in "other") with a muted `─ NAME ───` rule header per section; the layout is
  computed in `refresh()` (per-item `line` + a `line_map`) since headers make
  rows non-uniform. Selecting one (keyboard `<CR>`/`<Space>`/`l`, or a mouse
  click) **runs it and auto-closes** the modal, so it doubles as the
  discoverability entry point for the `:NvSinner*` surface. Discovered
  descriptions are sanitized (`strtrans` changing the string = the
  `nvim_get_commands` definition mangled multi-byte/`<...>` chars → blank);
  commands with rich descs get a `DESCS` override instead. Navigation mirrors
  the other modals: `j`/`k` (or arrows) move, `1`-`9` jump, hover moves the
  selection, `q`/`<Esc>` close. Same `NvMenu*` styling.
- **The list is self-maintaining**: `M.refresh()` (re-run on every open) scans
  `nvim_get_commands()` for names starting with `NvSinner` (excluding itself)
  — for Lua commands the returned `definition` field carries the registered
  `desc` (verified empirically), which becomes the description; a `DESCS`
  table overrides it where a keymap hint helps, and `EXTRAS` appends
  non-command entry points (`:checkhealth nvsinner`). A future `:NvSinnerFoo`
  shows up automatically with its `desc`.
- **`EXCLUDE` hides the AI commands** — `NvSinnerAskAI` / `NvSinnerComplete` /
  `NvSinnerCompleteToggle` / `NvSinnerPrompts` live inside the `:NvSinnerIA` hub
  (below), so the palette's "ai" section shows a single `NvSinnerIA` row instead
  of the scattered commands. The excluded commands still exist (keymaps + the
  hub call them); they're just skipped in `refresh()`.
- `M.run()` closes **before** executing on purpose: the target may open its own
  modal (`:NvSinnerMenu`, `:NvSinnerIA`) or window (`:checkhealth`) and must not
  land inside this float. It returns the command name (test seam).

## AI hub — `ia.lua` (required from `init.lua`)

- **`:NvSinnerIA`** (`<leader>xi`) — a Mason-style modal that consolidates every
  AI entry point, so `:NvSinnerHelp` lists one `NvSinnerIA` row (see `help.lua`'s
  `EXCLUDE`). Two sections of rows, each carrying a `kind`:
  - **SETTINGS** — `AI completion` (`kind = "toggle"` → flips `settings.ai_complete`
    in place, same effect as `:NvSinnerCompleteToggle`) and `Model`
    (`kind = "select"` → opens a `vim.ui.select` model picker).
  - **ACTIONS** — `Ask AI` / `Complete at cursor` / `Prompt library`
    (`kind = "action"` → runs `:NvSinnerAskAI` / `:NvSinnerComplete` /
    `:NvSinnerPrompts` and **closes first**, same rationale as `help.run()`).
- `M.activate()` dispatches by `kind`; `h`/`<Left>` = `activate_back` (flip / open
  picker for settings rows, no-op on actions). Same keyboard/mouse scheme,
  `NvMenu*` styling, and `backdrop.attach` as the other modals.
- **Model picker** — `open_model_picker()` calls
  `ai-complete.fetch_models()` (live Go catalogue, cached) then
  `vim.ui.select`; `M._model_items(catalog)` orders `RECOMMENDED` first (✓) then
  the rest, falling back to `M.FALLBACK_MODELS` offline. `M._choose_model(id)`
  persists `settings.ai_model` (what `ai-complete.M.model()` then reads) and
  re-renders — it's the test seam the picker callback routes through, so the
  choice logic is exercised without a real popup. Seams: `M.open/close/move/
  activate`, `M._rows/_model_items/_choose_model`.

## Document symbols — `symbols.lua` (required from `init.lua`)

- **`:NvSinnerSymbols`** / `<leader>cs` / `<leader>xo` — LSP document-symbols
  modal; pick a symbol to jump to it. `_flatten()` handles both LSP shapes
  (nested DocumentSymbol children indented, flat SymbolInformation;
  position-less entries skipped). The `nvsinner_symbols` float is nofile,
  non-modifiable, with cursorline; `run()` jumps the source window to the
  picked symbol; warns when no LSP client is attached.

## Backdrop — `backdrop.lua` (required from `init.lua`)

- Dimming backdrop behind the NvSinner modals: `attach()` opens a full-screen
  non-focusable `backdrop`-black float at `winblend` 60, one zindex layer
  below the modal, torn down by a `WinClosed` autocmd on the modal window;
  invalid-window guard included. `NvMenuBackdrop` carries the carbon
  `backdrop` role.

## Touch / focus feedback — `ui-touch.lua` (required from `init.lua`)

Makes focus and the mouse feel tactile, layered on the carbon theme (roles
pulled from `carbon.lua`). The illuminate/cursorline plugin notes live in
`lua/plugins/ui/CLAUDE.md`.

- **Active-window border + glow** — the focused window/terminal gets a lifted
  `Normal` (`NvFocusNormal` on `lift #1c1c1c`) plus an accent separator and a
  subtle `CursorLine` (`base01`); everything else stays on `base00 #161616`
  with a near-invisible `WinSeparator` (`base01`). **Focused terminals** (AI
  column / horizontal terminal) additionally get a **full-width top bar** (a
  `winbar`, `WinBar:` `NvTermFocusBar` on `base11 #33b1ff` — carbon's
  terminal-mode accent, dark text on a solid chip) plus a matching brighter
  separator (`NvTermFocusSeparator`) — a 1px split line was too faint on the
  near-black bg, so the bar carries the focus cue. The bar is **always
  present** (dim `NvTermBarDim` `base01` when unfocused, bright when focused)
  so the terminal never reflows; it just brightens. This works in all three
  terminal layouts (horizontal-only, vertical-only, both). Toggled via
  `WinEnter`/`WinLeave` autocmds setting per-window `winhighlight` (and
  `winbar` for terminals). Special windows (neo-tree, telescope, dashboard,
  floats) are skipped by an `eligible()` guard so their own `winhighlight` is
  left intact.
- **Agent / terminal activity spinner** — the terminal top bar is no longer an
  empty strip: its `winbar` is a live expression
  `%{%v:lua.require'core.ai-activity'.winbar(<buf>)%}` built per-window by
  `term_bar(win)` in `ui-touch.lua` (the buffer number is baked in — see
  *Agent activity* for why), so the bar shows a braille spinner + `working…`
  while the terminal is producing output and `● idle` when it goes quiet. Busy
  is drawn in an accent **chip** (`NvAiBusy`, carbon pink `base12`) so it
  stays visible even when the terminal is unfocused; for that the unfocused
  bar `NvTermBarDim` carries a readable muted `fg` (`base03`) instead of
  `fg == bg` (which hid the label).
- **Mouse hover** — `mousemoveevent` is on; a debounced `<MouseMove>` handler
  shows the LSP doc (or the line's diagnostics as fallback) for the symbol
  under the *pointer* in a `relative="mouse"` float, no `<K>` needed. The float
  is non-focusable and torn down on cursor move / mode / layout change.
- Highlights live in an `apply_hl()` re-applied on `ColorScheme`. All values
  are roles from `carbon.lua` — never hardcode a hex here.
- **First-open caveat** — a toggleterm window fires `BufWinEnter` while its
  buffer is still a scratch (`buftype ""`), so `focus()` would style it as a
  code pane and skip the terminal winbar; the `TermOpen` trigger added to the
  focus autocmd re-applies focus once the buffer is a `terminal`, so the bar +
  spinner show on the very first open.

## File badge — `filebadge.lua` (required from `init.lua`)

The native per-window filename badge — the in-repo replacement for
incline.nvim (`lua/plugins/ui/incline.lua` is kept `enabled = false` as a
one-line revert). Shows which file each window holds and where the focus is:
a right-aligned `● <icon> <filename> ●` badge (focus dot `base09` · devicons
filetype icon as fg-only color · name `base04` bold when focused / `base03`
muted otherwise · modified dot `base10`) rendered **in the winbar**, so it
owns its own line and never floats over buffer text (incline's float
overlapped line 1 on winbar-less windows).

One renderer (`M.parts(buf, focused)` → `M.fragment()`), two delivery paths:

- **Code windows** — barbecue's `custom_section` (`lua/plugins/ui/barbacue.lua`)
  calls `M.section()`, which returns the **dynamic** `M.SECTION_EXPR`
  (`%{%v:lua.require'core.filebadge'.fragment()%}`), so the badge rides the
  right end of the existing breadcrumb winbar. It must stay dynamic: barbecue
  only rebuilds the winbar string of the window an event touched, so a
  build-time focus check left stale focus dots on every other window — the
  expression re-evaluates on each redraw and decides focus at draw time via
  `g:actual_curwin`.
- **Markdown windows** (excluded from barbecue) — this module owns the winbar:
  `FileType markdown` / `BufWinEnter` autocmds set it to `M.EXPR`
  (`%{%v:lua.require'core.filebadge'.winbar()%}`, re-evaluated per redraw;
  focus detected via `g:actual_curwin`). The line renders
  `󰈙 Open view │ ● 󰍔 file.md`: the "Open view" reading-view chip is a native
  `%@…%X` click region driving `_G.NvMdReader.click` — chip state/label/toggle
  live in `lua/core/markdown.lua`.

Highlights (`NvBadgeDot/File/FileNC/Mod/Chip/Sep`) are carbon roles applied in
`apply_hl()` and re-applied on `ColorScheme`; per-icon-color groups are
created on demand and their cache dropped on `ColorScheme` (a colorscheme
switch clears them). devicons is `pcall`-required inside the render (this
module loads before lazy.nvim). Spec: `tests/core/filebadge_spec.lua`.

## Agent activity — `ai-activity.lua` (required from `init.lua`)

- Detects whether the program in a terminal — an AI CLI (`claude`, `kiro`,
  `opencode`, …) or any command — is **working vs. idle**, and renders it as a
  spinner in the terminal `winbar` (the content side of `ui-touch.lua`'s bar).
  Generic on purpose: vertical AI columns AND the horizontal `<leader>t`
  terminals light up (a long build shows `working…`).
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
  something is busy or a state just changed (no idle redraws). The timer handle
  is stored on the module table (`M._timer`) so luv won't GC the unreferenced
  active handle and silently stop the spinner.
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
  `base12` chip, `apply_hl` re-applied on `ColorScheme`) so it shows even on an
  unfocused/dim bar; idle is plain and inherits the focus-aware WinBar
  highlight. Tunables (`POLL_MS`, `IDLE_MS`, `SPINNER`, labels) live at the top
  of the file.
- **Per-terminal label** — `M.winbar(buf)` also prefixes a buffer var
  `b:nv_term_label` if present (e.g. `AI · 3 ⠹ working…`). `toggleterm.lua`
  sets it in `on_panel_open` from the term id: AI panels use the reserved ids
  100+ (`AI · <id-99>`), the `<leader>t` horizontals use 1–9 (`term <id>`);
  an AI column opened as a *plain terminal* (CLI picker) carries the
  `__nv_label` override and is titled `term` instead. Plain `:terminal`
  buffers have no label and just show the spinner.
- **Third state: "needs input" (opportunistic, via OSC)** — a `TermRequest`
  autocmd feeds `M._on_osc(buf, seq)` (test seam): OSC `133;B` (prompt-input
  start — it fires AFTER the prompt renders, so the prompt's own output can't
  clobber it via `on_lines`) sets `awaiting`; `133;C` (command start) clears
  it; OSC `9` / `777` terminal notifications also set it. The winbar renders a
  `◆ needs input` chip (`NvAiAwait`, `base10` — carbon's attention magenta —
  re-applied on `ColorScheme`); any fresh output clears `awaiting` in
  `on_lines` (output trumps a stale prompt mark; still a plain table write —
  fast-context legal). Probed on NVIM 0.12.3: `TermRequest`'s `ev.data` is a
  **table** `{ sequence = … }` (a string on 0.11 — the handler normalizes
  both) and the callback is NOT a fast event context. **Honest limits:** this
  only lights up for OSC emitters — shells with OSC-133 integration and CLIs
  that send notification sequences (unverified for `claude`); the 1.2s idle
  heuristic remains the primary signal. `_on_osc` repaints via the same
  `nvim__redraw` path (the idle-skipping timer wouldn't).
- **Cockpit API + badge** — `M.status(buf)` → `"working" | "awaiting" |
  "idle" | nil` (nil for untracked buffers) is the public per-buffer state;
  `lualine.lua` combines it with `ai-sessions.M.sessions()` into an
  `lualine_x` badge (`AI: 2 working · 1 needs input`, empty with no sessions —
  the existing 100ms statusline refresh keeps it live). `<leader>ja` opens a
  `vim.ui.select` picker (telescope-ui-select skins it) that jumps to a
  session's window (or reopens a hidden one via the toggleterm opener); like
  `<leader>j2…`, it costs a bare `<leader>j` one `timeoutlen`.

## Auto-reload — `autoreload.lua`

- When the AI CLI edits a file from the terminal column, the on-disk version is
  reloaded into the buffer automatically (no W11/W12 prompt). Done via
  `autoread` + a `FileChangedShell` handler that sets `v:fcs_choice = "reload"`,
  plus `checktime` on focus/window-enter events and a 1s `vim.uv` timer. The
  timer handle is anchored on the module table (`M._timer`) — an unreferenced
  active luv timer can be GC-reaped and silently stop the poll (same guard as
  `ai-activity.lua`).
- Trade-off: **disk wins** — unsaved in-Vim edits to a buffer the AI changes are
  discarded. Intended for the viewer-style workflow (edit in the AI pane).
- **Edit toast** — a small `vim.notify` (`🤖 AI · edited <file>`) names the file
  an external process just wrote. Hooked on **both** `FileChangedShell` (the
  conflict case) **and** `FileChangedShellPost`: with `autoread` on and the
  buffer unmodified — the common case — Neovim reloads silently and fires
  *only* `FileChangedShellPost`, NOT `FileChangedShell` (verified empirically),
  so the Post event is required to catch the usual AI edit. A 250ms per-file
  dedup keeps the two events from double-toasting one write. Only loaded
  buffers fire either, so you're notified for files you actually have open.

## AI edit highlights — `ai-edits.lua` (required from `init.lua`)

- The lines an external write changed get a **full-width background wash in
  the user's accent** (`NvAiEdit`: `base09` — follows the :NvSinnerMenu accent
  pack — blended into `base00` at low alpha, computed per-channel since
  highlights have no opacity; a CursorLine-subtle wash that carries the accent
  hue, so code text keeps contrast and the marks never read as git state;
  retinted live on ColorScheme). A per-buffer snapshot of the last
  *user-blessed* content (first read, last save, last clear) is `vim.diff`-ed
  against the reloaded buffer on `FileChangedShellPost`; deliberately NOT
  re-snapshotted on every `BufReadPost`, or the reload would overwrite the
  pre-reload content before the diff runs. Marks survive while focus stays in
  the AI column and clear the moment the user **takes over the file** — cursor
  move, edit, or insert in that buffer (autocmds armed one scheduled tick late
  so the reload's own cursor restore can't wipe them). Deletion-only hunks are
  skipped (no surviving line to wash); buffers over `M.MAX_LINES` (20000) and
  special buftypes are skipped. `M.mark`/`M.clear`/`M._reset`/`M._ns` are the
  test seams.

## Updater — `update.lua` (required from `init.lua`)

- Defines the `:NvSinnerUpdate` command (à la `:NvChadUpdate` / `:AstroUpdate`):
  `git -C <config> pull --ff-only` (async via `vim.system`) →
  `require("lazy").restore()` → `:checkhealth`, then a toast reminding you to
  **restart** (the pull rewrites the Lua files on disk but the running Neovim
  keeps the old modules loaded).
- **`restore`, not `sync`** — updates check every plugin out to the commit pinned
  in the committed `lazy-lock.json`, so installs/updates reproduce the tested
  plugin set instead of floating to latest (`:Lazy sync` is the opt-in "float"
  path). `install.sh` uses `Lazy! restore` for the same reason.
- **No-op-with-warning when the config dir isn't a git clone** (`is_git_repo`
  checks for a `.git` dir OR file): the dev machine's `~/.config/nvsinner` is a
  symlink to this repo and a manual copy has no remote — neither can `git pull`.
  `M.update({ dir = … })` takes an optional dir override purely as a test seam.

## Plugin/Mason sync — `sync.lua` (required from `init.lua`)

- Defines **`:NvSinnerSync`** — the explicit **opt-in "float" path** that the
  non-negotiable `restore`-doctrine reserves for developers:
  `require("lazy").sync()` (install missing + update to latest + clean removed
  — **rewrites `lazy-lock.json`**, so retest and commit it) followed by a
  **Mason package update** phase. It never replaces `:NvSinnerUpdate`, which
  stays pinned to the lockfile; install/update paths are untouched.
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

## Health check — `health.lua` (required from `init.lua`)

- Surfaces missing external tools (ripgrep, node, stylua, prettier, eslint_d, a
  Nerd Font) so features fail *loudly* instead of silently no-op-ing. **One tool
  table (`M.tools`), two entry points:**
  - **`:checkhealth nvsinner`** — `lua/nvsinner/health.lua` is a thin provider
    (`{ check = … }`) that Neovim discovers by module path
    (`lua/<name>/health.lua` → checkhealth name `<name>`); it delegates to
    `core.health.report()`, which walks `check_tools({ with_version = true })`
    and emits `vim.health.ok/warn` with an install hint per missing tool. It
    shows in the full `:checkhealth` (and the one `:NvSinnerUpdate` runs) under
    "nvsinner" too.
  - **First-run toast** — `M.setup()` (called at require time) registers a
    `User VeryLazy` autocmd that, after an 800ms defer (so nvim-notify is
    ready), runs `M.first_run_notify()`: if any tool is missing it fires a
    one-time `vim.notify` pointing at `:checkhealth nvsinner`. A marker file
    under `stdpath("state")` makes it **greet once** (written even when
    nothing's missing, so it never nags). `M.first_run_notify({ marker = … })`
    takes a marker override as a test seam (mirrors `update.lua`'s
    `{ dir = … }`).
- **Headless never consumes the first run** — `setup()` bails when
  `#vim.api.nvim_list_uis() == 0`, so the installer's headless `Lazy! restore`
  and the test harness don't write the marker or toast; the user's first
  *interactive* launch gets the greeting.
- **Nerd Font is info-only** — it's a terminal/GUI font setting that can't be
  probed from inside Neovim, so it's reported as `vim.health.info` and left OUT
  of the missing-count that drives the toast. Tool checks use
  `vim.fn.executable` (fast, no subprocess); versions shell out only for
  `:checkhealth`.

## Image viewer — `image-open.lua` (required from `init.lua`)

- Opening an image file shows it instead of dumping binary bytes. iTerm2 (this
  config's terminal) uses its own inline-image escapes, **not** the Kitty
  graphics protocol that in-buffer image plugins need, so the image is popped
  into **macOS Quick Look** (`qlmanage -p`, async/non-blocking) and the buffer
  shows a small placeholder (icon, filename, `sips` dimensions, size).
- **`BufReadCmd` takes over the read** for the image extensions (`png`, `jpg`,
  `webp`, `svg`, …, both cases) and sets `buftype = "nofile"` so `:w` can never
  overwrite the image with the placeholder text. Setting `filetype` last fires
  the `nvsinner_image` `FileType` autocmd, which binds `<cr>` (reopen Quick
  Look) and `gO` (open in Preview.app).
- **Auto-preview is interactive-only** — it bails when `#nvim_list_uis() == 0`
  (headless/tests) and skips **floating** windows
  (`win_config.relative ~= ""`), so telescope's preview doesn't spawn a Quick
  Look storm; a `b:` flag makes it pop once per buffer.

## Inline git blame — `git-blame.lua` (required from `init.lua`)

- Replaces git-blame.nvim (its spec is kept disabled as a one-line revert).
  The cursor line gets an eol virtual-text annotation
  ` <summary> • <date> • <author> • <sha7>` in `NvGitBlame` (carbon `base03`
  italic — the comment tone).
- **Debounce discipline**: movement clears the annotation immediately (a
  stale blame under a new cursor line reads as wrong data) and re-arms a
  `vim.uv` timer (`M.DELAY` 350ms, handle anchored on `M._timer`). The timer
  fires one async `git blame -L <line>,<line> --porcelain` via `vim.system`;
  a **generation counter** drops any in-flight result whose request predates
  the latest movement.
- **The buffer contents are blamed**, not the file on disk (`--contents -`
  with the buffer lines on stdin), so unsaved edits above the cursor don't
  shift annotations onto the wrong commit. All-zero shas (uncommitted lines)
  render nothing — no fake annotation.
- Untracked/non-repo buffers are cached as **dead** after the first failed
  blame (cleared on `BufWritePost`) so a scratch note doesn't spawn a git
  process per cursor move. While typing (`CursorMovedI`/`InsertEnter`) it
  only clears — re-blaming per keystroke is churn.
- `:NvSinnerBlameToggle` flips the whole feature. Seams: `M._ns`,
  `M.refresh(buf)` (immediate, no debounce — cursor autocmds don't fire
  headless), `M._format(porcelain)`, `M._reset()`.

## Symbol occurrences — `illuminate.lua` (required from `init.lua`)

- Replaces vim-illuminate (spec kept disabled). Two providers: LSP buffers
  use the builtin `vim.lsp.buf.document_highlight()` (rendered through
  `LspReferenceText/Read/Write`, styled here with the panel-gray underlines —
  `base01`, writes `base02`); buffers without a capable client get a
  **visible-range word-boundary scan** (extmarks in `nvsinner_illuminate`),
  gated to buffers with a treesitter parser so prose doesn't light up.
- Parity constants from the old spec: `M.DELAY` 120ms, `M.MAX_LINES` 4000,
  `M.DENYLIST` (neo-tree, alpha, dashboard, TelescopePrompt, toggleterm,
  lazy, mason, help). Same clear-then-debounce shape as `git-blame.lua`
  (`M._timer` anchored). Seams: `M._ns`, `M.refresh(buf)`, `M.clear(buf)`,
  `M._reset()`.

## Sessions — `sessions.lua` (required from `init.lua`)

- Replaces persistence.nvim (spec kept disabled). A thin `:mksession`
  wrapper: one session per cwd (percent-encoded path) under
  `stdpath("state")/sessions/` — NVIM_APPNAME-scoped, so nvsinner sessions
  never collide with another config's. `vim.o.sessionoptions` keeps the old
  `options` list verbatim (`buffers,curdir,tabpages,winsize`).
- **Autosave gate**: `VimLeavePre` saves only after a real file
  (`buftype == ""`) was opened this run (quitting straight from the dashboard
  must not overwrite a real session with an empty one), and not after
  `stop()`. `stop()` pauses ONLY the autosave — explicit `save()`/`load()`
  still work.
- Surface: `<leader>Sc` restore cwd session, `<leader>Sl` restore the newest
  session anywhere (mtime scan via `M.last()`), `<leader>SQ` quit no-save —
  plus `:NvSinnerSessionLoad/Last/Stop` so `:NvSinnerHelp` lists them. Seams:
  `M._reset({dir=…})`, `M._started()`.

## Indent guide — `indent.lua` (required from `init.lua`)

- Replaces indentmini.nvim (spec kept disabled), which ran `only_current =
  true`: ONE vertical guide on the indent level enclosing the cursor line, in
  `IndentLineCurrent` (carbon `base02` — same role the old spec set).
- **Compute/paint split**: cursor autocmds (`CursorMoved(I)`, `TextChanged(I)`,
  `BufEnter`, `WinScrolled`) recompute the scope into per-buffer state —
  normal context, so `vim.fn.indent` is safe — and a **decoration provider**
  paints it with *ephemeral* overlay extmarks (`virt_text_win_col`) at redraw
  time: nothing to clear, nothing stale. `on_win` gates to the window the
  scope was computed against (the "current" scope is a cursor concept).
- Scope = contiguous lines indented past `indent(cursor) - shiftwidth`
  (blank lines ride along, blank edges are trimmed; a blank cursor line takes
  the deeper of its neighbors). The scan is **clamped to the visible range**,
  so huge files cost the same as small ones. Columns are display cells
  (`vim.fn.indent` expands tabs), so tab-indented files line up.
- Guards: `buftype == ""` only, `M.DENYLIST` filetypes (illuminate's list +
  markdown — prose has no indent scopes). Seams: `M._ns`, `M.refresh(buf,
  win)`, `M._scope(buf)`, `M._reset()`.

## Hex color chips — `colorizer.lua` (required from `init.lua`)

- Replaces nvim-colorizer.lua (spec kept disabled): `#rgb` / `#rrggbb` /
  `#rrggbbaa` literals in the **visible range** get a bg chip in their own
  color. Hex codes were the only used surface — the plugin's
  css-function/tailwind/name machinery was dead weight.
- Chip bgs are by definition the buffer's literal colors (user data, not
  config choices — the no-hardcoded-hex rule is about the latter); the chip
  **fg is a carbon role**: `base00` on light chips, `base06` on dark ones,
  split at luminance 140. Groups (`NvColorRRGGBB`) are created on demand and
  the cache drops on `ColorScheme` (a colorscheme apply starts from
  `hi clear`).
- Boundary rules: only exact 3/6/8-digit runs, rejected when glued to a word
  char or another `#` (`abc#fff`, `##fff`); the alpha byte is dropped.
  Rescans on `BufWinEnter` / `TextChanged(I)` / `InsertLeave` /
  `WinScrolled`; `buftype == ""` only. Seams: `M._ns`, `M.refresh(buf, win)`.

## TODO keyword chips — `todo.lua` (required from `init.lua`)

- Replaces todo-comments.nvim (spec kept disabled; drops a plenary consumer):
  `TODO:` / `FIXME(author):` / `HACK:` … get a solid accent chip (dark
  `base00` text, bold) scanned over the **visible range**. The colon is
  required (plugin-default parity) so prose mentions never light up; an
  optional `(author)` tag joins the chip.
- Families → carbon roles, semantic: TODO `base13` (carbon's Todo green),
  FIX/FIXME/BUG/FIXIT/ISSUE `base10` (attention magenta), HACK/WARN/
  WARNING/XXX `base14` (the DiagnosticWarn purple), PERF/OPTIM/… `base15`,
  NOTE/INFO `base08`, TEST/TESTING/PASSED/FAILED `base07`. Groups `NvTodo*`,
  re-applied on `ColorScheme`; `M.KEYWORDS` is the public keyword→group map.
- `:TodoTelescope` is intentionally NOT replicated — telescope live-grep
  covers it until NvSinnerFind exists (roadmap). Same event set and guards as
  `colorizer.lua`. Seams: `M._ns`, `M.refresh(buf, win)`.

## Window picker — `window-picker.lua` (required from `init.lua`)

- Replaces nvim-window-picker (spec kept disabled). Sole consumer is
  neo-tree's `open_with_window_picker` (`w`), which does
  `pcall(require, "window-picker")` → `picker.pick_window({})` — so this
  module registers itself in **`package.preload["window-picker"]`** and
  neo-tree works unchanged. The preload shim first checks the rtp for the
  real plugin (`nvim_get_runtime_file`) and defers to it when found, so
  flipping the stub back to `enabled = true` stays a one-line revert.
- `pick_window`: candidates are the tab's non-floating windows minus
  `M.BT_IGNORE` (terminal/prompt/quickfix) and `M.FT_IGNORE` (neo-tree,
  notify, noice); a single candidate is returned without prompting; otherwise
  each gets a small centered non-focusable float chip (`NvWinPick`, `base00`
  on `base09`) with a letter from `M.CHARS`, and `getcharstr()` picks
  (case-insensitive; anything unmapped/interrupt → nil). Overlays are always
  torn down. Seams: `M._candidates()`, `M._getchar` (stub point).

## Markdown reading view — `markdown.lua` (required from `init.lua`)

- Replaces render-markdown.nvim (spec kept disabled — but reverting is NOT a
  one-liner: re-enabling the plugin must be paired with removing the
  `require("core.markdown")` line from `init.lua`, or `_G.NvMdReader` and
  `<leader>m` double-register). An opt-in, per-session reading view on
  markdown buffers, OFF by default and deliberately not persisted in
  core/settings: toggled via `<leader>m` (buffer-local, `FileType markdown`)
  or the winbar "Open view" chip.
- **The `_G.NvMdReader` seam**: the module itself is the global —
  `.on` (bool), `.label()` (`"󰈙 Reading view · on"` / `"󰈙 Open view"`),
  `.toggle()`, `.click()` — consumed duck-typed by `filebadge.lua`'s markdown
  winbar evaluator (which draws the `%@…%X` click region). Keep the shape or
  update filebadge in lockstep.
- **Feature set (minimal on purpose)**: accent heading bars (overlay `▎` over
  the `#…` run + `line_hl_group` `NvMdH1`–`H6`), `•`/`◦` bullet overlays,
  checkbox glyphs (`󰄱`/`󰱒`, done lines dimmed `NvMdDone`), blockquote `▍`
  bars + dim italic body, code-fence block shading (`NvMdCode`, bg-only on
  `blend`), and full-width `─` horizontal rules. NO tables, link concealing,
  or inline-code chips — this is a reading aid, not a renderer.
- **Pattern-based on purpose — never the markdown TS tree.** Plain Lua
  patterns over the visible range (same shape, event set and guards as
  `colorizer.lua`/`todo.lua`; `eligible()` additionally requires
  `filetype == "markdown"`). Parsing markdown with treesitter is the 0.12.x
  `node:range` nil-node crash zone; the old plugin's startup injection-query
  patch (keep only `markdown_inline`, drop the code-fence language directive)
  now lives at the TOP of this module — core loads pre-lazy, before any
  markdown LanguageTree caches its injection query — as insurance for future
  TS consumers; deletable once upstream fixes the crash.
- **Fence parity above the viewport**: `fence_open_at(buf, first)` counts
  fence-delimiter parity over `[0, first)` so a block opened above the
  visible window still shades; the pre-scan (fence shading only) is skipped
  past `M.MAX_SCAN` (10000) lines. Inside a fence nothing else decorates (a
  `# heading` in code is code). Any ```` ``` ````/`~~~` line toggles the
  state — indented-code and mixed-fence edge cases are not modeled.
- **Insert-mode skip**: the cursor line stays raw while inserting in the
  current buffer (`TextChangedI` keeps it live, `InsertLeave` restores).
  Toggling off clears the namespace on every loaded markdown buffer; the
  autocmds stay installed and no-op while off. Seams: `M._ns`,
  `M.refresh(buf, win)`, `M.MAX_SCAN`.
