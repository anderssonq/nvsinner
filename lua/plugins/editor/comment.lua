return {
	"numToStr/Comment.nvim",
	-- DISABLED: replaced by Neovim's builtin commenting (0.10+): `gcc` toggles
	-- the current line, `gc{motion}` / visual `gc` toggle a region, `gO`-style
	-- blockwise comes from `gc` in blockwise-visual. commentstring-aware via
	-- treesitter, so the builtin covers everything this spec configured (which
	-- was nothing — plain defaults). Kept as a one-line revert.
	enabled = false,
	event = "VeryLazy",
	config = function()
		require("Comment").setup()
	end,
}
