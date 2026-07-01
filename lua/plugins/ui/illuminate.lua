-- Highlight every occurrence of the symbol under the cursor — the "this text
-- is actionable" cue (like reference highlighting in an IDE). Uses LSP where
-- available, falling back to treesitter / regex so it works everywhere.
return {
	"RRethy/vim-illuminate",
	event = { "BufReadPost", "BufNewFile" },
	config = function()
		require("illuminate").configure({
			delay = 120, -- ms after the cursor settles before highlighting
			under_cursor = true, -- also mark the word the cursor is on
			large_file_cutoff = 4000, -- skip very large buffers (perf)
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

		-- Subtle glass underline so occurrences read as "actionable" without
		-- breaking the monochrome look. Re-applied on ColorScheme so it survives
		-- the kanagawa reload.
		local function hl()
			local set = vim.api.nvim_set_hl
			set(0, "IlluminatedWordText", { underline = true, bg = "#1b1b24" })
			set(0, "IlluminatedWordRead", { underline = true, bg = "#1b1b24" })
			set(0, "IlluminatedWordWrite", { underline = true, bg = "#211b22" })
		end
		hl()
		vim.api.nvim_create_autocmd("ColorScheme", { pattern = "*", callback = hl })
	end,
}
