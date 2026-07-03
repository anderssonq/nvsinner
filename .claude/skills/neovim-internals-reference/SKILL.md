---
name: neovim-internals-reference
description: >
  The Neovim-internals theory pack for NvSinner. Load BEFORE touching anything
  in lua/core/ (ai-activity, ui-touch, autoreload, update, health), terminal
  behavior (toggleterm, PTY buffers, TermOpen), autocmds and their ordering,
  statusline/winbar expressions, vim.uv timers, highlight groups /
  winhighlight, lazy.nvim loading/lockfile semantics, or the native vim.lsp
  API. Also load whenever a Neovim API behaves unexpectedly: E5560 errors,
  a winbar that renders empty or frozen, a spinner that stops, a changedtick
  that never moves, an autocmd that "doesn't fire", a highlight that reverts
  after a plugin loads, or a redraw that doesn't happen. This explains WHY the
  platform behaves that way and where this repo depends on each rule.
---

# Neovim internals, as NvSinner uses them

This is the platform-arcana reference: what Neovim actually guarantees (and
doesn't), each fact anchored to the exact file in this repo that depends on it.
Target: Neovim **0.11+** (the repo's hard floor); the dev machine runs 0.12.3
and every "verified" note below was checked on that build or verified
empirically by this repo's own development (labeled as such).

## When NOT to use this skill

- **You're debugging a live failure right now** → `nvsinner-debugging-playbook`
  (this file explains the mechanism; that one gives the triage steps).
- **You want the story of how a bug was found/fixed** →
  `nvsinner-failure-archaeology` (war stories live there; this file states only
  the resulting rules).
- **You want to re-run the experiments that established a fact** →
  `nvsinner-empirical-verification` (probe recipes live there).
- **You want the repo's design rules and layering rationale** →
  `nvsinner-architecture-contract`.
- **You want to know what a plugin/option is set to** → `nvsinner-config-catalog`.
- **You're installing, building, or running the distro** → `nvsinner-build-and-run`.
- **You're writing or running tests** → `nvsinner-testing-and-qa`.
- **You're about to edit files and need the process rules** → `nvsinner-change-control`.

## Quick reference: trap → rule → repo anchor

| Trap | Rule | Repo anchor |
|---|---|---|
| E5560 in a callback | uv-driven callbacks are fast contexts: no `vim.api`/`vim.fn`; plain Lua + `uv.now()` only, `vim.schedule` to escape | `on_lines` in `lua/core/ai-activity.lua` |
| Winbar expression renders empty | `vim.g.statusline_winid` is set for `'statusline'` eval, NOT `'winbar'` — bake the bufnr into a per-window string | `term_bar(win)` in `lua/core/ui-touch.lua`; `M.winbar(buf)` in `lua/core/ai-activity.lua` |
| Terminal `changedtick` frozen while output streams | Terminal lines aren't materialised (tick not bumped) unless attached or rendered — use `nvim_buf_attach` | header comment + `attach()` in `lua/core/ai-activity.lua` |
| Spinner frozen while focused in a terminal | `:redrawstatus` doesn't repaint the winbar in terminal mode — use `nvim__redraw{winbar=true, flush=true}` (pcall it: private API) | `tick()` in `lua/core/ai-activity.lua` |
| Terminal styled as a code pane on first open | toggleterm's `BufWinEnter` fires while `buftype == ""` — re-run styling on `TermOpen` | focus autocmd in `lua/core/ui-touch.lua` |
| External-edit autocmd never fires | With `autoread` + unmodified buffer, the silent reload fires ONLY `FileChangedShellPost`, not `FileChangedShell` — hook both | `lua/core/autoreload.lua` |
| Timer/spinner silently stops after a while | An active-but-unreferenced luv handle can be GC'd — pin it on a live table | `M._timer` in `lua/core/ai-activity.lua` |
| Custom highlight reverts after a plugin loads | Any `:colorscheme` (re)load wipes ad-hoc groups — re-apply via a `ColorScheme` autocmd | `apply_hl()` in `lua/core/ui-touch.lua`, `lua/core/ai-activity.lua`, `lua/plugins/ui/theme.lua`, `lua/plugins/ui/noice.lua` |
| Winbar label invisible when unfocused | `fg == bg` renders as a blank strip — give dim bars a readable muted fg | `NvTermBarDim` in `lua/core/ui-touch.lua` |
| New `lua/plugins/<dir>/` silently never loads | lazy.nvim `import` does NOT recurse — add `{ import = "plugins.<dir>" }` to `init.lua` | `init.lua` spec list |
| Update floats plugins to untested versions | `Lazy restore` pins to `lazy-lock.json`; `sync` floats — the distro updates with restore | `lua/core/update.lua`, `install.sh` |
| LSP repaints Treesitter colours ~1s after open | Nil `semanticTokensProvider` in a `"*"` `on_attach` BEFORE any server is enabled; keep `automatic_enable = false` | `lua/plugins/lsp/lsp-config.lua` |
| Markdown buffer crashes Neovim 0.12.x | Upstream treesitter bug (`node:range()` on nil node) — highlighter disabled for markdown | `after/ftplugin/markdown.lua` |

---

## 1. Fast event contexts

**Concept.** Neovim's event loop (libuv) can invoke Lua callbacks *between*
input processing, outside the main "editor loop". Such a callback runs in a
**fast event context** (`:help lua-loop-callbacks`, `:help vim.in_fast_event()`):
it may touch Lua state freely but NOT "editor" state — most `vim.api` and
`vim.fn` calls raise **E5560** (`<function> must not be called in a fast event
context`). Verified on 0.12.3: calling `vim.api.nvim_get_current_buf()` inside
a raw `uv.new_timer()` callback fails with exactly that error.

**Which callbacks are fast contexts (relevant here):**
- `vim.uv` timer callbacks (unless wrapped — see below).
- `nvim_buf_attach` callbacks (`on_lines`, `on_detach`, …). Per `:help
  api-buffer-updates-lua`, these are "called frequently in various contexts"
  under `textlock`; for a terminal buffer, output arrives via the event loop,
  so treat `on_lines` as fast-context code, always.
- `vim.system` callbacks (hence `vim.schedule_wrap` around the completion
  handler in `lua/core/update.lua`).

**Rules.**
1. Inside a fast context: plain Lua tables, `uv.now()`, string work — nothing
   else. `vim.uv` functions are safe (they don't touch editor state).
2. To do editor work, escape with `vim.schedule(fn)` / `vim.defer_fn`, or
   create the callback pre-wrapped with `vim.schedule_wrap(fn)` — then the body
   runs on the main loop and the full API is available.
3. `vim.in_fast_event()` tells you which world you're in, if you must branch.

**Where this repo relies on it.** `lua/core/ai-activity.lua` is the canonical
example of both halves: the `on_lines` callback only writes to the plain-Lua
`state` table and stamps `uv.now()` (comment in `attach()` marks it), while the
animation timer is started with `vim.schedule_wrap(tick)` — so `tick()` itself
is NOT fast-context and may legally call `vim.fn.mode()`, `nvim_buf_is_valid`,
and `nvim__redraw`. The hover debounce timer in `lua/core/ui-touch.lua` and the
1s checktime poller in `lua/core/autoreload.lua` use the same
`vim.schedule_wrap` pattern.

**The trap.** The failure is not always a loud E5560: some paths error only
when the callback happens to fire in a fast context, so a `vim.api` call inside
`on_lines` can appear to work in light testing and blow up under real streaming
output. Never put `vim.*` editor calls in `on_lines`; let a scheduled timer do
the redrawing.

## 2. Statusline vs winbar evaluation

**Concept.** `'statusline'`, `'winbar'`, and `'tabline'` share one printf-like
format language (`:help 'statusline'`). Two expression forms matter:
- `%{expr}` — evaluate `expr`, insert the *result as plain text*.
- `%{%expr%}` — evaluate `expr`, then **re-parse the result as statusline
  format**, so the returned string may itself contain items like `%=`
  (separator/centering) and `%#Group#…%*` (highlight switches). This is the
  form this repo uses; `v:lua.require'…'` calls Lua from the expression.

**The critical asymmetry (verified empirically by this repo).**
`vim.g.statusline_winid` (`:help g:statusline_winid`) is populated while a
`'statusline'` expression is evaluated, but **NOT** while a `'winbar'`
expression is evaluated. A winbar callback that asks "which window am I?" via
that global gets nothing and renders empty — that is exactly what happened
here, and it's why the design is what it is:

> ⚠️ Refinement (re-probed 2026-07-02, Neovim 0.12.3): the discriminator is the
> evaluation FORM, not the option. `%!expr` full-expressions see
> `g:statusline_winid` for BOTH `'statusline'` and `'winbar'`; `%{expr}` items
> see it for NEITHER. This repo's winbar uses a `%{%…%}` item, so the variable
> was genuinely absent. The rule below is unchanged: never rely on
> `statusline_winid` inside `%{}` items. Probe: `nvsinner-empirical-verification`
> recipe 2.

- `term_bar(win)` in `lua/core/ui-touch.lua` builds a **per-window** winbar
  string with the buffer number baked in as a literal:
  `%{%v:lua.require'core.ai-activity'.winbar(<buf>)%}`.
- `M.winbar(buf)` in `lua/core/ai-activity.lua` therefore takes its buffer as
  an **argument** and must never consult `vim.g.statusline_winid`. Its busy
  branch returns `%=%#NvAiBusy# … %*%=` — the `%{%…%}` re-parse is what makes
  the centering and the chip highlight work.

**Rules.**
1. Winbar expressions must be self-contained: pass identity (buf/win) in as a
   baked literal, one string per window.
2. If the expression returns format items (`%=`, `%#…#`), the option value must
   use `%{%…%}`, not `%{…}`.
3. Evaluation can happen at any redraw — keep these functions cheap and
   side-effect free (`M.winbar` only reads `state`, `vim.b[buf].nv_term_label`,
   and buffer validity).

**The trap.** The bar *looks* wired (option set, function exists) but renders
empty in real use — nothing errors. Test the rendered content, not just the
option: `tests/core/ui_touch_spec.lua` asserts the winbar string bakes the
buffer number; `tests/core/ai_activity_spec.lua` asserts `winbar(buf)` output.

## 3. Terminal buffer semantics

**Concept.** A `:terminal` (or toggleterm) buffer is PTY-backed: an external
process writes to a pseudo-terminal and Neovim ingests its output into a
special buffer with `buftype == "terminal"`. Several behaviors differ from file
buffers:

- **changedtick non-materialization (verified empirically by this repo).**
  Neovim does not materialise a terminal buffer's lines — and therefore does
  not bump `b:changedtick` — unless something is *attached* to the buffer or it
  is being *rendered*. Polling the tick of an unwatched terminal can sit frozen
  while output streams. Consequence: **`nvim_buf_attach` `on_lines` is the
  reliable activity signal** — an attached listener is always notified. This is
  the load-bearing fact behind `lua/core/ai-activity.lua` (its header comment
  records the rejection of tick polling).

  > ⚠️ Version caveat (re-probed 2026-07-02, Neovim 0.12.3 headless): the tick
  > of a hidden, unattached terminal buffer DID advance during streaming in the
  > re-probe, so the freeze is not reproducible as a current invariant. The
  > design verdict is unchanged — `on_lines` is a push signal with a delivery
  > contract; tick polling has none — but do not cite the freeze as current
  > fact without re-running `nvsinner-empirical-verification` recipe 3 on the
  > target version.
- **TermOpen timing.** `TermOpen` fires when a buffer *becomes* a terminal.
  `lua/core/ai-activity.lua` attaches its listener in a `TermOpen` autocmd (and
  sweeps already-open buffers at require time, for `:source` reloads).
- **The scratch → terminal transition (verified empirically by this repo).** A
  toggleterm window fires `BufWinEnter` while its buffer is still a scratch
  (`buftype == ""`); only afterwards does the buffer become `"terminal"`. Any
  buftype-branching logic run on `BufWinEnter` mis-classifies the pane. That is
  why the focus autocmd in `lua/core/ui-touch.lua` listens on
  `{"WinEnter", "BufWinEnter", "TermOpen"}` — `TermOpen` re-runs `focus()` once
  the buftype is real, so the terminal winbar shows on the very first open.
- **Terminal-mode redraw differences.** While the cursor is inside a terminal
  in terminal mode, some redraw commands skip the winbar — see §4.
- **Modes.** A focused terminal is in *terminal mode* (keys go to the process)
  or *terminal-normal mode* (`<C-\><C-n>`). `lua/core/autoreload.lua`
  auto-`startinsert`s on `WinEnter`/`BufEnter` into terminal buffers so a click
  is immediately typable; `lua/plugins/terminal/toggleterm.lua` maps `<Esc>`
  and `jk` back out. Also note Vim has no `CursorHold` in terminal mode, which
  is why `autoreload.lua` needs its 1s timer to keep running `checktime` while
  you sit in the AI column.

**The trap.** Terminal + agent UX is the repo's most fragile surface: signals
you'd trust for file buffers (changedtick, BufWinEnter-time buftype,
statusline redraw paths) are all subtly different for PTY buffers. When adding
terminal behavior, test with a *real* streaming PTY (see the terminal spec in
`tests/core/ai_activity_spec.lua`, which runs an actual `sh` loop and waits for
`working` → `idle`), never with a scratch buffer stand-in.

## 4. Redraw machinery

**Concept.** Setting a winbar/statusline option does not repaint anything by
itself; something must trigger re-evaluation.

- `:redrawstatus[!]` re-evaluates statuslines (and normally winbars), **but
  when focus is inside a terminal it does NOT repaint the winbar** — verified
  by this repo in a real PTY render (the spinner looked frozen exactly while
  you watch the agent work, the main use case).
- `vim.api.nvim__redraw({ statusline = true, winbar = true, flush = true })`
  re-evaluates *and flushes* the winbar in terminal mode too. **Note the double
  underscore: `nvim__redraw` is a private/unstable API** — it exists on 0.12.3
  (verified) but may change signature or vanish. This repo therefore calls it
  under `pcall` with a `vim.cmd("redrawstatus!")` fallback: see `tick()` in
  `lua/core/ai-activity.lua`.

**Rules.**
1. Any animated winbar content needs an explicit redraw tick; use
   `nvim__redraw` with the pcall fallback, exactly as `ai-activity.lua` does.
2. Redraw only when something changed or is animating — `tick()` gates on
   `any_busy or changed` so an idle editor burns zero redraws — and skip
   redraws while `vim.fn.mode() == "c"` (repainting during cmdline entry is
   disruptive; both `ai-activity.lua` and `autoreload.lua` guard on this).

**The trap.** "It works when I `:redrawstatus` by hand" proves nothing about
terminal mode. Reproduce with focus inside the terminal while output streams.

## 5. Autocmd events used here (and their ordering rules)

All autocmd wiring in this repo is Lua (`nvim_create_autocmd`) under named
`augroup`s with `clear = true` (idempotent re-`:source`).

- **`FileChangedShell` vs `FileChangedShellPost` × `autoread`** (verified
  empirically by this repo): when an external process changes a file on disk
  and the buffer is *unmodified* with `'autoread'` set — the common AI-edit
  case — Neovim reloads **silently and fires ONLY `FileChangedShellPost`**,
  never `FileChangedShell`. `FileChangedShell` fires in the conflict path
  (buffer modified, or no autoread), where the handler sets
  `vim.v.fcs_choice = "reload"` (`:help v:fcs_choice`) so disk wins with no
  W11/W12 prompt. `lua/core/autoreload.lua` hooks **both** events for its
  "AI edited <file>" toast, with a short per-file dedup (`last_notify`) so one
  write can't double-toast. Hooking only `FileChangedShell` would miss the
  normal case entirely.
- **`checktime`**: file timestamps are only compared when `:checktime` runs (or
  on a few built-in triggers). `autoreload.lua` runs it on
  `FocusGained/BufEnter/WinEnter/TermLeave/CursorHold/CursorHoldI` **plus** a
  1s `vim.uv` timer, because none of those events fire while you stay in
  terminal mode watching the agent.
- **`WinEnter` / `WinLeave`**: the focus-styling pair in `lua/core/ui-touch.lua`
  (per-window `winhighlight` + terminal winbar; see §7). Note `WinLeave` fires
  with the *leaving* window still current, hence
  `unfocus(vim.api.nvim_get_current_win())`.
- **`BufWinEnter` vs `TermOpen` ordering**: `BufWinEnter` precedes the buffer
  becoming a terminal for toggleterm windows (§3), so `ui-touch.lua` listens on
  both and lets `TermOpen` correct the classification.
- **`ColorScheme` as the re-apply hook (the `apply_hl` pattern)**: every
  `:colorscheme` load rebuilds highlights, wiping ad-hoc `nvim_set_hl` groups.
  The repo's convention: define groups in a local `apply_hl()`/`glass_hl()`
  function, call it once at load, and register it on a `ColorScheme` autocmd so
  it survives kanagawa reloads and lazy-loaded plugins that re-trigger
  colorscheme application. Instances: `lua/core/ui-touch.lua`,
  `lua/core/ai-activity.lua`, `lua/plugins/ui/theme.lua` (pattern
  `"kanagawa*"`), `lua/plugins/ui/noice.lua`. Keep the palettes in these files
  in sync — that is a CLAUDE.md rule.
- **`User VeryLazy`**: lazy.nvim's own synthetic event, fired once after
  startup + UI. `lua/core/health.lua` uses it (with `once = true` and an 800ms
  `vim.defer_fn`) so the first-run toast waits until nvim-notify (itself
  VeryLazy-loaded) can render it. Also usable as a lazy-load `event =
  "VeryLazy"` trigger (§8).
- **`TermOpen`**: attach point for the activity listener (§3) and the focus
  re-run (§3).

**The trap.** Autocmd reasoning fails when you assume an event fires that
doesn't (`FileChangedShell` on silent reload, `CursorHold` in terminal mode) or
fires *earlier than the state you need* (`BufWinEnter` before buftype is set).
When in doubt, verify the firing order empirically — recipes in
`nvsinner-empirical-verification`.

## 6. vim.uv (libuv): timers and the GC hazard

**Concept.** `vim.uv` (alias `vim.loop` pre-0.10; the repo writes
`vim.uv or vim.loop` for belt-and-braces) exposes libuv. Used here:

- `uv.new_timer()` + `timer:start(delay, repeat, cb)` — the animation tick in
  `ai-activity.lua` (`POLL_MS` 120ms), the hover debounce in `ui-touch.lua`
  (stop + restart = debounce), the checktime poller in `autoreload.lua`.
- `uv.now()` — the event-loop clock in ms; safe in fast contexts; used for the
  busy timestamps (`IDLE_MS` 1200ms quiet → idle) and the toast dedup.
- Timer callbacks are fast contexts unless wrapped in `vim.schedule_wrap` (§1).

**The GC hazard.** A luv handle is a Lua userdata; an **active but
unreferenced timer can be garbage-collected and silently stop firing** — no
error, the animation just freezes at some point. Documented luv behavior,
treated as load-bearing here: `ai-activity.lua` pins its handle as `M._timer`
on the returned module table (which lives forever in `package.loaded`), and
`tests/core/ai_activity_spec.lua` asserts `M._timer` exists precisely to guard
that pin. If you add a long-lived timer anywhere, anchor its handle to
something that outlives the scope.

**The trap.** Locals in a `config = function()` or module body are collectable
once the function returns. "Worked for a few minutes, then stopped" is the GC
signature — see `nvsinner-failure-archaeology` for the incident framing.

## 7. Window-local highlighting

**Concept.** `'winhighlight'` (`:help 'winhighlight'`) is a *window-local*
option remapping builtin highlight groups to substitutes, format
`From:To,From2:To2`. It lets two windows showing anything get different
`Normal`/`WinSeparator`/`WinBar` colours without touching global groups.

**Where this repo relies on it.** `lua/core/ui-touch.lua` implements all focus
feedback this way:
- Focused code pane: `Normal:NvFocusNormal,NormalNC:NvFocusNormal,WinSeparator:NvFocusSeparator`
  plus window-local `cursorline`.
- Focused terminal: same glass Normal + `WinSeparator:NvTermFocusSeparator` +
  `WinBar:NvTermFocusBar` (the bright top bar).
- Unfocused terminal: only `WinBar:NvTermBarDim` — the bar is *always present*
  so the terminal never reflows; focus only changes its colour.
- Unfocus of a code pane: `winhighlight = ""` (reset to globals).
- The `eligible()` guard skips floats (`nvim_win_get_config(win).relative ~= ""`)
  and special filetypes (neo-tree, telescope, dashboard, …) that own their own
  `winhighlight` — clobbering theirs breaks their theming.

**Winbar/statusline inline highlighting.** Inside the format string,
`%#Group#…%*` switches to `Group` and back. `ai-activity.lua` wraps the busy
state in `%#NvAiBusy#…%*` — a crimson chip — precisely so it overrides whatever
the bar's base WinBar mapping is and stays visible on an *unfocused/dim* bar.
Idle text carries no group and inherits the focus-aware WinBar colour.

**The `fg == bg` pitfall (found the hard way here).** `NvTermBarDim` originally
had fg = bg = `#16161d`; any text in the unfocused bar was invisible, so the
idle/working label seemed "missing". The fix: a readable muted fg (`#7a7f8d`)
on the dim bg. `tests/core/ui_touch_spec.lua` asserts fg ≠ bg for that group.
When you define any bar/chip group, check contrast in *both* focus states.

## 8. lazy.nvim loading model

**Concept.** lazy.nvim builds its plugin list from *specs* — Lua tables
returned by files. This repo's shape: `init.lua` bootstraps lazy (clone into
`stdpath("data")/lazy/lazy.nvim` if absent), requires `lua/core/*` (options
FIRST — leaders must exist before lazy evaluates any `keys` spec), then calls
`lazy.setup` with one `{ import = "plugins.<category>" }` per folder.

**Rules this repo depends on:**
- **`import` does NOT recurse into subfolders.** A new
  `lua/plugins/<category>/` folder needs its own `{ import = … }` line in
  `init.lua` or its files load never and *silently* (repo-verified convention,
  stated in both `init.lua` and CLAUDE.md). `tests/plugins/plugin_specs_spec.lua`
  loads every `lua/plugins/**/*.lua` as a spec, which catches malformed files
  but NOT a missing import line — check `init.lua` by eye.
- **Lazy-load triggers**: `event` (e.g. `BufReadPre`/`BufNewFile` for
  nvim-lspconfig, `VeryLazy` for noice and mason-lspconfig), `cmd` (`Mason`,
  the `Diffview*` commands), `keys`, `ft`. House rule: everything lazy-loads
  unless it must paint the UI at startup.
- **`lazy = false, priority = 1000`** — the colorscheme exception:
  `lua/plugins/ui/theme.lua` must run before anything renders; priority orders
  it ahead of other non-lazy plugins.
- **`enabled = false`** — the one-line disable that keeps the spec as
  documentation (e.g. `lua/plugins/ui/cursorline.lua`).
- **`lazy-lock.json` + restore vs sync**: the lockfile pins every plugin to a
  commit. `Lazy restore` checks plugins out to the pinned commits
  (reproducible, the tested set) — used by `:NvSinnerUpdate`
  (`lua/core/update.lua`) and `install.sh`. `Lazy sync` floats to latest and is
  the opt-in upgrade path only. Never "fix" an update flow by swapping restore
  for sync.
- **`User VeryLazy`** doubles as an autocmd hook for non-plugin code (§5).

**The trap.** Load-order bugs are silent: a plugin that never loads, a `keys`
spec read before the leader is set, a server enabled before the `"*"` LSP
config lands (§9). When behavior differs between `nvim` and `nvim --headless`,
suspect UI-gated events (`VeryLazy` fires in both, but `lua/core/health.lua`
deliberately bails when `#vim.api.nvim_list_uis() == 0`).

## 9. Native LSP (0.11+)

**Concept.** Neovim 0.11 introduced declarative client config:
`vim.lsp.config(name, cfg)` registers/extends config (the pseudo-name `"*"`
applies to all servers, merged with per-server configs), and
`vim.lsp.enable({...})` turns servers on (auto-attach by filetype/root
markers). Both verified present on 0.12.3. The old
`require("lspconfig").<server>.setup{}` path is deprecated — CLAUDE.md forbids
reintroducing it. nvim-lspconfig still provides the per-server *base defaults*
(its bundled `lsp/*.lua` files); this repo only layers on top.

**Where this repo relies on it** — `lua/plugins/lsp/lsp-config.lua`:

```lua
vim.lsp.config("*", {
  capabilities = require("cmp_nvim_lsp").default_capabilities(),
  on_attach = function(client, _)
    client.server_capabilities.semanticTokensProvider = nil
  end,
})
vim.lsp.enable({ "ts_ls", "solargraph", "html", "lua_ls" })
```

- **Capability surgery**: nil-ing `semanticTokensProvider` in `on_attach`
  prevents LSP semantic tokens (`@lsp.*` groups) from repainting the buffer
  ~1s after open — Treesitter stays the single source of syntax colour (a
  CLAUDE.md invariant).
- **Why order matters**: mason-lspconfig runs with `automatic_enable = false`.
  If it auto-enabled servers, one could attach *before* the `"*"` config (and
  its on_attach) is registered, and the `@lsp.*` repaint would return. The repo
  enables servers itself, after `vim.lsp.config("*", …)` has landed.
  `ensure_installed = { "lua_ls", "ts_ls", "html" }` still gives first-boot
  auto-install (solargraph is enabled but not ensure-installed — needs Ruby;
  enabling a non-installed server is harmless).

**The trap.** "Add a server" changes touch three places that must stay
consistent: `ensure_installed` (install), `vim.lsp.enable` (activation), and —
implicitly — the `"*"` config (behavior). Adding a server via any deprecated
or auto-enable path bypasses the semantic-token surgery.

## 10. Miscellaneous arcana this repo uses

- **`NVIM_APPNAME` + `stdpath()`**: the app name selects the XDG subdirectories
  — `stdpath("config")` → `~/.config/nvsinner`, and data/state/cache likewise
  isolated. That's the entire distro-isolation mechanism: `bin/nvsinner`
  exports `NVIM_APPNAME=nvsinner` and execs nvim; `install.sh`/`uninstall.sh`
  operate on the four nvsinner XDG dirs; `~/.config/nvim` is untouched. Code
  that persists state must use `stdpath` (the first-run marker in
  `lua/core/health.lua` lives under `stdpath("state")` so it's per-app);
  `lua/core/update.lua` pulls `stdpath("config")`. On the dev machine
  `~/.config/nvsinner` is a symlink to this repo.
- **Mouse hover floats**: `vim.o.mousemoveevent = true` makes Neovim deliver
  `<MouseMove>` as a mappable pseudo-key; `lua/core/ui-touch.lua` maps it (n +
  i) to a 200ms-debounced handler that reads `vim.fn.getmousepos()` and opens a
  `nvim_open_win` float with `relative = "mouse"` (anchored at the pointer),
  `focusable = false`, `noautocmd = true`. The float shows LSP hover as **plain
  text** deliberately — see the markdown-crash bullet below.
- **`timeoutlen` and prefix keymaps**: when one mapping is a strict prefix of
  another (`<leader>t` vs `<leader>t2`, `<leader>j` vs `<leader>j2`), Neovim
  waits `'timeoutlen'` after the prefix for a possible continuation (which-key
  uses the pause to show its menu), then falls back to the short mapping. This
  is intended behavior in `lua/plugins/terminal/toggleterm.lua` — the bare
  `<leader>t`/`<leader>j` are *supposed* to have that one-beat delay; don't
  "fix" it.
- **`vim.health` provider discovery**: `:checkhealth <name>` finds a check by
  module path `lua/<name>/health.lua` returning `{ check = fn }`. Hence
  `lua/nvsinner/health.lua` is a thin shim delegating to
  `require("core.health").report()`, which emits `vim.health.start/ok/warn/info`.
  The shim's *path* is the registration — don't move it.
- **`vim.system`**: 0.10+ async subprocess API. `lua/core/update.lua` uses it
  for the non-blocking `git pull --ff-only` with a `vim.schedule_wrap`ped
  completion callback (§1: the callback isn't main-loop code). Prefer it over
  `vim.fn.system` (blocking) and `jobstart` (legacy) for new code.
- **The 0.12.x markdown treesitter crash**: on 0.12.3 the markdown highlighter
  calls `node:range()` on a nil node (`runtime/treesitter.lua:197`) and crashes
  the buffer — a known upstream 0.12.x issue, hit and verified in this repo.
  Mitigations, all deliberate and all removable once upstream fixes land:
  `after/ftplugin/markdown.lua` (runs after the runtime ftplugin that
  unconditionally starts treesitter; `pcall(vim.treesitter.stop, 0)` + regex
  `syntax`), highlight-disable entries for markdown in the treesitter and
  telescope specs, LSP hover/signature kept OFF in `lua/plugins/ui/noice.lua`,
  and the plain-text hover float in `ui-touch.lua`. Do not route anything
  through markdown-treesitter rendering of transient floats until this is
  fixed upstream. (`after/ftplugin/*` ordering — user files run after
  `$VIMRUNTIME` ftplugins — is itself the arcana making the workaround
  possible.)

---

## Provenance and maintenance

**Facts verified: 2026-07-02** on Neovim 0.12.3 (dev machine), against this
repo's working tree at that date. Facts marked "verified empirically by this
repo" were established during NvSinner development (recorded in code comments,
CLAUDE.md, and `.tmp/*.md` PR descriptions) and are asserted by the test suite
where noted; the E5560 fast-context error, the existence of `nvim__redraw` /
`vim.lsp.config` / `vim.lsp.enable` / `vim.system` / `vim.uv.now`, the help
tags, and the `api.txt` fast-context wording were re-probed directly for this
document. Documented-but-not-locally-probed: the luv handle GC behavior (luv
docs + this repo's defensive pin), lazy.nvim's import/restore semantics (lazy
docs + this repo's reliance), and `relative="mouse"` float anchoring (in use in
`ui-touch.lua`, not exercised headless).

Re-verify with:

- `nvim --version | head -1` — still 0.11+? Which 0.12.x?
- `:help lua-loop-callbacks`, `:help vim.in_fast_event()`, `:help api-buffer-updates-lua` — fast contexts (§1)
- `nvim --headless -c 'lua local t=vim.uv.new_timer(); t:start(10,0,function() print(pcall(vim.api.nvim_get_current_buf)) end); vim.wait(200)' -c 'qa!'` — expect E5560 (§1)
- `:help 'statusline'` (the `%{%…%}` item), `:help g:statusline_winid`, `:help 'winbar'` — §2
- `:help TermOpen`, `:help FileChangedShellPost`, `:help v:fcs_choice`, `:help 'autoread'`, `:help checktime` — §3/§5
- `nvim --headless -c 'lua print(type(vim.api.nvim__redraw), type(vim.lsp.config), type(vim.lsp.enable), type(vim.system))' -c 'qa'` — API presence (§4/§9/§10)
- `:help 'winhighlight'`, `:help 'mousemoveevent'`, `:help nvim_open_win()` (`relative="mouse"`), `:help 'timeoutlen'`, `:help health-dev`, `:help NVIM_APPNAME`, `:help vim.system()` — §7/§10
- `make test` — the specs asserting these behaviors (`tests/core/ai_activity_spec.lua`, `tests/core/ui_touch_spec.lua`, `tests/core/autoreload_spec.lua`) still pass
- 0.12.x markdown crash still present? Open a markdown file with `after/ftplugin/markdown.lua` temporarily neutralised (recipe: `nvsinner-empirical-verification`); remove the workarounds once upstream fixes land.
