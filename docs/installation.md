# Installation (agent-executable)

These steps install the whole setup from scratch, written so an AI coding agent
can run them top-to-bottom. Commands target **macOS (Homebrew)**; Linux
equivalents are noted inline. Steps tagged **[manual]** need a human (interactive
auth or a GUI font selection) — surface those to the user instead of running them.

NvSinner runs under its own app name: either `export NVIM_APPNAME=nvsinner` for
the shell session (so the `nvim …` commands below load the nvsinner config) or
use the `nvsinner` launcher in place of `nvim`. The repo's `install.sh` automates
the whole flow (clone → launcher → plugin bootstrap).

## 1. System prerequisites

```bash
# macOS (Homebrew). Linux: swap brew for apt/dnf/pacman + cargo/npm equivalents.
brew install neovim ripgrep node   # Neovim >= 0.12; Node >= 20
```

The formatting/linting binaries (`stylua`, `prettier`, `eslint_d`, `shfmt`)
auto-install via Mason on first boot (`mason-tool-installer`, see the LSP
category docs), so no manual `brew install stylua` / `npm i -g prettier eslint_d`
is needed — those remain valid manual fallbacks if the Mason install fails.

The config uses 0.12's bundled packages (`nvim.undotree`), its bundled
treesitter parsers and its query API, so it will NOT work below 0.12 — verify:

```bash
nvim --version | head -1   # expect: NVIM v0.12.0 or newer
```

## 2. Install this config

```bash
# NvSinner installs under an isolated app name, so it does NOT clobber an
# existing ~/.config/nvim — clone straight into the nvsinner config dir.
git clone <THIS_REPO_URL> ~/.config/nvsinner
```

Then run it with `NVIM_APPNAME=nvsinner nvim` or the `nvsinner` launcher
(`bin/nvsinner`). `install.sh` automates this clone plus the launcher. (If you
are already running inside the cloned repo, skip the clone.)

## 3. Install plugins (lazy.nvim bootstraps itself)

```bash
nvim --headless "+Lazy! restore" +qa
```

Clones lazy.nvim and installs every plugin at the commit pinned in
`lazy-lock.json`. Use `restore`, not `sync`: `sync` floats every plugin to its
latest commit and rewrites the lockfile. Floating to latest is the deliberate,
opt-in `:NvSinnerSync` path — never an install step.

## 4. LSP servers via Mason (automatic)

`mason-lspconfig` auto-installs `lua_ls`, `vtsls`, `vue_ls`, `html`, `pyright`,
`bashls`, `jsonls`, `yamlls`, and `cssls` on first launch (`ensure_installed`
in `lsp-config.lua`) — no manual step needed. `vtsls` and `vue_ls` form the Vue
3 hybrid stack; `ts_ls` is intentionally absent so two TypeScript clients never
attach to the same buffer. The toolchain-gated servers are optional manual
installs: `solargraph` (Ruby), `gopls` (Go), `rust_analyzer` (Rust). NvSinner
only enables each one when its executable is available; restart after installing:

```bash
# Optional (each needs its language toolchain):
nvim --headless "+MasonInstall solargraph" +qa
```

## 5. Install the bundled Nerd Font  [manual]

```bash
cp fonts/*.ttf ~/Library/Fonts/                              # macOS
# Linux: cp fonts/*.ttf ~/.local/share/fonts/ && fc-cache -f
```

Then set the terminal's font to **"FiraCode Nerd Font"** (GUI step).

## 6. Set up an AI CLI  [manual]

The AI workflow is a CLI agent in the terminal column (`<leader>j`). Install one,
e.g. Claude Code, then run it once to authenticate:

```bash
npm install -g @anthropic-ai/claude-code
claude   # complete the interactive login
```

Any other CLI (opencode, ollama, …) works — just type it in the AI column. The
config itself does NOT need `ANTHROPIC_API_KEY`; the CLI handles its own auth.

