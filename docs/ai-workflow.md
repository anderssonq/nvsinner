# AI workflow

[← README](../README.md)

## Features

- **AI as a terminal column, not a plugin** — run any CLI agent (`claude`,
  `kiro-cli`, `opencode`, …) in up to 9 persistent vertical columns
  (`<leader>j`, `<leader>j2`…`j9`). The first open shows a picker asking which
  CLI to launch; the CLI handles its own auth, no API key touches the config.
- **Send-to-AI bridge** — pipe editor context straight into the AI column
  without touching the clipboard: `<leader>as` sends the visual selection,
  `<leader>ab` an `@path` mention, `<leader>ad` the current line's
  diagnostics. Text lands in the CLI's input as one editable block — never
  auto-submitted. And `<leader>jx` (sessions 2–9 via `<leader>jx2`…) focuses —
  or opens — an AI session with the input pre-primed with `@path` mentions of
  **every file you have on screen**, so you just type the question.
- **Ask AI modal** — select code and hit `<leader>x` (or just **triple-click
  a word**) for the IDE-style quick-action menu: **Fix / Refactor / Explain /
  Ask custom question**. The chosen prompt (with the file path and line
  range) plus the selection lands in the AI column's input; with more than
  one session open, a picker asks which one.
- **Inline AI completion** — Copilot-style ghost-text code suggestions on a
  manual trigger (insert-mode `<C-l>`, or `:NvSinnerComplete`), served
  **exclusively by OpenCode Zen** (the "Go" plan — no other provider is
  supported) with `minimax-m2.5`, the fastest verified model, as the default.
  Accept with `<Tab>`, dismiss with `<C-]>`. The API key lives only in
  `$OPENCODE_API_KEY` (never in the config); with no key it stays a quiet
  no-op. Toggle it — and pick the model — in the **`:NvSinnerIA` hub**.
- **AI hub** — `:NvSinnerIA` (`<leader>xi`) gathers every AI entry point in one
  modal: completion on/off, a **model picker** over the verified-safe OpenCode
  Zen "Go" models (each with its probe note; default `minimax-m2.5`, marked
  *fastest — recommended*), Ask-AI, and the prompt library. It's the single AI
  row in `:NvSinnerHelp`.
