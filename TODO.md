# TODO — NvSinner distro

Pending work to turn this config into a fully standalone, publishable Neovim
distribution. Done items live in [NVSINNER.md](NVSINNER.md); this file tracks
what's left.

## Distribution polish

- [ ] **`nvsinner` launcher install on non-`~/.local/bin` PATHs.** `install.sh`
      warns if `~/.local/bin` isn't on PATH but doesn't fix the shell rc. Decide
      whether to offer appending the `export PATH` / alias automatically.
- [ ] **Uninstall script / instructions.** A clean `uninstall.sh` (or README
      section) that removes `~/.config/nvsinner`, `~/.local/share/nvsinner`,
      `~/.local/state/nvsinner`, `~/.cache/nvsinner`, and the launcher.
- [ ] **Health check on first run.** Surface missing externals (ripgrep, node,
      stylua, prettier, eslint_d, a Nerd Font) with a friendly message instead of
      letting features silently no-op.

## Nice to have

- [ ] **Optional formatters via Mason** (stylua, prettier, eslint_d) so the
      distro needs zero manual `npm i -g` / `brew install` for formatting. Would
      need `mason-tool-installer` or an `ensure_installed` tools list.
- [ ] **Screenshots / GIF** in the README (dashboard, AI column, glass theme).
- [ ] **CI** that boots the config headless + runs `make test` on push.
- [ ] **Versioned releases / tags** once the repo is split out.

## Done (see NVSINNER.md for detail)

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
