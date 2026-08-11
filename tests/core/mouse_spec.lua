-- Tests for lua/core/mouse.lua — the missed-row guard shared by the two
-- explorers that open a row on click (neo-tree, diffview's file panels).
-- Mouse events can't be synthesized headless, so everything drives the
-- clicked_line(winid, mp) seam with a getmousepos()-shaped table.

local mouse = require("core.mouse")

describe("core.mouse", function()
	-- A real window over a real buffer: the helper reads getwininfo(), so the
	-- geometry has to exist for the row math to mean anything.
	local function make_win(lines)
		vim.cmd("vsplit | enew")
		local buf = vim.api.nvim_get_current_buf()
		local win = vim.api.nvim_get_current_win()
		vim.bo[buf].buftype = "nofile"
		vim.wo[win].wrap = false
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		return buf, win
	end

	local function mp(win, winrow)
		return { winid = win, winrow = winrow }
	end

	before_each(function()
		vim.cmd("only")
	end)

	it("maps a screen row onto its buffer line", function()
		local _, win = make_win({ "a", "b", "c" })
		assert.are.equal(1, mouse.clicked_line(win, mp(win, 1)))
		assert.are.equal(3, mouse.clicked_line(win, mp(win, 3)))
	end)

	-- The whole reason this helper exists: getmousepos().line CLAMPS to the last
	-- buffer line, so a click on the empty space below the last row would open
	-- that row's file. The true row comes from the window geometry instead.
	it("returns nil past the last line instead of clamping to it", function()
		local _, win = make_win({ "a", "b", "c" })
		assert.is_nil(mouse.clicked_line(win, mp(win, 4)))
		assert.is_nil(mouse.clicked_line(win, mp(win, 40)))
	end)

	it("offsets by the winbar, and ignores a click on the winbar itself", function()
		local _, win = make_win({ "a", "b", "c" })
		vim.wo[win].winbar = "explorer"
		-- Screen row 1 is now the winbar; the first text row is 2.
		assert.is_nil(mouse.clicked_line(win, mp(win, 1)))
		assert.are.equal(1, mouse.clicked_line(win, mp(win, 2)))
		assert.are.equal(2, mouse.clicked_line(win, mp(win, 3)))
		vim.wo[win].winbar = ""
	end)

	-- A click that started in the panel but was released elsewhere (or a
	-- handler firing for the wrong window) must not act on a foreign row.
	it("returns nil when the pointer is in another window", function()
		local _, win = make_win({ "a", "b", "c" })
		local other = vim.api.nvim_get_current_win()
		vim.cmd("split")
		other = vim.api.nvim_get_current_win()
		assert.are_not.equal(win, other)
		assert.is_nil(mouse.clicked_line(win, mp(other, 1)))
	end)

	it("returns nil for a window that no longer exists", function()
		local _, win = make_win({ "a", "b", "c" })
		local pos = mp(win, 1)
		vim.api.nvim_win_close(win, true)
		assert.is_nil(mouse.clicked_line(win, pos))
	end)

	-- A scrolled explorer: the row is topline-relative, not buffer-absolute.
	it("counts from topline, not from the top of the buffer", function()
		local lines = {}
		for i = 1, 200 do
			lines[i] = "row " .. i
		end
		local _, win = make_win(lines)
		vim.api.nvim_win_set_cursor(win, { 120, 0 })
		vim.cmd("normal! zt") -- put line 120 at the top of the window
		local topline = vim.fn.getwininfo(win)[1].topline
		assert.are.equal(topline, mouse.clicked_line(win, mp(win, 1)))
		assert.are.equal(topline + 2, mouse.clicked_line(win, mp(win, 3)))
	end)
end)
