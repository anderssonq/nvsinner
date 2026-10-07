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
			-- One-line toasts: "compact" folds the icon + title into the
			-- message line ("<icon> | <title>: <message>") instead of the
			-- default's separate header row. A multi-line message still keeps
			-- its extra lines — only the header is folded away.
			render = "compact",
		})
		vim.notify = notify
	end,
}
