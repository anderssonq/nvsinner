# Settings & theming

[← README](../README.md)

## `:NvSinnerMenu` — the settings modal

The easiest way to configure the theme (and a few layout choices) is
**`:NvSinnerMenu`**: a Mason-style floating panel where every change applies
live and persists across restarts (stored as JSON in the distro's `settings/`
folder). Navigate with `j`/`k`, change a value with `h`/`l` (or
`Enter`/`Space`), jump with `1`–`9`, close with `q` — or use the mouse:
hovering moves the selection and a click cycles the row's value.

| Row | Values |
|-----|--------|
| Background theme | **dark:** `carbon` (default) / `onedark` / `catppuccin-mocha` / `tokyonight` / `nord` / `monokai` / `rose-pine` / `everforest` / `cyberdream` / `nightfox` · **light:** `carbon-light` / `tokyonight-day` / `everforest-light` / `dayfox` — role-palette ports of each upstream scheme, not the plugins themselves |
| Transparency | `off` / `on` |
| Accent | `blue` / `magenta` / `green` / `purple` — swaps only the identity text accent, never the gray surfaces |
| Folder color | `accent` / `teal` / `aqua` / `pink` / `green` / `purple` / `gray` — recolors Neo-tree's folder names + icons |
| Notif color | `default` / `accent` / `teal` / `aqua` / `magenta` / `pink` / `green` / `purple` / `plain` — recolors info toasts (warnings/errors keep their semantic colors) |
| Variables | same choices — recolors syntax variables, parameters and fields |
| Strings | same choices — recolors syntax strings |
| Functions | same choices — paints the whole function/method family in one accent |
| Neo-tree side | `left` / `right` |
| Explorer click | `single` (default — one click opens a file / expands a folder) / `double` (the stock behavior). Applies to **both** explorers: the Neo-tree sidebar and the diff file list (`<leader>gd` / `<leader>gh`), where one click previews that file's diff |
| AI column side | `left` / `right` |
| AI completion | `on` / `off` — inline ghost-text completion (OpenCode Zen only; needs `$OPENCODE_API_KEY` — see the AI workflow section) |
| Inlay hints | `on` / `off` (default `off`) — LSP inlay hints (parameter names, inferred types) as virtual text. Off by default because they change how every line reads; `<leader>lh` is the same switch |
| herdr reporting | `on` / `off` (default `on`) — publish the AI columns' rolled-up `working` / `blocked` / `idle` state to a running [herdr](https://herdr.dev) server, so the multiplexer hosting this editor can see the agents inside it. Does nothing unless herdr owns this pane |
| herdr detail | `state` / `tokens` (default) / `full` — how much herdr gets: the lifecycle state alone, plus a per-column token (`j1` … `j9`, each naming its CLI and status), or plus the project title and state labels |
| Key timeout | `200ms` … `1000ms` (default `300ms`) — how long a key that is a prefix of a longer one waits for the rest before firing, i.e. the pause on `<leader>t`, `<leader>j`, `<leader>jx` and `<leader>f`. Lower = snappier; raise it if you type two-key sequences slowly and `<leader>t3` keeps opening terminal 1 |
| Notifications | `shown` / `hidden` (hides info toasts; warnings/errors still show) |

### Where it is stored, and what overrides it

Every row above is one key in a single JSON file:

```
~/.config/nvsinner/settings/nvsinner-settings.json
```

That file is **gitignored** — it is your machine's state, not part of the
distro. (`settings/prompts.json`, the prompt library, *is* committed.) Deleting
it resets everything to the defaults below; there is no other config file to
edit, and nothing here requires editing Lua.

| JSON key | Menu row | Default |
|----------|----------|---------|
| `theme` | Background theme | `"carbon"` |
| `transparent` | Transparency | `false` |
| `accent` | Accent | `"blue"` |
| `folder` | Folder color | `"accent"` |
| `notif` | Notif color | `"default"` |
| `variables` | Variables | `"default"` |
| `strings` | Strings | `"default"` |
| `functions` | Functions | `"default"` |
| `tree_side` | Neo-tree side | `"left"` |
| `tree_click` | Explorer click | `"single"` |
| `ai_side` | AI column side | `"right"` |
| `ai_complete` | AI completion | `true` |
| `inlay_hints` | Inlay hints | `false` |
| `key_timeout` | Key timeout | `300` |
| `quiet` | Notifications | `false` |
| `ai_model` | *(not in this menu — picked in `:NvSinnerIA`)* | `"minimax-m2.5"` |

Environment variables override the stored value at startup, which is what makes
a one-off launch possible without touching your saved settings:

```bash
NVSINNER_THEME=carbon-light nvsinner  # boot the light palette once
NVSINNER_ACCENT=purple nvsinner       # try an accent without saving it
```

Precedence is **`vim.g.nvsinner_*` → `$NVSINNER_*` → the JSON file → the
built-in default**. The supported variables are `NVSINNER_THEME`,
`NVSINNER_ACCENT`, `NVSINNER_TRANSPARENT`, `NVSINNER_FOLDER`, `NVSINNER_NOTIF`,
`NVSINNER_VARIABLES`, `NVSINNER_STRINGS` and `NVSINNER_FUNCTIONS`.
`NVSINNER_BACKGROUND=light` still works as a legacy alias for
`NVSINNER_THEME=carbon-light`.

