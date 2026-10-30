-- Panel slide-in (native, no deps).
--
-- A freshly opened side/bottom panel — the neo-tree sidebar, an AI column, a
-- <leader>t terminal — grows from START cells to the size its plugin gave it,
-- eased over DURATION ms, instead of snapping. The caller opens the panel
-- exactly as before (size, side, focus, insert mode all set by the plugin),
-- THEN calls `slide.open(win, "width"|"height", opts?)`: the current size is
-- the target, the window is shrunk synchronously (before the next redraw, so
-- the full-size frame is never painted) and a timer grows it back.
--
-- Contracts:
--   * Size only — with ONE exception: a TERMINAL sliding along its WIDTH.
--     Neovim resizes a terminal's PTY to its window on every frame, and the
--     terminal does not reflow its visible screen back after a shrink: the
--     CLI got a SIGWINCH per frame and every visible line was cut to the
--     narrowest width it passed through (and in agent mode the PTY size is
--     the min over every window showing the buffer, so the column in the
--     other tab was damaged too). So for that case the window shows a wiped
--     scratch PLACEHOLDER while it grows (a "hold"), and the terminal buffer
--     goes back into the window when the slide ends — on every exit path
--     where the window survives, and ALWAYS after the window is at its target
--     size. While the terminal buffer is in no window its PTY keeps its last
--     size, so the CLI only ever sees the final width. Height slides keep the
--     terminal (verified safe: 10 → 1 → 10 rows leaves the buffer unchanged).
--   * Terminal focus mode stays core/autoreload.lua's job: the swap-back at
--     the slide's NATURAL end, in the focused window, is an ordinary buffer
--     enter (BufEnter fires, so autoreload + toggleterm schedule the same
--     `startinsert` they run when a column opens without animation). Every
--     other swap — the swap-in, a swap-back in an unfocused window, and the
--     early ones (`stop`, `release`, which run right before a caller acts on
--     the column) — runs with 'eventignore' = all.
--   * A refused swap-back (e.g. while the cmdline window is open) stays a
--     pending hold: `release()` drains it, `held_term()` still maps the
--     placeholder to its terminal, and it is retried until it lands or the
--     window/terminal/placeholder is gone. A terminal wiped mid-slide closes
--     its placeholder column.
--   * The final frame restores the tab's window sizes as they were when the
--     slide started, so neighbours end where the plugin left them. A window
--     the USER resized mid-slide is dropped from that restore: their size
--     wins. `stop`/`release` restore too when the layout is unchanged.
--   * Interrupted cleanly: the window closing, the layout changing (split,
--     close, :resize of the panel, screen resize) or a second slide on the same
--     window stops the animation; one vim.uv timer per slide, closed on finish.
--     Entering the panel mid-slide raises it to 'winwidth'/'winheight': that
--     is Neovim, not a foreign resize, and the slide carries on from there.
--   * `opts.on_done(win)` runs once when the slide ends with the window still
--     valid — after a held terminal is back — never when the window was
--     closed, and never for a slide that snapped (open returned nil).
--   * Off when `vim.g.minianimate_disable` (the :NvSinnerMenu "Animations"
--     switch) or `b:minianimate_disable` is truthy, when mini.animate is not
--     loaded, and with no UI attached (headless: tests stay deterministic).
--   * `busy(win)` is what lua/plugins/ui/mini-animate.lua's predicates read,
--     so mini.animate's open float and its resize easing never run on top of a
--     slide (no double animation).
--   * Zero startup cost: required on demand by the open paths, not init.lua.
local M = {}

M.DURATION = 120 -- ms: same as mini.animate's open/resize timing
-- mini.animate reads resizes on WinScrolled, which Neovim fires on its next
-- main-loop check — AFTER the timer frame that caused it. busy() keeps
-- answering true this long past the last frame so that late event is ignored.
M.GRACE = 60 -- ms
M.RETRY_MS = 50 -- a refused swap-back is retried this often

local INTERVAL = 15 -- ms between frames (~8 frames per slide)
local START = 1 -- cells the panel starts from

local active = {} -- win → running slide (also pins its luv timer against GC)
local holds = {} -- win → terminal held out of it (lives until it is back)
local last_done = -math.huge

