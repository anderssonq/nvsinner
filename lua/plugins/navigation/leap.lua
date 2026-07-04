return {
	-- The repo moved from github (ggandor/leap.nvim) to Codeberg.
	url = "https://codeberg.org/andyg/leap.nvim",
	-- Lazy: load on the first jump key. These entries only tell lazy WHEN to
	-- load — the real <Plug> maps for the same keys are created in config(),
	-- and lazy re-feeds the pressed key after loading, so the first press
	-- already jumps.
	keys = {
		{ "s", mode = { "n", "x", "o" }, desc = "Leap forward" },
		{ "S", mode = { "n", "x", "o" }, desc = "Leap backward" },
		{ "gs", mode = { "n", "x", "o" }, desc = "Leap cross-window" },
	},
	config = function()
		local leap = require("leap")
		-- `case_sensitive` was removed; case sensitivity is now driven by Vim's
		-- `ignorecase` during leap. ignorecase = false  ->  case-sensitive jumps
		-- (the old `case_sensitive = true` behaviour).
		leap.opts.vim_opts["go.ignorecase"] = false

		-- Restore the classic "type 2 chars, then pick a label" flow: an empty
		-- `safe_labels` disables auto-jumping to the first match, so leap always
		-- labels every target and waits for you to choose one.
		leap.opts.safe_labels = ""

		-- add_default_mappings() is deprecated. These explicit maps reproduce its
		-- behaviour (Sneak-style, per :help leap-mappings):
		--   s  -> leap forward    S  -> leap backward    gs -> leap across windows
		vim.keymap.set({ "n", "x", "o" }, "s", "<Plug>(leap-forward)")
		vim.keymap.set({ "n", "x", "o" }, "S", "<Plug>(leap-backward)")
		vim.keymap.set({ "n", "x", "o" }, "gs", "<Plug>(leap-from-window)")
	end,
}
