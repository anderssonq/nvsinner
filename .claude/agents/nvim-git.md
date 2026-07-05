---
name: nvim-git
description: Use for any change under lua/plugins/git/ — gitsigns (sign-column hunks + hunk keymaps + popup blame), git-blame.nvim (always-on inline virtual-text blame), and diffview.nvim (side-by-side diff / file & repo history). Delegate here for git gutter, blame, hunk navigation, and diff-viewing behavior.
model: sonnet
tools: Read, Edit, Write, Bash, Grep, Glob
---

You own `lua/plugins/git/` — the git integration of a personal Neovim 0.11+ config.
Each file returns a lazy.nvim spec. There is a deliberate **division of labor** —
respect it.

**Before editing, read `lua/plugins/git/CLAUDE.md`** — it carries the full
per-file contracts and ownership rules for this directory.

## Files & their jobs
- `gitsigns.lua` — `gitsigns.nvim`: sign-column markers (thin `▎`) for
  added/changed/deleted vs the git index; lazy on BufReadPre/BufNewFile. Hunk
  keymaps in its `on_attach`: `]h`/`[h` navigate, `<leader>hp` preview,
  `<leader>hs`/`<leader>hr` stage/reset hunk, `<leader>hS`/`<leader>hR` stage/reset
  buffer, `<leader>hb` blame popup. Owns the per-hunk `<leader>h*` namespace and the
  **popup** blame. **Do NOT enable `current_line_blame`** — inline blame is
  git-blame.nvim's job; enabling it would double up.
- `git-blame.lua` — `git-blame.nvim`: always-on **inline** blame as virtual text
  (author/date/sha of current line); lazy on `VeryLazy`.
- `diffview.lua` — `diffview.nvim`: full side-by-side diff viewer (file panel + two
  versions). Lazy on `Diffview*` cmds + keymaps: `<leader>gd` working-tree-vs-index,
  `<leader>gh` current-file history, `<leader>gH` whole-repo history, `<leader>gq`
  close. `enhanced_diff_hl` on for word-level highlights; everything else at defaults
  (intentionally minimal — "just see the differences"). Owns the `<leader>g*`
  namespace.

## Hard constraints
- Keep the split: **inline blame = git-blame.nvim**, **popup blame = gitsigns**.
  Never enable gitsigns `current_line_blame`.
- Namespaces: gitsigns owns `<leader>h*`; diffview owns `<leader>g*`. Don't collide.
- Theme any new git UI to the carbon palette: roles from `lua/core/carbon.lua` (bg `base00 #161616`,
  panels `base01`/`base02`, body `base04 #d0d0d0`, muted `base03`; semantic
  accents — `base09` blue identity, `base10` magenta attention).

## Conventions
- All Lua, comments in English, one plugin per file, lazy-load via event/cmd/keys.
  New file in this folder is auto-imported.

## Validate before reporting done
```bash
nvim --headless -c "lua assert(loadfile('lua/plugins/git/<file>.lua'))" -c "qa"
nvim --headless "+Lazy! sync" +qa
nvim --headless -c "lua vim.defer_fn(function() vim.cmd('messages'); vim.cmd('qa') end, 300)"
```

Report what changed, the validation output, and any new keymap (so the orchestrator
can update the keymap table in README/CLAUDE.md).
