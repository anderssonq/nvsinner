-- Smooth window/cursor animations (mini.animate).
--
-- Makes the editor feel "alive": the AI column / horizontal terminal SLIDES in
-- and out instead of snapping, window resizes ease, and the cursor leaves a
-- short trail. Scrolling is deliberately left to neoscroll (lua/plugins/
-- smooth-scroll.lua) so the two don't fight over scroll events.
return {
	"echasnovski/mini.animate",
	version = false,
	event = "VeryLazy",
	config = function()
		local animate = require("mini.animate")
		animate.setup({
			-- Owned by neoscroll — disable here to avoid double-animating scroll.
			scroll = { enable = false },
			cursor = {
				enable = true,
				timing = animate.gen_timing.linear({ duration = 90, unit = "total" }),
			},
			resize = {
				enable = true,
				timing = animate.gen_timing.cubic({ duration = 120, unit = "total" }),
			},
			open = {
				enable = true,
				timing = animate.gen_timing.cubic({ duration = 120, unit = "total" }),
			},
			close = {
				enable = true,
				timing = animate.gen_timing.cubic({ duration = 120, unit = "total" }),
			},
		})
	end,
}
