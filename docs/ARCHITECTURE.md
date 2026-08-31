# Architecture

How NvSinner is put together, and why it is shaped this way.

This document covers the **system**: boot order, the layers and what may depend
on what, the abstractions that carry the design, one operation traced end to
end, where to extend, and the decisions that cost something.

It deliberately does **not** restate per-module contracts. Those live next to
the code they govern and are the authority on behavior:

| You want | Read |
|----------|------|
| What a native module guarantees, and what must never regress | [`lua/core/CLAUDE.md`](../lua/core/CLAUDE.md) |
| Why a plugin in a category is configured the way it is | `lua/plugins/<category>/CLAUDE.md` |
| What each spec pins and why | [`tests/CLAUDE.md`](../tests/CLAUDE.md) |
| How to make and ship a change | [`CONTRIBUTING.md`](CONTRIBUTING.md) |

## The shape

NvSinner is a Neovim configuration that treats the AI agent as **a process, not
a plugin**. The agent runs as a CLI in a terminal column; the editor's job is to
feed it context and show you what it changed. Everything below follows from
that one decision.

```
┌─ distro shell ──────────────────────────────────────────────┐
│  bin/nvsinner · install.sh · uninstall.sh · lua/nvsinner/    │
│  Isolates the distro under NVIM_APPNAME and versions it.     │
└───────────────────────────┬─────────────────────────────────┘
                            │
┌─ native core ─────────────▼─────────────────────────────────┐
│  lua/core/*.lua  (35 modules, ~8.7k lines)                   │
│  Zero plugin dependencies. Owns theming, settings, the AI    │
│  bridge, modals, and every feature migrated off a plugin.    │
└───────────────────────────┬─────────────────────────────────┘
                            │  registers itself into core
┌─ plugin specs ────────────▼─────────────────────────────────┐
│  lua/plugins/<category>/*.lua  (37 files, 26 live)           │
│  ui · lsp · git · editor · navigation · terminal             │
└─────────────────────────────────────────────────────────────┘
```

## Boot sequence

`init.lua` is short and its order is load-bearing.

1. **`vim.loader.enable()`** — the bytecode cache, first, so every `require`
   below hits it.
2. **Bootstrap lazy.nvim** — clone it if absent, prepend to `runtimepath`. A
   failed clone is fatal and says so rather than booting a half-configured
   editor.
3. **32 `require("core.*")` calls**, explicitly ordered (`init.lua:24-55`).
   Three positions in that list matter:
   - `options` **first** — it sets `mapleader`. Any `keys` spec lazy.nvim reads
     later resolves `<leader>` at definition time, so a leader set after
     `lazy.setup` would silently produce the wrong mappings.
   - `project` and `settings` **early** — `settings` seeds the carbon `vim.g.*`
     flags, and the theme applies during `lazy.setup`. Seeding afterwards would
     paint the wrong palette for one frame, then correct it.
   - everything else is order-independent and grouped by concern.
4. **`lazy.setup`** with six explicit imports.

### The import rule that bites

```lua
spec = {
  { import = "plugins.ui" },
  { import = "plugins.lsp" },
  { import = "plugins.git" },
  { import = "plugins.editor" },
  { import = "plugins.navigation" },
  { import = "plugins.terminal" },
},
```

**lazy.nvim's `import` does not recurse into subfolders.** A new category folder
without its own line here loads nothing — no error, no warning, no plugin. This
is the single most common way to add code to this repo and have it do nothing.

Two other `lazy.setup` choices are deliberate:

- `checker = { enabled = false }` — no background update check. Versions are
  pinned to `lazy-lock.json`, so a boot-time "updates available" probe would
  make network calls this config never acts on.
- `performance.rtp.disabled_plugins` lists only genuinely unused stock plugins.
  `netrwPlugin` is **kept** — neo-tree is lazy and does not hijack netrw, so
  netrw still owns `nvim <dir>`. `matchit`, `matchparen`, `osc52`, `man`,
  `editorconfig` and `spellfile` are kept for the same reason: they carry
  behavior the config relies on.

### The three modules not in that list

Of 35 modules in `lua/core/`, 32 are required at boot. The other three are
deliberate:

| Module | How it loads | Why |
|--------|--------------|-----|
| `carbon.lua` | Transitively | Every module's `apply_hl()` calls `require("core.carbon").colors()`. It is loaded eagerly in practice — just never named, because nothing "starts" it. |
| `backdrop.lua` | On demand | Required inside each modal's `open()`. Nothing to arm until a modal exists. |
| `mouse.lua` | On demand | A pure library — no autocmds, no state. Required only by the click handlers in neo-tree and diffview. |

