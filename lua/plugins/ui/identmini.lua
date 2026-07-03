return {
	"nvimdev/indentmini.nvim",
	event = { "BufReadPost", "BufNewFile" },
	config = function()
		require("indentmini").setup({
			only_current = true,
		})
		-- Carbon panel gray (base02) for the current-scope indent guide.
		local function hl()
			local c = require("core.carbon").colors()
			vim.api.nvim_set_hl(0, "IndentLineCurrent", { fg = c.base02 })
		end
		hl()
		vim.api.nvim_create_autocmd("ColorScheme", { pattern = "*", callback = hl })
	end,
}
