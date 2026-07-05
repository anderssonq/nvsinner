return {
	"folke/which-key.nvim",
	event = "VeryLazy",
	opts = {
		-- Group labels for the leader namespaces, so the which-key popup reads
		-- as a menu instead of a flat keymap dump. The individual entries come
		-- from each map's `desc` (already set everywhere).
		spec = {
			{ "<leader>a", group = "ai" },
			{ "<leader>c", group = "code" },
			{ "<leader>g", group = "git" },
			{ "<leader>h", group = "hunks" },
			{ "<leader>j", group = "ai sessions" },
			{ "<leader>l", group = "lsp" },
			{ "<leader>s", group = "search" },
			{ "<leader>S", group = "session" },
			{ "<leader>t", group = "terminal" },
			{ "<leader>x", group = "trouble · nvsinner" },
			-- <leader>x is dual: trouble namespace in normal mode, the Ask-AI
			-- modal (core/ai-ask.lua) in visual mode.
			{ "<leader>x", desc = "Ask AI about selection", mode = "x" },
		},
	},
	keys = {
		{
			"<leader>?",
			function()
				require("which-key").show({ global = false })
			end,
			desc = "Buffer Local Keymaps (which-key)",
		},
	},
	-- No custom `config`: with `opts` present, lazy.nvim runs
	-- require("which-key").setup(opts) automatically. An empty config function
	-- here would SUPPRESS that setup and disable the popup.
}
