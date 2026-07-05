# lua/plugins/terminal/ — toggleterm & sessions contracts

## Terminals — `toggleterm.lua`

- `<leader>t` → horizontal terminal 1 (forced `direction=horizontal`), sized to
  20% of `vim.o.lines`. `<leader>t2` … `<leader>t9` toggle additional
  independent horizontal terminals (ids 2–9), each via
  `exe "<N>ToggleTerm direction=horizontal"`. `<leader>t` is a prefix of
  `<leader>t2`…, so a bare `<leader>t` waits one `timeoutlen` (which-key shows
  the menu) before falling back to terminal 1. (Moved off `<C-t>` to avoid a
  Ctrl+T conflict.)
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
  open it — and that first open shows the **CLI picker** (below): the chosen
  CLI becomes the terminal's `cmd`, "plain terminal" runs the shell with a
  `term` winbar title.
- **First-open CLI picker** — the first time an AI session is toggled, a picker
  opens *in the column's own space* (a full-height side split, not a float)
  listing `claude` / `kiro-cli` / `opencode` (not-installed ones are marked and
  refuse selection with a warning) plus **"plain terminal — no AI"**. The
  choice becomes the toggleterm `cmd` (nil → default shell); picking plain
  terminal titles the column's winbar `term` (like the horizontals) instead of
  `AI · N` via the `__nv_label` override read by `on_panel_open`. Keyboard
  (`j`/`k`, `<CR>`, `1`-`4`, `q`/`<Esc>`) + mouse (click a row); styled with
  the NvMenu* groups from `core/menu.lua`.
- Each panel gets a reserved `id = 99 + N` (session 1 → 100, … session 9 →
  108), kept clear of the low ids 1–9 that the horizontal terminals use.
  Without reserved ids, opening an AI panel first would claim id 1 and
  `<leader>t` would just re-toggle that panel instead of opening a horizontal
  terminal.
- `<leader>j` is also a prefix of `<leader>j2`…, so a bare `<leader>j` waits
  one `timeoutlen` (which-key shows the menu) before falling back to session
  1; press a digit right after `<leader>j` to jump straight to that session.
- Resize via the global split-resize keymaps in `core/keymaps.lua`: `<C-,>` /
  `<C-.>` (width ±20 columns, use for the vertical AI panel) and `<C-;>` /
  `<C-'>` (height ±5 rows, use for the horizontal terminal). Both work from
  terminal mode. (The steps are absolute — Vim silently ignores a trailing `%`
  on `:resize`, so the old "±20%" wording was never percentual.)
- **Bridge integration**: `toggleterm.lua` pushes sessions into
  `core/ai-sessions.lua` (`register` on create, `touch` on open + a
  `TermEnter` autocmd, `unregister` on exit, `set_opener` for the fallback)
  and sets `b:nv_term_label` in `on_panel_open` for the activity winbar. Full
  bridge/labeling contracts: `lua/core/CLAUDE.md` §AI and §Agent activity.

## Sessions — `persistence.lua`

- `persistence.nvim`: `<leader>SQ` quit no-save, `<leader>Sc` restore cwd
  session, `<leader>Sl` restore last session.
