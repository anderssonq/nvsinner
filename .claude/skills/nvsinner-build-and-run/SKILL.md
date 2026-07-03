---
name: nvsinner-build-and-run
description: >
  Recreate, run, update, and remove the NvSinner environment from scratch.
  Load this when: installing NvSinner (curl|bash one-liner, manual clone, or
  dev-machine symlink), launching it (nvsinner launcher / NVIM_APPNAME
  mechanics), updating it (:NvSinnerUpdate, installer re-run, by-hand pull +
  restore, the restore-vs-sync doctrine), uninstalling it (uninstall.sh
  semantics, symlink safety), recreating the environment on a new machine,
  debugging install/update/first-boot failures (PATH, shallow clones, Mason
  auto-install, first-run health toast), or editing install.sh, uninstall.sh,
  bin/nvsinner, lua/core/update.lua, or lua/core/health.lua.
---

# NvSinner — Build, Run, Update, Remove

NvSinner is a git clone that runs Neovim under `NVIM_APPNAME=nvsinner`. There is
no build step: "building" the environment = clone + launcher + headless plugin
restore. Everything below documents what the scripts **actually do** (verified
line-by-line, 2026-07-02), not just what the README says.

## When NOT to use this skill

| You are actually doing… | Use instead |
|---|---|
| Editing config code (plugins, core modules, keymaps, colors) or deciding whether a change is allowed | `nvsinner-change-control` |
| Debugging a live in-editor failure (broken highlight, dead keymap, plugin error) | `nvsinner-debugging-playbook` |
| Understanding *why* the design is shaped this way (rejected approaches, incidents) | `nvsinner-architecture-contract`, `nvsinner-failure-archaeology` |
| Writing/running the plenary test suite | `nvsinner-testing-and-qa` |
| Looking up what a specific plugin/module configures | `nvsinner-config-catalog` |
| Neovim API arcana (stdpath internals, autocmd semantics, winbar evaluation) | `neovim-internals-reference` |
| Verifying a claimed behavior empirically | `nvsinner-empirical-verification` |

---

## 1. Environment from scratch (macOS primary; Linux notes inline)

### 1a. System prerequisites

```bash
# macOS (Homebrew). Linux: apt/dnf/pacman equivalents; stylua via cargo if unpackaged.
brew install neovim ripgrep node stylua     # neovim MUST be >= 0.11
npm install -g prettier eslint_d            # needs node first (see Traps)
```

Hard version gate — the config uses `vim.uv` and the native `vim.lsp.config` /
`vim.lsp.enable` API and will NOT work below 0.11:

```bash
nvim --version | head -1    # expect: NVIM v0.11.x or newer (dev machine: v0.12.3)
```

`install.sh` itself only hard-checks two binaries: `git` and `nvim` (lines
23–24; it exits 1 if either is missing). Everything else (ripgrep, stylua,
prettier, eslint_d) is surfaced later by `:checkhealth nvsinner` — features
no-op silently without them, they don't block install.

### 1b. Bundled Nerd Font  [manual — needs a human for the GUI step]

Three FiraCode Nerd Font `.ttf` files ship in `fonts/`
(Regular / Medium / Retina):

```bash
cp fonts/*.ttf ~/Library/Fonts/                                # macOS
# Linux: cp fonts/*.ttf ~/.local/share/fonts/ && fc-cache -f
```

Then set the terminal (or GUI) font to **"FiraCode Nerd Font"** — a GUI step no
agent can do. Note: the health check reports the Nerd Font as **info-only**
(`vim.health.info`), never pass/fail, because a terminal font can't be probed
from inside Neovim; it is also excluded from the first-run toast's missing
count (`lua/core/health.lua`).

### 1c. AI CLI  [manual — interactive auth]

AI in NvSinner is a CLI agent run in the toggleterm column (`<leader>j`) — no
in-editor AI plugin exists. Install one and authenticate once:

```bash
npm install -g @anthropic-ai/claude-code
claude    # interactive login — surface to the user, don't automate
```

The config **never reads `ANTHROPIC_API_KEY`**; the CLI owns its auth/billing.
Any other CLI (opencode, ollama, …) works — just type it in the AI column.

---

## 2. Install paths

### 2a. One-liner (`install.sh`) — what it actually does

```bash
curl -fsSL https://raw.githubusercontent.com/anderssonq/nvsinner/main/install.sh | bash
```

`install.sh` (bash, `set -euo pipefail`; source repo overridable via
`NVSINNER_REPO=<url>`), step by step:

