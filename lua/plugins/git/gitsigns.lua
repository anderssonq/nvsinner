-- Git change markers in the sign column of code buffers: shows which lines were
-- added / changed / deleted vs. the git index, plus hunk navigation and
-- stage / reset / preview actions. (Inline per-line blame is handled separately
-- by the native lua/core/git-blame.lua; gitsigns only draws the gutter here.)
--
-- It also owns the UNIFIED inline diff (<leader>gu) — the merged, one-column
-- reading Azure DevOps and GitHub call "unified". That cannot come from
-- diffview: its whole rendering model is Neovim's native window 'diff' mode,
-- which structurally needs two diffed windows, and its only single-window
-- layout (diff1_plain) is a plain window with diffs turned OFF, merge-tool
-- only. gitsigns already has the pieces, in the real editable buffer.

-- Whether the unified inline diff is on. Module-local rather than read back
-- from `gitsigns.config.show_deleted`: that field is deprecated as a *setup*
-- option (passing it makes gitsigns warn and drop it) even though the runtime
-- toggle still drives the renderer, so it is not a state we should depend on.
local inline = false

-- The three flags that together make the buffer read as a unified diff: the
-- index version of each hunk as virtual lines above the change, a full-line
-- wash on the added/changed lines, and the intra-line word differences tinted.
-- They are flipped as ONE unit — any subset reads as a bug, not a view.
local function toggle_inline()
	local gs = require("gitsigns")
	inline = not inline
	gs.toggle_deleted(inline)
	gs.toggle_linehl(inline)
	gs.toggle_word_diff(inline)
	vim.notify(inline and "Git: unified inline diff on" or "Git: unified inline diff off", vim.log.levels.INFO)
end

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

			-- The unified inline diff. In the <leader>g diff namespace rather than
			-- <leader>h*: it is a view over the whole buffer, not a hunk action.
			map("<leader>gu", toggle_inline, "Git: unified inline diff (toggle)")
		end,
	},
}
