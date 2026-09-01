return {
	"hrsh7th/nvim-cmp",
	-- Lazy: the completion engine is only needed once you start typing.
	event = "InsertEnter",
	dependencies = {
		"hrsh7th/cmp-nvim-lsp",
		{
			"L3MON4D3/LuaSnip",
			dependencies = {
				"saadparwaiz1/cmp_luasnip",
				"rafamadriz/friendly-snippets",
			},
		},
	},
	config = function()
		local cmp = require("cmp")
		require("luasnip.loaders.from_vscode").lazy_load()

		cmp.setup({
			snippet = {
				expand = function(args)
					require("luasnip").lsp_expand(args.body)
				end,
			},
			window = {
				completion = cmp.config.window.bordered(),
				documentation = cmp.config.window.bordered(),
			},
			mapping = cmp.mapping.preset.insert({
				["<C-b>"] = cmp.mapping.scroll_docs(-4),
				["<C-f>"] = cmp.mapping.scroll_docs(4),
				["<C-Space>"] = cmp.mapping.complete(),
				["<C-e>"] = cmp.mapping.abort(),
				["<CR>"] = cmp.mapping.confirm({ select = true }),
			}),
			sources = cmp.config.sources({
				{ name = "nvim_lsp" },
				{ name = "luasnip" },
			}),
		})

		-- ─── Snippet placeholder navigation ────────────────────────────────
		-- Expanding a snippet without these is a trap: you land on the first
		-- placeholder and cannot reach the second. Neovim 0.11+ ships default
		-- <Tab>/<S-Tab> jump maps, but they drive `vim.snippet`, and the
		-- `snippet.expand` above hands the body to LuaSnip — so
		-- `vim.snippet.active()` is false, the builtin maps fall through, and
		-- nothing else was bound. Verified on 0.12.3: after an expand,
		-- `luasnip.jumpable(1)` is true while `vim.snippet.active()` is false.
		--
		-- Select mode matters as much as insert: a placeholder is SELECTED
		-- after a jump, so `s` is the mode you are actually in when you press
		-- <Tab> to move on.
		--
		-- Insert-mode <Tab> is deliberately absent here — it is arbitrated in
		-- lua/core/ai-complete.lua, which already chains cmp and the AI ghost
		-- and now the forward jump too. Mapping it here would silently replace
		-- that chain and break ghost accept.
		local ls = require("luasnip")
		vim.keymap.set({ "i", "s" }, "<S-Tab>", function()
			if ls.jumpable(-1) then
				ls.jump(-1)
			end
		end, { silent = true, desc = "Snippet: previous placeholder" })
		vim.keymap.set("s", "<Tab>", function()
			if ls.jumpable(1) then
				ls.jump(1)
			end
		end, { silent = true, desc = "Snippet: next placeholder" })
	end,
}