- **AI edit highlights** — when the agent rewrites an open file, the changed
  lines get a soft wash of your accent color right in the file pane (distinct
  from git's gutter marks) and clear the moment you take the file over.
- **Live agent activity** — every terminal carries a winbar with a session
  label and a native busy/idle spinner (`⠹ working…` / `● idle`), plus an
  opportunistic `◆ needs input` state when the program signals a prompt via
  OSC sequences (shell integration / notifying CLIs). `<leader>ja` opens a
  picker that jumps to any session.
- **Agent cockpit** — `:NvSinnerAgents` (`<leader>xa`) lists every AI column
  with its status and a **live preview of that agent's chat**, so you can see
  at a glance which one is working, which one is blocked on a permission
  prompt, and what each was asked. `<CR>` focuses it (opening a hidden column
  first), `d` closes it for good. Status combines the output spinner with
  per-CLI screen signatures for `claude` / `kiro-cli` / `opencode` — that
  second layer is what catches a permission prompt, which emits no output and
  would otherwise read as idle.
- **Disk-wins auto-reload** — when the agent edits a file, the open buffer
  reloads automatically and a `🤖 AI · edited <file>` toast names it.
- **Prompt library** — `<leader>p` opens a modal of eleven reusable AI
  prompts (plain JSON, hand-editable) and copies your pick to the OS
  clipboard.
- **Inline blame that names the branch** — park the cursor on any line and the
  end of it tells you who wrote it and when, plus the branch the commit belongs
  to. Two cases, told apart by their glyph: ` release/v3.1.0 #22` for work
  **merged from** a branch, and ` feature/wip` for work **still in flight** on
  the branch you are on — the everyday case, which a search for the merge
  commit can never answer because there is no merge yet. A commit made straight
  on the mainline is never credited to someone else's branch, and squash-merges
  (no merge commit at all) still surface their PR number. Toggle it with
  `:NvSinnerBlameToggle`.
- **Mason-style modals** — `:NvSinnerMenu` (settings, persisted),
  `:NvSinnerIA` (the AI hub), `:NvSinnerPrompts`, and `:NvSinnerHelp` (a
  command palette that runs what you pick), all keyboard- and mouse-driven.
  While a modal is open the editor behind it is dimmed **and inert** — clicks
  and focus can't reach it; close the modal (`q`/`<Esc>`) to continue.
- **Carbon theme, configurable in one place** — dark/light variants,
  transparency, four accent packs, and per-role color slots, all from a
  single palette file (`lua/core/carbon.lua`) — live-applied and persisted.
- **Knows which project you're in** — the folder you launched in names both the
  **terminal tab** and the statusline — centered in a `‹ NvSinner ▏myproject ›`
  mark on wide terminals (click it for the `:NvSinnerHelp` palette), or
  `󰉋 myproject` on the left under 120 columns — so a row of nvsinner tabs is
  tellable apart at a glance. A subtle shimmer sweeps the statusline text every
  few seconds. Two clickable icons at the left of the statusline: the terminal
  toggles the bottom terminal (same as `<leader>t`) and the robot opens the
  agent cockpit (same as `<leader>xa`). The name is the repo root, so it stays
  put when you `cd` into a subdirectory — and in a monorepo it reports the repo,
  not the package.
- **Native-first** — focus glow, mouse-hover docs, agent activity, the
  send-to-AI bridge, health checks, and the updater are zero-dependency core
  modules, not plugins.
- **Code minimap** — an opt-in braille overview of the file on the right edge
  of the focused window (`:NvSinnerMinimap`, `<leader>xn`, or the *Minimap* row
  in `:NvSinnerMenu`). Click or sweep it to jump to that part of the file. It
  is a float, so it never disturbs your window layout, and it leaves the edge
  free for satellite's hunk/diagnostic ruler — minimap and overview ruler side
  by side, the way an IDE does it.
- **Copy on select** — like herdr, sweeping text with the mouse copies it: a
  drag, a double-clicked word or a triple-clicked line lands in the system
  clipboard the moment you let go, and the selection stays on screen. It works
  in code buffers and in the AI/terminal columns. Turn it off with the *Copy on
  select* row in `:NvSinnerMenu`. Keyboard selections (`v`…) are never copied.
- **Dashboard wallpaper** — a fallen-angel image painted *behind* the start
  screen, faded toward the theme background so the menu stays readable, and
  floating gently up and down while the dashboard is open. It is on by default; hide it with `:NvSinnerWallpaper off` (no argument toggles) or the
  *Wallpaper* row in `:NvSinnerMenu`. It needs nothing installed: the image ships
  as a small raw-pixel file that pure Lua resizes to the window, with no image
  protocol and no external process.
- **Distro table stakes** — Trouble diagnostics panel (`<leader>x*`), LSP
  rename (`<leader>rn`) alongside the Neovim 0.11 builtins, Telescope pickers
  for diagnostics/keymaps/commands/resume (`<leader>s*`), which-key group
  labels, and LSP servers for TypeScript, Lua, HTML/CSS/JSON/YAML, Python and
  Bash out of the box (Go/Rust/Ruby light up when their toolchains exist).
- **Fast** — almost everything is lazy-loaded; headless cold start **≈ 36 ms**
  (median of 11: 35.2 / 36.4 / 38.3 min-median-max, macOS, 2026-09-01). Measure
  yours the same way — a median of 3 is inside the noise, and a machine busy
  with something else reads 3-4× higher:
  `for i in $(seq 11); do nvim --headless --startuptime /tmp/s -c qa!; awk '/^[0-9]/{if($1+0>t)t=$1+0}END{print t}' /tmp/s; done | sort -n`
  Per-plugin breakdown: `:Lazy profile`.
- **Reproducible** — plugins are pinned in a committed `lazy-lock.json`;
  installs and updates `restore` to the tested set instead of floating to
  latest. A plenary test suite covers the core behavior (`make test`).

## The AI workflow

There are no in-editor AI plugins. AI is a **CLI agent run in the terminal
column**: press `<leader>j` to open it. The first time a session opens, a
picker appears in the column's own space asking which CLI to launch —
`claude`, `kiro-cli`, `opencode` (uninstalled ones are marked), or **plain
terminal — no AI**, which starts your shell and titles the column `term` like
the horizontal terminals. Navigate with `j`/`k`, launch with `Enter` (or
click a row), cancel with `q`. Sessions 2–9 (`<leader>j2`…`<leader>j9`) are
independent columns, each with its own agent. The column's side (left/right)
is configurable in `:NvSinnerMenu`.

Every terminal's top bar shows a **session label and activity spinner**
(`AI · 1 ⠹ working…` / `● idle`) driven by actual output, so a glance tells
you whether an agent — or a long build in a `<leader>t` terminal — is still
going. When the program signals a prompt (OSC 133 shell integration, or a
terminal notification), the bar flips to `◆ needs input` — this only works
for programs that emit those sequences; the output-based spinner covers
everything else. `<leader>ja` opens a picker that jumps to (or reopens) any
session. `<leader>jc` (or `:NvSinnerAIClear`) **clears** a session for good:
it kills the CLI and forgets the chosen agent, so the next `<leader>j` open
shows the CLI picker again — the counterpart to toggling, which only hides
the column and keeps the process alive.

**The cockpit for all of it** is `:NvSinnerAgents` (`<leader>xa`): a two-pane
modal listing every column — the CLI it runs, whether the column is open,
hidden or the CLI exited, and a status chip — beside a live preview of the
selected agent's chat, so a session you hid an hour ago tells you what it was
working on. `<CR>` focuses it (opening it when hidden), `d` clears it, `r`
refreshes, `<C-d>`/`<C-u>` scroll the preview. Status is read from the output
spinner *plus* each CLI's own on-screen prompts; the per-CLI patterns live in
`M.SIGNS` at the top of `lua/core/agents.lua`, so teaching it a new CLI — or
correcting one that reworded its prompt — is a one-line edit.

### Running under herdr

[herdr](https://herdr.dev) is a terminal multiplexer built for AI agents: it
recognises an agent inside a pane it owns and tracks it as working, blocked or
idle. NvSinner's columns live inside one Neovim process, so without help the
whole editor looks like a single pane "running an editor" — up to nine live
agents herdr cannot see, count, or tell you are blocked.

When herdr owns the pane, NvSinner reports them. The editor's pane shows one
agent whose state is the **rollup** of your columns — attention wins, so any
column waiting on you makes the pane `blocked` — plus a token per column
(`j1` … `j9`) naming its CLI and status. Everything here is inert outside
herdr, and `:NvSinnerMenu` → *herdr reporting* switches it off.

Because herdr tracks one agent per pane, it can see the columns but cannot type
into a single one. `nvsinner-herdr` is the way in — run it from any other herdr
pane, including from an agent working there:

```bash
nvsinner-herdr list                    # every column, its CLI and status
nvsinner-herdr focus 3                 # open or focus column 3
nvsinner-herdr send 3 "review the diff" # drop text into its CLI input
echo "$diff" | nvsinner-herdr send 3 -  # the same, from stdin
nvsinner-herdr read 3 --lines 80        # tail what column 3 is showing
```

It targets the calling pane by default (`--pane <id>` for another), speaks to
the editor over Neovim's own RPC socket, and `--json` makes any of it
machine-readable. **`send` never submits** — text lands in the CLI input for you
to review, exactly like the in-editor bridge below.

**Send context without the clipboard:** select code and hit `<leader>as` to
drop it into the AI column's input, `<leader>ab` to send an `@path` mention
of the current file, `<leader>ad` to send the current line's diagnostics.
Multi-line text arrives as one editable block (bracketed paste) and is never
auto-submitted — you review and press Enter. With no session open yet, the
bridge opens session 1 and asks you to resend. (To send `@path` mentions of
every file on screen, use `<leader>jx` — see below.)

**Ask about the files you can see:** `<leader>jx` (or `<leader>jx2` …
`<leader>jx9` for sessions 2–9) focuses the session's column — opening it
first if it was closed, CLI picker included — and drops `@path` mentions of
every file buffer **currently shown in a window** into the CLI input. Land in
insert mode, type your question after the mentions, press Enter. Only what you
can actually see counts: a file you opened earlier and then closed the window
on is still in Neovim's buffer list, but it is deliberately not mentioned —
split the files you want in scope (and floating previews never count). Every
press inserts the mentions (they add to whatever is already typed) and nothing
is ever auto-submitted; plain `<leader>j` stays the no-prime toggle.

**Ask AI about a selection:** select code and hit `<leader>x` to open the
Ask-AI modal — **Fix**, **Refactor**, **Explain**, or **Ask custom question**
(typed in a small input). The action becomes a prompt header carrying the
file's path and line range (`Fix this code in lua/core/foo.lua:10-25:`),
followed by the selected code, and lands in the AI column's input like every
other bridge send. With more than one AI session registered, a picker asks
which session to send to. `:NvSinnerAskAI` reruns it on the last selection,
and **triple-clicking a word** in a code pane opens the same modal over that
word (an active visual selection is used instead when there is one; special
panes like the tree and terminals are left alone). Three clicks, not two, so an
ordinary double-click stays Vim's own word-select.

> [!WARNING]
> Auto-reload is **disk-wins** by design: when the AI CLI edits a file on
> disk, the buffer reloads and unsaved in-editor edits to that buffer are
> discarded. It's built for the viewer-style workflow — you edit through the
> AI pane, the editor is the cockpit. Each reload fires a `🤖 AI · edited
> <file>` toast so nothing changes silently.

After each reload, the lines the agent changed get a **soft background wash
in your accent color** (the one picked in `:NvSinnerMenu`, blended into the
editor background like a tinted cursor-line so the code stays readable) right
in the file pane — you see at a glance what the AI just touched while you're
still reading its summary in the column. The marks clear as soon as you take
over the file — move the cursor in it or start editing. For a persistent,
reviewable diff use `<leader>gd` (Diffview) as usual — or `<leader>gi` to jump
straight into the diff of the file you're reading (or the one selected in the
tree), at the line you're on, pressing it again to hop between the diff and the
file list, and `gf` to drop back out onto the editable buffer. `<leader>gd` is
idempotent: press it as often as you like, you get the one diff tab back, never
a second copy. Both diff panes scroll together, including with the mouse
wheel over the pane that doesn't have focus. And `<leader>gu` reads the same changes **unified** — the old
lines inline above the new ones, right in the file you're editing.

### Inline AI completion (ghost text)

Separate from the agentic column above — that one is for building things with
a CLI agent; this completes code **inline in the buffer you're editing**,
Copilot-style. It's a native module (no plugin) served **exclusively by
[OpenCode Zen](https://opencode.ai)** — the "Go" plan is the only supported
provider; there is no OpenAI/Anthropic/local-model backend. The default model
is `minimax-m2.5`, the **fastest verified** model in the Go catalogue: a
reasoning-heavy model spends its token budget "thinking" and returns empty
completion text, so no ghost ever appears — which is exactly what
disqualified most of the catalogue (see the model picker below).

It is **manual on purpose** (no type-ahead requests, so token spend stays
predictable against the plan's usage caps): in insert mode press `<C-l>` (or run
`:NvSinnerComplete`) to request a suggestion at the cursor, `<Tab>` to accept it,
`<C-]>` to dismiss — any cursor move or edit also clears it. While the request is
in flight a small animated **`AI completion…` spinner** shows in the top-right
corner (where notifications appear) so the wait isn't a dead pause. `<Tab>` yields
to the completion popup: when nvim-cmp's menu is open it stays a normal Tab.

Two touches make accepting feel native. Trigger on a **comment-only line** (e.g.
`// create an arrow function`) and the suggestion previews as a block beneath it;
accepting **removes the comment and drops the code in its place**. Any accepted
code briefly **washes in the accent color** — the same "AI wrote this" cue as the
agent column — and clears the moment you type the first letter. And if the model
returns nothing, you get a quiet **"nothing to suggest"** notice instead of
silence (muted only if you've turned on `quiet` mode).

Everything AI lives in the **`:NvSinnerIA` hub** (`<leader>xi`): toggle completion
on/off, pick the model, or jump to Ask-AI / the prompt library. The **model
picker** offers only the **verified-safe** OpenCode Zen "Go" models — every id
survived a 5-run probe (Lua + TypeScript completion payloads, 2026-07-09) with
clean, code-only output on every run; the rest of the catalogue is filtered
out (empty/reasoning-only responses, narrated prose, `<think>` tags, HTTP
errors, or >12s latency). Your pick persists as `ai_model`
(`:NvSinnerCompleteToggle` still toggles completion directly):

| Model | Probe latency (avg of 5) | Note |
|-------|--------------------------|------|
| `minimax-m2.5` | ~4.1s (3.3–4.8s) | **fastest — recommended** (the default) |
| `minimax-m2.7` | ~4.7s (3.8–5.4s) | steadiest — never spends tokens on reasoning |
| `glm-5.2` | ~5.4s (1.5–10.6s) | works, but variable latency + reasoning bursts |

> [!NOTE]
> Completions take ~3–5s — that latency is the OpenCode Zen endpoint, not the
> editor. Model behavior **drifts server-side** (`glm-5.2` measured ~2s at
> launch and ~5.4s with reasoning bursts on the 2026-07-09 re-probe), so the
> safe list is re-verified when models misbehave. `$OPENCODE_MODEL` lets you
> force any catalogue id, verified or not.

> [!IMPORTANT]
> **OpenCode Zen is the only supported provider, and the API key never lives
> in this config.** Get a key from your [OpenCode](https://opencode.ai)
> account (the Zen dashboard), then export it in the shell that launches
> nvsinner — on macOS/zsh:
>
> ```sh
> # 1. add the key to your shell profile:
> echo 'export OPENCODE_API_KEY="sk-..."' >> ~/.zshrc
> # 2. reload the shell (or open a new terminal) and launch nvsinner:
> source ~/.zshrc
> ```
>
> Optional overrides (sane defaults are baked in):
>
> ```sh
> export OPENCODE_MODEL="minimax-m2.5"         # any Go id; verified: minimax-m2.5, minimax-m2.7, glm-5.2
> export OPENCODE_FALLBACK_MODEL="..."         # a free model to retry with on a 429
> export OPENCODE_ENDPOINT="https://opencode.ai/zen/go/v1/chat/completions"  # unsupported escape hatch
> ```
>
> The key is read from the environment at request time; it is never hardcoded,
> committed, or written to `settings/`. With no key set the feature is a quiet
> no-op after a single warning (and `:NvSinnerIA` shows the setup hint). `curl`
> must be on `PATH` (it ships by default on macOS/most Linux). On a usage-limit
> (429) it retries once with `$OPENCODE_FALLBACK_MODEL` if set, otherwise pauses
> for a few minutes instead of erroring on every trigger.

### `:NvSinnerPrompts` — the prompt library

Press `<leader>p` (or run `:NvSinnerPrompts`) to open a floating library of
reusable AI prompts — eleven ship as defaults: PR description, strict code
review, feature plan, bug fix, tests-from-pattern, commit message, refactor,
explain code, docstrings, security review, and git conflict resolution.
Picking one **copies the full prompt to the OS clipboard**, ready to paste
into the AI column's CLI (then fill in the `[PLACEHOLDERS]`). Digits `1`–`9`
jump to the first nine; reach the rest with `j`/`k` or the mouse.

> [!TIP]
> The library is plain JSON at `settings/prompts.json`: press `e` inside the
> modal to open it and add or edit prompts (`content` can be a string or an
> array of lines; the file is re-read on every open, so no restart needed).

### `:NvSinnerHelp` — the command palette

Can't remember a command? `:NvSinnerHelp` lists every NvSinner command
(`:NvSinnerMenu`, `:NvSinnerPrompts`, `:NvSinnerUpdate`, `:NvSinnerSync`,
`:checkhealth nvsinner`, …) with a one-line description. Press `Enter` — or
click a row — to **run it**; the palette closes itself. New commands are
discovered automatically, so the list is never stale.
