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
brew install neovim ripgrep node   # neovim MUST be >= 0.11
```

The formatting/linting binaries (`stylua`, `prettier`, `eslint_d`, `shfmt`)
auto-install via Mason on first boot (`mason-tool-installer`, see the LSP
category docs), so no manual `brew install stylua` / `npm i -g prettier eslint_d`
is needed — those remain valid manual fallbacks if the Mason install fails.

The config uses `vim.uv` and the native `vim.lsp` API, so it will NOT work below
0.11 — verify:

```bash
nvim --version | head -1   # expect: NVIM v0.11.x or newer
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
nvim --headless "+Lazy! sync" +qa
```

Clones lazy.nvim and every plugin pinned in `lazy-lock.json`.

## 4. LSP servers via Mason (automatic)

`mason-lspconfig` auto-installs `lua_ls`, `ts_ls`, `html`, `pyright`, `bashls`,
`jsonls`, `yamlls`, and `cssls` on first launch (`ensure_installed` in
`lsp-config.lua`) — no manual step needed. The toolchain-gated servers are
optional manual installs: `solargraph` (Ruby), `gopls` (Go), `rust_analyzer`
(Rust) — they are already enabled and light up once installed:

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

Neovim **0.11+** (hard requirement — uses `vim.uv` and the native `vim.lsp`
API), `git`, `ripgrep` (live grep), `node` (for `prettier` / `eslint_d`), a Nerd
Font, and for linting/formatting: `stylua`, `prettier`, `eslint_d`, `shfmt`
(auto-installed via Mason on first boot — see
`lua/plugins/lsp/mason-tools.lua`). For AI, install a CLI agent such as Claude
Code (`claude`).

## Install / uninstall scripts — `install.sh`, `uninstall.sh`

- `install.sh`: clone-or-update → `nvsinner` launcher (`~/.local/bin`) → headless
  `Lazy! restore`. If `~/.local/bin` isn't on PATH it **prints** the exact
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
