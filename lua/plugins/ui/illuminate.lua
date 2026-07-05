-- Highlight every occurrence of the symbol under the cursor — the "this text
-- is actionable" cue (like reference highlighting in an IDE).
return {
	"RRethy/vim-illuminate",
	-- DISABLED: replaced by the native module lua/core/illuminate.lua (builtin
	-- vim.lsp.buf.document_highlight + a visible-range word scan fallback,
	-- same delay/cutoff/denylist and the same panel-gray underlines via the
	-- LspReference* groups). Kept as a one-line revert.
	enabled = false,
	event = { "BufReadPost", "BufNewFile" },
	config = function()
		require("illuminate").configure({
			delay = 120,
			under_cursor = true,
			large_file_cutoff = 4000,
			providers = { "lsp", "treesitter", "regex" },
			filetypes_denylist = {
				"neo-tree",
				"alpha",
				"dashboard",
				"TelescopePrompt",
				"toggleterm",
				"lazy",
				"mason",
				"help",
			},
		})
	end,
}