-- Seam (tests force the animated path headless).
M._has_ui = function()
	return #vim.api.nvim_list_uis() > 0
end

local function now()
	return vim.uv.hrtime() / 1e6
end

local DIMS = {
	width = { get = vim.api.nvim_win_get_width, set = vim.api.nvim_win_set_width, min = "winwidth" },
	height = { get = vim.api.nvim_win_get_height, set = vim.api.nvim_win_set_height, min = "winheight" },
}

-- Should a panel showing `buf` slide at all?
local function enabled(buf)
	if vim.g.minianimate_disable then
		return false
	end
	if buf and vim.api.nvim_buf_is_valid(buf) and vim.b[buf].minianimate_disable then
		return false
	end
	if not package.loaded["mini.animate"] then
		return false
	end
	return M._has_ui()
end

-- Ease-out cubic: fast start, soft landing.
local function ease(t)
	return 1 - (1 - t) ^ 3
end

--- Size at progress `t` (0..1+) from `from` to `to`. Monotonic in `t`, exactly
--- `to` once `t >= 1`.
function M._size_at(from, to, t)
	if t >= 1 then
		return to
	end
	if t <= 0 then
		return from
	end
	return math.min(to, from + math.floor((to - from) * ease(t) + 0.5))
end

-- Non-floating windows of `tab` → { width, height }.
local function sizes(tab)
	local out = {}
	for _, w in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
		if vim.api.nvim_win_get_config(w).relative == "" then
			out[w] = { width = vim.api.nvim_win_get_width(w), height = vim.api.nvim_win_get_height(w) }
		end
	end
	return out
end

local function layout(tab)
	return vim.fn.winlayout(vim.api.nvim_tabpage_get_number(tab))
end

-- Put every window of the snapshot back at its size. Two passes: setting one
-- window shifts its neighbours, the second pass settles what the first moved.
local function restore(snapshot)
	for _ = 1, 2 do
		local settled = true
		for w, s in pairs(snapshot) do
			if vim.api.nvim_win_is_valid(w) then
				if vim.api.nvim_win_get_width(w) ~= s.width then
					settled = false
					pcall(vim.api.nvim_win_set_width, w, s.width)
				end
				if vim.api.nvim_win_get_height(w) ~= s.height then
					settled = false
					pcall(vim.api.nvim_win_set_height, w, s.height)
				end
			end
		end
		if settled then
			return
		end
	end
end

local function run_on_done(fn, win)
	if not fn then
		return
	end
	local ok, err = pcall(fn, win)
	if not ok then
		vim.notify("core.slide: on_done failed: " .. tostring(err), vim.log.levels.WARN)
	end
end

-- ─── Terminal hold (placeholder) ────────────────────────────────────────────

-- Run `fn` with every autocommand suppressed; 'eventignore' always comes back.
local function quietly(fn)
	local ei = vim.o.eventignore
	vim.o.eventignore = "all"
	local ok, err = pcall(fn)
	vim.o.eventignore = ei
	return ok, err
end

-- 'winfixbuf' is never copied: it would lock the placeholder in.
local SKIP_OPTS = { winfixbuf = true }

-- Every window-local option of `win` → its local value.
local function win_opts(win)
	local out = {}
	for name, info in pairs(vim.api.nvim_get_all_options_info()) do
		if info.scope == "win" and not SKIP_OPTS[name] then
			local ok, v = pcall(vim.api.nvim_get_option_value, name, { win = win, scope = "local" })
			if ok then
				out[name] = v
			end
		end
	end
	return out
end

local function set_win_opts(win, opts)
	for name, v in pairs(opts) do
		pcall(vim.api.nvim_set_option_value, name, v, { win = win, scope = "local" })
	end
end

