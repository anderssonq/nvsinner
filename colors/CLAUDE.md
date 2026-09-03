# colors/ — the carbon colorscheme

`carbon.lua` here is the real colorscheme (`:colorscheme carbon`) applying the
full highlight→role mapping. The palette source of truth is
`lua/core/carbon.lua` (base16 roles, accent/folder packs, single-role slots) —
never hardcode a hex here; reference a role. Full theme docs:
`lua/core/CLAUDE.md` §Theme.

Telescope is a deliberate transparency exception: its results remain on
`blend` and its code preview on darker `shade`, with matching invisible-border
backgrounds, so search stays a solid reading surface over its dim backdrop.
