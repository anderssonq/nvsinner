# TODO — NvSinner distro

Pending work to turn this config into a fully standalone, publishable Neovim
distribution. Done items live in [NVSINNER.md](NVSINNER.md); this file tracks
what's left.

## Update / upgrade path (existing users)

There is **no build step** (Lua is interpreted — the repo files are the runtime),
so publishing = `git push` to `main`. A *fresh* `install.sh` run gets the current
code. The gap is updating an **already-installed** `~/.config/nvsinner`:

- [ ] **`install.sh` update mode.** Right now it skips the clone if
      `~/.config/nvsinner` already exists, so re-running the one-liner does NOT
      pull new config code (only re-runs `Lazy sync`). Make it `git pull` (and
      re-sync) when the dir is already a NvSinner clone.
- [ ] **`:NvSinnerUpdate` command.** An in-editor updater (à la `:NvChadUpdate` /
      `:AstroUpdate`): `git -C <config> pull` → `Lazy restore`/`sync` →
      `checkhealth`. The most polished UX for end users.
- [ ] **README "Updating" section.** At minimum document the manual path:
      `git -C ~/.config/nvsinner pull` (until the above lands).
- [ ] **Drop `--depth=1` (shallow clone) in `install.sh`** — or `git pull
      --unshallow` on first update — so end users' clones update cleanly.
- [ ] **`Lazy! restore` vs `Lazy! sync` on install** for reproducible plugin
      versions from the committed `lazy-lock.json` (see the lazy-lock item below).

## Distribution polish

- [ ] **Pin or document the lazy-lock.json story.** Decide whether the distro
      ships a pinned `lazy-lock.json` (reproducible installs) or floats on
      latest. Right now it's committed and gets regenerated on `Lazy sync`.
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

- [x] `NVIM_APPNAME=nvsinner` launcher (`bin/nvsinner`) + dev symlink.
- [x] `install.sh` (clone → launcher → `Lazy! sync`).
- [x] First-boot Mason auto-install of LSP servers (lua_ls, ts_ls, html).
- [x] NvSinner branding (dashboard + README).
- [x] Separate repo (`anderssonq/nvsinner`), split out of the personal dotfile
      repo with a fresh history.
