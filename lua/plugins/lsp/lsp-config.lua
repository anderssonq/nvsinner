return {
	{
		"williamboman/mason.nvim",
		cmd = "Mason",
		config = function()
			require("mason").setup()
		end,
	},
	{
		"williamboman/mason-lspconfig.nvim",
		-- Defer just past startup so a fresh install still auto-installs the
		-- servers (ensure_installed) even when you land on the dashboard with no
		-- file open (VeryLazy fires after UI). mason must be set up first, hence
		-- the explicit dependency.
		event = "VeryLazy",
		dependencies = { "williamboman/mason.nvim" },
		config = function()
			require("mason-lspconfig").setup({
				-- First-boot auto-install (the distro should need no manual
				-- :MasonInstall). Everything here installs standalone via node —
				-- no extra toolchain needed. solargraph (Ruby), gopls (Go) and
				-- rust_analyzer (Rust) are intentionally omitted: they need their
				-- language toolchains; install by hand only if you edit those.
				ensure_installed = { "lua_ls", "ts_ls", "html", "pyright", "bashls", "jsonls", "yamlls", "cssls" },
				-- We enable + configure servers ourselves via the native vim.lsp
				-- API in nvim-lspconfig's config (the "*" config nils semantic
				-- tokens to keep Treesitter as the single colour source). Don't let
				-- mason-lspconfig auto-enable, or it could start a server before
				-- that "*" config lands and reintroduce the @lsp.* repaint.
				automatic_enable = false,
			})
		end,
	},
	{
		"neovim/nvim-lspconfig",
		-- Lazy: the LSP client only needs to start when a real file is opened.
		event = { "BufReadPre", "BufNewFile" },
		dependencies = {
			"williamboman/mason.nvim",
			"williamboman/mason-lspconfig.nvim",
			"hrsh7th/cmp-nvim-lsp",
		},
		config = function()
			local capabilities = require("cmp_nvim_lsp").default_capabilities()

			-- Neovim 0.11 native LSP API. Replaces the deprecated
			-- require("lspconfig").<server>.setup({}) calls and also fixes the
			-- previous typo (ts_lsp -> ts_ls). Per-server base configs come from
			-- nvim-lspconfig's bundled lsp/*.lua files; we just layer cmp
			-- capabilities onto all of them and enable the ones we want.
			vim.lsp.config("*", {
				capabilities = capabilities,
				-- Keep Treesitter as the SINGLE source of syntax colour. Without
				-- this, ~1s after a file opens the server attaches and its LSP
				-- semantic tokens (@lsp.*) repaint the buffer on top of Treesitter,
				-- flattening the palette (the "se ve menos colorido" effect). Nil
				-- the provider on attach so semantic-token highlighting never starts.
				on_attach = function(client, _)
					client.server_capabilities.semanticTokensProvider = nil
				end,
			})
			-- Enabling a server whose binary is absent is harmless (it just never
			-- starts), so the toolchain-gated servers (solargraph, gopls,
			-- rust_analyzer) stay enabled here even though ensure_installed above
			-- skips them: install the toolchain + server and they light up.
			vim.lsp.enable({
				"ts_ls",
				"solargraph",
				"html",
				"lua_ls",
				"pyright",
				"gopls",
				"rust_analyzer",
				"bashls",
				"jsonls",
				"yamlls",
				"cssls",
			})

			-- Global on purpose (not LspAttach/buffer-local): these call safe
			-- vim.lsp.buf functions that no-op without a client, and global maps
			-- keep which-key listings stable. Neovim 0.11 builtins cover the
			-- rest: grn (rename), grr (references), gri (implementation),
			-- gO (document symbols), ]d/[d (diagnostics) — documented in the
			-- README/CLAUDE.md keymap tables rather than remapped.
			vim.keymap.set("n", "K", vim.lsp.buf.hover, { desc = "LSP hover docs" })
			vim.keymap.set("n", "<leader>lf", vim.lsp.buf.format, { desc = "Format Code" })
			vim.keymap.set("n", "gd", vim.lsp.buf.definition, { desc = "Go to definition" })
			vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, { desc = "Code action" })
			vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, { desc = "Rename symbol" })
		end,
	},
}
