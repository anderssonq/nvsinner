return {
	"nvim-neo-tree/neo-tree.nvim",
	branch = "v3.x",
	-- Lazy: loads on the :Neotree command or the <leader>e keymap.
	cmd = "Neotree",
	dependencies = {
		"nvim-lua/plenary.nvim",
		"nvim-tree/nvim-web-devicons", -- not strictly required, but recommended
		"MunifTanjim/nui.nvim",
		"3rd/image.nvim", -- Optional image support in preview window: See `# Preview Mode` for more information
	},
	keys = {
		{
			"<leader>e",
			function()
				-- Check whether Neo-tree is currently visible
				local manager = require("neo-tree.sources.manager")
				local renderer = require("neo-tree.ui.renderer")
				local state = manager.get_state("filesystem")

				if renderer.window_exists(state) then
					-- Neo-tree is open, just close it
					vim.cmd("Neotree close")
				else
					-- Open it focused on the file you're editing/reading: `reveal`
					-- jumps to and highlights the current buffer's file in the tree.
					-- For non-file buffers (dashboard, terminals) fall back to a
					-- plain open at the cwd root.
					local file = vim.api.nvim_buf_get_name(0)
					if file ~= "" and vim.bo.buftype == "" and vim.fn.filereadable(file) == 1 then
						vim.cmd("Neotree reveal left")
					else
						vim.cmd("Neotree focus left")
					end
					vim.notify(
						" a add · r rename · d delete · y copy · x cut · p paste · ? help",
						vim.log.levels.INFO,
						{ title = "Neo-tree", timeout = 250 }
					)
				end
			end,
			desc = "Toggle Neo-tree",
		},
	},
	config = function()
		require("neo-tree").setup({
			filesystem = {
				filtered_items = {
					visible = true, -- If true, all "hide" rules just dim items out instead of hiding them
					hide_dotfiles = false,
					hide_gitignored = true,
				},
				window = {
					width = 30, -- Width in columns, adjust as needed
					position = "left",
				},
			},
		})
	end,
}
