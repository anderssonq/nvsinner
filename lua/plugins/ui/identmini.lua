return {
	"nvimdev/indentmini.nvim",
	event = { "BufReadPost", "BufNewFile" },
	config = function()
		require("indentmini").setup({
			only_current = true,
		})
		vim.cmd.highlight("IndentLineCurrent guifg=#676767")
	end,
}
