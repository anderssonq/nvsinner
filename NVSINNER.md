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
   Done — `lsp-config.lua` auto-installs the core servers, including the Vue 3
   hybrid pair (`vtsls` + `vue_ls`), through `mason-lspconfig` (`event =
   "VeryLazy"`, depends on `mason.nvim`, `automatic_enable = false`). No manual
   `:MasonInstall` for the core servers.
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
 10. ✅ **Versioned releases + update check (v1.0.0, current v3.1.0).** The
    semver lives in ONE place — [lua/nvsinner/init.lua](lua/nvsinner/init.lua)
        (`version = "3.1.0"`) — and [lua/core/version.lua](lua/core/version.lua)
    runs a once-per-session async check against that file fetched raw from
    `main`: the dashboard footer swaps the quote for an update prompt (or
    appends "NvSinner is up to date"), and the `:NvSinnerHelp` title shows
    `v3.1.0` plus the check status. Users update with `:NvSinnerUpdate`.
    Cutting a release: [docs/releasing.md](docs/releasing.md), coordinated by
    the `nvim-release` agent. **v1.1.0** added `<leader>jc` /
    `:NvSinnerAIClear` (clear an AI session's chosen CLI so the next open
    re-runs the picker) and a consistent `vim.ui.select` UI (telescope-backed
    from the first call of a session). **v1.2.0** added `<leader>jx<N>` —
    focus-or-open an AI session with the CLI input primed with `@path`
    mentions of your open buffers; **v1.2.1** narrowed those mentions to the
    buffers actually **visible in a window**, so files whose window you closed
    (still in Neovim's buffer list) no longer scope the agent. **v1.3.0**
    calibrated `timeoutlen` to 300 ms (it had never been set, so Neovim's
    1000 ms default made every prefix key — `<leader>t`, `<leader>j`,
    `<leader>jx`, `<leader>f` — pause a full second before acting), exposed it
    as the persisted **"Key timeout"** row in `:NvSinnerMenu`, and dropped the
    terminal-mode `jk` escape that was withholding every literal `j` typed
    into an AI CLI for the same interval. **v1.4.0** added `<leader>gi`/
    `<leader>go` to diffview — jump straight into the diff of the file and
    line you're on (toggling file panel ⇄ diff once inside), then back out to
    an editable buffer at the same line, closing the diff tab. **v1.5.0** made
    the editor stop losing your place: the project folder now names both the
    terminal tab and the statusline (`󰉋 myproject`), neo-tree opens on a
    **single click** (persisted "Neo-tree click" row) and its Buffers tab no
    longer blocks the UI on a synchronous `git status` every render, and the
    `<leader>gi`/`<leader>go` round trip stopped destroying the file tree on
    exit, honours the file selected in neo-tree, keeps `gi` inside the view as
    a diff ⇄ file-list toggle, and no longer lets a `<leader>gh` history tab
    hijack the jump. **v1.6.0** carried the single click into the *other*
    explorer: one click on a row of diffview's file panel previews that file's
    diff (focus stays in the list, so you can walk the changes), on the same
    persisted setting — relabelled **"Explorer click"** because it now governs
    both. The missed-row guard behind it moved to
    [lua/core/mouse.lua](lua/core/mouse.lua), shared by the tree and the
    panels. **v1.7.0** answered "what are my agents doing?": `:NvSinnerAgents`
    (`<leader>xa`) lists every AI column with its status beside a **live preview
    of that agent's chat**, and lets you focus one (opening it when hidden) or
    close it for good — including a column whose CLI already exited, which the
    `<leader>ja` picker could not see. Status combines
    [ai-activity](lua/core/ai-activity.lua)'s output signal with per-CLI screen
    signatures for `claude` / `kiro-cli` / `opencode`, which is what catches a
    permission prompt: it emits no output, so the output signal alone reads it
    as idle while the agent is really blocked on you. **v1.8.0** gave the git
    diff one tab and one way out: `<leader>gd` and `<leader>gH` now adopt the
    view already open instead of stacking a tabline entry per press (`:Diffview*`
    does not dedupe at all — every call is a fresh `tab split`), `<leader>go` was
    retired in favour of diffview's own `gf` — wrapped so it still lands the file
    in a code pane rather than wiping neo-tree or the AI column — and
    `<leader>gu` added the **unified inline diff**: the old version of each hunk
    as virtual lines above the new one, in the real editable buffer. That last
    one is gitsigns' rather than diffview's because diffview structurally cannot
    render a unified view: it draws through Neovim's native window `'diff'` mode,
    which needs two diffed windows. **v1.9.0** widened the look and finished the
    TODO chips: three more background themes — `briar` (Rosé Pine), `grove`
    (Everforest) and `neon` (cyberdream) — bring `:NvSinnerMenu`'s "Background
    theme" row to ten, each an original palette mapped onto carbon's fixed role
    semantics rather than a vendored colorscheme; and every TODO keyword now
    drops its Nerd Font glyph in the sign column beside the line number, the
    half of todo-comments.nvim the native
    [lua/core/todo.lua](lua/core/todo.lua) had not carried over. **v1.9.1** is
    documentation: `docs/ARCHITECTURE.md` and `docs/CONTRIBUTING.md` (neither
    had ever existed) plus a correction pass over the docs that had drifted
    from the code — most seriously, `CLAUDE.md` and `docs/installation.md` both
    instructed `Lazy! sync`, contradicting the restore-not-sync non-negotiable
    stated in the same file, and both README and `CLAUDE.md` claimed
    `install.sh` wires `core.hooksPath`, which it never has. **v2.0.0** is the
    first breaking release: the Neovim floor moves from 0.11 to **0.12**, and
    `install.sh` now enforces it instead of only claiming to. The floor bought
    the bundled `nvim.undotree` (`<leader>u`) and three native 0.12 LSP
    capabilities — linked editing, `:NvSinnerDiagnosticsWorkspace`, and an
    opt-in per-window LSP folding toggle (`<leader>zl`). It also settled the
    distro's longest-running defect: the "Neovim 0.12.x markdown treesitter
    crash" was never a Neovim bug, it was the frozen `nvim-treesitter` `master`
    reading 0.12's list-valued `match[id]` as a single node, which had silently
    broken HTML and bash injections too. `lua/core/ts-compat.lua` fixes it at
    the source and **six** suppression sites came out. Snippet placeholders were
    unreachable and now are not. Four claims that had been carried in the docs
    for months did not survive being measured — the startup number's
    methodology, the "dead" lockfile entries (they are the tombstone revert
    path), the "stale" pins (most were at their latest tag), and the crash
    narrative itself. **v3.0.0** makes Node 20+ an explicit installation floor
    and replaces `ts_ls` with the Vue 3 hybrid pair: `vtsls` owns TypeScript
    while `vue_ls` owns SFC regions, with a portable Mason plugin path and no
    duplicate TypeScript client. `:checkhealth nvsinner` now reports the exact
    Node executable and rejects incompatible versions; optional Ruby, Go and
    Rust servers only enable when their toolchain exists, avoiding repeated LSP
    log noise. Telescope becomes a solid adaptive search surface: results and a
    larger dark preview sit side by side on wide screens, stack vertically on
    narrow screens, and dim the editor only for preview-based pickers.
    **v3.1.0** gives LSP navigation a peek mode: `<leader>ld` /
    `<leader>lt` open the definition / type definition in the Telescope picker
    with its code preview instead of jumping (`jump_type = "never"` —
    telescope otherwise jumps straight to a single result, which made the peek
    indistinguishable from `gd`), and neo-tree's Git tab is gone from the
    winbar: its synchronous `git status` scan is the tab's whole content
    (~5× a plain status, scaling with the ignored tree) and diffview already
    owns git, so the tree keeps only Files / Buffers while Files keeps its
    async git state.

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
