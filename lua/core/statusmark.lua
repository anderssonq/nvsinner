-- Statusline shimmer + the centered identity mark "‹ NvSinner ▏<project> ›".
-- Every gray text segment of the bar (branch, project, filename, the mark,
-- filetype, progress) carries a subtle shimmer: ONE slightly brighter band
-- sweeps the whole bar left→right now and then — the terminal cousin of a web
-- "shimmer-text" loading label. Colored chips and icons (mode, location,
-- diagnostics, devicons) keep their semantic colors and are skipped.
--
-- Rendering is split from lualine on purpose. lualine builds the statusline in
-- Lua and stores the result as a LITERAL string (it does not escape function
-- component output). Each wrapped component's `fmt` (M.fmt) stashes the
-- component's text here and hands lualine a %{%…%} expression (M.expr) that
-- Neovim re-evaluates on every statusline repaint. Animating therefore costs
-- one statusline-row repaint per frame (nvim__redraw), never a lualine refresh.
--
-- Loaded by lua/plugins/ui/lualine.lua (NOT from init.lua): the shimmer only
-- exists when lualine does.
local M = {}

local uv = vim.uv

-- Below this many columns the mark is hidden (lualine `cond`) and the project
-- name falls back to the left-hand component — both read this one constant.
M.MIN_COLUMNS = 120

-- Shimmer tunables. The band travels at SPEED cells/s, so a sweep lasts as long
-- as the bar is wide (M.sweep_ms); frames repaint every FRAME_MS; between
-- sweeps the timer sleeps REST_MS with zero wakeups. REST_MS = 0 = continuous.
M.SPEED = 30
M.FRAME_MS = 50
M.REST_MS = 2600
-- Half-width of the bright band, in cells.
M.BAND = 5
-- Brightness steps: NvStatusMark1 (rest) … NvStatusMark<LEVELS> (peak).
M.LEVELS = 5
-- The rest tone sits this far from base03 toward base04: close to the bar's
-- body gray, so the text stays readable. The peak IS base04, so the band never
-- outshines ordinary body text.
M.REST_MIX = 0.6

M.PREFIX = "‹ NvSinner ▏"
M.SUFFIX = " ›"

-- Mix `fg` into `bg` at `alpha`, per channel (same helper as ai-edits.lua).
local function mix(bg, fg, alpha)
	local function ch(i)
		local b = tonumber(bg:sub(i, i + 1), 16)
		local f = tonumber(fg:sub(i, i + 1), 16)
		return math.floor(b + (f - b) * alpha + 0.5)
	end
	return string.format("#%02x%02x%02x", ch(2), ch(4), ch(6))
end

--- Highlight group for a brightness level.
function M.group(level)
	return "NvStatusMark" .. level
end

-- Roles only: rest = base03→base04 at REST_MIX, peak = base04. bg is base00,
-- the surface lualine paints sections b/c (and their x/y mirrors) on.
local function apply_hl()
	local c = require("core.carbon").colors()
	local rest = mix(c.base03, c.base04, M.REST_MIX)
	for level = 1, M.LEVELS do
		local fg = mix(rest, c.base04, (level - 1) / (M.LEVELS - 1))
		vim.api.nvim_set_hl(0, M.group(level), { fg = fg, bg = c.base00, italic = true })
	end
end
apply_hl()
vim.api.nvim_create_autocmd("ColorScheme", {
	group = vim.api.nvim_create_augroup("NvStatusMarkHl", { clear = true }),
	pattern = "*",
	callback = apply_hl,
})

--- The mark's plain text (its lualine component body). The name comes from
--- core/project.lua, which caches the root lookup until DirChanged.
function M.text()
	return M.PREFIX .. require("core.project").name() .. M.SUFFIX
end

--- Sweep duration for a bar of `n` shimmering cells: the band enters fully
--- off the left edge and leaves fully off the right one.
function M.sweep_ms(n)
	return (n + 2 * M.BAND) / M.SPEED * 1000
end

-- Band centre (in cells) `t` ms into a sweep over `n` cells; nil = resting.
local function band_pos(n, t)
	if not t or t < 0 or t >= M.sweep_ms(n) then
		return nil
	end
	return -M.BAND + M.SPEED * t / 1000
end

-- Level of cell `i` for band centre `p`: linear falloff, smoothstepped.
local function level_at(i, p)
	if not p then
		return 1
	end
	local x = math.max(0, 1 - math.abs(i - p) / M.BAND)
	x = x * x * (3 - 2 * x)
	return 1 + math.floor(x * (M.LEVELS - 1) + 0.5)
end

--- Brightness level (1..LEVELS) of each of `n` cells `t` ms into a sweep.
--- Pure — the test seam for the frame math.
function M._levels(n, t)
	local p, out = band_pos(n, t), {}
	for i = 1, n do
		out[i] = level_at(i, p)
	end
	return out
end

-- ── Segments ─────────────────────────────────────────────────────────────
-- seg id → { chars = codepoints }, written by M.fmt on each lualine refresh.
M._segs = {}

-- One evaluation pass of the statusline calls M.seg for the visible segments
-- in layout order (ids ascend left→right), so a repeated-or-lower id means a
-- new pass began. `offset` is the running cell position that stitches the
-- segments into one virtual line; `total` is the previous pass's width (the
-- sweep length). Gaps between segments (icons, chips, the %= fill) are not
-- counted: the band glides over the text and hops the gaps.
local pass = { last = math.huge, offset = 0, total = 0 }

