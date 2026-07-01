-- Breadcrumb winbar (path > LSP symbols) on code windows, recolored to the dark
-- glass theme so it speaks the same language as the rest of the UI: muted
-- dirname / separators, a clean FG basename, soft symbol icons, and the lone
-- crimson accent reserved for the "modified" marker.
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
		-- Glass palette (kept in sync with lua/plugins/theme.lua).
		local FG = "#c5c9d5"
		local MUTED = "#7a7f8d"
		local DIM = "#54546d"
		local CRIMSON = "#c4746e" -- lone accent
		local CONTEXT = "#9aa0b4" -- soft tone for LSP symbol icons

		require("barbecue").setup({
			theme = {
				normal = { fg = FG },
				ellipsis = { fg = DIM },
				separator = { fg = DIM },
				modified = { fg = CRIMSON },
				dirname = { fg = MUTED },
				basename = { fg = FG, bold = true },
				context = { fg = CONTEXT },

				-- Symbol/context icons: one soft tone across the board (monochrome).
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
	end,
}
