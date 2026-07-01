return {
	"rcarriga/nvim-notify",
	event = "VeryLazy",
	config = function()
		local notify = require("notify")
		notify.setup({
			-- On-screen time at full visibility.
			timeout = 250,
			-- `timeout` is NOT the total lifetime: the stages animation runs
			-- ON TOP of it. The default "fade_in_slide_out" added ~750ms of
			-- fade-in + fade-out/slide, so toasts lingered ~1s. "fade" is the
			-- short option — a quick opacity fade only, no slide — so a toast
			-- stays readable ~250ms with just a brief transition. Higher fps
			-- keeps that fade smooth.
			stages = "fade",
			fps = 60,
		})
		vim.notify = notify
	end,
}
