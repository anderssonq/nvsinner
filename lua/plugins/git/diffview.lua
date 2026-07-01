-- Side-by-side diff viewer for git changes: a `git diff` you can read inside the
-- editor. `<leader>gd` opens the working-tree-vs-index view (a file panel on the
-- left, the two versions of the selected file side by side), `<leader>gh` shows
-- the git history of the current file, and `<leader>gq` closes the tab. Kept
-- intentionally minimal — just "see the differences"; defaults handle the rest.
return {
	"sindrets/diffview.nvim",
	-- Lazy: only pulled in when one of its commands or keymaps is used.
	cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewFileHistory", "DiffviewToggleFiles" },
	keys = {
		{ "<leader>gd", "<cmd>DiffviewOpen<cr>", desc = "Diff: working tree vs index" },
		{ "<leader>gh", "<cmd>DiffviewFileHistory %<cr>", desc = "Diff: history of current file" },
		{ "<leader>gH", "<cmd>DiffviewFileHistory<cr>", desc = "Diff: history of whole repo" },
		{ "<leader>gq", "<cmd>DiffviewClose<cr>", desc = "Diff: close view" },
	},
	opts = {
		-- Brighter, word-level diff highlights so changes stand out clearly.
		enhanced_diff_hl = true,
	},
}
