-- DISABLED: replaced by the native hex-chip module in lua/core/colorizer.lua
-- (visible-range #rgb/#rrggbb/#rrggbbaa scan → bg extmarks; the plugin's
-- css/tailwind machinery was unused). Kept as a one-line revert.
return {
	"NvChad/nvim-colorizer.lua",
	enabled = false,
	event = { "BufReadPost", "BufNewFile" },
	config = function()
		require("colorizer").setup()
	end,
}
