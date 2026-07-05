-- DISABLED: replaced by the native current-scope indent guide in
-- lua/core/indent.lua (decoration-provider overlay, same only_current look,
-- same IndentLineCurrent carbon panel gray). Kept as a one-line revert.
return {
	"nvimdev/indentmini.nvim",
	enabled = false,
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
