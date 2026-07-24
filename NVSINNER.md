# NvSinner — distribution plan

Plan to convert this personal configuration into an **installable, named Neovim
distribution**, in the style of NvChad / LazyVim / AstroNvim: a repo that
anyone can clone and run as an isolated Neovim instance without affecting their
real `~/.config/nvim`.

## Core idea

Neovim natively supports this via `NVIM_APPNAME` (0.9+): each app name gets its
own config/data/state/cache dir. No extra tricks needed for multiple instances
to coexist.

```bash
git clone <repo-nvsinner> ~/.config/nvsinner
NVIM_APPNAME=nvsinner nvim
```

This creates `~/.config/nvsinner`, `~/.local/share/nvsinner`,
`~/.local/state/nvsinner` — completely separate from any other config.

## What already works as-is (no changes needed)

- [init.lua](init.lua) already auto-clones `lazy.nvim` if missing (standard
  bootstrap for any distro).
- `stdpath("data")` already resolves according to `NVIM_APPNAME`, so there are
  no hardcoded user paths that would break someone else's installation.

## What's missing to make it a distributable product (not just a dotfile)

1. ✅ **Auto-install LSP servers from Mason on first boot.**
   Done — `lsp-config.lua` carries `ensure_installed = { "lua_ls", "ts_ls",
   "html" }` (`mason-lspconfig`, `event = "VeryLazy"`, depends on `mason.nvim`,
   `automatic_enable = false`). No manual `:MasonInstall` for the core servers.
2. ✅ **Branding.** Dashboard logo + footer already spell "NvSinner"
   ([dashboard.lua](lua/plugins/ui/dashboard.lua)); [README.md](README.md) title
   and intro now read "NvSinner" too.
3. ✅ **One-liner installation README.** [README.md](README.md) leads with a
   `curl … | bash` one-liner (and a manual `NVIM_APPNAME=nvsinner` path).
4. ✅ **Separate repo.** NvSinner now lives in its own repo,
   [`anderssonq/nvsinner`](https://github.com/anderssonq/nvsinner), split out of
   the personal dotfile repo (`anderssonq/ander-nvim-lazy`) with a fresh history
   so commit history + README tell the distro's story.
5. ✅ `install.sh` automates `git clone` → `nvsinner` launcher (`~/.local/bin`)
   → headless `Lazy! restore`. Launcher source also kept at [bin/nvsinner](bin/nvsinner).
6. ✅ **Update path for existing installs.** `install.sh` `git pull`s an existing
   clone (unshallowing old `--depth=1` installs) instead of skipping, and a new
   `:NvSinnerUpdate` command ([lua/core/update.lua](lua/core/update.lua)) does
   `git pull --ff-only` → `Lazy restore` → `checkhealth` in-editor. Both install
   and update use `Lazy! restore` against the committed `lazy-lock.json`, so the
   plugin set is reproducible (pinned versions, not floating to latest).
7. ✅ **Distribution polish — PATH help, uninstall, first-run health.**
   `install.sh` prints the exact `export PATH` line (naming the likely shell rc)
   when `~/.local/bin` isn't on PATH, without editing the user's files. A new
   [uninstall.sh](uninstall.sh) removes the four `nvsinner` XDG dirs + the
   launcher (confirm on TTY / `--yes` when piped; unlinks a symlinked config dir
   rather than following it). Missing externals surface via `:checkhealth
   nvsinner` ([lua/core/health.lua](lua/core/health.lua) +
   [lua/nvsinner/health.lua](lua/nvsinner/health.lua)) plus a one-time first-run
   toast. README documents Health check + Uninstalling.
8. ✅ **Mason-managed formatters.** A new
   [lua/plugins/lsp/mason-tools.lua](lua/plugins/lsp/mason-tools.lua)
   (`mason-tool-installer.nvim`, `event = "VeryLazy"` like `mason-lspconfig`)
   auto-installs `stylua`, `prettier`, and `eslint_d` via Mason on first boot —
   no manual `npm i -g` / `brew install` for formatting. `auto_update = false`
   on purpose: package updates stay the opt-in `:NvSinnerSync` path.
   `:checkhealth nvsinner` hints now point at `:MasonToolsInstall` as the
   retry, with brew/npm as manual fallbacks.
9. ✅ **CI.** [.github/workflows/ci.yml](.github/workflows/ci.yml) runs on
   push/PR: stable Neovim, plugin cache keyed on `lazy-lock.json`,
   `Lazy! restore` against the pinned lockfile, a headless boot check that
   fails on startup errors, then the full `make test` suite.
10. ✅ **Versioned releases + update check (v1.0.0, current v1.2.1).** The
    semver lives in ONE place — [lua/nvsinner/init.lua](lua/nvsinner/init.lua)
    (`version = "1.2.1"`) — and [lua/core/version.lua](lua/core/version.lua)
    runs a once-per-session async check against that file fetched raw from
    `main`: the dashboard footer swaps the quote for an update prompt (or
    appends "NvSinner is up to date"), and the `:NvSinnerHelp` title shows
    `v1.2.1` plus the check status. Users update with `:NvSinnerUpdate`.
    Cutting a release: [docs/releasing.md](docs/releasing.md), coordinated by
    the `nvim-release` agent. **v1.1.0** added `<leader>jc` /
    `:NvSinnerAIClear` (clear an AI session's chosen CLI so the next open
    re-runs the picker) and a consistent `vim.ui.select` UI (telescope-backed
    from the first call of a session). **v1.2.0** added `<leader>jx<N>` —
    focus-or-open an AI session with the CLI input primed with `@path`
    mentions of your open buffers; **v1.2.1** narrowed those mentions to the
    buffers actually **visible in a window**, so files whose window you closed
    (still in Neovim's buffer list) no longer scope the agent.

## Status

Distro plumbing is in place: its own repo
([`anderssonq/nvsinner`](https://github.com/anderssonq/nvsinner)),
`NVIM_APPNAME=nvsinner` launcher (`bin/nvsinner`), `install.sh` with an
install-or-update flow, an in-editor `:NvSinnerUpdate`, first-boot Mason
auto-install, and NvSinner branding across the dashboard + README. On the dev
machine `~/.config/nvsinner` is a **symlink** to this repo (`~/.config/nvim`) so
both `nvim` and `nvsinner` load the same files. The distribution-polish items
(PATH help, `uninstall.sh`, first-run health surfacing) are done, and so are
Mason-managed formatters, CI, and v1.0.0 versioning with the in-editor update
check.
**Remaining:** the "nice to have" items tracked in [TODO.md](TODO.md) — README
screenshots/GIF (needs a human with a GUI terminal); pushing an actual
`vX.Y.Z` git tag stays optional (the update check only depends on `main`).
