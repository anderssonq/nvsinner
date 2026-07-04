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
		{ "<leader>sd", "<cmd>Telescope diagnostics<cr>", desc = "Search diagnostics" },
		{ "<leader>sk", "<cmd>Telescope keymaps<cr>", desc = "Search keymaps" },
		{ "<leader>sc", "<cmd>Telescope commands<cr>", desc = "Search commands" },
		{ "<leader>sr", "<cmd>Telescope resume<cr>", desc = "Resume last search" },
		{ "<leader>sh", "<cmd>Telescope help_tags<cr>", desc = "Search help" },
		{ "<leader>ss", "<cmd>Telescope lsp_document_symbols<cr>", desc = "Document symbols" },
		{ "<leader>sR", "<cmd>Telescope lsp_references<cr>", desc = "LSP references" },
		-- <leader>fb (buffers) is mapped in lua/core/keymaps.lua and also triggers
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
				-- Never surface git internals even when searching hidden files below.
				file_ignore_patterns = { "^%.git/" },
			},
			pickers = {
				-- <leader>f finds hidden dotfiles too (rg --hidden). .git/ is still
				-- excluded via file_ignore_patterns above so it doesn't flood results.
				find_files = {
					hidden = true,
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
