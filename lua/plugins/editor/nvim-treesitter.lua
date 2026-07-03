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
			highlight = {
				enable = true,
				-- Neovim 0.12.x ships a treesitter runtime where the markdown
				-- highlighter calls `node:range()` on a nil node and crashes
				-- (runtime treesitter.lua:197, "attempt to call method 'range'").
				-- Fall back to Vim's regex syntax for markdown until the upstream
				-- fix lands. Mirrors the other 0.12.x markdown workarounds documented
				-- in CLAUDE.md (noice LSP paths off, ui-touch plain-text hover).
				disable = { "markdown", "markdown_inline" },
			},
			indent = { enable = true },
		})
	end,
}
