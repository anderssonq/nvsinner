-- Breadcrumb winbar (path > LSP symbols) on code windows, recolored to the
-- carbon theme so it speaks the same language as the rest of the UI: muted
-- dirname / separators, a clean base04 basename, soft blue symbol icons, and
-- carbon's attention magenta (base10) reserved for the "modified" marker.
return {
	"utilyre/barbecue.nvim",
	name = "barbecue",
	version = "*",
	event = { "BufReadPost", "BufNewFile" },
	dependencies = {
		"SmiteshP/nvim-navic",
		"nvim-tree/nvim-web-devicons",
	},
	config = function()
		-- Applied with FRESH carbon roles (single source: lua/core/carbon.lua)
		-- and re-run on ColorScheme, so a live dark↔light / accent switch
		-- (:NvSinnerMenu) recolors the breadcrumbs too.
		local function apply()
			local c = require("core.carbon").colors()
			local FG = c.base04
			local MUTED = c.base03
			local DIM = c.base02
			local MODIFIED = c.base10 -- carbon's attention magenta
			local CONTEXT = c.base09 -- identity accent for LSP symbol icons

			require("barbecue").setup({
				-- markdown owns its winbar for the "Open view" reading-view button
				-- (see render-markdown.lua) — keep barbecue's breadcrumb off it so the
				-- two don't fight over the same line.
				exclude_filetypes = { "netrw", "toggleterm", "markdown" },
				theme = {
					normal = { fg = FG },
					ellipsis = { fg = DIM },
					separator = { fg = DIM },
					modified = { fg = MODIFIED },
					dirname = { fg = MUTED },
					basename = { fg = FG, bold = true },
					context = { fg = FG },

					-- Symbol/context icons: one soft blue tone across the board.
					context_file = { fg = CONTEXT },
					context_module = { fg = CONTEXT },
					context_namespace = { fg = CONTEXT },
					context_package = { fg = CONTEXT },
					context_class = { fg = CONTEXT },
					context_method = { fg = CONTEXT },
					context_property = { fg = CONTEXT },
					context_field = { fg = CONTEXT },
					context_constructor = { fg = CONTEXT },
					context_enum = { fg = CONTEXT },
					context_interface = { fg = CONTEXT },
					context_function = { fg = CONTEXT },
					context_variable = { fg = CONTEXT },
					context_constant = { fg = CONTEXT },
					context_string = { fg = CONTEXT },
					context_number = { fg = CONTEXT },
					context_boolean = { fg = CONTEXT },
					context_array = { fg = CONTEXT },
					context_object = { fg = CONTEXT },
					context_key = { fg = CONTEXT },
					context_null = { fg = CONTEXT },
					context_enum_member = { fg = CONTEXT },
					context_struct = { fg = CONTEXT },
					context_event = { fg = CONTEXT },
					context_operator = { fg = CONTEXT },
					context_type_parameter = { fg = CONTEXT },
				},
			})
		end
		apply()
		vim.api.nvim_create_autocmd("ColorScheme", {
			group = vim.api.nvim_create_augroup("nv_barbecue_carbon", { clear = true }),
			pattern = "*",
			callback = apply,
		})
	end,
}
