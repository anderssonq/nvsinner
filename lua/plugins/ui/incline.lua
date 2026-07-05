-- Per-window filename badge (top-right of each split), recolored to the carbon
-- theme: the ACTIVE window's badge is marked with the blue identity accent
-- (base09), every other window stays muted on a panel gray. The "modified" dot
-- uses base10 (carbon's attention magenta). The filetype icon keeps its own
-- colour as foreground (no coloured block) so surfaces stay gray-dominant.
--
-- DISABLED: replaced by the native badge in lua/core/filebadge.lua — incline's
-- float overlapped the first buffer line on winbar-less (markdown) windows and
-- its non-focusable float couldn't host a clickable "Open view" chip. The
-- winbar-based native badge has neither problem. Kept as a one-line revert.
return {
	"b0o/incline.nvim",
	enabled = false,
	event = "VeryLazy",
	dependencies = { "nvim-tree/nvim-web-devicons" },
	config = function()
		local devicons = require("nvim-web-devicons")

		-- Carbon palette roles (single source: lua/core/carbon.lua), cached in a
		-- table that is REFILLED on ColorScheme so a live dark↔light / accent
		-- switch (:NvSinnerMenu) restyles the badge instead of keeping the
		-- boot-time colors. render() reads the cache, not config-time upvalues.
		local pal = {}
		local function refresh()
			local c = require("core.carbon").colors()
			pal.ACCENT = c.base09 -- identity accent: the active window
			pal.MODIFIED = c.base10 -- magenta: unsaved-changes marker
			pal.FG = c.base04
			pal.MUTED = c.base03
			pal.BG_ACTIVE = c.base02 -- lifted chip for the active badge
			pal.BG_INACTIVE = c.base01
		end
		refresh()
		vim.api.nvim_create_autocmd("ColorScheme", {
			group = vim.api.nvim_create_augroup("nv_incline_carbon", { clear = true }),
			pattern = "*",
			callback = refresh,
		})

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

				local bg = is_current and pal.BG_ACTIVE or pal.BG_INACTIVE

				return {
					is_current and { "● ", guifg = pal.ACCENT, guibg = bg } or "",
					ft_icon and { ft_icon, " ", guifg = ft_color, guibg = bg } or "",
					{
						filename,
						gui = modified and "bold,italic" or "bold",
						guifg = is_current and pal.FG or pal.MUTED,
						guibg = bg,
					},
					modified and { " ●", guifg = pal.MODIFIED, guibg = bg } or "",
					guibg = bg,
				}
			end,
		})
	end,
}
