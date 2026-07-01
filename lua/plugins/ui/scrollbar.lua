-- Slim right-edge scrollbar (satellite.nvim).
--
-- A decoration-based (no real window) scrollbar that overlays git hunks,
-- diagnostics, search hits and the cursor position on the right margin — a
-- subtle minimap-lite that pairs with gitsigns + diagnostics. Semi-transparent
-- so it reads as part of the glass surface rather than a solid bar.
return {
	"lewis6991/satellite.nvim",
	event = { "BufReadPost", "BufNewFile" },
	config = function()
		require("satellite").setup({
			current_only = false,
			winblend = 50,
			zindex = 40,
			excluded_filetypes = {
				"neo-tree",
				"alpha",
				"dashboard",
				"TelescopePrompt",
				"toggleterm",
				"lazy",
				"mason",
			},
			handlers = {
				cursor = { enable = true },
				search = { enable = true },
				diagnostic = { enable = true },
				gitsigns = { enable = true },
				marks = { enable = false },
			},
		})
	end,
}
