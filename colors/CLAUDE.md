# colors/ — the carbon colorscheme

`carbon.lua` here is the real colorscheme (`:colorscheme carbon`) applying the
full highlight→role mapping. The palette source of truth is
`lua/core/carbon.lua` (base16 roles, accent/folder packs, single-role slots) —
never hardcode a hex here; reference a role. Full theme docs:
`lua/core/CLAUDE.md` §Theme.

**Only claim a group that is measurably wrong or missing.** Neovim 0.12
default-links most modern groups onto ones this file already sets — TabLine,
Substitute, SpecialKey, FloatFooter, WildMenu, `Pmenu{Kind,Extra}`,
SnippetTabstop, `Lsp*`, every `Diagnostic*` detail group, `@lsp.type.*` — and
re-declaring those adds maintenance for no pixel change. The groups that ARE
claimed here were each verified undefined or carrying an off-palette hex after
a carbon apply: `Conceal`, `MsgArea`, `TabLineSel`, `PmenuMatch`,
`ComplMatchIns`, `DiagnosticDeprecated`, `Added`/`Changed`/`Removed` (Neovim
ships its own pastels, and `@diff.plus/minus/delta` link to them),
`@markup.heading.1`–`.6` (the same ramp `core/markdown.lua` uses, so a markdown
buffer looks identical with the reading view on or off), the Neo-tree gaps, and
`LspInlayHint`. Two plugin UIs hardcode literal hexes instead of linking and so
must be remapped: **mason** (`#DCA561` / `#56B6C2`) and **leap** (`#ffaf3f` /
`#ccff88`). lazy.nvim, trouble, satellite and diffview all self-theme off
standard groups — leave them alone. `tests/core/carbon_spec.lua` pins the
claimed set; re-run the audit before adding more.

Telescope is a deliberate transparency exception: its results remain on
`blend` and its code preview on darker `shade`, with matching invisible-border
backgrounds, so search stays a solid reading surface over its dim backdrop.
