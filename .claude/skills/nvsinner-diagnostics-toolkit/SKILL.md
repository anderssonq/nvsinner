---
name: nvsinner-diagnostics-toolkit
description: >
  NvSinner's measurement instruments — "measure, don't eyeball". Load when you
  need to VERIFY editor state instead of guessing: boot errors, startup time,
  keymap presence, palette drift, health of external tools, or runtime state of
  terminals/windows/highlights/autocmds. Ships tested scripts (boot-check,
  startup-time, keymap-audit, palette-audit) in scripts/. Do NOT load it for
  experiment DESIGN on unsettled Neovim behavior (nvsinner-empirical-
  verification), for the test suite (nvsinner-testing-and-qa), or for
  symptom-driven debugging flow (nvsinner-debugging-playbook — it will send you
  back here for specific measurements).
---

# NvSinner diagnostics toolkit

Instruments + interpretation guides. All scripts live in this skill's
`scripts/` dir, are read-only, and run from the **repo root**:

```bash
.claude/skills/nvsinner-diagnostics-toolkit/scripts/<name>.sh
```

All four were run successfully on 2026-07-02 (outputs below are real).

## When NOT to use this skill

- The question is "does Neovim behave like X?" (unsettled) → `nvsinner-empirical-verification`.
- You want the regression suite → `nvsinner-testing-and-qa` (`make test`).
- You have a symptom and no idea where to look → `nvsinner-debugging-playbook` first.
- Install-time problems (PATH, Mason, launcher) → `nvsinner-build-and-run`.

## 1. Boot diagnostics — `scripts/boot-check.sh`

Boots the real config headless, prints `:messages`, exits 1 on any output.

```
$ scripts/boot-check.sh
boot clean, no messages          # ← healthy. Anything else = startup error.
```

Interpretation: `E5113`/stack traces name the failing file — syntax-check it
directly (`nvim --headless -c "lua assert(loadfile('lua/plugins/<cat>/<f>.lua'))" -c "qa"`);
`module 'plugins.X' not found` → missing `{ import = ... }` line in `init.lua`.
Bisect a bad plugin with `enabled = false` (see `nvsinner-config-catalog` §8e).

## 2. Startup performance — `scripts/startup-time.sh`

Runs `nvim --startuptime`, prints the total and the 10 slowest entries.

Real output (2026-07-02): `total startup: 112.697 ms` on one run, ~62 ms on
another — **headless startuptime varies ±2× run-to-run** (cache warmth, machine
load). Take 3 runs and use the median before believing a regression. The
slowest entries were `sourcing init.lua` and `require('null-ls')` —
`lua/plugins/lsp/none-ls.lua` has no lazy trigger, so it loads at startup
(catalogued in `nvsinner-config-catalog` §4).

Interpretation: columns are `clock  self+sourced  self: event`. A plugin
appearing here that should be lazy = its trigger is wrong or missing.
Interactive deep-dive: `:Lazy profile`. The README's "cold start ≈ 60 ms"
claim must be re-measured (median of 3) before repeating it publicly
(`nvsinner-frontier` owns claim discipline).

## 3. Keymap audit — `scripts/keymap-audit.sh`

Probes a headless instance of the real config for the load-bearing maps
(`<leader>j`, `<leader>t`, `<leader>fb`, resize keys in n **and** t modes,
`<C-Y>`, terminal `<Esc>`). Real output ends with `ALL KEYMAPS PRESENT`
(exit 0); any `MISS` line exits 1. Note: `<leader>j`/`<leader>t` come from
`lua/plugins/terminal/toggleterm.lua`, which loads at startup — if these two
are missing but core maps are fine, toggleterm didn't load.

## 4. Palette drift audit — `scripts/palette-audit.sh`

Greps every 6-digit hex in `lua/` and fails on any not in the whitelist
(canonical glass palette + the monochrome secondary shades, mirrored from
`nvsinner-config-catalog` §3 — update both together). Real output:
`palette clean: every hex in lua/ is whitelisted`. A violation means someone
introduced an off-palette color — the one-accent doctrine
(`nvsinner-change-control`) says fix or whitelist-with-justification, never
ignore.

## 5. Health checks

- `:checkhealth nvsinner` (interactive) — provider `lua/nvsinner/health.lua`
  delegates to `lua/core/health.lua:report()`. Sections: Neovim version
  (error if < 0.11), each external tool as ok-with-version or warn-with-install-
  hint (ripgrep, node, stylua, prettier, eslint_d), Nerd Font as info-only.
- Headless capture of everything:
  `nvim --headless "+checkhealth" "+w! /tmp/health.txt" +qa` then read the file.
- Quick binary presence without Neovim: `for t in rg node stylua prettier eslint_d; do command -v $t >/dev/null && echo "OK $t" || echo "MISS $t"; done`

## 6. Runtime state probes (one-liners)

Run inside Neovim (`:lua ...`) or via `nvim --headless -c`:

| What | Probe |
|---|---|
| terminal buffer state | `:lua local b=vim.api.nvim_get_current_buf(); print(vim.bo[b].buftype, vim.b[b].nv_term_label, vim.bo[b].channel)` |
| window's winhighlight/winbar | `:lua local w=vim.api.nvim_get_current_win(); print(vim.wo[w].winhighlight); print(vim.wo[w].winbar)` |
| highlight group values | `:lua print(vim.inspect(vim.api.nvim_get_hl(0, { name = "NvAiBusy" })))` |
| autocmd group exists | `:lua print(#vim.api.nvim_get_autocmds({ group = "nv_ai_activity" }))` (also: `nv_touch`, `auto_reload_on_disk_change`, `term_focus_startinsert`) |
| ai-activity attached? | `:lua print(vim.inspect(require("core.ai-activity")))` then check `_timer` non-nil |
| toggleterm ids in use | `:lua for _,t in pairs(require("toggleterm.terminal").get_all(true)) do print(t.id, t.direction) end` |

Headless caveat when probing with `print()`: multiple `print` calls run their
lines together; use `io.stdout:write(s .. "\n")` (this bit the keymap-audit
script — fixed there).

## 7. Limits of headless

Headless Neovim has no compositor: it cannot verify winbar/statusline
**repaint**, spinner animation, focus glow, or float visuals. Those need an
interactive session; the honest procedure is in
`nvsinner-empirical-verification` (recipe 5). A headless pass on state
(highlight defined, winbar string set) plus an interactive spot-check on
rendering is the full evidence.

## Provenance and maintenance

Facts verified: 2026-07-02 — all four scripts executed from the repo root at
commit `a65af7f` with the outputs quoted above; runtime probes syntax-checked
against the module/augroup names in `lua/core/*.lua`.

Re-verification one-liners:

- Scripts still pass: run each (§1–§4) from the repo root
- Augroup names unchanged: `grep -rn 'create_augroup' lua/core/`
- Health tool list unchanged: `grep -n 'cmd = ' lua/core/health.lua`
- Whitelist still matches catalog §3: `grep -A3 'whitelist=(' .claude/skills/nvsinner-diagnostics-toolkit/scripts/palette-audit.sh`
