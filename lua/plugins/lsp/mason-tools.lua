-- Auto-install the external formatter/linter binaries none-ls consumes
-- (stylua, prettier, eslint_d) via Mason, so a fresh NvSinner install needs
-- no manual `brew install` / `npm i -g` for formatting. Mason prepends its
-- bin dir to PATH in setup(), so none-ls and :checkhealth nvsinner resolve
-- the binaries once this has run (mason loads as a dependency here, at
-- VeryLazy — same trigger as mason-lspconfig, so a fresh install still
-- installs the tools even when you land on the dashboard with no file open).
return {
	"WhoIsSethDaniel/mason-tool-installer.nvim",
	event = "VeryLazy",
	dependencies = { "williamboman/mason.nvim" },
	config = function()
		require("mason-tool-installer").setup({
			ensure_installed = { "stylua", "prettier", "eslint_d" },
			-- Install what's missing on start, but never auto-UPDATE: package
			-- updates are the explicit opt-in :NvSinnerSync path, mirroring the
			-- lazy-lock restore doctrine (ship pinned, float on request).
			run_on_start = true,
			auto_update = false,
		})
	end,
}