-- Swap `win`'s terminal buffer for a wiped scratch placeholder dressed like
-- the column (same window options: winhighlight, winbar — so the text area
-- keeps its height — number/sign columns, …). Returns the hold, or nil when
-- the swap failed (the window then still shows the terminal).
local function hold(win)
	local term = vim.api.nvim_win_get_buf(win)
	local opts = win_opts(win)
	local ph
	local ok = quietly(function()
		-- Scratch = nofile, noswapfile, unlisted already. Its other options are
		-- set only once it is IN the window: setting a buffer option on an
		-- undisplayed buffer borrows Neovim's autocmd window, which is created
		-- showing the current buffer — the terminal — at full screen width,
		-- and that alone resized the PTY (measured: 50 → 80 cols).
		ph = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_win_set_buf(win, ph)
		local bo = vim.bo[ph]
		bo.bufhidden = "wipe"
		bo.undolevels = -1
		bo.modifiable = false
		set_win_opts(win, opts)
	end)
	if not ok then
		if ph and vim.api.nvim_buf_is_valid(ph) then
			quietly(function()
				if vim.api.nvim_win_get_buf(win) == ph then
					vim.api.nvim_win_set_buf(win, term)
				end
				vim.api.nvim_buf_delete(ph, { force = true })
			end)
		end
		return nil
	end
	-- The caller already ran `startinsert!` for the terminal (and toggleterm
	-- schedules another): neither may leave Insert mode in the placeholder.
	-- `:stopinsert` drops the pending one; the InsertEnter guard catches a
	-- scheduled one (or an `i` typed mid-slide). The guard must itself be
	-- scheduled — a `:stopinsert` run inside InsertEnter does not take
	-- (probed in an --embed child: mode stayed "i"). The real mode comes
	-- back with the terminal buffer.
	if vim.api.nvim_get_current_win() == win then
		vim.cmd("stopinsert")
	end
	vim.api.nvim_create_autocmd("InsertEnter", {
		buffer = ph,
		callback = function()
			vim.schedule(function()
				if vim.api.nvim_get_current_buf() == ph then
					vim.cmd("stopinsert")
				end
			end)
		end,
	})
	local h = { term = term, placeholder = ph, opts = opts }
	holds[win] = h
	return h
end

-- ui-touch styles a window on WinEnter/WinLeave, and both skip the
-- placeholder (nofile). A column that lost focus mid-slide would come back
-- wearing its focused look: replay ui-touch's own WinLeave for it.
local function restyle_unfocused(win)
	pcall(vim.api.nvim_win_call, win, function()
		vim.api.nvim_exec_autocmds("WinLeave", { group = "nv_touch" })
	end)
end

-- Put the held terminal back into `win`. Returns false only when the switch
-- was refused (the hold stays pending); otherwise the hold is over — the
-- terminal is back, or there is nothing left to put back — and on_done ran if
-- the window survived.
local function unhold(win, h, quiet)
	if holds[win] ~= h then
		return true -- already settled by another path
	end
	if not vim.api.nvim_win_is_valid(win) then
		holds[win] = nil -- window closed: the placeholder was wiped with it
		return true
	end
	local shows_ph = vim.api.nvim_buf_is_valid(h.placeholder) and vim.api.nvim_win_get_buf(win) == h.placeholder
	if not shows_ph then
		holds[win] = nil -- someone put another buffer in the window: theirs wins
		run_on_done(h.on_done, win)
		return true
	end
	if not vim.api.nvim_buf_is_valid(h.term) then
		-- The terminal was wiped mid-slide (<leader>jc, :bd!): an ownerless
		-- placeholder column must not stay behind.
		holds[win] = nil
		pcall(vim.api.nvim_win_close, win, true)
		return true
	end
	local focused = vim.api.nvim_get_current_win() == win
	local ok
	if focused and not quiet then
		-- An ordinary enter: BufEnter lets autoreload/toggleterm restore
		-- terminal-insert exactly as on an unanimated open.
		ok = pcall(vim.api.nvim_win_set_buf, win, h.term)
	else
		-- Quiet: a set_buf on an unfocused window fires its BufEnter with that
		-- window temporarily current, and toggleterm's handler would schedule
		-- an unconditional `startinsert` into the window that really has
		-- focus; an early swap (stop/release) precedes the caller's own move.
		ok = quietly(function()
			vim.api.nvim_win_set_buf(win, h.term)
		end)
	end
	if not ok then
		return false
	end
	holds[win] = nil
	set_win_opts(win, h.opts)
	if not focused then
		restyle_unfocused(win)
	end
	run_on_done(h.on_done, win)
	return true
end

-- Keep retrying a refused swap-back until it lands or the hold is moot
-- (unhold settles it once the window, terminal or placeholder is gone).
local function retry(win, h, quiet)
	vim.defer_fn(function()
		if holds[win] == h and not unhold(win, h, quiet) then
			retry(win, h, quiet)
		end
	end, M.RETRY_MS)