The background themes are named after the schemes they port. The earlier
invented names still resolve, so a saved `kyoto` boots `tokyonight` and heals
itself on the next save. The full map is `moon`→`carbon-light`,
`onedusk`→`onedark`, `mocha`→`catppuccin-mocha`, `kyoto`→`tokyonight`,
`fjord`→`nord`, `monolith`→`monokai`, `briar`→`rose-pine`, `grove`→`everforest`,
`neon`→`cyberdream`.

The inline-completion feature reads four more, none of which are ever stored by
the config: `OPENCODE_API_KEY` (required — the feature is a quiet no-op without
it), `OPENCODE_MODEL` (outranks the saved `ai_model`), `OPENCODE_FALLBACK_MODEL`
(retried once when the primary model returns 429) and `OPENCODE_ENDPOINT`.

## Theme options (carbon)

The theme flags can also be set per launch via an environment variable, or
with a `vim.g` global early in `lua/core/options.lua`. Precedence: `vim.g`
wins over the environment, which wins over the persisted `:NvSinnerMenu`
value:

| Flag | Values | Per launch | Persistent |
|------|--------|-----------|------------|
| Background theme | dark: `carbon` (default) / `onedark` / `catppuccin-mocha` / `tokyonight` / `nord` / `monokai` / `rose-pine` / `everforest` / `cyberdream` / `nightfox`; light: `carbon-light` / `tokyonight-day` / `everforest-light` / `dayfox` | `NVSINNER_THEME=nord nvsinner` | `vim.g.nvsinner_theme = "nord"` |
| Transparency | off (default) / on | `NVSINNER_TRANSPARENT=1 nvsinner` | `vim.g.nvsinner_transparent = true` |
| Accent pack | `blue` (default) / `magenta` / `green` / `purple` | `NVSINNER_ACCENT=green nvsinner` | `vim.g.nvsinner_accent = "green"` |
| Folder color | `accent` (default) / `teal` / `aqua` / `pink` / `green` / `purple` / `gray` | `NVSINNER_FOLDER=aqua nvsinner` | `vim.g.nvsinner_folder = "aqua"` |
| Notif color | `default` / `accent` / `teal` / `aqua` / `magenta` / `pink` / `green` / `purple` / `plain` | `NVSINNER_NOTIF=pink nvsinner` | `vim.g.nvsinner_notif = "pink"` |
| Variables color | same choices as Notif color | `NVSINNER_VARIABLES=aqua nvsinner` | `vim.g.nvsinner_variables = "aqua"` |
| Strings color | same choices as Notif color | `NVSINNER_STRINGS=green nvsinner` | `vim.g.nvsinner_strings = "green"` |
| Functions color | same choices as Notif color | `NVSINNER_FUNCTIONS=purple nvsinner` | `vim.g.nvsinner_functions = "purple"` |

Transparent mode drops every full-surface background (editor, floats, side
panels) so your terminal's own background/blur shows through; small solid
elements (the statusline mode chip, the AI busy chip, the terminal focus bar)
keep their color so the UI stays legible. This is the lever for a glass look
under Ghostty: with transparency **off**, carbon paints a solid `#161616`
editor background that overrides Ghostty's `background-opacity`/blur, so enable
it (`NVSINNER_TRANSPARENT=1` or the `:NvSinnerMenu` toggle) if you run Ghostty
with an opaque-defeating opacity set.

<details>
<summary>Migrating from the glass theme (kanagawa-dragon)</summary>

Nothing is required for a stock install — `:NvSinnerUpdate` (or `git pull`
followed by `nvim --headless "+Lazy! restore" +qa`) picks up the carbon theme
automatically, since the colorscheme ships inside this repo. Two optional
cleanups if you customized things:

- **Leftover plugin:** kanagawa.nvim is no longer in the plugin set; run
  `:Lazy clean` once to delete it from disk.
- **Personal highlight tweaks:** anything referencing the old glass hexes
  (`#0a0a0f`, `#111118`, `#c4746e`, …) should switch to palette roles —
  `local c = require("core.carbon").colors()` and use `c.base00`, `c.base09`,
  etc. (the full role table and design notes live in `lua/core/carbon.lua`).
  Rough mapping: bg `#0a0a0f` → `base00`, glass `#111118` → `blend`, FG
  `#c5c9d5` → `base04`, muted `#7a7f8d` → `base03`, accent `#c4746e` →
  `base09` (identity) or `base10` (attention).

</details>

## Ghostty over SSH

`xterm-ghostty` terminfo often isn't installed on remote hosts, so over SSH
`$TERM` falls back to `xterm-256color` — which loses synchronized output
(flicker-free redraws), truecolor, and undercurl advertising. Install Ghostty's
terminfo on the remote once:

```bash
infocmp -x xterm-ghostty | ssh HOST -- tic -x -
```

The system clipboard also works remotely without a GUI provider: inside an SSH
session (`$SSH_TTY` set) `lua/core/options.lua` routes the `+`/`*` registers
through **OSC 52**, which Ghostty supports, so `y`/`p` reach your local
clipboard. Local (non-SSH) sessions keep using `pbcopy`/`pbpaste`. Copy on
select goes through the same path, so a mouse selection over SSH also reaches
your local clipboard.
