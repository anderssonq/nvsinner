-- core/slide.lua: the panel slide-in.
--
-- The suite is headless, where slide.open() deliberately snaps (no UI → no
-- animation, so every other spec stays deterministic). These tests force the
-- animated path through the `_has_ui` seam plus a stand-in mini.animate entry
-- in package.loaded, and drive the module's REAL vim.uv timer, sampling the
-- panel size with vim.wait.

local slide = require("core.slide")

local function size(win, dim)
	return dim == "height" and vim.api.nvim_win_get_height(win) or vim.api.nvim_win_get_width(win)
end

-- Every non-floating window of the current tab → "WxH".
local function layout_sizes()
	local out = {}
	for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if vim.api.nvim_win_get_config(w).relative == "" then
			out[w] = vim.api.nvim_win_get_width(w) .. "x" .. vim.api.nvim_win_get_height(w)
		end
	end
	return out
end

-- Run a slide to completion, sampling the size every ms.
local function run(win, dim)
	local samples = {}
	local t0 = vim.uv.hrtime()
	local anim = slide.open(win, dim)
	assert.is_not_nil(anim, "the forced-UI path must animate")
	table.insert(samples, size(win, dim))
	local done_ms
	vim.wait(400, function()
		if vim.api.nvim_win_is_valid(win) then
			table.insert(samples, size(win, dim))
		end
		if anim.done then
			done_ms = (vim.uv.hrtime() - t0) / 1e6
			return true
		end
		return false
	end, 1)
	return samples, done_ms, anim
end

local function assert_monotonic(samples)
	for i = 2, #samples do
		assert.is_true(samples[i] >= samples[i - 1], "size went backwards: " .. vim.inspect(samples))
	end
end

