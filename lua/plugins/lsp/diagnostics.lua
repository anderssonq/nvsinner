-- Pretty diagnostics (tiny-inline-diagnostic.nvim).
--
-- Replaces the default end-of-line virtual_text with an elegant rounded inline
-- bubble for the diagnostic on the cursor line, and themes the diagnostic
-- floats + sign icons to match the glass theme. Underlines stay on so problem
-- spans are still visible at a glance.
return {
	"rachartier/tiny-inline-diagnostic.nvim",
	event = "LspAttach",
	priority = 1000, -- load before other LspAttach consumers so virtual_text is off first
	config = function()
		require("tiny-inline-diagnostic").setup({
			preset = "modern",
			options = {
				show_source = false,
				multilines = { enabled = true, always_show = false },
				show_all_diags_on_cursorline = false,
			},
		})

		-- Inline bubbles own the line, so turn off the default virtual_text and
		-- give floats/signs a consistent rounded glass look + crimson errors.
		vim.diagnostic.config({
			virtual_text = false,
			underline = true,
			update_in_insert = false,
			severity_sort = true,
			float = { border = "rounded", source = true },
			signs = {
				text = {
					[vim.diagnostic.severity.ERROR] = "",
					[vim.diagnostic.severity.WARN] = "",
					[vim.diagnostic.severity.INFO] = "",
					[vim.diagnostic.severity.HINT] = "",
				},
			},
		})
	end,
}