1. **Hard-requires `git` and `nvim`** on PATH; exits 1 otherwise. It does NOT
   verify the nvim version — only presence (the warning text says ">= 0.11"
   but nothing enforces it).
2. **Config dir** (`${XDG_CONFIG_HOME:-$HOME/.config}/nvsinner`), three-way:
   - **`$CONFIG_DIR/.git` is a directory** → existing clone: if
     `git rev-parse --is-shallow-repository` says `true` (legacy `--depth=1`
     installs), it first runs `git fetch --unshallow --quiet || true`, then
     `git pull --ff-only`. Re-running the one-liner is therefore the
     out-of-editor update path.
   - **Path exists but is not a git clone** (e.g. a manual copy) → left
     completely untouched; the script continues to the launcher + plugin steps
     anyway.
   - **Absent** → `git clone "$REPO_URL" "$CONFIG_DIR"` — **full clone, no
     `--depth=1`**, on purpose, so `git pull` / `:NvSinnerUpdate` work cleanly.
3. **Launcher**: writes `~/.local/bin/nvsinner` (heredoc, `chmod +x`) whose
   entire body is `exec env NVIM_APPNAME=nvsinner nvim "$@"` — functionally
   identical to the repo's `bin/nvsinner`. Overwrites unconditionally
   (idempotent).
4. **PATH advice**: if `~/.local/bin` is not in `$PATH`, it **prints** the
   exact line to add — picking the rc file from `$SHELL`: fish →
   `~/.config/fish/config.fish` with `fish_add_path $HOME/.local/bin`; zsh →
   `${ZDOTDIR:-$HOME}/.zshrc`; bash → `~/.bash_profile` on macOS (login shell)
   / `~/.bashrc` on Linux; unknown → generic. It **never edits any rc file**.
5. **Plugins**: `NVIM_APPNAME=nvsinner nvim --headless "+Lazy! restore" +qa` —
   `restore`, NOT `sync`: installs the exact commits pinned in the committed
   `lazy-lock.json` (50 plugins), so every install reproduces the tested set.
   lazy.nvim clones missing plugins first (its self-bootstrap in `init.lua`
   runs during this same headless boot).
6. Prints launch (`nvsinner`) + update (`:NvSinnerUpdate`) hints.

### 2b. Manual

```bash
git clone https://github.com/anderssonq/nvsinner.git ~/.config/nvsinner
NVIM_APPNAME=nvsinner nvim    # lazy.nvim self-bootstraps + installs on first launch
```

You get no launcher and no PATH advice this way; either export
`NVIM_APPNAME=nvsinner` per session or copy `bin/nvsinner` to your PATH
yourself. Caveat: a plain first launch lets lazy.nvim *install* plugins (which
does honor the lockfile for fresh installs); for a byte-identical pinned set
run the explicit restore: `NVIM_APPNAME=nvsinner nvim --headless "+Lazy! restore" +qa`.

### 2c. Dev-machine layout (this repo)

On the dev machine `~/.config/nvsinner` is a **symlink** to this repo
(`~/.config/nvim`), so `nvim` and `nvsinner` load the same files. Verify:

```bash
readlink ~/.config/nvsinner    # → /Users/<you>/.config/nvim
```

Consequences you must know:

- The symlink resolves to a real `.git` directory, so `install.sh` re-run on
  the dev machine **will `git pull` your working repo** through the link.
- `:NvSinnerUpdate` works here only because the repo has a remote; a copied
  (non-git) install hits the no-op-with-warning path instead (section 5).
- `uninstall.sh` unlinks the symlink but never touches the repo (section 6).
- Data/state/cache are still **separate per app name** even with a shared
  config: `nvim` and `nvsinner` on the same machine have independent plugin
  installs, lockfile-restore states, and first-run markers.

---

## 3. NVIM_APPNAME mechanics

`NVIM_APPNAME` (Neovim 0.9+) swaps the last path component of every `stdpath`
result. Verified on this machine:

```bash
NVIM_APPNAME=nvsinner nvim --headless \
  -c "lua print(vim.fn.stdpath('config'), vim.fn.stdpath('data'), vim.fn.stdpath('state'), vim.fn.stdpath('cache'))" -c qa
```

| stdpath | Resolves to (respecting `XDG_*_HOME`) | Holds |
|---|---|---|
| `config` | `~/.config/nvsinner` | this repo (clone or symlink) |
| `data` | `~/.local/share/nvsinner` | lazy.nvim + all plugins, Mason packages |
| `state` | `~/.local/state/nvsinner` | shada, undo, the first-run health marker |
| `cache` | `~/.cache/nvsinner` | luac bytecode cache, logs |

