# TODO — NvSinner distro

Pending work to turn this config into a fully standalone, publishable Neovim
distribution. Done items live in [NVSINNER.md](NVSINNER.md); this file tracks
what's left.

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
