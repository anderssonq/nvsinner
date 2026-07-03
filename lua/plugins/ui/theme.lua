-- Carbon theme — a native, self-contained port of the oxocarbon / IBM Carbon look.
--
-- The colorscheme itself is self-contained in this repo (no external theme
-- plugin): colors/carbon.lua applies the full highlight→role mapping and
-- lua/core/carbon.lua holds the one base16 palette every module shares.
-- This spec is a local "virtual" plugin whose only job is to apply the
-- colorscheme at startup with theme priority.
--
-- NOTE: this replaces the previous kanagawa-dragon "glassmorphism" setup.
-- Design discipline (see lua/core/carbon.lua): industrial grayscale core, blue-forward
-- accents (base09 #78a9ff is the identity accent), color only where it means
-- something. Floats are borderless and recessed on `blend` (#131313).

return {
	{
		name = "carbon-theme",
		dir = vim.fn.stdpath("config"),
		lazy = false,
		priority = 1000,
		config = function()
			-- "dark" is the reference variant; the flag (vim.g.nvsinner_background
			-- or $NVSINNER_BACKGROUND) boots the light variant through the same
			-- role table. Transparency is read inside colors/carbon.lua.
			vim.o.background = require("core.carbon").background()
			vim.cmd.colorscheme("carbon")
		end,
	},
}