## Layers, and what may depend on what

The dependency rule is one-directional: **plugin specs may require core; core
may not require plugins.**

That holds literally. `lua/core/` contains no `require("toggleterm")`,
`require("telescope")`, or `require("neo-tree")`. The two apparent exceptions
are `update.lua` and `sync.lua`, which require **lazy.nvim itself** — the plugin
manager, not a plugin — because managing the plugin set is their entire purpose.

### How the terminal column reaches core without core reaching back

The AI workflow needs core to open, clear, and track terminal panels that only
toggleterm knows how to build. Rather than have core require toggleterm, the
spec **pushes itself in** at config time
(`lua/plugins/terminal/toggleterm.lua`):

```lua
require("core.ai-sessions").register(n, ai_panels[n])   -- :216
require("core.ai-sessions").set_opener(function(n) …)    -- :493
require("core.ai-sessions").set_clearer({ … })           -- :503
```

`ai-sessions` holds a registry of `{ n, term, last_used }` plus two injected
callbacks. It can open a session it cannot construct and kill one it cannot
create, while remaining a plain Lua module with no plugin dependency — which is
also what makes it testable headlessly.

## Key abstractions

### `carbon.lua` — one source of color

Every color in the distro resolves through this module. No module hardcodes a
hex.

Seven full palettes (`dark`, `light`, `onedusk`, `mocha`, `kyoto`, `fjord`,
`monolith`) each fill an identical role-key set: a `base00`–`base05` grayscale
ramp, `base06` white, `base07`–`base15` accents, plus `blend`, `lift`, `shade`,
`backdrop` and the diff roles.

On top sit three narrower override layers, each touching only what it must:

- **Accent packs** (`blue`, `magenta`, `green`, `purple`) override *only*
  `base09` and its pale companion `base15`. Gray surfaces are untouched, so an
  accent recolors text, never the background.
- **Folder packs** recolor neo-tree's folder name and icon roles.
- **Color slots** (`notif`, `variables`, `strings`, `functions`) repoint one
  syntax family at one role.

`M.colors()` composes the active palette with the accent overlay and is what
every `apply_hl()` consumes. Resolution order for each flag is `vim.g.*` →
`$NVSINNER_*` → the persisted setting → the default.

Because a colorscheme change re-fires `ColorScheme`, nearly every module pairs
its highlight setup with a re-apply:

```lua
apply_hl()
vim.api.nvim_create_autocmd("ColorScheme", { pattern = "*", callback = apply_hl })
```

That idiom is why switching themes at runtime repaints native features that no
plugin knows about.

### `settings.lua` — persisted preferences without a config file

Fifteen keys in one JSON file
(`settings/nvsinner-settings.json`, gitignored). `M.set(key, value)` validates
against `M.defaults`, persists, applies the change live, and then broadcasts:

```lua
vim.api.nvim_exec_autocmds("User", { pattern = "NvSinnerSetting", data = { key, value } })
```

The broadcast is what lets a lazy-loaded plugin react to a settings change
without core requiring it, and without the setting being read eagerly at boot.

`settings` is one of only three modules with a self-invoked `setup()` — it must
run at require time, because the theme depends on the flags it seeds.

### `ai-sessions.lua` — the send-to-AI bridge

The registry plus the rules for choosing a target and shaping a payload.

`M.target()` resolves in priority order: the terminal you are currently inside →
the most recently used open session → the most recent session with a live job.

`M._payload(text)` is small and load-bearing. Multi-line text is wrapped in
bracketed paste (`\27[200~` … `\27[201~`) so a CLI receives it as one paste
rather than line-by-line input. It **never appends `\r`**.

That absence is a contract, not an oversight: payloads land in the CLI's input
line for you to read and submit. Nothing is ever sent on your behalf.

Context builders — `selection_text()`, `buffer_mention()`, `buffer_mentions()`,
`diagnostics_text()` — turn editor state into text. `buffer_mentions()` walks
**windows**, not the buffer list, so it mentions what you can actually see
rather than everything Neovim happens to have loaded.

### `backdrop.lua` — the shared modal substrate

All seven modals (`menu`, `prompts`, `help`, `symbols`, `ia`, `agents`,
`ai-ask`) call `require("core.backdrop").attach(win)`.

It opens a full-screen dim float beneath the modal at `zindex - 10` and does
three things that are easy to get wrong alone:

- **`mouse = true`** even though it is `focusable = false` — otherwise clicks
  fall through the dim onto the buffer behind it.