## 7. Validate

```bash
# Boot and surface any startup errors:
nvim --headless -c "lua vim.defer_fn(function() vim.cmd('messages'); vim.cmd('qa') end, 500)"
# Health check (LSP, treesitter, etc.):
nvim --headless "+checkhealth" +qa
```

Then open `nvim` and run `:Lazy` / `:Mason` to confirm everything installed.

## External requirements

Neovim **0.12+** (hard requirement — bundled packages, bundled treesitter
parsers and the 0.12 query API; `install.sh` gates on it and
`:checkhealth nvsinner` re-checks it),
`git`, `ripgrep` (live grep), Node **20+** (JS/TS/Vue LSPs plus `prettier` /
`eslint_d`), a Nerd Font, and for linting/formatting: `stylua`, `prettier`,
`eslint_d`, `shfmt`
(auto-installed via Mason on first boot — see
`lua/plugins/lsp/mason-tools.lua`). For AI, install a CLI agent such as Claude
Code (`claude`).

## Install / uninstall scripts — `install.sh`, `uninstall.sh`

- `install.sh`: hard-gates git, Neovim 0.12+, and Node 20+, then
  clone-or-update → `nvsinner` launcher (`~/.local/bin`) → headless `Lazy!
  restore`. If `~/.local/bin` isn't on PATH it **prints** the exact
  `export PATH` line (naming the likely rc: `.zshrc` / `.bash_profile` on macOS /
  `.bashrc` on Linux / fish's `config.fish` with `fish_add_path`) — it never
  edits the user's shell files.
- `uninstall.sh`: removes the four `nvsinner` XDG dirs (config/data/state/cache,
  each respecting `XDG_*_HOME`) + the `~/.local/bin/nvsinner` launcher. Lists what
  it'll remove, then **confirms** — prompts on a TTY, requires `--yes`/`-y` when
  piped (`curl | bash` has no TTY). A **symlinked** config dir (dev machine) is
  `rm -f`'d (unlink only) — never followed into its target; real dirs are
  `rm -rf`'d. `~/.config/nvim` is untouched (different app name).
- `install.sh` mirrors `:NvSinnerUpdate` out-of-editor: on an existing clone it
  `git pull`s (unshallowing old `--depth=1` installs) instead of skipping; fresh
  clones are full-depth so `git pull` / `:NvSinnerUpdate` update cleanly.

## Requirements

| Tool | Used by |
|------|---------|
| Neovim **0.12+** | bundled `nvim.undotree`, bundled treesitter parsers, built-in markdown highlighting |
| `git` | lazy.nvim plugin fetch |
| `ripgrep` | Telescope live grep |
| Node **20+** | JS/TS/Vue language servers, `prettier` / `eslint_d` |
| A **Nerd Font** | icons (FiraCode Nerd Font is bundled in `fonts/`) |
| `eslint_d`, `prettier`, `stylua`, `shfmt` | none-ls formatting/linting (auto-installed via Mason on first boot) |
| an AI CLI, e.g. `claude` | AI terminal column (optional) |

> [!IMPORTANT]
> Neovim **0.12+** is a hard requirement and will not load on older versions.
> (It was 0.11+ through v1.9.1; the floor moved for 0.12's bundled packages —
> `nvim.undotree` behind `<leader>u` — its bundled treesitter parsers, and
> built-in markdown highlighting.) Verify with `nvim --version | head -1`.

The AI workflow is just a CLI agent run in the terminal column — install one
(e.g. `npm i -g @anthropic-ai/claude-code`) and run it once to log in. No
`ANTHROPIC_API_KEY` needed by the config; the CLI handles its own auth.

The one exception is the optional **inline AI completion** feature (ghost
text): it calls **OpenCode Zen** directly — the only supported provider — and
reads an `$OPENCODE_API_KEY` from the environment (never stored in the
config), and needs `curl` on `PATH`. It stays a quiet no-op until you set that
key — see
[The AI workflow → Inline AI completion](ai-workflow.md#inline-ai-completion-ghost-text).

## Getting started

### One-liner

```bash
curl -fsSL https://raw.githubusercontent.com/anderssonq/nvsinner/main/install.sh | bash
```

Clones NvSinner into `~/.config/nvsinner`, installs a `nvsinner` launcher into
`~/.local/bin`, and bootstraps every plugin. Then just run:

```bash
nvsinner
```

### The first 60 seconds

Once `nvsinner` opens, this is the whole loop the distro exists for:

| Press | What happens |
|-------|--------------|
| `<leader>e` | File tree. Single click opens a file (`:NvSinnerMenu` → "Explorer click" restores stock double-click). Click-dragging selects nothing — the tree is a picker, not text; drag its edge to resize |
| `<leader>f` | Find files · `<leader>sf` greps the project |
| `<leader>j` | Opens the AI column on the right. **First open asks which CLI to run** — `claude`, `kiro-cli`, `opencode`, or a plain shell. Only CLIs found on your `PATH` are offered |
| select some code, `<leader>x` | Ask AI about it — Fix / Refactor / Explain / your own question |
| `<leader>ab` | Drops an `@path` mention of the current file into that column |

The payload always lands **in the CLI's input line, unsubmitted** — you read it
and press Enter yourself. Nothing is ever sent on your behalf.

When the agent edits a file on disk, the buffer reloads under you and the
changed lines are briefly washed in the accent color so you can see what moved.
`<leader>jc` kills a session and forgets the CLI choice, so the next `<leader>j`
asks again.

> [!WARNING]
> Auto-reload means **disk wins**. If you have unsaved changes to a file the
> agent rewrites, your in-buffer edits are discarded. This is deliberate — the
> editor is a viewer for agent-authored work — but it is worth knowing before
> you hand a file you were mid-edit on to an agent.

### Manual

```bash
git clone https://github.com/anderssonq/nvsinner.git ~/.config/nvsinner
NVIM_APPNAME=nvsinner nvim     # lazy.nvim bootstraps + installs on first launch
```

> [!NOTE]
> `NVIM_APPNAME=nvsinner` gives the distro its own config/data/state/cache
> dirs, so it never collides with another Neovim setup — your existing
> `~/.config/nvim` is untouched.

LSP servers (`lua_ls`, `vtsls`, `vue_ls`, `html`, `pyright`, `bashls`,
`jsonls`, `yamlls`, `cssls`) and the formatting/linting tools (`stylua`,
`prettier`, `eslint_d`, `shfmt`) auto-install via Mason on first launch — no
manual `:MasonInstall` or `npm i -g` needed. On the first interactive launch a
one-time toast points at `:checkhealth nvsinner` if any external tool is
missing or incompatible. Verify anytime with `:Lazy` and `:checkhealth`.

## Updating

NvSinner tells you when it's time: once per session (on the dashboard, or when
you open `:NvSinnerHelp`) it checks the version on `main` — if a newer one
exists, the dashboard footer shows an update prompt and the help title
shows `· update available` next to the version.

NvSinner is just a git clone, so an update is a `git pull` plus a plugin
restore. Pick whichever you like:

- **In-editor (recommended):** run `:NvSinnerUpdate`. It `git pull`s the
  config, restores plugins to the pinned `lazy-lock.json`, and runs
  `:checkhealth`. **Restart Neovim afterwards** so the new Lua config loads.
- **Re-run the installer:** the one-liner is idempotent — on an existing
  clone it `git pull`s and re-installs plugins instead of skipping.
- **By hand:**

  ```bash
  git -C ~/.config/nvsinner pull
  NVIM_APPNAME=nvsinner nvim --headless "+Lazy! restore" +qa
  ```

Plugins are pinned in the committed `lazy-lock.json` and updates use
`Lazy! restore` (not `sync`), so you get the exact plugin versions the distro
was tested with.

> [!WARNING]
> To deliberately float every plugin to its latest commit instead, run
> **`:NvSinnerSync`** — it runs `:Lazy sync` (which **rewrites
> `lazy-lock.json`**) and then updates any outdated Mason packages. This
> leaves the tested, pinned plugin set: retest afterwards, and commit the new
> lockfile if you maintain your own clone. If a plugin **changes branch**
> during the sync (an upstream default-branch flip usually means a rewrite),
> a warning names it and gives the rollback recipe:
> `git restore lazy-lock.json` + `:Lazy restore`.

## Troubleshooting

Symptoms users actually hit, with the check that tells you which cause you have.
Anything not listed here is usually answered by `:checkhealth nvsinner` (below)
or `:Lazy`.

### Icons render as boxes or question marks

Your terminal is not using a Nerd Font. NvSinner bundles one in `fonts/` —
install it and select it in your terminal's profile:

```bash
# macOS
cp fonts/*.ttf ~/Library/Fonts/
# Linux
cp fonts/*.ttf ~/.local/share/fonts/ && fc-cache -f
```

A font cannot be probed from inside Neovim, so `:checkhealth nvsinner` reports
it as informational only — it will never flag this for you.

### `<leader>t`, `<leader>j`, `<leader>jx` or `<leader>f` pauses before acting

**Working as intended.** Each is a prefix of a longer map (`<leader>t2`…`t9`,
`<leader>fb`, and so on), so Neovim waits `timeoutlen` for a possible
continuation. Type the digit immediately after the prefix and there is no wait
at all.

The wait defaults to **300 ms**, not Neovim's 1000 ms. Check the live value:

```vim
:set timeoutlen?
```

It should match `:NvSinnerMenu` → "Key timeout", which is where you tune it —
your saved `key_timeout` is written through to `'timeoutlen'` at startup, so a
customised value is expected to differ from 300. If it reports `1000`, the
setting genuinely regressed.

### A buffer didn't reload after the agent edited the file

Auto-reload only touches files that are **open in a buffer**. If the agent
created or edited a file you never opened, there is nothing to reload — that is
by design, not a failure.

If the file *is* open and still stale, the reload chain has broken:

```vim
:lua print("autoread=" .. tostring(vim.o.autoread) .. " timer=" .. tostring(require("core.autoreload")._timer ~= nil))
```

Both must report true: `autoread` off, or a dead poll timer, breaks the chain.

Remember that **disk wins**: unsaved in-buffer edits to a file the agent
rewrites are discarded rather than prompting for a merge.

### The agent activity spinner in the terminal winbar is frozen or empty

Frozen usually means the redraw path regressed. `lua/core/ai-activity.lua` must
repaint with `nvim__redraw{ winbar = true, flush = true }` — `:redrawstatus`
does **not** repaint a winbar while focus is inside a terminal, so a switch to
it looks correct and silently stops updating.

Empty usually means the winbar expression lost its baked-in buffer number.
Check that it names a buffer rather than relying on `vim.g.statusline_winid`,
which is never populated during winbar evaluation:

```vim
:lua print(vim.wo.winbar)
```

### Syntax colors flatten or shift about a second after opening a file

An LSP server is repainting Treesitter's colors with semantic tokens. This
config disables them on attach, so seeing this means the guard was bypassed:

```vim
:lua =vim.tbl_map(function(c) return { c.name, c.server_capabilities.semanticTokensProvider } end, vim.lsp.get_clients())
```

Every entry must report `vim.NIL`. Treesitter is the single source of syntax
color here by design.

### Inline AI completion does nothing

It is a deliberate quiet no-op until configured. In order, check:

1. `$OPENCODE_API_KEY` is exported in the shell that launched Neovim. Without
   it you get one warning and silence thereafter.
2. `curl` is on `PATH` — the request is a plain `curl` call, not a plugin.
3. Completion is on: `:NvSinnerIA` → "AI completion", or `:NvSinnerCompleteToggle`.

Remember it is **manual**: `<C-l>` requests a suggestion, `<Tab>` accepts one,
`<C-]>` dismisses. Nothing appears as you type.

### `<leader>t` opens the AI column instead of a horizontal terminal

A terminal id collision. The `<leader>t` terminals own ids 1–9 and the AI
columns are deliberately parked at 100+ (session *N* is id `99 + N`), so they
can never collide. If they do, something claimed a low id:

```vim
:lua =vim.tbl_map(function(t) return t.id end, require("toggleterm.terminal").get_all(true))
```

### A plugin never loads

Two causes, in order of likelihood:

1. **Its category folder has no import line.** `lazy.nvim`'s `import` does not
   recurse into subfolders, so every folder under `lua/plugins/` needs its own
   `{ import = "plugins.<category>" }` line in `init.lua`. A new folder without
   one loads nothing, silently and with no error.
2. **Its lazy trigger never fires.** Confirm it is even in the spec list with
   `:Lazy`, then check its `event` / `cmd` / `keys` / `ft`.

Note that eleven specs are intentionally `enabled = false` — they are retired
plugins kept as one-line reverts, replaced by native modules. `:Lazy` will not
show them.

### Neovim crashes opening a markdown file

**Fixed.** This was never a Neovim bug. Neovim 0.12 changed treesitter's query
API so a directive's `match[id]` is a *list* of nodes; nvim-treesitter's frozen
`master` branch still read it as a single node, so every markdown code fence
threw `attempt to call method 'range' (a nil value)`. The same defect silently
broke HTML `<script type=…>` and bash heredoc injections, which nobody noticed
because only markdown got reported.

`lua/core/ts-compat.lua` re-registers the affected directives with 0.12
semantics, and the guards that used to hide the crash are gone. If it ever
comes back, run `make test-file FILE=tests/core/ts_compat_spec.lua` — that spec
pins the API contract itself.

### The test suite fails immediately

Usually plenary is missing rather than a real regression — the suite borrows it
from Telescope's dependencies, so plugins must be installed first:

```bash
nvim --headless "+Lazy! restore" +qa
make test
```

Isolate a single spec with `make test-file FILE=tests/core/options_spec.lua`.

### Nothing boots at all

```bash
nvim --headless -c "lua vim.defer_fn(function() vim.cmd('messages'); vim.cmd('qa') end, 300)"
```

That prints the startup errors. To syntax-check one file without loading
anything:

```bash
nvim --headless -c "lua assert(loadfile('lua/core/options.lua'))" -c "qa"
```

## Health check

Missing external tools (ripgrep, Node 20+, curl, stylua, prettier, eslint_d,
shfmt, a Nerd Font) make features silently no-op rather than error. To see
what's present — including the exact Node executable and whether its version
can run the JS/TS/Vue servers — at a glance:

```vim
:checkhealth nvsinner
```

It lists each external with an install hint for anything missing or
incompatible. On the **first interactive launch** NvSinner also pops a
one-time toast if something is wrong, pointing you here — it never nags again.

## Uninstalling

NvSinner keeps everything under its own `nvsinner` app name, so removing it
never touches your other `~/.config/nvim`. Run the uninstaller (prompts for
confirmation from a terminal; pass `--yes` when piping):

```bash
curl -fsSL https://raw.githubusercontent.com/anderssonq/nvsinner/main/uninstall.sh | bash -s -- --yes
# or, from a clone:  ./uninstall.sh
```

It removes the four `nvsinner` dirs — config (`~/.config/nvsinner`), data
(`~/.local/share/nvsinner`), state (`~/.local/state/nvsinner`), cache
(`~/.cache/nvsinner`) — and the `~/.local/bin/nvsinner` launcher. If your
config dir is a symlink (e.g. a dev checkout), only the link is removed; the
target is left intact. Or remove those five paths by hand.