-- uv.now() at the start of the running sweep; nil while resting.
M._sweep_t0 = nil

--- Statusline expression for segment `id`.
function M.expr(id)
	return "%{%v:lua.require'core.statusmark'.seg(" .. id .. ")%}"
end

--- lualine `fmt` for segment `id`: stash the component's text and hand
--- lualine the expression instead. The text is run through
--- nvim_eval_statusline first, which both un-escapes lualine's `%%` and
--- resolves components that ARE statusline items (progress is `%3P`), so the
--- stash holds exactly what the component would have drawn.
function M.fmt(id)
	return function(str)
		local ok, res = pcall(vim.api.nvim_eval_statusline, str, {})
		M._segs[id] = { chars = vim.fn.split(ok and res.str or str, "\\zs") }
		return M.expr(id)
	end
end

--- Markup for segment `id` in the current frame: runs of same-level cells,
--- each behind its own %#group#. At rest that is one group around the text.
--- `%` is escaped because %{%…%} re-parses its result as statusline items.
function M.seg(id)
	local s = M._segs[id]
	if not s or #s.chars == 0 then
		return ""
	end
	if id <= pass.last then
		pass.total, pass.offset = pass.offset, 0
	end
	pass.last = id
	local start = pass.offset
	pass.offset = start + #s.chars

	local n = math.max(pass.total, pass.offset)
	local p = band_pos(n, M._sweep_t0 and (uv.now() - M._sweep_t0) or nil)
	local out, run, cur = {}, {}, nil
	local function flush()
		if cur then
			out[#out + 1] = "%#" .. M.group(cur) .. "#" .. table.concat(run)
		end
	end
	for i, ch in ipairs(s.chars) do
		local level = level_at(start + i, p)
		if level ~= cur then
			flush()
			cur, run = level, {}
		end
		run[#run + 1] = ch == "%" and "%%" or ch
	end
	flush()
	return table.concat(out)
end

--- lualine `on_click` for the mark: open the command palette (left button).
function M.click(_, button)
	if button == "l" then
		vim.cmd("NvSinnerHelp")
	end
end

--- Build a lualine `on_click` that runs the normal-mode map `lhs` on a left
--- click (the statusline icons: `<leader>t` terminal, `<leader>xa` agents).
--- The map's callback is called directly — never fed as keys, which would pay
--- the 'timeoutlen' wait of maps that prefix others (`<leader>t2`..). A `<cmd>`
--- string rhs is executed too. Silent no-op when the map does not exist.
function M.map_click(lhs)
	return function(_, button)
		if button ~= "l" then
			return
		end
		local map = vim.fn.maparg(lhs, "n", false, true)
		if type(map.callback) == "function" then
			map.callback()
		elseif type(map.rhs) == "string" then
			local cmd = map.rhs:match("^<[Cc][Mm][Dd]>(.-)<[Cc][Rr]>$")
			if cmd then
				vim.cmd(cmd)
			end
		end
	end
end

M.terminal_click = M.map_click("<leader>t")
M.agents_click = M.map_click("<leader>xa")

-- ── Loop ─────────────────────────────────────────────────────────────────
-- Repaint the statusline row only. nvim__redraw, not :redrawstatus — the
-- latter misses repaints while focus is inside a terminal (ai-activity.lua).
local function redraw()
	if not pcall(vim.api.nvim__redraw, { statusline = true, flush = true }) then
		pcall(vim.cmd, "redrawstatus")
	end
end

M._running = false

local rest, begin_sweep

local function tick()
	if not M._running or not M._sweep_t0 then
		return
	end
	if uv.now() - M._sweep_t0 >= M.sweep_ms(pass.total) then
		M._sweep_t0 = nil
		redraw() -- the final rest frame
		rest()
		return
	end
	-- Skip while the cmdline is active; the next frame catches up.
	if vim.fn.mode() ~= "c" then
		redraw()
	end
end

-- Sleep REST_MS as a one-shot: no wakeups between sweeps.
function rest()
	M._timer:stop()
	M._timer:start(M.REST_MS, 0, vim.schedule_wrap(begin_sweep))
end

function begin_sweep()
	if not M._running then
		return
	end
	M._sweep_t0 = uv.now()
	M._timer:stop()
	M._timer:start(0, M.FRAME_MS, vim.schedule_wrap(tick))
end

--- Start the shimmer loop. No-op headless (the suite and the installer's
--- headless boot never run timers) and when already running.
function M.start()
	if M._running or #vim.api.nvim_list_uis() == 0 then
		return
	end
	-- Anchored on the module table so luv cannot GC an active handle.
	M._timer = M._timer or uv.new_timer()
	M._running = true
	rest()
end

--- Stop the loop and settle on the rest frame.
function M.stop()
	M._running = false
	M._sweep_t0 = nil
	if M._timer then
		M._timer:stop()
	end
	redraw()
end

--- Test seam: stop the loop, forget every segment and the pass state.
function M._reset()
	M.stop()
	M._segs = {}
	pass.last, pass.offset, pass.total = math.huge, 0, 0
end

-- An unfocused editor has nobody watching: park the loop until focus returns.
local aug = vim.api.nvim_create_augroup("NvStatusMark", { clear = true })
vim.api.nvim_create_autocmd("FocusLost", { group = aug, callback = M.stop })
vim.api.nvim_create_autocmd("FocusGained", { group = aug, callback = M.start })
vim.api.nvim_create_autocmd("VimLeavePre", { group = aug, callback = M.stop })

return M
