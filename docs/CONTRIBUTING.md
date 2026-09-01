# Contributing

How to set up, change, verify and ship work in this repository.

Read [ARCHITECTURE.md](ARCHITECTURE.md) first if you have not — it explains the
boot order and the layering that most of the rules below protect.

## Local setup

NvSinner runs under its own app name, so you can develop it without disturbing
an existing Neovim configuration.

```bash
git clone https://github.com/anderssonq/nvsinner.git ~/src/nvsinner
ln -s ~/src/nvsinner ~/.config/nvsinner       # nvsinner loads your working copy
cd ~/src/nvsinner
nvim --headless "+Lazy! restore" +qa          # install the pinned plugin set
```

Launch it with `nvsinner` (or `NVIM_APPNAME=nvsinner nvim`). The symlink means
edits in your clone are live on the next launch — no copy step.

> `Lazy! restore` installs the commits pinned in `lazy-lock.json`. Do not use
> `Lazy sync` here: it floats every plugin to its latest commit and rewrites the
> lockfile. See [Plugin versions](#plugin-versions).

### Enable the pre-push hook

**The hook is opt-in and nothing wires it for you** — not `install.sh`, not the
clone. Enable it once per clone:

```bash
git config core.hooksPath .githooks
chmod +x .githooks/pre-push
```

It runs `stylua --check` and `make test` before every push that touches a `.lua`
file, and skips itself entirely when none do. This matters more than it looks:
**CI does not check formatting at all**, so this hook is the only thing standing
between formatting drift and `main`.

Bypass one push with `git push --no-verify`; disable it for the repo with
`git config --unset core.hooksPath`.

## Conventions

### Language and layout

- **Lua only.** The single `vim.cmd([[ … ]])` block in `lua/core/options.lua` is
  the sole exception and must not grow.
- **English** in comments and in every `.md` file.
- **One plugin per file**, in the right `lua/plugins/<category>/` folder,
  returning a spec table or a list of them.
- **A new category folder needs `{ import = "plugins.<category>" }` in
  `init.lua`.** `lazy.nvim`'s import does not recurse — without that line the
  folder loads nothing, silently.
- **Lazy-load** with `event` / `cmd` / `keys` / `ft`. `lazy = false` needs a
  reason in a comment; today only the theme and toggleterm qualify.
- **Retire with `enabled = false`, don't delete.** Keep the spec and comment
  what replaced it, so re-enabling stays a one-line revert.

### Code

- **Never hardcode a hex color.** Every color is a role from
  `lua/core/carbon.lua`. Pair `apply_hl()` with a `ColorScheme` autocmd so it
  survives a theme switch.
- **Core may not require a plugin.** `lua/core/` depends on nothing in
  `lua/plugins/`. If a plugin needs to reach core, have it register itself —
  `ai-sessions.set_opener()` is the worked example.
- **Name augroups `nv_snake_case`** and namespaces `nvsinner_<module>`, exposing
  the namespace as `M._ns`.
- **Expose seams rather than inviting mocks.** Prefix with `M._` anything a spec
  needs to replace (`_fetch`, `_headless`, `_warn`).
- **Comment the "why", never the "what".** The house style explains
  non-obvious decisions and platform quirks; it does not narrate code.

### Keymaps

`<leader>` is Space, `<localleader>` is `\`. Check the **Full keybindings
reference** in [README.md](../README.md) before claiming a key. The namespaces:

| Prefix | Owns |
|--------|------|
| `a` | send-to-AI bridge |
| `c` | code |
| `g` | git / diffview |
| `h` | hunks (gitsigns) |
| `j` | AI sessions |
| `l` | LSP |
| `s` | search (telescope) |
| `S` | sessions |
| `t` | terminals |
| `x` | Trouble + NvSinner shortcuts (normal) · Ask-AI (visual) |

Two standing rules: Neovim's builtin LSP maps (`grn`, `gra`, `grr`, `gri`,
`grt`, `gO`, `]d`, `[d`) are documented rather than remapped; and **no
plain-letter map in terminal mode** — a `jk` escape withholds every literal `j`
you type into a CLI for one `timeoutlen`. `<Esc>` is the terminal escape.

## Verifying a change

Run these from the repo root. All four are what CI and the hook run.

| Command | What it does |
|---------|--------------|
| `make test` | The whole suite — 40 spec files under a fresh headless Neovim |
| `make test-file FILE=tests/core/options_spec.lua` | One spec file |
| `stylua --check lua/ tests/` | Formatting gate |
| `nvim --headless -c "lua vim.defer_fn(function() vim.cmd('messages'); vim.cmd('qa') end, 300)"` | Boot check — surfaces startup errors |

To syntax-check a single file without loading anything:

```bash
nvim --headless -c "lua assert(loadfile('lua/plugins/ui/lualine.lua'))" -c "qa"
```

There is no `.stylua.toml`: **stylua's defaults are the house style** (tabs for
indentation, which is what the existing code uses). Format with
`stylua lua/ tests/`.

Interactively, `:Lazy`, `:checkhealth` and `:Mason` are the other three things
worth looking at.

## Tests

The suite is [plenary](https://github.com/nvim-lua/plenary.nvim) busted.
Plenary arrives as a Telescope dependency, so there is nothing extra to install
— but plugins must be installed before the suite will run.

Each spec runs in a fresh headless Neovim via `tests/minimal_init.lua`, which
puts only this config and plenary on the runtimepath. No plugins load, and no
state leaks between specs.

### Writing one

Name it `tests/<area>/<name>_spec.lua` and require the module under test at the
top of the `describe` block.

```lua
local version = require("core.version")

describe("core.version", function()
	before_each(function()
		version._reset()
	end)

	it("reports outdated when main is ahead", function()
		local orig_fetch, orig_headless = version._fetch, version._headless
		version._headless = function()
			return false
		end
		version._fetch = function(on_done)
			on_done({ ok = true, body = 'return { version = "99.0.0" }' })
		end

		version.check()
		vim.wait(200, function()
			return version.status() ~= "checking"
		end)
		local status = version.status()

		-- Restore BEFORE asserting: a failed assert aborts the test, and an
		-- unrestored seam would leak into every spec that runs after it.
		version._fetch, version._headless = orig_fetch, orig_headless

		assert.are.equal("outdated", status)
	end)
end)
```

Three conventions that matter:

- **plenary busted has no `setup` or `finally`.** Use `before_each` and restore
  state inline.
- **Restore a swapped seam *before* asserting.** A failed assert aborts the
  test, so restoring afterwards leaks the stub into every later spec.
- **Prefer real Neovim behavior over mocking.** Open a real terminal, write a
  real file, `vim.wait` for the state to settle. The suite does this throughout,
  and it is why the specs catch regressions that mocked tests would not.

Add a row to the inventory table in [`tests/CLAUDE.md`](../tests/CLAUDE.md)
describing what your spec pins.

## What CI covers, and what it does not

`.github/workflows/ci.yml` runs on every pull request and every push to `main`:
it checks out, installs Neovim `v0.12.0` **and** `stable` (a two-entry matrix,
so the declared 0.12 floor is actually exercised, not merely claimed), restores
the pinned plugins, runs the boot check, then `make test`.

Three gaps worth knowing before you rely on a green check:

1. **CI does not check formatting.** Only the local pre-push hook does, and that
   hook is opt-in and skippable. An unformatted commit can reach `main` green.
2. **One platform: `ubuntu-latest` × Neovim `{v0.12.0, stable}`.** The floor
   and current stable both run, but nothing exercises macOS — where the config
   is primarily developed and where the Quick Look image preview only works —
   and nothing exercises nightly.
3. **CI symlinks the checkout to `~/.config/nvim`**, not `~/.config/nvsinner`,
   so the `NVIM_APPNAME` isolation the distro is built around is never itself
   tested.

## Plugin versions

`lazy-lock.json` is the tested set, and it is committed.

- **Installs and updates use `Lazy restore`** — the pinned commits.
- **`:NvSinnerSync` is the only float-to-latest path.** It rewrites the
  lockfile, so a sync means: retest, then commit the new lockfile as its own
  change.
- **`nvim-treesitter` pins `branch = "master"` on purpose.** Upstream's `main`
  is a full rewrite without the `nvim-treesitter.configs` module this config
  calls. Do not remove the pin.

## Commits and pull requests

Commits use gitmoji plus a conventional-commit subject, matching the log:

```
✨ feat(git): one diff tab, one way out, and a unified inline diff
🐛 fix(terminal): stop the spinner freezing when the column is hidden
⚡ perf(core): debounce the visible-range rescans
📝 docs: sync the keybindings reference with the code
🔧 chore: bump the pinned plugin set
🔖 release: v1.8.0 — one diff tab, one way out, and the unified view
```

Scopes match the area you touched: `core`, `ui`, `lsp`, `git`, `editor`,
`navigation`, `terminal`, `ai`, `keymaps`. Write commit messages **in English**,
and do not add `Co-Authored-By` trailers.

For a pull request:

- Branch off `main`; work merges back through a PR.
- Say what changed and why. If you changed behavior, say what a user will notice.
- **Sync the docs in the same PR.** A new plugin, keymap, command, core module
  or setting is not done until the reference that documents it is updated —
  README for user-facing behavior, the relevant `CLAUDE.md` for contracts,
  `tests/CLAUDE.md` for a new spec.
- Include the evidence: which gates you ran and that they passed.

## Releasing

The full runbook is [releasing.md](releasing.md). The mechanism in brief:

- The version lives in **one** place — `lua/nvsinner/init.lua` — and **the
  one-line shape is load-bearing**. Installed clients fetch that file raw from
  `main` and parse it with `version%s*=%s*"([^"]+)"`. Never split the assignment
  across lines.
- **Merging to `main` is the release.** Each install runs a once-per-session
  check against `main` and offers `:NvSinnerUpdate` when it is behind.
- Bump: patch for fixes, minor for features, major for breaking changes to the
  user-facing contract (keymaps, commands, install layout).
- Run every gate, sync `NVSINNER.md` and README, then commit as
  `🔖 release: vX.Y.Z — <headline>`.

Git tags are optional publicity — the update mechanism depends only on `main`.
Tagging has in practice been inconsistent (the tree currently sits at `1.8.0`
with tags only through `v1.7.0`), so if you want tags to mean something, cut
them deliberately.
