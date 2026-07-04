return {
	"nvimtools/none-ls.nvim",
	-- Lazy: formatters/linters only matter once a real file is open.
	event = { "BufReadPre", "BufNewFile" },
	-- eslint_d diagnostics were moved out of none-ls core into this extras repo.
	dependencies = { "nvimtools/none-ls-extras.nvim" },
	config = function()
		local null_ls = require("null-ls")

		null_ls.setup({
			sources = {
				null_ls.builtins.formatting.stylua,
				null_ls.builtins.formatting.prettier,
				-- Loaded from none-ls-extras (no longer a core builtin).
				-- Requires the `eslint_d` binary on your PATH to actually run.
				--
				-- Only enable it when the project actually has an ESLint config.
				-- Without this guard, eslint_d errors in plain folders (no config)
				-- and none-ls surfaces the raw error as a bogus diagnostic:
				--   "failed to decode json: Expected value but found invalid token".
				require("none-ls.diagnostics.eslint_d").with({
					condition = function(utils)
						return utils.root_has_file({
							".eslintrc",
							".eslintrc.js",
							".eslintrc.cjs",
							".eslintrc.json",
							".eslintrc.yaml",
							".eslintrc.yml",
							"eslint.config.js",
							"eslint.config.mjs",
							"eslint.config.cjs",
							"eslint.config.ts",
						})
					end,
				}),
			},
		})
	end,
}