Because all four are suffixed by app name, NvSinner coexists with any
`~/.config/nvim` with **zero** shared files — nothing to migrate, nothing to
clobber, and uninstalling one never touches the other. There are no hardcoded
user paths in the config; everything goes through `stdpath` (e.g. the
lazy.nvim bootstrap uses `stdpath("data") .. "/lazy/lazy.nvim"`).

---

## 4. First-boot behavior

Ordered by what actually happens on the first interactive launch:

1. **lazy.nvim self-bootstrap** (`init.lua`, top block): if
   `stdpath("data")/lazy/lazy.nvim` doesn't exist, it `git clone
   --filter=blob:none --branch=stable` from GitHub, and on clone failure echoes
   the error, waits for a keypress, and `os.exit(1)`. Then prepends the path to
   `rtp` and `require("lazy").setup{}` imports the six category folders
   explicitly (lazy's `import` does not recurse — see
   `nvsinner-architecture-contract`).
2. **Mason LSP auto-install** (`lua/plugins/lsp/lsp-config.lua`):
   `mason-lspconfig` runs at `event = "VeryLazy"` (fires even when you land on
   the dashboard with no file open) with `dependencies = { mason.nvim }`, and
   `ensure_installed = { "lua_ls", "ts_ls", "html" }` — so those three servers
   download on first boot with no manual `:MasonInstall`.
   `automatic_enable = false` is deliberate: servers are enabled by *our*
   `vim.lsp.enable` only after the `"*"` config lands (whose `on_attach` nils
   `semanticTokensProvider`); letting mason-lspconfig auto-enable could start a
   server early and reintroduce the `@lsp.*` repaint. Do not flip it.
3. **solargraph is optional** — enabled in `vim.lsp.enable` (harmless when
   absent) but left out of `ensure_installed` because it needs a Ruby
   toolchain. Only if you edit Ruby:
   `NVIM_APPNAME=nvsinner nvim --headless "+MasonInstall solargraph" +qa`.
4. **First-run health toast** (`lua/core/health.lua`, `M.setup()` runs at
   require time from `init.lua`): registers a once-only `User VeryLazy`
   autocmd → 800ms defer (so nvim-notify is ready) → `first_run_notify()`. It
   probes the tool table (ripgrep, node, stylua, prettier, eslint_d — via
   `vim.fn.executable`, no subprocess) and, if anything is missing, fires one
   `vim.notify` pointing at `:checkhealth nvsinner`. A **marker file** at
   `stdpath("state") .. "/nvsinner-health-checked"` (i.e.
   `~/.local/state/nvsinner/nvsinner-health-checked`) is written **even when
   nothing is missing**, so it greets exactly once and never nags. To re-test
   the toast, delete the marker.
5. **Headless never consumes the marker**: `setup()` returns immediately when
   `#vim.api.nvim_list_uis() == 0`. This is why the installer's headless
   `Lazy! restore` and the test harness don't eat the greeting — the user's
   first *interactive* launch still gets it.

---

## 5. Updating

### 5a. `:NvSinnerUpdate` anatomy (`lua/core/update.lua`)

The command (registered at require time from `init.lua`) runs `M.update()`:

1. **Git-clone check** — `M.is_git_repo(dir)`: true if `<dir>/.git` is a
   directory (plain clone) **or** a readable file (worktree/submodule). If
   false — a manual copy, or any dir with no repo — it is a
   **no-op-with-warning** ("not a git clone, so there's nothing to pull… re-run
   install.sh or update by hand") and returns.
2. **`git -C <config> pull --ff-only`** via `vim.system` (async; editor stays
   responsive). `--ff-only` never invents a merge commit and fails loudly if
   the local clone diverged. Non-zero exit → error toast with git's stderr,
   stop. Output containing "Already up to date" → info toast, stop (no
   restore).
3. **`require("lazy").restore()`** — awaited via `runner:wait(...)`; checks
   every plugin out to the commit pinned in the (freshly pulled)
   `lazy-lock.json`.
4. **`:checkhealth`** + a toast: *"Updated. Restart Neovim to load the new
   config."* — the pull rewrote the Lua files on disk but the running Neovim
   keeps the old modules loaded, so the update only fully takes effect after a
   restart. Always relay this.

Test seam: `M.update({ dir = "<path>" })` overrides the pulled dir — used by
`tests/core/update_spec.lua` to exercise the not-a-clone warning without
touching the real config.

Nuance: `update.lua` accepts a `.git` **file** (worktree) but `install.sh`
line 29 only checks for a `.git` **directory** — a worktree-backed install
would be updatable in-editor yet treated as "not a git clone — leaving it
untouched" by a re-run of the installer.

### 5b. Installer re-run (idempotent)

The one-liner is the out-of-editor update: on an existing clone it unshallows
(if needed) + `git pull --ff-only` + rewrites the launcher + `Lazy! restore`
(section 2a). Nothing is skipped-because-present except a non-git config dir.

### 5c. By hand

```bash
git -C ~/.config/nvsinner pull --ff-only
NVIM_APPNAME=nvsinner nvim --headless "+Lazy! restore" +qa
```

(README's by-hand snippet omits `--ff-only`; both scripted paths use it —
prefer it by hand too so a diverged clone fails loudly instead of merging.)

### 5d. Restore-vs-sync doctrine

- The committed `lazy-lock.json` is the **golden plugin set** — the exact
  commits the distro was tested with. Install (`install.sh`) and update
  (`:NvSinnerUpdate`, by-hand) all use **`Lazy! restore`** against it:
  reproducible, never floats.
- **`:Lazy sync` is the opt-in float**: it updates plugins to latest and
  **rewrites your local `lazy-lock.json`**. On a user install that's a
  deliberate departure from the tested set; in the dev repo it's how you *bump*
  the golden set (then commit the new lock — see `nvsinner-change-control`).

---

## 6. Uninstall (`uninstall.sh`) — what it actually removes

```bash
curl -fsSL https://raw.githubusercontent.com/anderssonq/nvsinner/main/uninstall.sh | bash -s -- --yes
# or, from a clone:  ./uninstall.sh     (prompts)
```

Behavior, verified line-by-line:

- **Targets** (five): the four XDG dirs — config
  (`${XDG_CONFIG_HOME:-~/.config}/nvsinner`), data
  (`${XDG_DATA_HOME:-~/.local/share}/nvsinner`), state
  (`${XDG_STATE_HOME:-~/.local/state}/nvsinner`), cache
  (`${XDG_CACHE_HOME:-~/.cache}/nvsinner`) — plus the launcher
  `~/.local/bin/nvsinner`. Each respects its `XDG_*_HOME` override
  individually.
- **Existence filter**: keeps only paths where `-e` **or** `-L` is true, so a
  *dangling* symlink is still caught and removed. Nothing present → "Nothing
  to remove", exit 0.
- **Preview then confirm**: lists every path it will remove (symlinks are
  annotated with their target and "target left untouched"). Confirmation:
  - Interactive TTY (`-t 0`) → `Proceed? [y/N]` prompt; anything but
    y/Y/yes/YES aborts with exit 1, nothing removed.
  - **Piped (no TTY)** → refuses outright unless `--yes`/`-y` was passed
    (`curl | bash` has no terminal to read from), exit 1.
- **Symlink safety rule**: a symlinked path (the dev machine's config dir) is
  `rm -f`'d — **unlink only, never followed** into its target; real dirs are
  `rm -rf`'d. Your working repo survives an uninstall.
- **`~/.config/nvim` is untouched** — different app name; the script never
  references it.
- Flags: only `-y`/`--yes` and `-h`/`--help`; anything else errors out
  (exit 1) before touching anything.
- Not undone: the PATH line you may have added to your shell rc (the script
  just reminds you), and any globally installed tools (node packages, brew
  formulae, fonts, the AI CLI).

---

## 7. Validation after any of the above

Run from the repo (or anywhere, since paths resolve via appname). All verified
working:

```bash
# 1. Boot probe — surfaces startup errors (empty output = clean boot):
NVIM_APPNAME=nvsinner nvim --headless -c "lua vim.defer_fn(function() vim.cmd('messages'); vim.cmd('qa') end, 500)"

# 2. Full health check (includes the "nvsinner" section):
NVIM_APPNAME=nvsinner nvim --headless "+checkhealth" +qa

# 3. Distro-specific health only — Neovim version gate + external tools with
#    versions + Nerd Font info (provider: lua/nvsinner/health.lua → core.health.report):
NVIM_APPNAME=nvsinner nvim "+checkhealth nvsinner"        # interactive is easiest to read

# 4. Plugin state matches the lock:  :Lazy   (interactive; look for "restore" cleanliness)
# 5. LSP servers landed:             :Mason  (lua_ls, ts_ls, html installed)
```

For the repo's own test suite (`make test`) see `nvsinner-testing-and-qa`.

---

## 8. Known traps

| Trap | Symptom | Fix |
|---|---|---|
| `~/.local/bin` not on PATH | `nvsinner: command not found` right after a successful install | Paste the exact line install.sh printed into the rc it named (zsh `~/.zshrc`, macOS bash `~/.bash_profile`, Linux bash `~/.bashrc`, fish `fish_add_path`); or run via `NVIM_APPNAME=nvsinner nvim` |
| Legacy shallow clone (old installer used `--depth=1`) | `git pull` errors / odd history behavior | Re-run the installer — it detects `--is-shallow-repository` and `fetch --unshallow`s automatically; or by hand: `git -C ~/.config/nvsinner fetch --unshallow` |
| No restart after `:NvSinnerUpdate` | New config code "doesn't take effect" | Expected — the pull rewrites disk but old Lua modules stay loaded in the running instance. Restart Neovim (the final toast says so) |
| Running the wrong appname | Plain `nvim` shows another config; changes "missing"; separate plugin/state dirs confuse debugging | Always launch via `nvsinner` or `NVIM_APPNAME=nvsinner nvim`; remember data/state/cache are per-appname even on the dev symlink machine |
| solargraph missing | Ruby LSP never attaches (silently — `vim.lsp.enable` of an uninstalled server is harmless) | Needs a Ruby toolchain; then `:MasonInstall solargraph`. Intentionally not in `ensure_installed` |
| npm globals before node | `npm: command not found` installing prettier/eslint_d/claude-code | `brew install node` first; re-run the npm installs; confirm with `:checkhealth nvsinner` |
| Manual-copy install (no `.git`) | `:NvSinnerUpdate` warns "not a git clone"; installer re-run leaves the dir untouched | Replace the copy with a real clone (back up local edits first), or update by copying files by hand |
| `:Lazy sync` on a user install | Local `lazy-lock.json` rewritten; plugin set drifts from the tested one | That's the documented opt-in float. To return to golden: `git -C ~/.config/nvsinner checkout lazy-lock.json && nvim --headless "+Lazy! restore" +qa` (with appname) |
| First-run toast never appears when testing | You expected the missing-tools nudge | Marker already written: delete `~/.local/state/nvsinner/nvsinner-health-checked`. Headless runs never write it, so only an interactive launch consumes it |
| Diverged local clone | `:NvSinnerUpdate` / installer fail on `--ff-only` | Deliberate loud failure. Inspect with `git -C ~/.config/nvsinner status`; rebase or reset your local commits, then update again |

---

## Provenance and maintenance

**Facts verified: 2026-07-02** — by reading every line of `install.sh`,
`uninstall.sh`, `bin/nvsinner`, `lua/core/update.lua`, `lua/core/health.lua`,
`lua/nvsinner/health.lua`, `init.lua`, `lua/plugins/lsp/lsp-config.lua`, and
`lazy-lock.json` (50 lines), plus safe probes (`bash -n` on all three scripts;
live `stdpath` resolution under `NVIM_APPNAME=nvsinner`; `readlink
~/.config/nvsinner`; `nvim --version` = v0.12.3). Known doc drift at
verification time: TODO.md's done-list still says install.sh ends in
`Lazy! sync` (it's `restore`); README's by-hand update omits `--ff-only`;
CLAUDE.md's step 3 uses `Lazy! sync` where the installer pins with `restore`.

Re-verify each section with one command:

- Installer behavior: `sed -n '1,90p' install.sh` (clone/pull/unshallow, launcher, PATH advice, `Lazy! restore`)
- Uninstaller behavior: `sed -n '1,91p' uninstall.sh` (five targets, TTY/--yes, symlink `rm -f`)
- Launcher: `cat bin/nvsinner` (one `exec env NVIM_APPNAME=nvsinner nvim "$@"`)
- Update anatomy: `sed -n '1,86p' lua/core/update.lua` (`--ff-only`, `is_git_repo`, restore→checkhealth→restart toast)
- Health/first-run: `sed -n '100,180p' lua/core/health.lua` (marker path, headless bail, greet-once)
- Mason first-boot: `sed -n '9,31p' lua/plugins/lsp/lsp-config.lua` (`ensure_installed`, `automatic_enable = false`)
- XDG resolution: `NVIM_APPNAME=nvsinner nvim --headless -c "lua print(vim.fn.stdpath('config'), vim.fn.stdpath('data'), vim.fn.stdpath('state'), vim.fn.stdpath('cache'))" -c qa`
- Script syntax: `bash -n install.sh uninstall.sh bin/nvsinner`
