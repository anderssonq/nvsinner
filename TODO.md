# TODO — NvSinner distro

Pending work to turn this config into a fully standalone, publishable Neovim
distribution. Done items live in [NVSINNER.md](NVSINNER.md); this file tracks
what's left.

## Native migration (distro, not config pack)

Full analysis and justifications: [docs/native-roadmap.md](docs/native-roadmap.md).
Migrated plugins keep their spec as an `enabled = false` one-line-revert stub.

### Migrated

- [x] **incline.nvim** → `lua/core/filebadge.lua` (winbar file badge + markdown
      "Open view" chip).
- [x] **nvim-cursorline** → covered by `lua/core/ui-touch.lua` + illuminate.
- [x] **kanagawa-dragon (theme plugin)** → native carbon (`lua/core/carbon.lua`
      + `colors/carbon.lua`).
- [x] **Comment.nvim** → Neovim 0.10+ builtin `gcc` / `gc{motion}` commenting.
- [x] **git-blame.nvim** → `lua/core/git-blame.lua` (async porcelain blame of
      the buffer contents → eol virtual text; `:NvSinnerBlameToggle`).
- [x] **vim-illuminate** → `lua/core/illuminate.lua` (builtin LSP
      `document_highlight` + visible-range fallback).
- [x] **persistence.nvim** → `lua/core/sessions.lua` (`:mksession` per cwd;
      `<leader>Sc/Sl/SQ` + `:NvSinnerSession*`).
- [x] **indentmini.nvim** → `lua/core/indent.lua` (decoration-provider
      current-scope guide).
- [x] **nvim-colorizer** → `lua/core/colorizer.lua` (visible-range #hex scan
      → bg chips).
- [x] **todo-comments.nvim** → `lua/core/todo.lua` (visible-range keyword
      chips; drops a plenary consumer).
- [x] **nvim-window-picker** → `lua/core/window-picker.lua` (letter-overlay
      floats; serves neo-tree's `require("window-picker")` via
      package.preload).
- [x] **render-markdown.nvim** → `lua/core/markdown.lua` (minimal pattern-based
      reading view — headings, bullets, checkboxes, quotes, fence shading,
      rules; same `_G.NvMdReader` chip + `<leader>m`).

### Pending — Wave 2 (distro identity)
### From here on, we should review each repository to migrate those that haven't been updated in a long time.

- [ ] **alpha-nvim** → `core/dashboard.lua` (the spec is already ~90% custom
      NvSinner code).
- [ ] **nvim-notify** → `core/toast.lua` (owning `vim.notify` also unblocks the
      noice decision).
- [ ] **barbecue.nvim + nvim-navic** → LSP breadcrumbs inside
      `core/filebadge.lua` (unifies winbar ownership).
- [ ] **satellite.nvim** → native decoration-provider scrollbar (lowest
      priority of the tier).

### Pending — Wave 3 (flagships, future goals)

- [ ] **telescope** → NvSinnerFind: `matchfuzzy()` + async fd/rg picker, the
      sixth Mason-style modal.
- [ ] **toggleterm** → native terminal manager (only behind the terminal-UX
      campaign's edge-case matrix; reserved ids 100+ must survive).
- [ ] **lualine** → native statusline (winbar-expression expertise transfers).
- [ ] **noice** → evaluate drop vs replace once `core/toast.lua` exists.

Everything else stays on purpose (engines and deep tools — treesitter, LSP
stack, gitsigns, diffview, neo-tree, leap, which-key, …); the roadmap lists
each with its rationale.

## Nice to have

- [ ] **Screenshots / GIF** in the README (dashboard, AI column, carbon theme).
      *Needs a human with a GUI terminal — can't be captured headlessly.*
- [ ] **Versioned releases / tags.** The repo is split out, so this is just
      picking a version (e.g. `v1.0.0`), tagging, and pushing — a publishing
      decision for the maintainer.

## Done (see NVSINNER.md for detail)

- [x] **Formatters via Mason** — `lua/plugins/lsp/mason-tools.lua`
      (`mason-tool-installer.nvim`) auto-installs `stylua`, `prettier`, and
      `eslint_d` on first boot; no manual `npm i -g` / `brew install` needed.
      `auto_update = false` (updates stay the opt-in `:NvSinnerSync` path);
      `:checkhealth nvsinner` hints point at `:MasonToolsInstall`.
- [x] **CI** — `.github/workflows/ci.yml`: installs stable Neovim, restores the
      pinned plugin set (`Lazy! restore` against `lazy-lock.json`, cached), does
      a headless boot check that fails on startup errors, then runs `make test`.
- [x] **Distribution polish — PATH help, uninstall, first-run health.**
      `install.sh` no longer just warns about `~/.local/bin`: it prints the exact
      `export PATH` line naming the likely shell rc (zsh/bash/fish), but never
      edits the user's files. A new `uninstall.sh` removes the four
      `nvsinner` XDG dirs (config/data/state/cache) + the launcher, confirming
      first (prompt on a TTY, `--yes` required when piped) and unlinking — not
      following — a symlinked config dir. Missing externals are surfaced via
      `:checkhealth nvsinner` (`lua/nvsinner/health.lua` → `lua/core/health.lua`)
      plus a one-time first-run toast; README has an "Uninstalling" section.
- [x] **Update / upgrade path for existing users.** `install.sh` now `git pull`s
      an existing clone (and unshallows old `--depth=1` installs) instead of
      skipping; a new `:NvSinnerUpdate` command (`lua/core/update.lua`) does
      `git pull --ff-only` → `Lazy restore` → `checkhealth` in-editor; README has
      an "Updating" section. Fresh clones are full (no `--depth=1`), and both
      install and update use `Lazy! restore` against the committed
      `lazy-lock.json` for reproducible plugin versions (the lazy-lock story:
      ship pinned, `restore` on install/update, `:Lazy sync` to float on latest).
- [x] `NVIM_APPNAME=nvsinner` launcher (`bin/nvsinner`) + dev symlink.
- [x] `install.sh` (clone → launcher → `Lazy! sync`).
- [x] First-boot Mason auto-install of LSP servers (lua_ls, ts_ls, html).
- [x] NvSinner branding (dashboard + README).
- [x] Separate repo (`anderssonq/nvsinner`), split out of the personal dotfile
      repo with a fresh history.
