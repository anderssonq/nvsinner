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
   → headless `Lazy! sync`. Launcher source also kept at [bin/nvsinner](bin/nvsinner).

## Status

Distro plumbing is in place: `NVIM_APPNAME=nvsinner` launcher (`bin/nvsinner`),
`install.sh`, first-boot Mason auto-install, and NvSinner branding across the
dashboard + README. On the dev machine `~/.config/nvsinner` is a **symlink** to
this repo (`~/.config/nvim`) so both `nvim` and `nvsinner` load the same files.
**Remaining:** carve NvSinner into its own repo (item 4) before publishing the
one-liner widely.
