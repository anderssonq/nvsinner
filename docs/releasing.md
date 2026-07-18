# Releasing NvSinner

How a version goes out the door. The flow is coordinated by the
**`nvim-release`** agent (`.claude/agents/nvim-release.md`); this file is the
runbook it follows — and the reference for cutting a release by hand.

## The mechanism

- The version lives in **one** place: `lua/nvsinner/init.lua` →
  `version = "X.Y.Z"`. **The one-line shape is load-bearing**: installed
  clients fetch that file raw from `main` and `lua/core/version.lua` parses it
  with the Lua pattern `version%s*=%s*"([^"]+)"` — never split the assignment
  across lines.
- **Merging to `main` IS the release.** Every install runs a once-per-session
  async check (on dashboard load or `:NvSinnerHelp`) comparing its local
  version against raw `main` with `vim.version`. When remote > local, the
  dashboard swaps the footer quote for an update prompt and the help title
  shows `· update available`; the user updates with `:NvSinnerUpdate`
  (`git pull --ff-only` → `Lazy restore` → `checkhealth`).
- Git tags (`vX.Y.Z`) are optional publicity — the mechanism depends only on
  `main`.

## The flow

1. **Decide the bump** from what landed since the version line last changed
   (`git log -p --follow -- lua/nvsinner/init.lua` shows the last bump):
   patch = fixes only, minor = features, major = breaking changes to the
   user-facing contract (keymaps, commands, install layout).
2. **Edit `lua/nvsinner/init.lua`**, keeping `version = "X.Y.Z"` on one line.
3. **Run the gates** (all must pass): `make test` ·
   `stylua --check lua/ tests/` · headless boot check
   (`nvim --headless -c "lua vim.defer_fn(function() vim.cmd('messages'); vim.cmd('qa') end, 300)"`).
4. **Sync docs**: the [NVSINNER.md](../NVSINNER.md) status log; README.md if
   anything user-visible changed.
5. **Commit** in the repo's gitmoji style (e.g.
   `🔖 release: vX.Y.Z — <headline>`) and merge to `main`. Optionally
   `git tag vX.Y.Z && git push origin vX.Y.Z`.
