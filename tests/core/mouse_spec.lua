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

	-- ─── Click, never drag-select ─────────────────────────────────────────────

	describe("in_text_area", function()
		it("is true for a pointer over real text", function()
			local _, win = make_win({ "a", "b", "c" })
			assert.is_true(mouse.in_text_area(win, { winid = win, line = 2 }))
		end)

		-- :h getmousepos() — on a status line or the vertical separator right of
		-- a window, `line`/`column` are ZERO while winid still names the window.
		it("is false on the separator / status line, where line is 0", function()
			local _, win = make_win({ "a", "b", "c" })
			assert.is_false(mouse.in_text_area(win, { winid = win, line = 0 }))
		end)

		-- The load-bearing half, and the non-obvious one. During a separator
		-- resize-drag the pointer leaves this window, so getmousepos() reports the
		-- NEIGHBOUR (with an ordinary line number) while the mapping still
		-- resolves against this buffer. Falling through there is what keeps
		-- resize working: a real-PTY probe resized 39 -> 54 columns with this
		-- predicate and stayed stuck at 39 with a `line == 0`-only predicate.
		it("is false when the pointer is over another window", function()
			local _, win = make_win({ "a", "b", "c" })
			vim.cmd("split")
			local other = vim.api.nvim_get_current_win()
			assert.are_not.equal(win, other)
			assert.is_false(mouse.in_text_area(win, { winid = other, line = 2 }))
		end)
	end)

	describe("lock_selection", function()
		local function maps_of(buf)
			local by_lhs = {}
			for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
				by_lhs[m.lhs] = m
			end
			return by_lhs
		end

		it("locks every selection gesture, buffer-locally", function()
			local buf = make_win({ "a", "b", "c" })
			mouse.lock_selection(buf)
			local by_lhs = maps_of(buf)
			assert.is_true(#mouse.SELECT_KEYS > 0)
			for _, key in ipairs(mouse.SELECT_KEYS) do
				assert.is_not_nil(by_lhs[key], key .. " should be locked")
			end
		end)

		-- <2-LeftMouse> is the explorers' own double-click open. Locking it here
		-- would silently disable "double" mode in :NvSinnerMenu → Explorer click.
		it("leaves the explorers' own double-click alone", function()
			assert.is_not.same({}, mouse.SELECT_KEYS)
			for _, key in ipairs(mouse.SELECT_KEYS) do
				assert.are_not.equal("<2-LeftMouse>", key)
			end
		end)

		-- replace_keycodes is load-bearing, not decorative: the fallthrough
		-- returns the literal "<LeftDrag>" string, and without translation it is
		-- fed through as text — the separator resize-drag dies SILENTLY.
		it("maps them as noremap expr with replace_keycodes and a desc", function()
			local buf = make_win({ "a", "b", "c" })
			mouse.lock_selection(buf)
			local by_lhs = maps_of(buf)
			for _, key in ipairs(mouse.SELECT_KEYS) do
				local m = by_lhs[key]
				assert.are.equal(1, m.expr, key .. " must be an expr map")
				assert.are.equal(1, m.replace_keycodes, key .. " must replace keycodes")
				assert.are.equal(1, m.noremap, key .. " must not remap its own result")
				assert.is_true(type(m.desc) == "string" and #m.desc > 0, key .. " needs a desc")
			end
		end)

		-- The behavioural core: swallow inside the text area, fall through to the
		-- BUILTIN anywhere else so a drag begun on the border still resizes.
		it("swallows a drag over text and falls through elsewhere", function()
			local buf, win = make_win({ "a", "b", "c" })
			mouse.lock_selection(buf)
			local rhs = maps_of(buf)["<LeftDrag>"].callback

			local real = vim.fn.getmousepos
			vim.fn.getmousepos = function()
				return { winid = win, line = 2 }
			end
			local inside = rhs()
			vim.fn.getmousepos = function()
				return { winid = win, line = 0 } -- the separator
			end
			local border = rhs()
			vim.fn.getmousepos = real

			assert.are.equal("", inside, "a drag over rows must select nothing")
			assert.are.equal("<LeftDrag>", border, "a drag from the border must still resize")
		end)
	end)
end)
