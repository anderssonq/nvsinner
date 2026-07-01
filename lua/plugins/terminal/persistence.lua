return {
	"folke/persistence.nvim",
	event = "BufReadPre", -- this will only start session saving when an actual file was opened
	config = function()
		require("persistence").setup({
			dir = vim.fn.expand(vim.fn.stdpath("config") .. "/session/"),
			options = { "buffers", "curdir", "tabpages", "winsize" },
		})

		-- Make sure which-key is loaded
		local wk = require("which-key")

		-- Define the mappings (with notifications) per the new spec
		wk.add({
			{ "<leader>S", group = "Session" },

			{
				"<leader>SQ",
				function()
					vim.cmd("lua require('persistence').stop()")
					vim.notify("■ Session paused", vim.log.levels.INFO, { timeout = 250 })
				end,
				desc = "Quit without saving session",
			},

			{
				"<leader>Sc",
				function()
					vim.cmd("lua require('persistence').load()")
					vim.notify("↺ Session restored", vim.log.levels.INFO, { timeout = 250 })
				end,
				desc = "Restore last session for current dir",
			},

			{
				"<leader>Sl",
				function()
					vim.cmd("lua require('persistence').load({ last = true })")
					vim.notify("↺ Last session restored", vim.log.levels.INFO, { timeout = 250 })
				end,
				desc = "Restore last session",
			},
		})
	end,
}
