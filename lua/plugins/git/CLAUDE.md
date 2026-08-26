# lua/plugins/git/ — git plugin ownership rules

- `git-blame.lua` — `git-blame.nvim` is **disabled** (`enabled = false`):
  replaced by the native inline blame in `lua/core/git-blame.lua` (async
  `git blame --porcelain` of the buffer contents → eol virtual text,
  `:NvSinnerBlameToggle`). Kept as a one-line revert. Inline blame is still
  that module's job — the gitsigns rule below is unchanged.
- `gitsigns.lua` — `gitsigns.nvim`: sign-column markers for added / changed /
  deleted lines vs. the git index (a thin `▎` bar), lazy-loaded on
  `BufReadPre` / `BufNewFile`. Hunk keymaps live in its `on_attach`: `]h` /
  `[h` navigate, `<leader>hp` preview, `<leader>hs` / `<leader>hr` stage /
  reset hunk, `<leader>hS` / `<leader>hR` stage / reset buffer, `<leader>hb`
  blame popup. Keep the **inline** blame as `core/git-blame.lua`'s job and
  the **popup** blame as gitsigns' — don't enable gitsigns
  `current_line_blame` (it would double up).

  It also owns the **unified inline diff** — `<leader>gu`, the merged
  one-column reading Azure DevOps and GitHub call "unified". It is here and
  not in diffview for a structural reason worth knowing before anyone tries
  to move it: **diffview cannot render a unified diff and no config flag
  unlocks one.** Its rendering model is Neovim's native *window* `'diff'` mode
  (`vcs/file.lua` sets `diff`/`scrollbind`/`foldmethod=diff` per window), which
  needs two diffed windows to produce highlighting at all; its only
  single-window layout, `diff1_plain`, is a plain window with diffs turned
  **off** ("without the visual noise from diffs" — upstream's own docs),
  merge-tool only, and rejected by config validation for `view.default` /
  `view.file_history`. `actions.cycle_layout` cycles horizontal ⇄ vertical
  and nothing else. Rules for the toggle:

  - **The three flags flip as ONE unit.** `toggle_deleted` (the index version
    of each hunk as virtual lines above the change), `toggle_linehl` (a
    full-line wash on the added/changed lines) and `toggle_word_diff` (the
    intra-line regions). Any subset reads as a rendering bug: `show_deleted`
    alone shows the old lines with nothing marking the new ones, `linehl`
    alone is just the sign column widened.
  - **State is a module-local boolean, never `gitsigns.config.show_deleted`.**
    `show_deleted` is deprecated as a *setup* option — passing it through
    `opts` makes gitsigns warn and drop it — while `toggle_deleted(v)` still
    sets it at runtime and the renderer still honours it. Depending on a field
    in that state is asking for it to disappear.
  - **`<leader>gu` lives in the `<leader>g` diff namespace**, not `<leader>h*`:
    it is a view over the whole buffer, not a hunk action. It is still a
    buffer-local `on_attach` map like the rest — it only means anything where
    gitsigns attached.
  - The word-level groups are pinned in `colors/carbon.lua`. gitsigns derives
    its line washes from `DiffAdd`/`DiffChange`/`DiffDelete` (which carbon
    defines) but falls `GitSignsAddInline`/`ChangeInline`/`DeleteInline` back
    to **`TermCursor`**, which reads as a cursor artefact — hence the three
    explicit definitions, from existing roles, no new hexes.
- `diffview.lua` — `diffview.nvim`: a full side-by-side `git diff` viewer
  (file panel + two versions of the file). Lazy-loaded on its `Diffview*`
  commands and keymaps: `<leader>gd` open working-tree-vs-index, `<leader>gh`
  current-file history, `<leader>gH` whole-repo history, `<leader>gq` close.
  `enhanced_diff_hl` is on for word-level highlights. The `<leader>g` git
  namespace is otherwise diffview's, apart from gitsigns' `<leader>gu`
  unified-inline toggle; gitsigns owns the per-hunk `<leader>h*` maps.

  On top of the viewer, the spec adds a **review round trip** — the one place
  this file is not "just defaults". One way in, one way out, one tab:

  - `<leader>gd` the diff itself, in **at most one tab** (see the idempotence
    contract below).
  - `<leader>gi` *into* the diff. Outside a Diffview tab it opens (or switches
    to) the view **on the current file, at the current line**, with focus in
    the right-hand working-tree pane. Inside the tab it toggles focus between
    the diff and the file panel, so you can walk the changed files. It must
    **never** land on the editable buffer — leaving the view is `gf`'s job,
    and conflating the two costs you the file list mid-review.
  - `gf` *out of* the diff — back to the real editable buffer, tab left
    standing. `<leader>gd` returns to it; `<leader>gq` closes it.

  Contracts to preserve when editing:

  - **`<leader>gd` must never open a second view.** `DiffviewOpen` does not
    dedupe *at all*: `lib.diffview_open` never inspects `lib.views`, and
    `View:open()` unconditionally runs `tab split`. A raw
    `"<cmd>DiffviewOpen<cr>"` therefore stacked one tabline entry per press,
    each holding its own copy of the same diff — and the `gf`-then-`<leader>gd`
    loop hit it every time, because `gf` leaves you in the *previous* tabpage
    with the diff tab still open. `open_diff()` resolves `diff_view(lib)`
    first: already in that tabpage → `focus_panel` (re-list the changes);
    elsewhere → `nvim_set_current_tabpage` (focus stays where that tab left it,
    so it is a true "back to where I was reading"); nothing open → the one
    `DiffviewOpen`. Both reuse paths finish with `DiffviewRefresh` so an
    adopted tab is never a stale file list.
  - **`<leader>gH` carries the same guard, `<leader>gh` deliberately does not.**
    `lib.file_history` never inspects `lib.views` either. But two files are two
    legitimate histories, so `repo_history_view()` adopts only a history view
    opened with **no path args** — which is exactly what separates a
    `<leader>gH` tab from a `<leader>gh` one. Read them from the view's OWN
    `adapter.ctx.path_args`: `vcs.get_adapter` builds a fresh adapter instance
    per call, so that field is per-view state, not a shared last-call-wins one.
    Both view types listen for `refresh_files` and `emit` dispatches to the
    current tabpage's view, so the shared `DiffviewRefresh` works for either.
  - **`diff_view(lib)` is the DiffView-only scanner**, `repo_history_view(lib)`
    its exact complement plus the empty-path-args test, and `open_view(lib)` the
    anything-open one. `lib.views` holds every view ever opened, including
    ones whose tabpage the user has since closed — hence the
    `nvim_tabpage_is_valid` check in all three.
  - **`gf` is wrapped, not used raw.** diffview binds stock
    `actions.goto_file_edit` in three keymap groups (`view`, `file_panel`,
    `file_history_panel`), and it edits into the target tabpage's *last
    accessed* window — as often neo-tree or the AI terminal column as a code
    pane, and `:edit` there wipes the panel. `goto_file()` points the tab at
    `core.window-picker.editable_win(tab)` BEFORE calling the action, and
    overrides `gf` in **all three** groups. This is the contract `<leader>go`
    used to carry; it moved rather than disappeared.
  - **Selection goes through `--selected-file`**, not a manual open-then-seek.
    Diffview normalises the absolute path against the repo toplevel itself.
    Note it is **init-only** (`not self.initialized` gates it in
    `diff_view.lua`), so it cannot retarget a live view — that is `set_file`'s
    job, which is what `jump_to` uses.
  - **The in-view toggle calls `panel:focus()` directly**, not
    `emit("focus_files")`. The event is dropped while the view is closing and
    depends on the listener table being wired; the listener body is exactly
    that call. `Panel:focus()` also reopens a panel that was toggled away
    (`<leader>b`), so the key is never a silent no-op.
  - **`<leader>gi` outside a view prefers a real `DiffView`.** A `<leader>gh`
    tab is a `FileHistoryView`: no `files:iter()`, no `set_file_by_path`, so
    adopting it turns the jump into a bogus "no changes" toast. `open_view()`
    tries `diff_view()` — `files` **and** `set_file` — first and only then
    falls back.
  - **The file `<leader>gi` means is resolved, not assumed.** From a non-file
    window it is neo-tree's selected node (`get_state_for_window` →
    `tree:get_node()`, files only — a directory row designates nothing), else
    the last file window in the tab. A bare `DiffviewOpen` (first changed file)
    is the last resort, not the first answer.
  - **The cursor lands from the `diff_buf_win_enter` hook, never a timer.**
    `DiffviewOpen` and `set_file` are `async.void`, so nothing is placeable
    synchronously. Only `ctx.symbol == "b"` (the working-tree side) may take
    the cursor; `"a"` is the index blob. The hook re-checks the landed buffer
    name against the requested path — when they differ the requested file had
    no changes and diffview fell back to the first entry, which is an INFO
    toast, not a jump. `view_closed` clears the queued jump.
  - **Resolve entries by `absolute_path` yourself** (`view.files:iter()`).
    `DiffView.set_file_by_path` matches the *repo-relative* `file.path`, so
    handing it an absolute path silently matches nothing.
  - **`require("diffview").close(tabpage)` does NOT close a view** — with an
    argument it only disposes stray views. Closing a specific tab would be
    `lib.tabpage_to_view(tp)` → `view:close()` → `lib.dispose_view(view)`.
    Nothing in this file does that any more (`<leader>gq` / `DiffviewClose`
    owns closing), but the recipe is recorded because the obvious call is wrong.
  - **Exit via `actions.goto_file_edit()`**, don't hand-roll it: it restores
    the window options (`diff` / `scrollbind` / `foldmethod`) *before* the
    `:edit`, so the buffer arrives as a plain editable file, and it resolves
    the target from the diff pane *or* the file panel. It bails silently when
    the file isn't on disk.
  - **`<leader>go` was retired, not lost.** It closed the tab on the way out;
    with `<leader>gd` now reusing an open tab, keeping the view around is
    strictly better than tearing it down and rebuilding it. Its one load-bearing
    behaviour — the `editable_win` pre-positioning — moved onto `gf`. Do not
    reintroduce a second exit key.

  **Click-to-preview in the file panels** — diffview's ONLY stock mouse
  binding is `{ "n", "<2-LeftMouse>", actions.select_entry }`
  (`diffview/config.lua`), so seeing a file's diff cost two clicks while
  neo-tree opened on one. `CLICK_MAPS` adds `<LeftRelease>` behind the **same
  persisted `tree_click` setting** neo-tree uses (`:NvSinnerMenu` →
  "Explorer click", default `single`), reaching both
  `opts.keymaps.file_panel` (`<leader>gd`/`<leader>gi`) and
  `file_history_panel` (`<leader>gh`/`<leader>gH`) through `panel_maps()` —
  which builds a **fresh list per panel** (mouse gestures + `gf`), so an edit
  to one panel's maps can never silently rewrite the other's. Rules:

  - **`select_entry`, never `focus_entry`.** `select_entry` is
    `view:set_file(item, false)` — the diff panes update and focus **stays in
    the list**, so you can walk the changed files by clicking. Descending into
    the diff is `<leader>gi`'s job; swapping the action would take the file
    list away on every click. On a directory row it toggles the fold.
  - **The maps merge; `keymaps.disable_defaults` must never be set.**
    `config.setup` rebuilds its keymap tables from pristine defaults
    (`utils.tbl_clone(M.defaults.keymaps)`) and then runs
    `extend_keymaps(defaults, user)`, which keys entries by `"<mode> <lhs>"` —
    so these two override the stock `<2-LeftMouse>` and every other default
    survives. An earlier `vim.tbl_deep_extend` in the same function *does*
    produce an index-wise hybrid of the two lists; that value is discarded.
    Don't "fix" it by pre-merging the lists yourself.
  - Same three guards as the tree, for the same reasons: `<LeftRelease>` (not
    `<LeftMouse>`) so the press still positions the cursor;
    `core.mouse.clicked_line` because `getmousepos().line` clamps to the last
    buffer line (a click below the list would otherwise preview the last
    file — the panels run `wrap = false` + `foldenable = false`, so the
    topline row math is exact); and in `single` mode `<2-LeftMouse>` is a
    deliberate **no-op** so a reflexive double-click can't re-collapse the
    folder the first click just expanded.
  - Each map carries a `desc` — diffview's `g?` help panel renders it.
  - The handlers `require` lazily inside their bodies, so the spec table stays
    loadable with no plugins on the runtimepath (what
    `tests/plugins/diffview_spec.lua` asserts).
