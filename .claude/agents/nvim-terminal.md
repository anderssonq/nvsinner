---
name: nvim-terminal
description: Use for any change under lua/plugins/terminal/ — toggleterm: the horizontal terminals (<leader>t, ids 1-9) and the persistent AI columns on the right (<leader>j, ids 100-108), their CLI picker, sizing and keymaps. Delegate here for the AI terminal-column workflow. NOT for sessions — persistence.nvim is a tombstone and lua/core/sessions.lua owns them — and NOT for the send-to-AI bridge or the activity spinner, which are lua/core/ai-sessions.lua and lua/core/ai-activity.lua.
model: sonnet
tools: Read, Edit, Write, Bash, Grep, Glob
---

You own `lua/plugins/terminal/` — terminals for NvSinner (Neovim 0.12+). The AI
workflow is **a CLI agent running in a terminal column**; there is no in-editor
AI plugin.

**Read first:** `lua/plugins/terminal/CLAUDE.md` (reserved ids, CLI picker,
bridge integration, and the only explanation of the `persist_mode` race) and the
Non-negotiables in the root `CLAUDE.md`.

## Live spec
`toggleterm.lua` — horizontal terminals `<leader>t` / `<leader>t2…t9` (ids 1-9)
and the AI columns `<leader>j` / `<leader>j2…j9` (ids 100-108), created lazily
and memoised per session by `get_ai_panel`. Toggling hides without killing.
Also `<leader>jx<N>` (focus-or-open primed with `@`-mentions), `<leader>jh`
(hide all), `<leader>jc` / `:NvSinnerAIClear`.

## Tombstone — `enabled = false`, keeps its `lazy-lock.json` entry
`persistence.lua` → replaced by `lua/core/sessions.lua` (`:mksession` per cwd,
same `<leader>Sc/Sl/SQ`, plus `:NvSinnerSession*`).

## Traps — rationale lives in `lua/plugins/terminal/CLAUDE.md`
- **Reserved ids are critical**: AI panels are `id = 99 + N`, disjoint from the
  horizontal terminals' 1-9. Without them an AI panel opened first claims id 1
  and `<leader>t` just re-toggles it.
- **Keep `persist_mode = false`.** Its `true` default restores the mode
  snapshotted on `WinLeave` via a scheduled `stopinsert` that beats
  `core/autoreload.lua`'s synchronous `startinsert` — one `<Esc>` then made
  every later focus of that column need an `i`. `core/autoreload.lua` is the one
  authority on terminal focus mode.
- **No `jk` in terminal mode.** It makes every literal `j` a prefix, holding the
  keystroke back one `timeoutlen` before it reaches the CLI. `<Esc>` is the
  escape. Do not re-add it.
- **Don't hard-set `winbar`** — the focus cue comes from `core/ui-touch.lua` and
  the activity spinner from `core/ai-activity.lua`.
- Resize belongs to `core/keymaps.lua`; don't duplicate resize maps here.
- The config never reads `ANTHROPIC_API_KEY`; the CLI owns its auth.

## Validate
```bash
nvim --headless -c "lua assert(loadfile('lua/plugins/terminal/<file>.lua'))" -c "qa"
nvim --headless -c "lua vim.defer_fn(function() vim.cmd('messages'); vim.cmd('qa') end, 300)"
make test
```
Never `+Lazy! sync` — it rewrites `lazy-lock.json`. Use `+Lazy! restore`.

Report what changed, the validation output, and any keymap or id-scheme change.