- A `WinEnter` trap bounces focus back to the modal if it escapes to a normal
  window, while **exempting floats** so `vim.ui.select`/`vim.ui.input` pickers
  layered on top still work.
- A one-shot `WinClosed` teardown, so closing the modal always removes the dim.

### `ai-activity.lua` — busy / idle / awaiting

The winbar spinner is driven by `nvim_buf_attach` on `TermOpen`. Two constraints
shape the implementation and both look like mistakes until you know why:

**`on_lines` runs in a fast event context.** Most of the API is forbidden there,
so the callback only writes plain table fields and touches a timer. All real
work happens on the poll.

**The repaint uses `nvim__redraw`, not `:redrawstatus`.** `:redrawstatus` does
not repaint a winbar while focus is inside a terminal — which is exactly the
situation the spinner exists for. Switching to it looks correct and silently
stops updating.

The poll timer is **busy-gated**: started on first output, stopped once nothing
is busy, so an idle editor does no periodic work. A third state, "awaiting",
comes from OSC sequences (`133;B` prompt-start, `133;C` command-start, OSC 9
notifications) and marks an agent waiting on *you*.

## One operation, end to end

Select code in visual mode and press `<leader>x`.

| # | Where | What happens |
|---|-------|--------------|
| 1 | `ai-ask.lua` keymap | `capture_visual()` grabs the selection via `ai-sessions.selection_text()`, plus the line range and buffer path. |
| 2 | same, immediately | Feeds `<Esc>` **synchronously** to leave visual mode. It must happen before the modal opens (buffer-local maps assume normal mode) and must not be queued, or a stray `<Esc>` lands in the AI terminal after focus moves. |
| 3 | `M.open(ctx)` | Opens the float, attaches the backdrop, renders four actions: Fix · Refactor · Explain · Ask. |
| 4 | `M.run()` | **Closes the modal first**, then builds the payload. For "Ask", opens `vim.ui.input` and builds in the callback. |
| 5 | `M.build()` | Formats a header — `Fix this code in <path>:<l1>-<l2>:` — followed by the selection. |
| 6 | `dispatch()` | One session: send directly. More than one: `vim.ui.select` labelled with each session's live activity status. |
| 7 | `ai-sessions.send_to()` | Resolves the target, or calls the injected `opener(1)` and warns you to resend if nothing is live. |
| 8 | `M._payload()` | Wraps multi-line text in bracketed paste. **No trailing `\r`.** |
| 9 | `vim.fn.chansend(job_id, …)` | Text enters the PTY. |
| 10 | back in `send_to()` | Focuses the terminal window and `startinsert!`. |

You end up inside the CLI with the prompt sitting in its input, unsent. Step 8
is why: the distro composes prompts, you decide when they run.

## Extension points

