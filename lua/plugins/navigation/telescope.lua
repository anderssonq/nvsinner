return {
	"nvim-telescope/telescope.nvim",
	tag = "0.1.8",
	-- Lazy: loads on the :Telescope command or any of the keymaps below.
	cmd = "Telescope",
	dependencies = {
		"nvim-lua/plenary.nvim",
		"nvim-telescope/telescope-ui-select.nvim",
	},
	keys = {
		{ "<leader>f", "<cmd>Telescope find_files<cr>", desc = "Find files" },
		{ "<leader>sf", "<cmd>Telescope live_grep<cr>", desc = "Live grep" },
		-- <leader>fb (buffers) is mapped in lua/vim-config.lua and also triggers
		-- this lazy load via the :Telescope command stub.
	},
	config = function()
		require("telescope").setup({
			defaults = {
				-- Neovim 0.12.x crashes the markdown treesitter highlighter
				-- (node:range on a nil node). The file preview highlights markdown
				-- with treesitter, so disable it for markdown/markdown_inline and
				-- fall back to regex syntax. See lua/plugins/editor/nvim-treesitter.lua.
				preview = {
					treesitter = {
						disable = { "markdown", "markdown_inline" },
					},
				},
			},
			extensions = {
				["ui-select"] = {
					require("telescope.themes").get_dropdown({}),
				},
			},
		})
		require("telescope").load_extension("ui-select")
	end,
}
