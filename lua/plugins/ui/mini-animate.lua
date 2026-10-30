-- Smooth window/cursor animations (mini.animate).
--
-- Makes the editor feel "alive": windows fade in/out on open/close, window
-- resizes ease, and the cursor leaves a short trail. Scrolling is deliberately
-- left to neoscroll (lua/plugins/smooth-scroll.lua) so the two don't fight over
-- scroll events.
--
-- The layout panels (neo-tree, AI columns, <leader>t terminals) SLIDE in
-- instead — lua/core/slide.lua grows them from the edge. While a slide runs,
-- the open/resize predicates below stand mini.animate down, so the panel is
-- never animated twice: no open float over the sliding window, and no resize
-- easing for the frames the slide itself produces (the panel and the windows
-- that shrink to make room). Both switches read the same flag:
-- vim.g.minianimate_disable (the :NvSinnerMenu "Animations" row).

-- True while core/slide.lua is animating `win_id` (or, with no window, any
-- panel). package.loaded, not require: nothing has slid until the module was
-- loaded by an open path, and the predicates run on every WinScrolled.
local function sliding(win_id)
	local slide = package.loaded["core.slide"]
	return slide ~= nil and slide.busy(win_id)
end

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
				subresize = animate.gen_subresize.equal({
					predicate = function()
						return not sliding()
					end,
				}),
			},
			open = {
				enable = true,
				timing = animate.gen_timing.cubic({ duration = 120, unit = "total" }),
				-- mini.animate's default open winconfig (static, 25 steps), minus
				-- the window a slide is growing.
				winconfig = animate.gen_winconfig.static({
					predicate = function(win_id)
						return not sliding(win_id)
					end,
				}),
			},
			close = {
				enable = true,
				timing = animate.gen_timing.cubic({ duration = 120, unit = "total" }),
			},
		})
	end,
}
