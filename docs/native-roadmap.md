# Native migration roadmap

NvSinner's direction is **distro, not config pack**: every plugin that can be
replaced by a small, tested, zero-dependency `lua/core/` module should be —
that is what makes the project *ours* (one palette, one modal system, one set
of conventions) instead of a curated list of other people's plugins. This
document is the per-plugin verdict: what stays, what goes native, and why.

Judging criteria, in order:

1. **Surface-to-depth ratio** — how much of the plugin do we actually use vs.
   how much machinery it ships? A plugin whose used surface is one extmark and
   a debounce is a migration; a plugin with years of edge-case depth
   (gitsigns' hunk staging, treesitter's parsers) is not.
2. **Builtin coverage** — Neovim 0.10/0.11 absorbed a lot (`gc` commenting,
   `vim.lsp.buf.document_highlight`, `vim.diagnostic` virtual_lines,
   `vim.system`, `vim.diff`). When the builtin covers the used surface, the
   plugin is dead weight.
3. **Identity value** — things a user *sees and touches* (dashboard, badges,
   toasts, modals, the AI column) are the distro's brand; owning them natively
   is worth medium effort. Invisible infrastructure is not.
4. **Existing infrastructure** — `lua/core/` already has floats + backdrop,
   Mason-style modals, extmark washes, async `vim.system`, `vim.uv` debounce
   timers, winbar expressions, and a ColorScheme re-apply pattern. A migration
   that reuses those is cheap; one that needs new primitives is not.

House rule reminder: a migrated plugin's spec is **kept with
`enabled = false`** as a one-line revert (like `incline.lua`), never deleted.

## Done (the precedent)

| Was | Now | Migrated |
|---|---|---|
| incline.nvim | `core/filebadge.lua` (winbar badge + "Open view" chip) | cc20c30 |
| nvim-cursorline | `core/ui-touch.lua` + illuminate | (disabled stub) |
| kanagawa-dragon theme plugin | `core/carbon.lua` + `colors/carbon.lua` | 3090e58 |
| avante / codecompanion (in-editor AI) | CLI in the AI column + `core/ai-*` bridge | (removed) |
| **Comment.nvim** | **builtin `gc`/`gcc` (Neovim 0.10+)** | **Wave 1** |
| **git-blame.nvim** | **`core/git-blame.lua`** | **Wave 1** |
| **vim-illuminate** | **`core/illuminate.lua`** | **Wave 1** |
| **persistence.nvim** | **`core/sessions.lua`** | **Wave 1** |
| **indentmini.nvim** | **`core/indent.lua`** | **Wave 1.5** |
| **nvim-colorizer** | **`core/colorizer.lua`** | **Wave 1.5** |
| **todo-comments.nvim** | **`core/todo.lua`** | **Wave 1.5** |
| **nvim-window-picker** | **`core/window-picker.lua`** | **Wave 1.5** |
| **render-markdown.nvim** | **`core/markdown.lua`** (minimal reading view) | **Wave 1.6** |

## Wave 1 (landed) — justifications

- **Comment.nvim → builtin.** The spec carried zero configuration; Neovim
  0.10's builtin `gc`/`gcc` is commentstring-aware through treesitter and
  covers every documented mapping. Pure deletion — the best kind of migration.
