-- Health provider so `:checkhealth nvsinner` works: Neovim discovers health
-- checks by the module path (`lua/<name>/health.lua` → checkhealth name `<name>`)
-- and calls `.check()`. The actual checks live in core.health, shared with the
-- first-run toast, so there's a single source of truth for what's probed.
return {
	check = function()
		require("core.health").report()
	end,
}
