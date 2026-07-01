-- Disabled: redundant with the rest of the UI.
--   • cursorword (symbol-under-cursor underline) is handled by vim-illuminate
--     (lua/plugins/illuminate.lua), which is LSP/treesitter-aware.
--   • cursorline is handled by lua/ui-touch.lua, which turns it on for the
--     focused code pane (persistent glass wash) — no reveal-on-idle flicker.
-- Kept here (enabled = false) so it's a one-line revert if ever wanted.
return {
	"yamatsum/nvim-cursorline",
	enabled = false,
	event = { "BufReadPost", "BufNewFile" },
	config = function()
		require("nvim-cursorline").setup({
			cursorline = {
				enable = true,
				timeout = 1000,
				number = false,
			},
			cursorword = {
				enable = true,
				min_length = 3,
				hl = { underline = true },
			},
		})
	end,
}
