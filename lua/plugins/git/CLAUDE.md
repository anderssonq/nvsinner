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
    the file panel and the diff.
  - `<leader>go` *out of* the diff — back to the real editable buffer at the
    cursor line, and the Diffview tab is closed.

  Contracts to preserve when editing:

  - **Selection goes through `--selected-file`**, not a manual open-then-seek.
    Diffview normalises the absolute path against the repo toplevel itself.
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
