-- Per-window filename badge (top-right of each split), recolored to the dark
-- glass theme: the ACTIVE window's badge glows in the lone crimson accent
-- (kanagawa dragonRed), every other window stays muted on base. The filetype
-- icon keeps its own colour as foreground (no coloured block) to stay monochrome.
return {
	"b0o/incline.nvim",
	event = "VeryLazy",
	dependencies = { "nvim-tree/nvim-web-devicons" },
	config = function()
		local devicons = require("nvim-web-devicons")

		-- Glass palette (kept in sync with lua/plugins/theme.lua + ui-touch.lua).
		local CRIMSON = "#c4746e" -- lone accent: the active window
		local FG = "#c5c9d5"
		local MUTED = "#7a7f8d"
		local BG_ACTIVE = "#1c1c26" -- subtle glass lift for the active badge
		local BG_INACTIVE = "#121219"

		require("incline").setup({
			window = {
				padding = { left = 1, right = 1 },
				margin = { horizontal = 0, vertical = { top = 0, bottom = 1 } },
				placement = { vertical = "top", horizontal = "right" },
			},
			render = function(props)
				local filename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(props.buf), ":t")
				if filename == "" then
					filename = "[No Name]"
				end

				local ft_icon, ft_color = devicons.get_icon_color(filename)
				local modified = vim.bo[props.buf].modified
				local is_current = vim.api.nvim_get_current_buf() == props.buf

				local bg = is_current and BG_ACTIVE or BG_INACTIVE
				local fg = is_current and CRIMSON or MUTED

				return {
					is_current and { "● ", guifg = CRIMSON, guibg = bg } or "",
					ft_icon and { ft_icon, " ", guifg = ft_color, guibg = bg } or "",
					{
						filename,
						gui = modified and "bold,italic" or "bold",
						guifg = is_current and FG or MUTED,
						guibg = bg,
					},
					modified and { " ●", guifg = CRIMSON, guibg = bg } or "",
					guibg = bg,
				}
			end,
		})
	end,
}