- **git-blame.nvim → `core/git-blame.lua`.** The used surface was one
  virtual-text annotation. Native version: debounced `vim.uv` timer → async
  `git blame -L <line>,<line> --porcelain --contents -` (buffer contents on
  stdin, so unsaved edits don't shift the blame) → one eol extmark, with a
  generation counter so a stale async result never paints a moved cursor
  line. ~200 lines, all patterns already proven in `ai-edits`/`update`.
  Bonus over the plugin: `:NvSinnerBlameToggle` appears in `:NvSinnerHelp`.
- **vim-illuminate → `core/illuminate.lua`.** The LSP provider — the one that
  matters — is a builtin (`vim.lsp.buf.document_highlight`). The fallback for
  parser-backed buffers is a visible-range word-boundary scan (what
  illuminate's regex provider effectively did). Same 120ms delay, 4000-line
  cutoff, filetype denylist, and panel-gray underlines (now on the standard
  `LspReference*` groups).
- **persistence.nvim → `core/sessions.lua`.** A thin `:mksession` wrapper:
  per-cwd file under `stdpath("state")/sessions/` (NVIM_APPNAME-scoped),
  VimLeavePre autosave gated on a real file having been opened, same
  `<leader>Sc/Sl/SQ` maps plus `:NvSinnerSession*` commands. Also removes the
  old spec's config-time hard `require("which-key")` coupling.

## Wave 1.5 (landed) — justifications

- **indentmini.nvim → `core/indent.lua`.** The spec ran `only_current = true`
  with one recolored highlight — the whole used surface is "one guide on the
  cursor's enclosing scope". Native shape: cursor autocmds compute the scope
  (guide column + top/bottom, blanks riding along, visible-range-clamped) and
  a decoration provider paints it with *ephemeral* overlay extmarks at redraw
  time — nothing to clear, nothing stale. Display-cell columns
  (`vim.fn.indent` + `virt_text_win_col`), so tab-indented files line up.
- **nvim-colorizer → `core/colorizer.lua`.** We only colorize hex codes; the
  plugin ships css-function/tailwind/name machinery that never ran. Native:
  visible-range `#rgb`/`#rrggbb`/`#rrggbbaa` scan → bg extmarks with
  on-demand `NvColorRRGGBB` groups (carbon-role contrast fg, cache dropped on
  ColorScheme).
- **todo-comments.nvim → `core/todo.lua`.** Drops a plenary consumer. Native:
  visible-range keyword+colon scan (optional `(author)` tag) → solid carbon
  accent chips, families mapped semantically (TODO green `base13`, FIX
  magenta `base10`, HACK/WARN purple `base14`, …). `:TodoTelescope` is
  deliberately not replicated — telescope live-grep covers it until
  NvSinnerFind exists.
- **nvim-window-picker → `core/window-picker.lua`.** Only consumed by
  neo-tree's open-with (`w`), whose seam is
  `pcall(require, "window-picker")` → `pick_window({})` — the native module
  registers itself in `package.preload["window-picker"]` (deferring to the
  real plugin if the stub is ever re-enabled), so neo-tree needed zero config
  change. Letter chips are non-focusable centered floats on the carbon
  accent; single candidate auto-returns.

## Wave 2 — distro identity

| Plugin | Native shape | Justification |
|---|---|---|
| `alpha-nvim` | `core/dashboard.lua` | the spec is already ~90% custom NvSinner code (logo, gradient, mouse pills, quotes); alpha only contributes the buffer scaffold, which `menu.lua` already knows how to build. The start screen is the first thing a user sees — it should be ours end to end. |
| `nvim-notify` | `core/toast.lua` | stacked top-right floats + fade timer; every primitive (floats, `vim.uv` timers, carbon roles, ColorScheme re-apply) exists. Owning `vim.notify` also unblocks noice decisions (noice currently routes messages through nvim-notify). |
| `barbecue.nvim` + `nvim-navic` | breadcrumbs inside `core/filebadge.lua` | reuses `symbols.lua`'s DocumentSymbol flattening; **unifies winbar ownership** (today split across barbecue / filebadge / ui-touch — a documented friction point). Two plugins out, one owner in. |
| `satellite.nvim` | native scrollbar (decoration provider) | lowest priority of the tier; nontrivial rendering, purely cosmetic payoff. |

## Wave 3 — flagships (future goals; documented, not started)

- **telescope → NvSinnerFind.** A fuzzy picker built on `matchfuzzy()` +
  async `fd`/`rg`, styled as the sixth Mason-style modal. This is the single
  biggest "distro, not config" statement — the picker is the most-touched UI
  in any editor. Risks: preview windows (needs scratch-buffer previews without
  the 0.12.x markdown TS crash), sorter quality vs fzf-native, replacing
  `telescope-ui-select` (`vim.ui.select` shim — the NvMenu modal can host it).
  Prerequisite: none technically, but land Waves 1.5–2 first to grow the
  modal/decoration muscle.
- **toggleterm → native terminal manager.** The AI column *is* the distro's
  identity, and the intelligence (`ai-sessions`, `ai-activity`, the CLI
  picker, winbar labels) is already native — toggleterm only contributes
  window/id plumbing and layout restore. Risks: the layout-restore matrix and
  the terminal-UX fragility campaign (see `nvsinner-terminal-ux-campaign`);
  reserved-id semantics (100+) must survive the migration. Do this only
  behind the campaign's edge-case reproduction matrix.
- **lualine → native statusline.** The winbar-expression expertise
  (`filebadge`, `ai-activity`) transfers directly; the per-session status
  data is already core-native. Payoff: the last big chrome plugin out of the
  identity path.
- **noice → evaluate.** Its cmdline UI needs `ui_attach` (historically
  fragile on 0.12.x, LSP paths already disabled here). Once `core/toast.lua`
  owns `vim.notify`, re-evaluate whether noice earns its weight or the native
  cmdline suffices. Verdict deferred on purpose — "evaluate", not "migrate".

## Keep — justified

| Plugin | Why it stays |
|---|---|
| `nvim-treesitter` | the syntax engine; pinned `branch = "master"` (incident FA-24). Not replaceable. |
| `mason` ×3 + `nvim-lspconfig` | distro infrastructure: server install + the server-config data set. The *API* is already native (`vim.lsp.config`/`enable`); lspconfig is used as data, not framework. |
| `nvim-cmp` + LuaSnip | completion engines are deep (sorting, sources, snippet grammar). Watch Neovim's builtin completion/snippet work; re-evaluate when autotrigger lands stably. |
| `none-ls` + mason-tool-installer | formatter/linter orchestration depth (eslint_d condition, project detection). |
| `tiny-inline-diagnostic` | native `virtual_lines = { current_line = true }` exists (0.11) but loses the rounded-bubble look that is part of the distro's face. Re-evaluate when native styling improves. |
| `trouble` | list UX depth; only lists — `diagnostics.lua` owns the config. |
| `neoconf` | tiny, cmd-lazy, zero identity surface. |
| `gitsigns` | hunk staging/reset/preview is years of edge cases (staged vs index vs head). The sign column alone would be migratable, but the keymaps are the value. |
| `diffview` | a full merge-quality diff UI; intentionally minimal config. |
| `neo-tree` | a tree with git/diagnostic/rename integration is a project, not a module. Revisit only after NvSinnerFind exists. **Known upstream defect carried in the meantime:** its `buffers` and `git_status` sources hard-call the *synchronous* `git.status` (`vim.fn.system`), which `git_status_async` does not cover — only the filesystem source reads that option. We neutralize it for Buffers via `before_render`; the Git tab still blocks (~73 ms on a 24k-file repo with a 24k-file ignored tree, vs 14 ms for a plain `git status`, because it forces `--untracked-files=all` over `--ignored=traditional`). Not fixable from config — the real fix is upstream calling `git.status_async`. Do NOT retry `core.fsmonitor`/`core.untrackedCache`: measured A/B, both were slower. See `lua/plugins/navigation/CLAUDE.md`. |
| `leap` | motion-model depth (labels, multi-window). |
| `nvim-surround`, `nvim-autopairs` | operator/pair edge cases exceed their tiny specs; near-zero cost (lazy, defaults). |
| `which-key` | the discovery UI over the whole keymap tree; deep and load-bearing for the leader namespaces. |
| `mini.animate` + `neoscroll` | animation timing engines; low value to own. |
| `nvim-web-devicons` | shared icon data for many keepers; drops out only when its dependents do. |
| `telescope`, `toggleterm`, `lualine`, `noice`, `alpha`, `notify`, `barbecue`, `satellite` | staying **for now** — they are the Wave 2/3 targets above. |

## Bundled 0.12 packages — evaluated (2026-08-31)

The 0.12 baseline move unlocked `$VIMRUNTIME/pack/dist/opt/`. Two of its
packages were assessed; one landed, one was declined. Both `packadd`-only, so
neither costs anything until used.

| Package | Verdict |
|---------|---------|
| `nvim.undotree` | **Adopted.** `<leader>u` + a `:NvSinnerHelp` palette row. Fills a real gap — nothing here browsed undo history. `packadd` is idempotent (guarded by `g:loaded_undotree_plugin`; the rtp entry is never duplicated), so the keymap re-runs it on every press with no bookkeeping, and `:Undotree` toggles. Its buffer is `buftype = nofile`, which every visible-range decorator (`illuminate`, `indent`, `colorizer`, `todo`) and `ui-touch.eligible()` already skip — no denylist edits. Two upstream limits worth knowing, both left unpatched: (1) its augroup is created with `clear = true`, so opening a tree for a second buffer silently desyncs the first — one tree at a time is the supported model; (2) `undotree.lua:271` reads `vim.b[outbuf]` from a `vim.schedule` without re-validating the buffer, and the tree buffer is `bufhidden = wipe`, so opening and closing it **within one event-loop tick** prints a non-fatal `Invalid buffer id` to `:messages`. Probed: every realistic sequence is clean — open/close/reopen with a tick in between, and quitting with the tree open — because a real key press always yields to the loop. Not worth carrying a debounce for. |
| `nvim.difftool` | **Declined.** It does cover something diffview cannot — arbitrary **non-git** file/directory diffing — but `lua/difftool.lua:64` calls `:only`, tearing down the AI terminal column and neo-tree in the current tab. Diffview already owns `<leader>g*` under non-negotiables that route `<leader>gd`/`<leader>gH` through `open_diff()` in at most one tab, precisely to stop the tab-stacking this would reintroduce. It also registers a load-time `VimEnter` autocmd with **no augroup** that hijacks `nvim -d`. The non-git file case is already `nvim -d a b` in a terminal. |

## `'winborder'` — measured and rejected (2026-08-31)

Neovim 0.12 adds a global default border for floats that pass no `border` key.
It looked like a free win. It is not, and the reasoning is recorded here so it
reads as measured rather than overlooked.

**Precedence, probed on 0.12.3:** no `border` key → global applies; `border =
nil` in the table → identical to absent, global applies; any explicit value
(`"none"` included) wins. So the blast radius is exactly "floats that pass no
border key".

**For NvSinner's own UI it is a no-op.** All 12 `nvim_open_win` sites already
pass a border — 9 × `"rounded"` (prompts, symbols, agents ×2, menu, ia, help,
ai-ask, ui-touch) and 2 × `"none"` (backdrop, ai-complete) — with one
exception: `lua/core/window-picker.lua:103`, whose 7×3 letter overlay is
centred by arithmetic assuming no border and whose `winhighlight` maps
`Normal`/`NormalFloat` but not `FloatBorder`. That one would **regress**.

**The rest of the effect is on third-party floats, and three of them are bad:**
lazy.nvim's backdrop (`view/float.lua:145`) and none-ls's (`info.lua:54`) are
`columns × lines` floats with no border key — probed, a full-screen float plus a
border clamps its content (78×21 on an 80×24 screen) and draws a rounded frame
around the whole display, on every `:Lazy`. Both are hardcoded upstream and
**cannot be overridden from config**. noice's `popupmenu` view (via nui's
`get_default_winborder()`) would gain a frame on every `:` completion, drawn in
`NoicePopupmenuBorder` where `bg == fg` — invisible but space-consuming.
which-key gains one too (its `border = "none"` default is **commented out** at
`config.lua:67`). nvim-cmp's `window.bordered()` reads the option directly, so
the completion and documentation windows change as well.

Unaffected: telescope (plenary hardcodes `"none"` on both the content window
and its separate border wrapper — the double-border worry is unfounded),
neo-tree (`popup_border_style = "NC"`), trouble, toggleterm, nvim-notify,
satellite, mini.animate, image, neoconf.

**Net:** four suppression sites plus two unfixable artifacts, to gain borders on
`:Mason`, gitsigns popups and native `K` hover. Not worth it. The explicit
per-site borders stay — cheap, self-documenting, and immune to a future
upstream default change.

*Revert recipe if this is ever revisited:* `vim.opt.winborder = "rounded"` in
`core/options.lua`, `border = "none"` at `window-picker.lua:103`, plus
`views.popupmenu.border.style` in the noice spec and a which-key `win.border`
decision.

**`'pumborder'`** was evaluated separately and also left unset: it styles the
*builtin* popup menu, not nvim-cmp's floats, and `core/options.lua`'s
`pumblend = 10` is a deliberate borderless "glass" look.

## Scoreboard

37 plugin specs at the start of Wave 1 → 4 disabled in Wave 1 (comment,
git-blame, illuminate, persistence), **4 more in Wave 1.5** (indentmini,
colorizer, todo-comments, window-picker), **1 more in Wave 1.6**
(render-markdown → `core/markdown.lua`: the used surface was the off-by-default
"Open view" toggle, and the minimal reading view — heading bars, bullets,
checkboxes, quote bars, fence shading, rules — fits the colorizer/todo
visible-range pattern without ever touching the crash-prone markdown TS tree;
the full conceal/table renderer the original "keep" verdict priced in was never
used), 2 previously disabled (incline,
cursorline). Wave 2 targets 5 (incl. navic). A completed Wave 2 leaves ~21
active plugins, all of them either engines (treesitter, LSP, cmp) or deep
tools (gitsigns, diffview, neo-tree) — and every pixel of NvSinner's visible
identity rendered by native code.
