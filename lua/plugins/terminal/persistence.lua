return {
	"folke/persistence.nvim",
	-- DISABLED: replaced by the native :mksession wrapper in
	-- lua/core/sessions.lua (same <leader>Sc/Sl/SQ maps + :NvSinnerSession*
	-- commands; sessions now live under stdpath("state")/sessions/). Kept as
	-- a one-line revert.
	enabled = false,
	event = "BufReadPre",
	config = function()
		require("persistence").setup({
			dir = vim.fn.expand(vim.fn.stdpath("config") .. "/session/"),
			options = { "buffers", "curdir", "tabpages", "winsize" },
		})
	end,
}
