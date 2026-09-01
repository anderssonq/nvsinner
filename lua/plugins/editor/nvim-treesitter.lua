return {
	"nvim-treesitter/nvim-treesitter",
	-- Pin to master ON PURPOSE. Upstream flipped its default branch to `main`,
	-- which is a full rewrite: no `nvim-treesitter.configs` module (this spec's
	-- config would error on boot) and a new install pipeline that recompiles
	-- every parser from source (the markdown pair failed to link on arm64).
	-- An unpinned `:NvSinnerSync`/`:Lazy sync` follows the upstream default and
	-- jumped to `main` — incident 2026-07-03, see CLAUDE.md *Plugin/Mason sync*.
	-- Migrating to `main` is a deliberate config rewrite, not a version bump.
	branch = "master",
	build = ":TSUpdate",
	event = { "BufReadPost", "BufNewFile" },
	config = function()
		-- Set up nvim-treesitter
		require("nvim-treesitter.configs").setup({
			auto_install = true,
			ensure_installed = {
				"lua",
				"vim",
				"typescript",
				"vue",
				"javascript",
				"html",
				"css",
				-- markdown + markdown_inline are needed as a pair (the block parser
				-- injects the inline one). Installed so docs render, but their TS
				-- highlight is disabled below — see the comment on `highlight.disable`.
				"markdown",
				"markdown_inline",
			},
			-- markdown/markdown_inline were disabled here for months against a
			-- misdiagnosed "0.12.x runtime crash". The cause was this pin's own
			-- query_predicates reading 0.12's list-valued `match[id]` as a single
			-- node; core/ts-compat (applied below) fixes it, so markdown
			-- highlights like every other language again.
			highlight = { enable = true },
			indent = { enable = true },
		})

		-- MUST run after configs.setup{} (which pulls in the plugin's
		-- query_predicates). This pin predates Neovim 0.12's query API, where a
		-- directive's `match[id]` is a LIST of nodes; the plugin still reads it
		-- as one node and throws on every markdown fence, HTML <script type=…>
		-- and bash heredoc. core/ts-compat re-registers the affected directives
		-- with 0.12 semantics — it is the compensating control for the pin
		-- above, so the two live and die together. Registering it earlier does
		-- NOT work: the plugin's own add_directive would silently overwrite it.
		require("core.ts-compat").apply()
	end,
}
