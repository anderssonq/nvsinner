# colors/ — the carbon colorscheme

`carbon.lua` here is the real colorscheme (`:colorscheme carbon`) applying the
full highlight→role mapping. The palette source of truth is
`lua/core/carbon.lua` (base16 roles, accent/folder packs, single-role slots) —
never hardcode a hex here; reference a role. Full theme docs:
`lua/core/CLAUDE.md` §Theme.