end

-- ─── Lifecycle ──────────────────────────────────────────────────────────────

-- End `anim` once. `how`:
--   land    → put the window at its target first (forced for a held
--             terminal: its PTY may only ever see the target).
--   restore → also put the neighbours back, if the layout is unchanged.
--   quiet   → swap a held terminal back with no events (stop/release).
local function finish(anim, how)
	if anim.done then
		return
	end
	how = how or {}
	anim.done = true
	local timer = anim.timer
	if timer and not timer:is_closing() then
		timer:stop()
		timer:close()
	end
	if active[anim.win] == anim then
		active[anim.win] = nil
	end
	last_done = now()
	local win = anim.win
	local h = anim.held
	if not vim.api.nvim_win_is_valid(win) then
		if h and holds[win] == h then
			holds[win] = nil
		end
		return
	end
	if how.land or h then
		pcall(DIMS[anim.dim].set, win, anim.target)
		local tab_ok = vim.api.nvim_tabpage_is_valid(anim.tab)
		if how.restore and tab_ok and vim.deep_equal(layout(anim.tab), anim.layout) then
			restore(anim.snapshot)
			pcall(DIMS[anim.dim].set, win, anim.target)
		end
	end
	if h then
		h.on_done = anim.on_done -- runs once the terminal is back
		if not unhold(win, h, how.quiet) then
			retry(win, h, how.quiet)
		end
	else
		run_on_done(anim.on_done, win)
	end
end

-- Has something other than this slide changed the layout since the last frame?
local function interrupted(anim)
	if not vim.api.nvim_tabpage_is_valid(anim.tab) then
		return "gone"
	end
	local d = DIMS[anim.dim]
	local size = d.get(anim.win)
	if size ~= anim.last then
		-- Entering the panel raises it to 'winwidth'/'winheight': Neovim's
		-- doing, not a foreign resize. Carry on, never below that floor.
		if
			vim.api.nvim_get_current_win() == anim.win
			and size == math.max(anim.last, vim.o[d.min])
			and size < anim.target
		then
			anim.floor = size
			anim.last = size
			anim.seen = sizes(anim.tab) -- the raise moved the neighbours too
			return nil
		end
		return "resized" -- someone else sized the panel: theirs wins
	end
	if vim.o.lines ~= anim.lines or vim.o.columns ~= anim.columns then
		return "layout"
	end
	if not vim.deep_equal(layout(anim.tab), anim.layout) then
		return "layout"
	end
end

