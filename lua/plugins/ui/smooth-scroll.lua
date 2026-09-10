-- Page scrolling. neoscroll's ctrl_u/ctrl_d helpers travel `&scroll` lines —
-- half a window, ~28 on a full-height split — which reads as a teleport
-- rather than a page, especially since <S-Down>/<S-Up> (Vim builtins for
-- CTRL-F/CTRL-B) already own the full-window jump. These keys are the gentle
-- step between "one line" and "one screen".
--
-- The distance is a *fraction* of the window, not a line count: neoscroll.scroll
-- treats a float as a window fraction, so the step stays proportional in a tall
-- editor and a short split alike.
local STEP = 0.25
-- A file list is scanned row by row, so a page there should keep more context
-- on screen than a page of code does.
local STEP_BY_FILETYPE = { ["neo-tree"] = 0.15 }

-- Note on where the cursor lands: `scrolloff` (6, core/options.lua) makes
-- neoscroll pin the cursor to window row scrolloff+1 for the whole animation,
-- so the first press off the top of a buffer settles it there and every later
-- press holds that row. That settle is scrolloff's doing, not the step size.
return {
	"karb94/neoscroll.nvim",
	event = "VeryLazy",
	config = function()
		local neoscroll = require("neoscroll")

		-- One global map per direction, filetype-aware: neo-tree binds nothing to
		-- <PageUp>/<PageDown> (its stock <C-f>/<C-b> scroll the *preview* window),
		-- so a table lookup here beats a buffer-local override racing this spec's
		-- own VeryLazy load.
		local function page(direction)
			return function()
				local step = STEP_BY_FILETYPE[vim.bo.filetype] or STEP
				-- duration stays short on purpose: neoscroll emits one WinScrolled
				-- per animation frame, and colorizer/todo/markdown/indent/ui-touch
				-- all debounce on that event.
				neoscroll.scroll(direction * step, { move_cursor = true, duration = 10 })
			end
		end

		local modes = { "n", "v", "x" }
		vim.keymap.set(modes, "<PageUp>", page(-1), { desc = "Scroll up (quarter window)" })
		vim.keymap.set(modes, "<PageDown>", page(1), { desc = "Scroll down (quarter window)" })
	end,
}