describe("core.slide", function()
	local saved_ui, saved_mini, saved_flag

	before_each(function()
		saved_ui, saved_mini, saved_flag = slide._has_ui, package.loaded["mini.animate"], vim.g.minianimate_disable
		slide._has_ui = function()
			return true
		end
		package.loaded["mini.animate"] = saved_mini or {}
		vim.g.minianimate_disable = nil
		vim.cmd("silent! only!")
	end)

	after_each(function()
		for _, w in ipairs(vim.api.nvim_list_wins()) do
			slide.stop(w)
		end
		slide._has_ui = saved_ui
		package.loaded["mini.animate"] = saved_mini
		vim.g.minianimate_disable = saved_flag
		vim.cmd("silent! only!")
	end)

	describe("_size_at (the eased curve)", function()
		it("starts at `from`, ends exactly at `to`, never goes backwards", function()
			local prev = slide._size_at(1, 50, 0)
			assert.are.equal(1, prev)
			for i = 1, 100 do
				local s = slide._size_at(1, 50, i / 100)
				assert.is_true(s >= prev and s <= 50)
				prev = s
			end
			assert.are.equal(50, slide._size_at(1, 50, 1))
			assert.are.equal(50, slide._size_at(1, 50, 1.7))
		end)

		it("eases out (more than half the way at half the time)", function()
			assert.is_true(slide._size_at(1, 51, 0.5) > 26)
		end)
	end)

	describe("an animated slide", function()
		it("grows a right column from <=2 cells to its target, monotonically, within 150ms", function()
			vim.cmd("vsplit") -- two editor windows + the panel: neighbours must settle back
			vim.cmd("botright vsplit")
			local panel = vim.api.nvim_get_current_win()
			vim.api.nvim_win_set_width(panel, 30)
			local before = layout_sizes()
			local cur = vim.api.nvim_get_current_win()

			local samples, done_ms, anim = run(panel, "width")

			assert.is_true(samples[1] <= 2, "starts collapsed: " .. vim.inspect(samples))
			assert_monotonic(samples)
			assert.are.equal(30, samples[#samples])
			assert.is_true(#samples > 3, "intermediate frames were painted")
			assert.is_true(done_ms <= 150 + 50, ("finished in %.1f ms"):format(done_ms))
			assert.are.same(before, layout_sizes(), "every window ends where the plugin left it")
			assert.are.equal(cur, vim.api.nvim_get_current_win(), "a slide never moves focus")
			assert.is_true(anim.timer:is_closing(), "the one timer is closed on finish")
			assert.are.equal(0, slide._count())
		end)

		it("grows a bottom panel along its height", function()
			vim.cmd("botright split")
			local panel = vim.api.nvim_get_current_win()
			vim.api.nvim_win_set_height(panel, 8)
			local before = layout_sizes()

			local samples = run(panel, "height")

			assert.is_true(samples[1] <= 2, vim.inspect(samples))
			assert_monotonic(samples)
			assert.are.equal(8, samples[#samples])
			assert.are.same(before, layout_sizes())
		end)

		-- mini-animate.lua's predicates read busy(): true for the sliding
		-- window while it runs, and globally for the GRACE tail (the WinScrolled
		-- of the last frame lands after it).
		it("reports busy while running, then releases mini.animate", function()
			vim.cmd("botright vsplit")
			local panel = vim.api.nvim_get_current_win()
			vim.api.nvim_win_set_width(panel, 30)
			local anim = slide.open(panel, "width")
			assert.is_true(slide.busy(panel))
			assert.is_true(slide.busy())
			assert.is_false(slide.busy(vim.fn.win_getid(1)), "the editor window is not the one sliding")
			vim.wait(400, function()
				return anim.done
			end, 5)
			assert.is_false(slide.busy(panel))
			vim.wait(slide.GRACE + 40)
			assert.is_false(slide.busy())
		end)
	end)

	describe("snaps instead of sliding", function()
		local function panel30()
			vim.cmd("botright vsplit")
			local panel = vim.api.nvim_get_current_win()
			vim.api.nvim_win_set_width(panel, 30)
			return panel
		end

		it("when vim.g.minianimate_disable is set (the Animations switch)", function()
			local panel = panel30()
			vim.g.minianimate_disable = true
			assert.is_nil(slide.open(panel, "width"))
			assert.are.equal(30, vim.api.nvim_win_get_width(panel), "opens at full size in one step")
			assert.are.equal(0, slide._count())
		end)

		it("when b:minianimate_disable is set on the panel's buffer", function()
			local panel = panel30()
			vim.b[vim.api.nvim_win_get_buf(panel)].minianimate_disable = true
			assert.is_nil(slide.open(panel, "width"))
			assert.are.equal(30, vim.api.nvim_win_get_width(panel))
			vim.b[vim.api.nvim_win_get_buf(panel)].minianimate_disable = nil
		end)

		it("when mini.animate is not loaded", function()
			local panel = panel30()
			package.loaded["mini.animate"] = nil
			assert.is_nil(slide.open(panel, "width"))
			assert.are.equal(30, vim.api.nvim_win_get_width(panel))
		end)

		it("headless (the real _has_ui)", function()
			local panel = panel30()
			slide._has_ui = saved_ui
			assert.is_nil(slide.open(panel, "width"))
			assert.are.equal(30, vim.api.nvim_win_get_width(panel))
		end)

		it("for floats and bad arguments", function()
			local buf = vim.api.nvim_create_buf(false, true)
			local float =
				vim.api.nvim_open_win(buf, false, { relative = "editor", row = 1, col = 1, width = 20, height = 5 })
			assert.is_nil(slide.open(float, "width"))
			vim.api.nvim_win_close(float, true)
			assert.is_nil(slide.open(float, "width"), "an invalid window is a no-op, not an error")
			assert.is_nil(slide.open(vim.api.nvim_get_current_win(), "depth"))
		end)
	end)

	-- The AI-column bug: Neovim resizes a terminal's PTY to its window, and the
	-- terminal does NOT reflow its visible screen back after a shrink, so a
	-- width slide (1 → 50 cols) cut every visible line down and sent the CLI a
	-- SIGWINCH per frame. A real job here logs `stty size` on every SIGWINCH
	-- and prints known lines; after the slide the screen must be intact and
	-- the PTY must never have seen any width but the final one.
	describe("a terminal window sliding along its width", function()
		local log, job, term_buf

		local function read_log()
			if vim.fn.filereadable(log) == 0 then
				return {}
			end
			return vim.tbl_filter(function(l)
				return l ~= ""
			end, vim.fn.readfile(log))
		end

		local function screen(buf)
			local out = {}
			for _, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
				l = l:gsub("%s+$", "")
				if l ~= "" then
					table.insert(out, l)
				end
			end
			return out
		end

		before_each(function()
			log = vim.fn.tempname()
			vim.cmd("botright vsplit")
			vim.api.nvim_win_set_width(0, 50)
			vim.cmd("enew")
			term_buf = vim.api.nvim_get_current_buf()
			local script = table.concat({
				[[stty size >> "$SLIDE_LOG"]],
				[[trap 'stty size >> "$SLIDE_LOG"' WINCH]],
				[[i=1; while [ $i -le 6 ]; do printf 'row-%d-abcdefghijklmnopqrstuvwxyz0123456789\n' $i; i=$((i+1)); done]],
				[[while :; do sleep 0.05; done]],
			}, "\n")
			job = vim.fn.jobstart({ "sh", "-c", script }, { term = true, env = { SLIDE_LOG = log } })
			assert.is_true(job > 0)
			assert.is_true(
				vim.wait(3000, function()
					return #read_log() >= 1
						and vim.tbl_contains(screen(term_buf), "row-6-abcdefghijklmnopqrstuvwxyz0123456789")
				end, 10),
				"the job printed its rows and logged its starting size"
			)
		end)

		after_each(function()
			pcall(vim.fn.jobstop, job)
			if vim.api.nvim_buf_is_valid(term_buf) then
				vim.api.nvim_buf_delete(term_buf, { force = true })
			end
			vim.fn.delete(log)
		end)

		it("keeps the screen intact and shows the PTY only the final width", function()
			local win = vim.api.nvim_get_current_win()
			local start = read_log()[1]
			local before = screen(term_buf)
			local anim = slide.open(win, "width")
			assert.is_not_nil(anim, "the forced-UI path animates")
			assert.is_true(vim.wait(400, function()
				return anim.done
			end, 5))
			vim.wait(300) -- let any late SIGWINCH reach the trap, and the screen refresh

			assert.are.equal(term_buf, vim.api.nvim_win_get_buf(win), "the terminal is back in its window")
			assert.are.equal(50, vim.api.nvim_win_get_width(win))
			assert.are.equal(win, vim.api.nvim_get_current_win(), "focus never moved")
			assert.are.same(before, screen(term_buf), "no visible line was cut by the slide")
			for _, logged in ipairs(read_log()) do
				assert.are.equal(start, logged, "the PTY saw an intermediate size: " .. vim.inspect(read_log()))
			end
			assert.are.equal(0, slide._count())
		end)

		it("slides a wiped, unlisted scratch placeholder dressed like the column", function()
			local win = vim.api.nvim_get_current_win()
			vim.wo[win].winhighlight = "Normal:NvFocusNormal"
			local anim = slide.open(win, "width")
			local ph = vim.api.nvim_win_get_buf(win)
			assert.are_not.equal(term_buf, ph, "the terminal left the window while it slides")
			assert.are.equal("nofile", vim.bo[ph].buftype)
			assert.are.equal("wipe", vim.bo[ph].bufhidden)
			assert.is_false(vim.bo[ph].buflisted)
			assert.is_false(vim.bo[ph].swapfile)
			assert.is_false(vim.bo[ph].modifiable)
			assert.are.equal("Normal:NvFocusNormal", vim.wo[win].winhighlight)
			assert.are.equal(term_buf, anim.held.term)
			vim.wait(400, function()
				return anim.done
			end, 5)
			assert.are.equal(term_buf, vim.api.nvim_win_get_buf(win))
			assert.is_false(vim.api.nvim_buf_is_valid(ph), "the placeholder is wiped")
			assert.are.equal("Normal:NvFocusNormal", vim.wo[win].winhighlight)
		end)

		it("lands at the target and puts the terminal back on every early exit", function()
			local win = vim.api.nvim_get_current_win()
			slide.open(win, "width")
			vim.wait(30)
			slide.stop(win)
			assert.are.equal(term_buf, vim.api.nvim_win_get_buf(win))
			assert.are.equal(50, vim.api.nvim_win_get_width(win))

			slide.open(win, "width")
			slide.release(term_buf) -- toggleterm's way: "give me my column back"
			assert.are.equal(term_buf, vim.api.nvim_win_get_buf(win))
			assert.are.equal(50, vim.api.nvim_win_get_width(win))

			slide.open(win, "width")
			vim.wait(30)
			vim.cmd("wincmd t | split") -- layout interruption
			vim.wait(slide.DURATION + 60)
			assert.are.equal(term_buf, vim.api.nvim_win_get_buf(win))
			assert.are.equal(50, vim.api.nvim_win_get_width(win))
			assert.are.equal(0, slide._count())
		end)

		it("leaves the terminal hidden and alive when the window closes mid-slide", function()
			local win = vim.api.nvim_get_current_win()
			local anim = slide.open(win, "width")
			local ph = vim.api.nvim_win_get_buf(win)
			vim.wait(30)
			vim.api.nvim_win_close(win, true)
			vim.wait(slide.DURATION + 60)
			assert.is_true(anim.done)
			assert.is_false(vim.api.nvim_buf_is_valid(ph))
			assert.is_true(vim.api.nvim_buf_is_valid(term_buf))
			assert.are.equal(-1, vim.fn.jobwait({ job }, 0)[1], "the CLI keeps running")
		end)

		it("keeps the terminal in place for a height slide (verified safe)", function()
			vim.cmd("split")
			local win = vim.api.nvim_get_current_win()
			vim.api.nvim_win_set_buf(win, term_buf)
			local anim = slide.open(win, "height")
			assert.are.equal(term_buf, vim.api.nvim_win_get_buf(win))
			assert.is_nil(anim.held)
			vim.wait(400, function()
				return anim.done
			end, 5)
		end)

		local function pty_only_saw(start)
			for _, logged in ipairs(read_log()) do
				assert.are.equal(start, logged, "the PTY saw an intermediate size: " .. vim.inspect(read_log()))
			end
		end

		-- Entering the column mid-slide raises it to 'winwidth' (20). That is
		-- Neovim, not a foreign resize: the slide must keep going, and in any
		-- case the terminal may only come back at the target width.
		it("lands at the target when the column is entered mid-slide ('winwidth')", function()
			local win = vim.api.nvim_get_current_win()
			local start = read_log()[1]
			local before = screen(term_buf)
			vim.o.winwidth = 20
			local anim = slide.open(win, "width")
			vim.wait(20)
			vim.cmd("wincmd p")
			vim.cmd("wincmd p")
			vim.wait(400, function()
				return anim.done
			end, 5)
			vim.wait(300)
			assert.are.equal(win, vim.api.nvim_get_current_win())
			assert.are.equal(term_buf, vim.api.nvim_win_get_buf(win))
			assert.are.equal(50, vim.api.nvim_win_get_width(win))
			assert.are.same(before, screen(term_buf))
			pty_only_saw(start)
		end)

		-- A refused swap-back (the cmdline window refuses with E11; headless
		-- stand-in: 'winfixbuf', E1513) must keep the hold visible to release()
		-- and held_term(), retry until it lands, and only then run on_done.
		it("keeps a refused swap-back pending, retries it, and runs on_done after", function()
			local win = vim.api.nvim_get_current_win()
			local done = 0
			local anim = slide.open(win, "width", {
				on_done = function()
					done = done + 1
				end,
			})
			local ph = vim.api.nvim_win_get_buf(win)
			vim.wo[win].winfixbuf = true
			vim.wait(400, function()
				return anim.done
			end, 5)
			vim.wait(slide.RETRY_MS * 3)
			assert.are.equal(ph, vim.api.nvim_win_get_buf(win), "still refused")
			assert.are.equal(0, done, "on_done waits for the terminal")
			assert.are.equal(term_buf, slide.held_term(ph), "the placeholder still maps to its terminal")
			slide.release(term_buf) -- refused too: must not drop the hold
			assert.are.equal(term_buf, slide.held_term(ph))
			vim.wo[win].winfixbuf = false
			slide.release(term_buf) -- now it can land, synchronously
			assert.are.equal(term_buf, vim.api.nvim_win_get_buf(win))
			assert.are.equal(1, done)
			vim.wait(slide.RETRY_MS * 3)
			assert.are.equal(1, done, "on_done ran once")
			assert.is_nil(slide.held_term(ph))
		end)

		it("retries a refused swap-back on its own once the refusal ends", function()
			local win = vim.api.nvim_get_current_win()
			local anim = slide.open(win, "width")
			vim.wo[win].winfixbuf = true
			vim.wait(400, function()
				return anim.done
			end, 5)
			vim.wait(slide.RETRY_MS * 3)
			vim.wo[win].winfixbuf = false
			assert.is_true(vim.wait(slide.RETRY_MS * 6, function()
				return vim.api.nvim_win_get_buf(win) == term_buf
			end, 5))
			assert.are.equal(50, vim.api.nvim_win_get_width(win))
		end)

		-- <leader>jc / the cockpit's `d` / :bd! wipe the terminal mid-slide:
		-- the column must not stay behind as an ownerless placeholder.
		it("closes the column when its terminal is wiped mid-slide", function()
			local win = vim.api.nvim_get_current_win()
			local anim = slide.open(win, "width")
			vim.wait(20)
			vim.fn.jobstop(job)
			vim.api.nvim_buf_delete(term_buf, { force = true })
			vim.wait(400, function()
				return anim.done
			end, 5)
			vim.wait(40)
			assert.is_false(vim.api.nvim_win_is_valid(win))
		end)

		-- release()/stop() are called right before toggleterm acts on the
		-- column (close, re-show): a BufEnter there makes toggleterm schedule
		-- a `startinsert` that lands in whatever window takes focus next.
		it("swaps back quietly on release() and stop(), even in the focused window", function()
			local win = vim.api.nvim_get_current_win()
			local enters = 0
			local au = vim.api.nvim_create_autocmd("BufEnter", {
				buffer = term_buf,
				callback = function()
					enters = enters + 1
				end,
			})
			slide.open(win, "width")
			slide.release(term_buf)
			assert.are.equal(term_buf, vim.api.nvim_win_get_buf(win))
			slide.open(win, "width")
			slide.stop(win)
			assert.are.equal(term_buf, vim.api.nvim_win_get_buf(win))
			vim.api.nvim_del_autocmd(au)
			assert.are.equal(0, enters)
		end)

		it("swaps back with BufEnter in the focused window on a natural finish", function()
			local win = vim.api.nvim_get_current_win()
			local enters = 0
			local au = vim.api.nvim_create_autocmd("BufEnter", {
				buffer = term_buf,
				callback = function()
					enters = enters + 1
				end,
			})
			local anim = slide.open(win, "width")
			vim.wait(400, function()
				return anim.done
			end, 5)
			vim.api.nvim_del_autocmd(au)
			assert.are.equal(1, enters, "autoreload + toggleterm restore terminal-insert from this")
		end)

		it("swaps back quietly in an unfocused window and replays ui-touch's WinLeave", function()
			local win = vim.api.nvim_get_current_win()
			local enters, left = 0, {}
			local au = vim.api.nvim_create_autocmd("BufEnter", {
				buffer = term_buf,
				callback = function()
					enters = enters + 1
				end,
			})
			local grp = vim.api.nvim_create_augroup("nv_touch", { clear = true })
			vim.api.nvim_create_autocmd("WinLeave", {
				group = grp,
				callback = function()
					table.insert(left, vim.api.nvim_get_current_win())
				end,
			})
			local anim = slide.open(win, "width")
			vim.cmd("wincmd p")
			local other = vim.api.nvim_get_current_win()
			left = {}
			vim.wait(400, function()
				return anim.done
			end, 5)
			vim.api.nvim_del_autocmd(au)
			vim.api.nvim_del_augroup_by_id(grp)
			assert.are.equal(term_buf, vim.api.nvim_win_get_buf(win))
			assert.are.equal(other, vim.api.nvim_get_current_win(), "focus stays where the user put it")
			assert.are.equal(0, enters)
			assert.are.same({ win }, left, "ui-touch dims the column it could not see leave")
		end)

		it("restores 'eventignore' when the swap-in fails, and snaps", function()
			local win = vim.api.nvim_get_current_win()
			local ei = vim.o.eventignore
			vim.wo[win].winfixbuf = true
			assert.is_nil(slide.open(win, "width"))
			vim.wo[win].winfixbuf = false
			assert.are.equal(ei, vim.o.eventignore)
			assert.are.equal(term_buf, vim.api.nvim_win_get_buf(win))
			assert.are.equal(50, vim.api.nvim_win_get_width(win))
		end)

		-- Agent mode: the same terminal shown in a second tab. The PTY size is
		-- the min over every window on the buffer, so a mangled frame here
		-- would damage the other tab's column too.
		it("leaves the same terminal in another tab untouched (agent mode)", function()
			local win = vim.api.nvim_get_current_win()
			vim.cmd("tabnew")
			vim.cmd("botright vsplit")
			vim.api.nvim_win_set_width(0, 60)
			vim.api.nvim_win_set_buf(0, term_buf)
			local other = vim.api.nvim_get_current_win()
			vim.cmd("tabprevious")
			vim.wait(300) -- the tab line and the second window settle the PTY first
			local log0 = read_log()
			local start = log0[#log0]
			local before = screen(term_buf)
			local anim = slide.open(win, "width")
			vim.wait(400, function()
				return anim.done
			end, 5)
			vim.wait(300)
			assert.are.equal(term_buf, vim.api.nvim_win_get_buf(other))
			assert.are.equal(term_buf, vim.api.nvim_win_get_buf(win))
			assert.are.same(before, screen(term_buf))
			local log1 = read_log()
			for i = #log0 + 1, #log1 do
				assert.are.equal(start, log1[i], "the PTY saw an intermediate size: " .. vim.inspect(log1))
			end
			vim.cmd("tabonly!")
		end)
	end)

	describe("on_done", function()
		local function panel(w)
			vim.cmd("botright vsplit")
			local win = vim.api.nvim_get_current_win()
			vim.api.nvim_win_set_width(win, w or 30)
			return win
		end

		it("runs once, with the window at its target, when the slide finishes", function()
			local win = panel()
			local got = {}
			local anim = slide.open(win, "width", {
				on_done = function(w)
					table.insert(got, { w, vim.api.nvim_win_get_width(w) })
				end,
			})
			vim.wait(400, function()
				return anim.done
			end, 5)
			vim.wait(40)
			assert.are.same({ { win, 30 } }, got)
		end)

		it("runs once on an interrupted finish (layout change, stop, replacement)", function()
			local win = panel()
			local n = 0
			local function count()
				n = n + 1
			end
			slide.open(win, "width", { on_done = count })
			vim.wait(30)
			vim.cmd("wincmd t | split")
			vim.wait(slide.DURATION + 60)
			assert.are.equal(1, n)

			slide.open(win, "width", { on_done = count })
			slide.stop(win)
			slide.stop(win)
			assert.are.equal(2, n)

			local second = slide.open(win, "width", { target = 30, on_done = count })
			slide.open(win, "width", 30) -- replaces `second`: its on_done fires
			assert.is_true(second.done)
			assert.are.equal(3, n)
		end)

		it("never runs when the window was closed", function()
			local win = panel()
			local n = 0
			local anim = slide.open(win, "width", {
				on_done = function()
					n = n + 1
				end,
			})
			vim.api.nvim_win_close(win, true)
			vim.wait(slide.DURATION + 60, function()
				return anim.done
			end, 5)
			assert.is_true(anim.done)
			assert.are.equal(0, n)
		end)

		it("never runs for a slide that snapped", function()
			local win = panel()
			vim.g.minianimate_disable = true
			local n = 0
			assert.is_nil(slide.open(win, "width", {
				on_done = function()
					n = n + 1
				end,
			}))
			assert.are.equal(0, n)
		end)
	end)

	-- The final frame restores the tab's sizes; a window the USER resized
	-- while the slide ran keeps the user's size.
	it("does not undo a neighbour resize made mid-slide", function()
		vim.cmd("split") -- two stacked editor windows left of the panel
		local top = vim.api.nvim_get_current_win()
		vim.cmd("botright vsplit")
		local p = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_width(p, 30)
		local anim = slide.open(p, "width")
		vim.wait(30)
		vim.api.nvim_win_set_height(top, 5)
		vim.wait(400, function()
			return anim.done
		end, 5)
		assert.are.equal(5, vim.api.nvim_win_get_height(top))
		assert.are.equal(30, vim.api.nvim_win_get_width(p))
	end)

	describe("stops cleanly", function()
		local function start()
			vim.cmd("botright vsplit")
			local panel = vim.api.nvim_get_current_win()
			vim.api.nvim_win_set_width(panel, 40)
			return panel, slide.open(panel, "width")
		end

		it("when the window closes mid-slide (no error, no timer leak)", function()
			local panel, anim = start()
			vim.wait(30)
			vim.api.nvim_win_close(panel, true)
			vim.wait(slide.DURATION + 60)
			assert.is_true(anim.done)
			assert.is_true(anim.timer:is_closing())
			assert.are.equal(0, slide._count())
		end)

		it("when the layout changes mid-slide: the panel lands at its target", function()
			local panel, anim = start()
			vim.wait(30)
			vim.api.nvim_set_current_win(vim.fn.win_getid(1))
			vim.cmd("split")
			vim.wait(slide.DURATION + 60)
			assert.is_true(anim.done)
			assert.are.equal(40, vim.api.nvim_win_get_width(panel))
			assert.are.equal(0, slide._count())
		end)

		it("when something else resizes the panel: that size wins", function()
			local panel, anim = start()
			vim.wait(30)
			vim.api.nvim_win_set_width(panel, 22)
			vim.wait(slide.DURATION + 60)
			assert.is_true(anim.done)
			assert.are.equal(22, vim.api.nvim_win_get_width(panel))
		end)

		it("when a second slide starts on the same window", function()
			local panel, first = start()
			local second = slide.open(panel, "width", 40)
			assert.is_true(first.done)
			assert.is_true(first.timer:is_closing())
			vim.wait(400, function()
				return second.done
			end, 5)
			assert.are.equal(40, vim.api.nvim_win_get_width(panel))
			assert.are.equal(0, slide._count())
		end)
	end)
end)