| Adding | Where | The gotcha |
|--------|-------|------------|
| A plugin | `lua/plugins/<category>/<name>.lua`, returning a spec | Lazy-load it (`event`/`cmd`/`keys`/`ft`). Files in an existing category are picked up automatically. |
| A plugin **category** | New folder under `lua/plugins/` | **Add `{ import = "plugins.<category>" }` to `init.lua`** or nothing in it ever loads. |
| A core module | `lua/core/<name>.lua` + a `require` line in `init.lua` | Being required *is* your setup — see the conventions below. |
| A theme | A palette table in `carbon.lua` + an entry in `M.themes` and `M.theme_names` | Fill the **entire** role-key set; a missing role is a nil highlight, not a fallback. |
| An accent / folder / slot pack | The matching table in `carbon.lua` | Override only the roles that pack owns. |
| A prompt | `settings/prompts.json` (committed) | Shipped library, user-editable, surfaced by `:NvSinnerPrompts`. |
| An LSP server | `ensure_installed` and `vim.lsp.enable({…})` in `lsp-config.lua` | A server needing an external toolchain (`gopls`, `rust_analyzer`, `solargraph`) is enabled but **not** auto-installed — harmless when absent. |
| A spec | `tests/<area>/<name>_spec.lua` | See [CONTRIBUTING](CONTRIBUTING.md#tests). |

### Conventions a new core module follows

- **Activation is `require`.** Only `settings`, `health` and `image-open` define
  a self-invoked `M.setup()`. Everywhere else, top-level code — highlights,
  autocmds, keymaps — runs at require time.
- **Augroups are `nv_snake_case`**, suffixed per buffer or window when the group
  is scoped (`nv_ai_edits_clear_<buf>`, `nv_backdrop_<win>`).
- **Namespaces are `nvsinner_<module>`**, exposed as `M._ns` so specs can read
  the extmarks back.
- **Colors come from roles**, via `apply_hl()` re-armed on `ColorScheme`.
- **Expose seams, not mocks.** Functions a spec must replace are `M._`-prefixed
  (`_fetch`, `_headless`, `_warn`), so tests swap behavior without patching
  globals.

## Design decisions, and what they cost

### The agent is a CLI, not a plugin

There is no in-editor AI plugin, and the config never reads
`ANTHROPIC_API_KEY`. The agent is whatever you run in the column — `claude`,
`kiro-cli`, `opencode`, or a plain shell.

*Why:* CLI agents move faster than editor plugins can track, they already handle
their own auth and session state, and the editor never becomes a bottleneck on
someone else's release cycle.

*Cost:* no editor-native inline chat, no structured diff review. Integration is
text in, files on disk out.

*The one exception:* `ai-complete.lua` provides opt-in inline ghost-text
completion. It supports **OpenCode Zen exclusively**, reads `$OPENCODE_API_KEY`
from the environment at request time, never stores a key, and is a quiet no-op
without one.

### Disk wins on auto-reload

When a file changes underneath an open buffer, the buffer reloads. Unsaved
in-buffer edits are discarded.

*Why:* the workflow is agent-writes / you-review. Prompting on every external
write would interrupt constantly during a normal agent run.

*Cost:* **this can lose work.** Edit a file, leave it unsaved, ask an agent to
rewrite it, and your edits are gone. Deliberate, but a genuine sharp edge —
which is why changed lines are washed in the accent color afterwards, so you can
at least see what moved.

### `Lazy restore`, never `Lazy sync`

`lazy-lock.json` is the tested plugin set. Installs and updates **restore** to
it. `:NvSinnerSync` is the only path that floats to latest, and it rewrites the
lockfile — which then wants retesting and committing.

*Why:* a config that silently drifts to upstream HEAD breaks at the worst
moment. The incident behind the `nvim-treesitter` `branch = "master"` pin is the
worked example: upstream's `main` is a full rewrite with no
`nvim-treesitter.configs` module, and an unpinned sync jumped onto it.

*Cost:* upstream fixes need a deliberate sync.

### Retired plugins stay as tombstones

Eleven specs carry `enabled = false` rather than being deleted — each replaced
by a native module, each with a comment naming its replacement.

*Why:* re-enabling is a one-line revert, and the spec documents what the native
module owes you.

*Cost:* 37 spec files of which only 26 do anything, and a `lua/plugins/` tree
that reads as larger than it is.

### Treesitter is the only source of syntax color

The global LSP config nils `semanticTokensProvider` on attach.

*Why:* two systems coloring the same buffer produce the "colors change a second
after open" flicker, and semantic tokens win by arriving last.

*Cost:* no semantic-token-only distinctions.

### Isolation via `NVIM_APPNAME`

The distro installs to `~/.config/nvsinner` with its own data, state and cache
directories, launched by a one-line `bin/nvsinner` wrapper.

*Why:* it coexists with an existing `~/.config/nvim`. Trying it costs nothing
and uninstalling leaves your other config untouched.

*Cost:* `nvim` and `nvsinner` are different editors on the same machine, which
surprises people once. On the development machine `~/.config/nvsinner` is a
symlink to the repo, so both names load the same files.

## Where to go deeper

| Subsystem | Contract |
|-----------|----------|
| Native core modules | [`lua/core/CLAUDE.md`](../lua/core/CLAUDE.md) |
| UI chrome and the theme | [`lua/plugins/ui/CLAUDE.md`](../lua/plugins/ui/CLAUDE.md) |
| LSP, completion, formatting | [`lua/plugins/lsp/CLAUDE.md`](../lua/plugins/lsp/CLAUDE.md) |
| Terminals and the AI columns | [`lua/plugins/terminal/CLAUDE.md`](../lua/plugins/terminal/CLAUDE.md) |
| Git: gitsigns / blame / diffview | [`lua/plugins/git/CLAUDE.md`](../lua/plugins/git/CLAUDE.md) |
| Editor plugins and the treesitter pin | [`lua/plugins/editor/CLAUDE.md`](../lua/plugins/editor/CLAUDE.md) |
| Navigation: telescope, neo-tree, leap | [`lua/plugins/navigation/CLAUDE.md`](../lua/plugins/navigation/CLAUDE.md) |
| The test suite | [`tests/CLAUDE.md`](../tests/CLAUDE.md) |
| Installation runbook | [`installation.md`](installation.md) |
| Release flow | [`releasing.md`](releasing.md) |
| The plugin → native migration plan | [`native-roadmap.md`](native-roadmap.md) |
