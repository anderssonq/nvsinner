-- Git change markers in the sign column of code buffers: shows which lines were
-- added / changed / deleted vs. the git index, plus hunk navigation and
-- stage / reset / preview actions. (Inline per-line blame is handled separately
-- by the native lua/core/git-blame.lua; gitsigns only draws the gutter here.)
return {
	"lewis6991/gitsigns.nvim",
	-- Lazy: attach once a real file buffer is opened.
	event = { "BufReadPre", "BufNewFile" },
	opts = {
		-- A thin left bar reads as a clean "changed line" marker (VS Code style).
		signs = {
			add = { text = "▎" },
			change = { text = "▎" },
			delete = { text = "" },
			topdelete = { text = "" },
			changedelete = { text = "▎" },
			untracked = { text = "▎" },
		},
		signcolumn = true, -- draw the markers in the sign column

		on_attach = function(bufnr)
			local gs = require("gitsigns")
			local function map(lhs, rhs, desc)
				vim.keymap.set("n", lhs, rhs, { buffer = bufnr, desc = desc })
			end

			-- Jump between changed hunks.
			map("]h", gs.next_hunk, "Next git hunk")
			map("[h", gs.prev_hunk, "Prev git hunk")

			-- Act on the hunk under the cursor.
			map("<leader>hp", gs.preview_hunk, "Preview hunk")
			map("<leader>hs", gs.stage_hunk, "Stage hunk")
			map("<leader>hr", gs.reset_hunk, "Reset hunk")
			map("<leader>hb", function()
				gs.blame_line({ full = true })
			end, "Blame line (full)")

			-- Whole-buffer variants.
			map("<leader>hS", gs.stage_buffer, "Stage buffer")
			map("<leader>hR", gs.reset_buffer, "Reset buffer")
		end,
	},
}
