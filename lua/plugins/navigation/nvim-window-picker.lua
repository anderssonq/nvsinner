-- DISABLED: replaced by the native letter-overlay picker in
-- lua/core/window-picker.lua, which serves `require("window-picker")` via
-- package.preload so neo-tree's `open_with_window_picker` (`w`) keeps
-- working unchanged. Re-enabling this spec hands the require back to the
-- real plugin (the preload shim defers to the rtp). One-line revert.
return {
	"s1n7ax/nvim-window-picker",
	name = "window-picker",
	enabled = false,
	event = "VeryLazy",
	version = "2.*",
	config = function()
		require("window-picker").setup()
	end,
}
