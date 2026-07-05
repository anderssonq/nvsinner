---
name: nvsinner-docs-and-style
description: >
  NvSinner's docs-of-record map, house writing style, doc-sync checklist, and
  commit/PR templates. Load when writing or updating ANY markdown in this repo
  (CLAUDE.md, README.md, NVSINNER.md, TODO.md, .claude/ files), when a code
  change needs its documentation synced (new plugin, keymap, core module,
  behavior change), when writing a commit message or PR description, or when
  authoring/maintaining a skill in .claude/skills/. Do NOT load it to decide
  WHETHER docs must be updated for a change (nvsinner-change-control gates
  that) or for the technical content itself (the subsystem skills own facts).
---

# NvSinner docs and house style

## When NOT to use this skill

- Deciding what gates a change must pass → `nvsinner-change-control`.
- Looking up a technical value to write about → `nvsinner-config-catalog` or
  the code itself; never write a doc claim you did not verify.
- Test documentation conventions → `nvsinner-testing-and-qa`.

## 1. The docs of record

| Doc | Role | Audience | Update when |
|---|---|---|---|
| `CLAUDE.md` (root) | **The lean per-session manifest.** Identity, layout map, conventions, one-line non-negotiables, leader-namespace map, validation/test commands, index of the nested docs. Deliberately small — it loads in EVERY session. | AI agents working on the repo | A convention/non-negotiable changes, the layout map changes, or a nested doc is added/moved |
| Nested `CLAUDE.md` (`lua/core/`, `lua/plugins/<category>/`, `tests/`, `colors/`) | **The per-directory contracts.** Full subsystem deep-dives, load-bearing warnings with rationale, spec inventory. Loaded lazily — only when working under that directory. | AI agents editing that directory | That directory's subsystem behavior, tunables, or tests change |
| `docs/installation.md` | Agent-executable install runbook (7 steps, `[manual]` tags), external requirements, `install.sh`/`uninstall.sh` anatomy. Read on demand, not auto-loaded. | AI agents installing from scratch | The install flow or scripts change |
| `README.md` | User-facing distro docs: pitch, requirements, plugin tables, **the single full keybindings reference**, install/update/health/uninstall guides. | Humans installing NvSinner | Anything user-visible changes |
| `NVSINNER.md` | Distro plan + status log, ✅-checklist style ("What's missing… → ✅ Done — …"). | Owner + agents tracking distro maturity | A distro milestone lands |
| `TODO.md` | Open items only. Completed items move to a short "Done" summary pointing at NVSINNER.md for detail. | Same | An item opens or completes |
| `.claude/agents/*.md` | Per-category Sonnet owner-agent contracts (files owned, hard constraints, validation commands). | Claude Code subagents | That category's rules change |
| `.claude/skills/*/SKILL.md` | This library. | Sonnet-class agents | Facts drift (see each skill's Provenance section) |
| `.tmp/*-PR-DESCRIPTION.md` | Archived PR descriptions, named `MM-DD-YY_NN_<topic>-PR-DESCRIPTION.md`. Rich engineering history — treat as read-only archive. | History mining | New PR written |

Rule: **all markdown is English** (a written CLAUDE.md convention). Code
comments are English too, and explain *why*/constraints, not *what*.

## 2. House style (derived from the real artifacts)

1. **Rationale-first.** State the decision, then `**because**`, then the
   rejected alternative. Real example (CLAUDE.md, Agent activity):
   *"Signal: `nvim_buf_attach` `on_lines`, NOT changedtick polling. … Polling
   `b:changedtick` was tried and **rejected**: Neovim doesn't materialise a
   terminal buffer's lines …"*
2. **"verified empirically"** marks hard-won runtime facts. Real examples:
   *"the tick can sit frozen while output streams — verified empirically"*,
   *"that global is populated for 'statusline' evaluation but **not** for
   'winbar' evaluation (verified)"*. Only use this phrase when a probe was
   actually run (see `nvsinner-empirical-verification`); it is a load-bearing
   marker, not decoration.
3. **Bold key terms** on first use; backticks for every identifier, path, key,
   and command.
4. **Tables** for keymaps, inventories, requirements; prose for rationale.
5. README uses emoji section headers (`## 📦 Requirements`, `## 🚀 Getting
   started`); CLAUDE.md uses plain headers.
6. Negative space is documented: what NOT to do lives next to what to do
   ("Do **not** reintroduce `require("lspconfig").<server>.setup()`").

## 3. Keymap documentation (single full table)

The **only full keymap table** is `README.md` → **"⌨️ Full keybindings
reference"** (multiple themed tables, includes modes). The root `CLAUDE.md`
keeps just a leader-**namespace** map (one line per namespace) — do NOT
reintroduce a full keymap table there; that duplication was deliberately cut.
Subsystem keymaps (hunks, diffview, terminals, …) are also described in prose
in the owning nested `CLAUDE.md`.

Checklist when a keymap changes: update README's table; update the owning
nested `CLAUDE.md` if it names the key; update the root namespace map only if
a namespace is added/removed; check which-key `desc` strings in the code match
the doc wording; re-grep the old key sequence across `*.md` to catch
stragglers: `grep -rn '<leader>x' CLAUDE.md README.md lua/ tests/ docs/ .claude/`

## 4. Doc-sync checklist by change type

| Change | root CLAUDE.md | nested CLAUDE.md | README.md | NVSINNER.md | TODO.md | agents/ | skills/ |
|---|---|---|---|---|---|---|---|
| New plugin | Layout table if new category | subsystem note in the category's file | plugin table row (+ keys row) | — | — | category agent if constraints change | `nvsinner-config-catalog` trigger map |
| New/changed keymap | namespace map only if a namespace changes | owning subsystem prose | Full keybindings | — | — | — | catalog if terminal/AI axis |
| New core module | Layout block | subsystem section in `lua/core/CLAUDE.md` | folder-structure block | — | — | nvim-core.md | architecture-contract + catalog |
| Behavior change | non-negotiables list if a rule changes | affected subsystem section | if user-visible | — | — | owning agent | affected skill(s) |
| New convention/rule | **Conventions** / **Non-negotiables** section | full rationale in the owning file | — | — | — | affected agents | change-control |
| Distro milestone | pointer only | — | relevant guide section | status entry (✅) | move item to Done | — | build-and-run |
| Install-flow change | — | — | Getting started | — | — | — | build-and-run |

Install-flow changes must also update `docs/installation.md` — it is the
agent-executable runbook (the root CLAUDE.md only points at it).

## 5. Commit-message and PR-description style

Commit headlines, from real history — two accepted forms:

- Feature/major: `# ✨ feat: distribution polish — PATH help, uninstall script, first-run health check` (a leading `#`, a gitmoji, `feat:`/`fix:` type, em-dash summary of the 2–4 headline items)
- Small scoped: `Dashboard: make menu items mouse-clickable` (`<Area>: <imperative sentence>`)

PR descriptions follow the `.tmp/` archive skeleton (real example:
`.tmp/06-29-26_01_ai-activity-indicator-and-tests-PR-DESCRIPTION.md`):

```markdown
# <headline, same style as the commit>

**Branch:** `<branch>`  **Author:** <name>  **Date:** MM/DD/YY

## Problem
<what was broken/missing, from the user's point of view, with the why>

## Solution
<one paragraph per shipped artifact, sizes and counts where honest>

## Technical details
### <subsystem 1>
- **<decision>.** <rationale; rejected alternative; `file.lua:line` refs>
...

## Test plan / validation
<commands run + outcomes>
```

Archive new PR descriptions as `.tmp/MM-DD-YY_NN_<topic>-PR-DESCRIPTION.md`
(NN = per-day counter). Note: `.tmp/` contents are historical evidence for
`nvsinner-failure-archaeology` — never rewrite old ones.

## 6. Templates

**Nested-CLAUDE.md subsystem section** (subsystem deep-dives live in the
directory's own CLAUDE.md — `lua/core/CLAUDE.md`,
`lua/plugins/<category>/CLAUDE.md` — never back in the root):

```markdown
### <Subsystem name> — `lua/<path>` (native | plugin)
- <What it does, one sentence>. <Load/require path and trigger>.
- **<Load-bearing decision>, NOT <rejected alternative>.** <Why; empirical
  evidence if any; "verified empirically" only if a probe ran>.
- Tunables (`X_MS`, `Y`) live at the top of the file.
```

**README plugin-table row:**

```markdown
| `<file>.lua` | <plugin-name> | <what it does / main keys> |
```

**Skill file (this library):** YAML frontmatter with `name` and a trigger-rich
`description` stating when to load AND when not; a "When NOT to use this
skill" block near the top routing to siblings; ground-truth-only facts with
repo-relative paths; unproven ideas labeled open/candidate; ends with
"Provenance and maintenance" containing "Facts verified: <date>" and one-line
re-verification commands for anything that may drift. Each fact lives in ONE
skill; siblings cross-reference by name.

## Provenance and maintenance

Facts verified: 2026-07-02 against commit `a65af7f` (doc sections, commit
headlines from `git log --oneline --all`, PR skeleton from
`.tmp/06-29-26_01_*.md`). Docs-of-record map updated 2026-07-04 for the
CLAUDE.md split (lean root + nested CLAUDE.md files + `docs/installation.md`).

Re-verification one-liners:

- Doc sections still exist: `grep -n '^## ' CLAUDE.md README.md`
- Keymap tables: `grep -n 'Keymap reference\|keybindings reference' CLAUDE.md README.md`
- Commit style drift: `git log --oneline -10`
- PR archive convention: `ls .tmp/`
