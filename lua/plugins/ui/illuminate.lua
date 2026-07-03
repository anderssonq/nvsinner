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

		-- Subtle panel-gray underline so occurrences read as "actionable"
		-- without breaking the gray-dominant carbon look (writes get one step
		-- brighter). Re-applied on ColorScheme so it survives a reload.
		local function hl()
			local c = require("core.carbon").colors()
			local set = vim.api.nvim_set_hl
			set(0, "IlluminatedWordText", { underline = true, bg = c.base01 })
			set(0, "IlluminatedWordRead", { underline = true, bg = c.base01 })
			set(0, "IlluminatedWordWrite", { underline = true, bg = c.base02 })
		end
		hl()
		vim.api.nvim_create_autocmd("ColorScheme", { pattern = "*", callback = hl })
	end,
}
