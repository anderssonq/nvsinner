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
				-- :MasonInstall). Mason manages everything here without an external
				-- language toolchain; the JS-based servers require Node 20+. vtsls
				-- + vue_ls work together for Vue SFCs; do not also enable ts_ls or
				-- two TypeScript clients attach.
				-- solargraph (Ruby), gopls (Go) and rust_analyzer (Rust) are
				-- intentionally omitted: install them only with their toolchains.
				ensure_installed = {
					"lua_ls",
					"vtsls",
					"vue_ls",
					"html",
					"pyright",
					"bashls",
					"jsonls",
					"yamlls",
					"cssls",
				},
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

			-- Native LSP API. Per-server base configs come from nvim-lspconfig's
			-- bundled lsp/*.lua files; we layer cmp capabilities onto all of them
			-- and enable the ones we want.
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

			-- Vue 3 language-tools uses hybrid mode: vue_ls owns the SFC's
			-- HTML/CSS regions while vtsls, extended with the Vue TypeScript
			-- plugin, owns JavaScript/TypeScript in the same buffer. Mason ships
			-- the plugin inside vue-language-server, so this path is portable
			-- across NVIM_APPNAMEs and operating systems.
			local vue_language_server_path = vim.fs.joinpath(
				vim.fn.stdpath("data"),
				"mason",
				"packages",
				"vue-language-server",
				"node_modules",
				"@vue",
				"language-server"
			)
			vim.lsp.config("vtsls", {
				settings = {
					vtsls = {
						tsserver = {
							globalPlugins = {
								{
									name = "@vue/typescript-plugin",
									location = vue_language_server_path,
									languages = { "vue" },
									configNamespace = "typescript",
								},
							},
						},
					},
				},
				filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact", "vue" },
			})

			vim.lsp.enable({
				"vtsls",
				"vue_ls",
				"html",
				"lua_ls",
				"pyright",
				"bashls",
				"jsonls",
				"yamlls",
				"cssls",
			})

			-- These servers require language-specific toolchains and are not
			-- Mason-managed by default. Native vim.lsp.enable() validates `cmd`
			-- eagerly, so enabling an absent binary floods lsp.log on every file.
			-- Probe first; installing one later makes it available next launch.
			for _, optional in ipairs({
				{ server = "solargraph", binary = "solargraph" },
				{ server = "gopls", binary = "gopls" },
				{ server = "rust_analyzer", binary = "rust-analyzer" },
			}) do
				if vim.fn.executable(optional.binary) == 1 then
					vim.lsp.enable(optional.server)
				end
			end

			-- ─── Neovim 0.12 native LSP capabilities ──────────────────────────
			-- Opt-in per client, gated on the server actually advertising the
			-- method. All of this is builtin — no plugin — which is the only
			-- reason it belongs here rather than in a spec of its own.
			vim.api.nvim_create_autocmd("LspAttach", {
				group = vim.api.nvim_create_augroup("nvsinner_lsp_0_12", { clear = true }),
				callback = function(ev)
					local client = vim.lsp.get_client_by_id(ev.data.client_id)
					if not client then
						return
					end
					-- Rename an HTML/JSX tag and its pair follows as you type.
					-- Free, and this config edits a lot of TS/Vue/HTML.
					if client:supports_method("textDocument/linkedEditingRange") then
						pcall(vim.lsp.linked_editing_range.enable, true, { client_id = client.id })
					end
					-- Inlay hints follow the persisted setting rather than the
					-- server's capability alone: they put virtual text on most
					-- lines, which is a real change to how code reads, so it is
					-- the user's call (:NvSinnerMenu -> "Inlay hints", or
					-- <leader>lh). Buffers attaching later land here and inherit
					-- whatever the setting currently says.
					if client:supports_method("textDocument/inlayHint") then
						local ok, settings = pcall(require, "core.settings")
						pcall(
							vim.lsp.inlay_hint.enable,
							ok and settings.get("inlay_hints") or false,
							{ bufnr = ev.buf }
						)
					end

					-- NOT set up here: vim.lsp.document_color. Neovim 0.12
					-- enables it by DEFAULT (see :h lsp-defaults — the docs only
					-- describe how to opt OUT), so there is nothing to turn on.
				end,
			})

			-- Workspace-wide diagnostics: pulls problems from files that are NOT
			-- open, which Trouble's <leader>xx cannot do — it only ever sees
			-- loaded buffers. Ask for them, then the usual list is complete.
			vim.api.nvim_create_user_command("NvSinnerDiagnosticsWorkspace", function()
				local ok, err = pcall(vim.lsp.buf.workspace_diagnostics)
				if not ok then
					vim.notify("Workspace diagnostics unavailable: " .. tostring(err), vim.log.levels.WARN)
					return
				end
				vim.notify("Requested workspace diagnostics — open :Trouble diagnostics to read them")
			end, { desc = "Pull diagnostics for the whole workspace, not just open buffers" })

			-- LSP folding is a per-WINDOW toggle, not a default, because
			-- 'foldmethod' is exclusive: with "expr" set, `:fold` raises E350 and
			-- <leader>zf (fold the visual selection) silently stops working.
			-- Verified on 0.12.3. So structural folds are opt-in per window and
			-- restore the manual method when toggled back off.
			vim.keymap.set("n", "<leader>zl", function()
				if vim.wo.foldmethod == "expr" then
					vim.wo.foldmethod = "manual"
					vim.wo.foldexpr = ""
					vim.notify("LSP folding off — <leader>zf works again")
					return
				end
				local supported = false
				for _, c in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
					if c:supports_method("textDocument/foldingRange") then
						supported = true
						break
					end
				end
				if not supported then
					vim.notify("No attached LSP client offers folding ranges here", vim.log.levels.WARN)
					return
				end
				vim.wo.foldmethod = "expr"
				vim.wo.foldexpr = "v:lua.vim.lsp.foldexpr()"
				vim.notify("LSP folding on — note <leader>zf (manual fold) is unavailable while it is")
			end, { desc = "Toggle LSP structural folding (this window)" })

			-- Global on purpose (not LspAttach/buffer-local): these call safe
			-- vim.lsp.buf functions that no-op without a client, and global maps
			-- keep which-key listings stable. Neovim 0.11 builtins cover the
			-- rest: grn (rename), grr (references), gri (implementation),
			-- gO (document symbols), ]d/[d (diagnostics) — documented in the
			-- README/CLAUDE.md keymap tables rather than remapped.
			vim.keymap.set("n", "K", vim.lsp.buf.hover, { desc = "LSP hover docs" })
			vim.keymap.set("n", "<leader>lf", vim.lsp.buf.format, { desc = "Format Code" })

			-- Inlay hints: flip the persisted setting, so the toggle and the
			-- :NvSinnerMenu row are the same switch rather than two that can
			-- disagree. settings.set() applies it live to every attached buffer.
			vim.keymap.set("n", "<leader>lh", function()
				local settings = require("core.settings")
				local on = not settings.get("inlay_hints")
				settings.set("inlay_hints", on)
				vim.notify("Inlay hints " .. (on and "on" or "off"), vim.log.levels.INFO, { timeout = 250 })
			end, { desc = "Toggle LSP inlay hints" })
			vim.keymap.set("n", "gd", vim.lsp.buf.definition, { desc = "Go to definition" })
			vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, { desc = "Code action" })
			vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, { desc = "Rename symbol" })
		end,
	},
}
