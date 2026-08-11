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
- `diffview.lua` — `diffview.nvim`: a full side-by-side `git diff` viewer
  (file panel + two versions of the file). Lazy-loaded on its `Diffview*`
  commands and keymaps: `<leader>gd` open working-tree-vs-index, `<leader>gh`
  current-file history, `<leader>gH` whole-repo history, `<leader>gq` close.
  `enhanced_diff_hl` is on for word-level highlights. The `<leader>g` git
  namespace is otherwise free; gitsigns owns the per-hunk `<leader>h*` maps.

  On top of the viewer, the spec adds a **review round trip** — the one place
  this file is not "just defaults":

  - `<leader>gi` *into* the diff. Outside a Diffview tab it opens (or switches
    to) the view **on the current file, at the current line**, with focus in
    the right-hand working-tree pane. Inside the tab it toggles focus between
    the diff and the file panel, so you can walk the changed files. It must
    **never** land on the editable buffer — leaving the view is `<leader>go`'s
    job, and conflating the two costs you the file list mid-review.
  - `<leader>go` *out of* the diff — back to the real editable buffer at the
    cursor line, and the Diffview tab is closed.

  Contracts to preserve when editing:

  - **Selection goes through `--selected-file`**, not a manual open-then-seek.
    Diffview normalises the absolute path against the repo toplevel itself.
  - **The in-view toggle calls `panel:focus()` directly**, not
    `emit("focus_files")`. The event is dropped while the view is closing and
    depends on the listener table being wired; the listener body is exactly
    that call. `Panel:focus()` also reopens a panel that was toggled away
    (`<leader>b`), so the key is never a silent no-op.
  - **The exit pre-positions the target tab's window.** `goto_file_edit` opens
    the file in the target tabpage's *last accessed window* — which is just as
    often neo-tree or the AI terminal column as a code pane, and `:edit` there
    wipes the panel. `leave_diff` points the tab at
    `core.window-picker.editable_win(tab)` (the same buftype/filetype filter
    neo-tree's window picker uses) BEFORE calling the action.
  - **`<leader>gi` outside a view prefers a real `DiffView`.** A `<leader>gh`
    tab is a `FileHistoryView`: no `files:iter()`, no `set_file_by_path`, so
    adopting it turns the jump into a bogus "no changes" toast. `open_view()`
    scans for `files` **and** `set_file` first and only then falls back.
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
    argument it only disposes stray views. Closing a specific tab is
    `lib.tabpage_to_view(tp)` → `view:close()` → `lib.dispose_view(view)`.
  - **Exit via `actions.goto_file_edit()`**, don't hand-roll it: it restores
    the window options (`diff` / `scrollbind` / `foldmethod`) *before* the
    `:edit`, so the buffer arrives as a plain editable file, and it resolves
    the target from the diff pane *or* the file panel. Close the tab only
    after confirming the tabpage actually changed — it bails when the file
    isn't on disk.
  - Diffview's built-in `gf` remains the *keep the tab open* variant; that's
    why `<leader>go` closes and no setting was added.

  **Click-to-preview in the file panels** — diffview's ONLY stock mouse
  binding is `{ "n", "<2-LeftMouse>", actions.select_entry }`
  (`diffview/config.lua`), so seeing a file's diff cost two clicks while
  neo-tree opened on one. `CLICK_MAPS` adds `<LeftRelease>` behind the **same
  persisted `tree_click` setting** neo-tree uses (`:NvSinnerMenu` →
  "Explorer click", default `single`), wired into both
  `opts.keymaps.file_panel` (`<leader>gd`/`<leader>gi`) and
  `file_history_panel` (`<leader>gh`/`<leader>gH`). Rules:

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