-- A window whose size moved since our last frame was resized by someone else
-- (the user dragging a neighbour, a plugin's :resize): drop it from the final
-- restore so their size survives.
local function forget_foreign(anim)
	for w, s in pairs(sizes(anim.tab)) do
		local seen = anim.seen[w]
		if seen and (seen.width ~= s.width or seen.height ~= s.height) then
			anim.snapshot[w] = nil
		end
	end
end

-- One frame, driven by the slide's own timer.
local function tick(anim)
	if anim.done then
		return
	end
	local win = anim.win
	if not vim.api.nvim_win_is_valid(win) then
		return finish(anim)
	end
	if anim.held and not vim.api.nvim_buf_is_valid(anim.held.term) then
		return finish(anim) -- terminal wiped: unhold closes the column
	end
	local why = interrupted(anim)
	if why then
		-- Structure changed under a panel still mid-slide: land it at its
		-- target rather than leave it half-open. A panel someone else resized
		-- (or a tab that is gone) is left alone — unless it holds a terminal,
		-- which always lands at the target (finish forces it).
		return finish(anim, { land = why == "layout" })
	end
	forget_foreign(anim)
	local size = M._size_at(anim.from, anim.target, (now() - anim.t0) / M.DURATION)
	if size >= anim.target then
		pcall(DIMS[anim.dim].set, win, anim.target)
		restore(anim.snapshot)
		pcall(DIMS[anim.dim].set, win, anim.target)
		return finish(anim)
	end
	pcall(DIMS[anim.dim].set, win, math.max(size, anim.floor or 0))
	anim.last = DIMS[anim.dim].get(win)
	anim.seen = sizes(anim.tab)
end

--- Slide `win` in along `dim` ("width" | "height").
--- `opts` (optional): `{ target = n, on_done = fn(win) }`; a bare number is the
--- target (default: the window's current size — i.e. call this right after the
--- plugin sized the panel).
--- Returns the running slide, or nil when it snapped (disabled, headless, a
--- float, an invalid window, a target too small to animate).
function M.open(win, dim, opts)
	if type(opts) ~= "table" then
		opts = { target = opts }
	end
	local d = DIMS[dim]
	if not (d and win and vim.api.nvim_win_is_valid(win)) then
		return nil
	end
	M.stop(win)
	if vim.api.nvim_win_get_config(win).relative ~= "" then
		return nil
	end
	local buf = vim.api.nvim_win_get_buf(win)
	if not enabled(buf) then
		return nil
	end
	local target = opts.target or d.get(win)
	if target <= START + 1 then
		return nil
	end
	if d.get(win) ~= target and not pcall(d.set, win, target) then
		return nil
	end
	-- A terminal leaves the window BEFORE the first shrink, at its final width.
	local held
	if dim == "width" and vim.bo[buf].buftype == "terminal" then
		held = hold(win)
		if not held then
			return nil -- could not swap: snap rather than mangle the screen
		end
	end
	local tab = vim.api.nvim_win_get_tabpage(win)
	local snapshot = sizes(tab) -- the final layout, restored on the last frame
	if not pcall(d.set, win, START) then
		if held and not unhold(win, held, true) then
			retry(win, held, true)
		end
		return nil
	end
	local from = d.get(win)
	local anim = {
		win = win,
		dim = dim,
		target = target,
		from = from,
		last = from,
		t0 = now(),
		tab = tab,
		snapshot = snapshot,
		seen = sizes(tab),
		layout = layout(tab),
		lines = vim.o.lines,
		columns = vim.o.columns,
		held = held,
		on_done = opts.on_done,
		timer = assert(vim.uv.new_timer()),
	}
	active[win] = anim
	anim.timer:start(
		INTERVAL,
		INTERVAL,
		vim.schedule_wrap(function()
			tick(anim)
		end)
	)
	return anim
end

--- End `win`'s slide now (no-op when none runs): the window lands at its
--- target, the neighbours settle, a held terminal goes back quietly, on_done
--- runs. A swap-back still pending on `win` is retried here too.
function M.stop(win)
	local anim = active[win]
	if anim then
		finish(anim, { land = true, restore = true, quiet = true })
	end
	local h = holds[win]
	if h then
		unhold(win, h, true)
	end
end

--- End every slide holding terminal buffer `buf` out of its window, and drain
--- any swap-back of it still pending — quietly, because the caller (toggleterm,
--- about to close or re-show the column) moves focus itself.
function M.release(buf)
	-- Collect first, then finish: finish → unhold → on_done may open a new
	-- slide, and adding keys to a table mid-`pairs` is undefined in Lua.
	local anims, pending = {}, {}
	for _, anim in pairs(active) do
		if anim.held and anim.held.term == buf then
			anims[#anims + 1] = anim
		end
	end
	for win, h in pairs(holds) do
		if h.term == buf then
			pending[#pending + 1] = { win, h }
		end
	end
	for _, anim in ipairs(anims) do
		finish(anim, { land = true, restore = true, quiet = true })
	end
	for _, p in ipairs(pending) do
		if holds[p[1]] == p[2] then
			unhold(p[1], p[2], true)
		end
	end
end

--- The terminal buffer a placeholder stands in for (nil for any other
--- buffer). Lets toggleterm treat a mid-slide column as the column.
function M.held_term(buf)
	for _, h in pairs(holds) do
		if h.placeholder == buf then
			return h.term
		end
	end
end

--- Is a slide running on `win` — or, with no `win`, anywhere (including the
--- GRACE tail after the last one, see above)?
function M.busy(win)
	if win ~= nil then
		return active[win] ~= nil
	end
	return next(active) ~= nil or (now() - last_done) < M.GRACE
end

--- Number of running slides (tests: timer-leak check).
function M._count()
	local n = 0
	for _ in pairs(active) do
		n = n + 1
	end
	return n
end

return M
