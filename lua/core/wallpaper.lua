-- ─── Dashboard wallpaper ─────────────────────────────────────────────────────
-- One image painted BEHIND the alpha start screen (lua/plugins/ui/dashboard.lua),
-- on by default, gently floating while the dashboard is on screen (see *The
-- float* below). The only knob is on/off: the `wallpaper_on` setting, the
-- *Wallpaper* row in :NvSinnerMenu, and :NvSinnerWallpaper [on|off].
--
-- Zero external dependencies at runtime: the image ships as a small binary PPM
-- (assets/wallpapers/angel.ppm — raw pixels), decoded and resampled here in pure
-- Lua to the window (cover-fit, bilinear), then laid onto the dashboard buffer as
-- extmarks — no float, no image protocol, no process:
--   * blank cells → an overlay virt_text `▄` whose fg/bg are the cell's two
--     pixels (bottom / top), so the image keeps two pixels per cell;
--   * text cells  → the character stays, only its bg becomes the average of the
--     two pixels (alpha's own fg highlight still applies). A lone space between
--     two text characters counts as text, so a label like "Find file" sits on
--     one patch and the hover pill (priority 1000) is never cut;
--   * pure-black pixels are TRANSPARENT (M.KEY_MAX): a cell black on both halves
--     gets no mark, so the window's real Normal bg shows under any theme.
-- Colours are pulled toward carbon `base00` by M.STRENGTH and quantized (STEP)
-- to bound the number of highlight groups.
--
-- alpha's draw clears EVERY namespace and rewrites the lines, so the paint is
-- re-applied after each draw by wrapping `alpha.draw` (attach_alpha). The
-- decoded image and the last sample are memoized per window size.

local M = {}

M.ns = vim.api.nvim_create_namespace("nvsinner_wallpaper")
M.IMAGE = "assets/wallpapers/angel.ppm" -- runtimepath-relative
M.STRENGTH = 0.35 -- how much of the image shows through (the rest is base00)
M.STEP = 6 -- per-channel colour quantization step
M.PRIORITY = 10 -- under alpha's fg highlights' bg and the hover pill (1000)
M.FLOAT_PX = 3 -- float amplitude in pixel rows (one pixel = half a cell)
M.FLOAT_MS = 6000 -- one full up-and-down cycle
M.FRAME_MS = 100 -- tick interval; a tick repaints only when the offset changes

local function utf8_len(b)
	return b < 0x80 and 1 or b < 0xE0 and 2 or b < 0xF0 and 3 or 4
end

-- ─── Colour ──────────────────────────────────────────────────────────────────

local function hex2rgb(h)
	return { tonumber(h:sub(2, 3), 16), tonumber(h:sub(4, 5), 16), tonumber(h:sub(6, 7), 16) }
end

local function rgb2hex(c)
	return string.format("#%02x%02x%02x", c[1], c[2], c[3])
end

-- Pull `c` toward `base` (c at weight `a`), quantized to `step` (default STEP).
-- nil → base.
function M.mix(c, base, a, step)
	if not c then
		return { base[1], base[2], base[3] }
	end
	step = step or M.STEP
	local o = {}
	for j = 1, 3 do
		local v = base[j] + (c[j] - base[j]) * a
		o[j] = math.max(0, math.min(255, math.floor(v / step + 0.5) * step))
	end
	return o
end

local made = {} -- highlight groups created this colorscheme generation

local function group(fg, bg)
	local name = "NvWallpaper_" .. (fg and rgb2hex(fg):sub(2) or "x") .. "_" .. rgb2hex(bg):sub(2)
	if not made[name] then
		vim.api.nvim_set_hl(0, name, { fg = fg and rgb2hex(fg) or nil, bg = rgb2hex(bg) })
		made[name] = true
	end
	return name
end

-- :hi clear (inside every :colorscheme) wipes the groups; forget them so the
-- next paint recreates them.
vim.api.nvim_create_autocmd("ColorScheme", {
	group = vim.api.nvim_create_augroup("nv_wallpaper_hl", { clear = true }),
	callback = function()
		made = {}
	end,
})

-- ─── Image ───────────────────────────────────────────────────────────────────

-- Parse a binary PPM (P6, maxval 255) → { w, h, data } or nil. Comments
-- (`# …`) in the header are skipped.
function M.parse_ppm(raw)
	local pos, fields = 1, {}
	while #fields < 4 do
		local s, e, tok = raw:find("^%s*([^%s#]+)", pos)
		if not s then
			local cs, ce = raw:find("^%s*#[^\n]*\n", pos)
			if not cs then
				return nil
			end
			pos = ce + 1
		else
			fields[#fields + 1] = tok
			pos = e + 1
		end
	end
	local w, h, max = tonumber(fields[2]), tonumber(fields[3]), tonumber(fields[4])
	if fields[1] ~= "P6" or not w or not h or max ~= 255 then
		return nil
	end
	local data = raw:sub(pos + 1) -- exactly one whitespace byte ends the header
	if #data < w * h * 3 then
		return nil
	end
	return { w = w, h = h, data = data }
end

-- Parse a BMP → { w, h, data } (RGB, top-down) or nil. Handles 24- and 32-bit
-- (BGR / BGRA; alpha is dropped), compression 0 or BI_BITFIELDS (3), and both
-- row orders: a negative height means top-down, a positive one bottom-up. This
-- is the shape macOS `sips -s format bmp` writes (32-bit, bitfields, top-down),
-- which is how lua/core/image-open.lua feeds arbitrary images into this
-- pipeline. Palette formats (<= 8 bpp) and RLE are rejected.
function M.parse_bmp(raw)
	if type(raw) ~= "string" or #raw < 34 or raw:sub(1, 2) ~= "BM" then
		return nil
	end
	local byte = string.byte
	-- LuaJIT has no string.unpack: little-endian reads by hand.
	local function u16(p)
		local a, b = byte(raw, p, p + 1)
		return a + b * 256
	end
	local function u32(p)
		local a, b, c, d = byte(raw, p, p + 3)
		return a + b * 256 + c * 65536 + d * 16777216
	end
	local function i32(p)
		local v = u32(p)
		return v >= 2147483648 and v - 4294967296 or v
	end
	local offset, w, h, bpp, comp = u32(11), i32(19), i32(23), u16(29), u32(31)
	local top_down = h < 0
	h = math.abs(h)
	if w <= 0 or h == 0 or (bpp ~= 24 and bpp ~= 32) or (comp ~= 0 and comp ~= 3) then
		return nil
	end
	local bytes = bpp / 8
	local stride = math.floor((bpp * w + 31) / 32) * 4
	if offset + (h - 1) * stride + w * bytes > #raw then
		return nil
	end
	local pat = bpp == 32 and "(.)(.)(.)." or "(.)(.)(.)"
	local rows = {}
	for y = 0, h - 1 do
		local src = offset + y * stride + 1
		local row = raw:sub(src, src + w * bytes - 1):gsub(pat, "%3%2%1")
		rows[top_down and y + 1 or h - y] = row
	end
	return { w = w, h = h, data = table.concat(rows) }
end

-- Contain-fit: the largest cell box that holds `img` whole (no crop) inside a
-- `cols` × `rows` area, plus its centring offsets. Returns dc, dr (cells), then
-- col0, row0 (cells from the area's top-left). Feed dc, dr to M.pixels: the
-- cover-fit it runs is then an exact fit (at most a pixel of crop).
function M.contain(img, cols, rows)
	local scale = math.min(cols / img.w, rows * 2 / img.h)
	local dc = math.max(1, math.min(cols, math.floor(img.w * scale + 0.5)))
	local dr = math.max(1, math.min(rows, math.floor(img.h * scale / 2 + 0.5)))
	return dc, dr, math.floor((cols - dc) / 2), math.floor((rows - dr) / 2)
end

-- Resample `img` to `cols` × `rows * 2` pixels (two pixel rows per cell),
-- cover-fit (scale to fill, crop the overflow, centred), bilinear. Returns the
-- pixel rows 0-based: px[ty][tx + 1] = { r, g, b }.
function M.pixels(img, cols, rows)
	local tw, th = cols, rows * 2
	local iw, ih, data = img.w, img.h, img.data
	local scale = math.max(tw / iw, th / ih)
	local ox, oy = (iw - tw / scale) / 2, (ih - th / scale) / 2
	local byte, floor, min, max = string.byte, math.floor, math.min, math.max
	-- Source coordinates + weights are separable: compute them once per
	-- column / pixel row instead of per pixel (17 ms → 5 ms at 210×59).
	local function axis(n, o, size)
		local lo, hi, f = {}, {}, {}
		for t = 0, n - 1 do
			local s = min(max(o + (t + 0.5) / scale - 0.5, 0), size - 1)
			local a = floor(s)
			lo[t], hi[t], f[t] = a, min(a + 1, size - 1), s - a
		end
		return lo, hi, f
	end
	local xl, xh, xf = axis(tw, ox, iw)
	local yl, yh, yf = axis(th, oy, ih)
	-- One pixel row of the target, as flat r,g,b arrays.
	local function row_px(ty)
		local o0, o1, fy = yl[ty] * iw, yh[ty] * iw, yf[ty]
		local out = {}
		for tx = 0, tw - 1 do
			local i00, i10 = (o0 + xl[tx]) * 3 + 1, (o0 + xh[tx]) * 3 + 1
			local i01, i11 = (o1 + xl[tx]) * 3 + 1, (o1 + xh[tx]) * 3 + 1
			local fx = xf[tx]
			local px = {}
			for k = 0, 2 do
				local top = byte(data, i00 + k) * (1 - fx) + byte(data, i10 + k) * fx
				local bot = byte(data, i01 + k) * (1 - fx) + byte(data, i11 + k) * fx
				px[k + 1] = top * (1 - fy) + bot * fy
			end
			out[tx + 1] = px
		end
		return out
	end
	local px = {}
	for ty = 0, th - 1 do
		px[ty] = row_px(ty)
	end
	return px
end

-- Build the ▄ cell grid (top pixel → bg, bottom → fg) with the image shifted
-- DOWN by `off` pixel rows (negative = up); off = 0 is the image at rest. Rows
-- shifted in from beyond an edge repeat that edge row, so a figure the canvas
-- crops never shows a hard blank band. One pixel row is half a cell, which is
-- what keeps the float smooth.
function M.frame(px, cols, rows, off)
	local th = rows * 2
	local function src(y)
		return px[math.min(math.max(y - off, 0), th - 1)]
	end
	local grid = {}
	for r = 0, rows - 1 do
		local top, bot = src(2 * r), src(2 * r + 1)
		local row = {}
		for c = 1, cols do
			row[c] = { ch = "▄", bg = top and top[c], fg = bot and bot[c] }
		end
		grid[r + 1] = row
	end
	return grid
end

-- The image at rest as a `cols`×`rows` cell grid.
function M.sample(img, cols, rows)
	return M.frame(M.pixels(img, cols, rows), cols, rows, 0)
end

function M.enabled()
	local ok, s = pcall(require, "core.settings")
	return not ok or s.get("wallpaper_on") ~= false
end

-- Absolute path of the shipped image (via the runtimepath), or nil.
function M.path()
	return vim.api.nvim_get_runtime_file(M.IMAGE, false)[1]
end

local memo = { img = nil, key = nil, px = nil }

-- The float: the image's current vertical shift in pixel rows (0 = at rest).
M.off = 0

-- The image as a grid at w×h, shifted by the current float offset (decoded once;
-- the last resample memoized, so a frame only re-pairs pixel rows).
function M.grid(w, h)
	local key = w .. "x" .. h
	if memo.key ~= key then
		memo.px = M._load_pixels(w, h)
		memo.key = memo.px and key or nil
	end
	if not memo.px then
		return nil
	end
	return M.frame(memo.px, w, h, M.off)
end

function M._load_pixels(w, h)
	if not memo.img then
		local p = M.path()
		local fd = p and io.open(p, "rb")
		if not fd then
			return nil
		end
		local raw = fd:read("*a")
		fd:close()
		memo.img = M.parse_ppm(raw)
		if not memo.img then
			return nil
		end
	end
	return M.pixels(memo.img, w, h)
end

-- ─── Painting ────────────────────────────────────────────────────────────────

-- Display columns of `line` that hold text: col → { byte_start, byte_end }.
-- A lone space between two non-space characters counts as text.
local function text_cells(line)
	local cells, spans = {}, {}
	local col, bi = 0, 1
	while bi <= #line do
		local len = utf8_len(line:byte(bi))
		local ch = line:sub(bi, bi + len - 1)
		local w = math.max(1, vim.fn.strdisplaywidth(ch))
		spans[#spans + 1] = { col = col, w = w, s = bi - 1, e = bi - 1 + len, space = ch == " " }
		col, bi = col + w, bi + len
	end
	for k, sp in ipairs(spans) do
		local is_text = not sp.space
		if sp.space and spans[k - 1] and spans[k + 1] then
			is_text = not spans[k - 1].space and not spans[k + 1].space
		end
		if is_text then
			for c = sp.col, sp.col + sp.w - 1 do
				cells[c] = { sp.s, sp.e }
			end
		end
	end
	return cells
end

-- Pad the buffer with empty lines so every screen row has a line to anchor on.
local function pad_lines(buf, h)
	local n = vim.api.nvim_buf_line_count(buf)
	if n >= h then
		return
	end
	local blank = {}
	for k = 1, h - n do
		blank[k] = ""
	end
	local was = vim.bo[buf].modifiable
	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, n, n, false, blank)
	vim.bo[buf].modifiable = was
end

-- A pixel at or below KEY_MAX on every channel is the transparency key.
-- Built-ins mark their "no image here" background as pure black; a photo's
-- own near-black (a night sky) only differs from base by a few levels anyway.
M.KEY_MAX = 6

local function transparent(c)
	return c == nil or (c[1] <= M.KEY_MAX and c[2] <= M.KEY_MAX and c[3] <= M.KEY_MAX)
end

-- Lay `grid` onto `buf` as shown in `win`. `opts` (all optional; the defaults
-- are the wallpaper's behaviour exactly) lets another consumer reuse the paint:
--   ns       extmark namespace (default M.ns)
--   priority extmark priority (default M.PRIORITY)
--   key      false → no black-is-transparent key (a photo has real blacks)
--   step     colour quantization step (default M.STEP)
--   col0/row0 the grid's top-left cell inside the window's text area (default 0)
--   width/height the text area to paint in (default the whole window)
-- Returns how many distinct highlight groups the paint used.
function M.paint_grid(win, buf, grid, strength, opts)
	opts = opts or {}
	local ns = opts.ns or M.ns
	local priority = opts.priority or M.PRIORITY
	local keyed = opts.key ~= false
	local step = opts.step
	local col0, row0 = opts.col0 or 0, opts.row0 or 0
	local w = opts.width or vim.api.nvim_win_get_width(win)
	local h = opts.height or vim.api.nvim_win_get_height(win)
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	pad_lines(buf, h)
	local base = hex2rgb(require("core.carbon").colors().base00)
	local top = vim.api.nvim_win_call(win, function()
		return vim.fn.line("w0")
	end) - 1
	local lines = vim.api.nvim_buf_get_lines(buf, top + row0, top + h, false)
	local set = vim.api.nvim_buf_set_extmark
	local used, nused = {}, 0 -- distinct groups this paint touched (returned)
	local function use(fg_, bg_)
		local name = group(fg_, bg_)
		if not used[name] then
			used[name], nused = true, nused + 1
		end
		return name
	end
	for r = 1, math.min(h - row0, #grid, #lines) do
		local row, lnum = grid[r], top + row0 + r - 1
		local tc = text_cells(lines[r])
		local chunks, start = {}, nil
		local function flush()
			if start then
				set(buf, ns, lnum, 0, { virt_text = chunks, virt_text_win_col = start, priority = priority })
				chunks, start = {}, nil
			end
		end
		for c = 0, math.min(w - col0, #row) - 1 do
			local cell = row[c + 1]
			local col = c + col0
			-- Pure-black pixels are TRANSPARENT: they become nil, which mixes to
			-- base, and a cell that is transparent on both halves gets no mark at
			-- all, so the editor's real Normal bg shows (theme-proof).
			-- (Not `transparent(x) and nil or x`: a nil in the middle of an
			-- and/or chain always falls through to the `or` branch.)
			local cfg, cbg = cell.fg, cell.bg
			if keyed then
				if transparent(cfg) then
					cfg = nil
				end
				if transparent(cbg) then
					cbg = nil
				end
			end
			local fg, bg = M.mix(cfg, base, strength, step), M.mix(cbg, base, strength, step)
			local t = tc[col]
			if not cfg and not cbg then
				flush()
			elseif t then
				flush()
				local avg = M.mix({ (fg[1] + bg[1]) / 2, (fg[2] + bg[2]) / 2, (fg[3] + bg[3]) / 2 }, base, 1, step)
				set(buf, ns, lnum, t[1], { end_col = t[2], hl_group = use(nil, avg), priority = priority })
			else
				start = start or col
				chunks[#chunks + 1] = { cell.ch, use(fg, bg) }
			end
		end
		flush()
	end
	return nused
end

-- Paint the wallpaper onto the dashboard in `win`/`buf`, or clear it when off.
function M.paint(win, buf)
	if not (vim.api.nvim_win_is_valid(win) and vim.api.nvim_buf_is_valid(buf)) then
		return
	end
	if not M.enabled() then
		vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
		M.stop()
		return
	end
	local grid = M.grid(vim.api.nvim_win_get_width(win), vim.api.nvim_win_get_height(win))
	if grid then
		M.paint_grid(win, buf, grid, M.STRENGTH)
		M.start()
	end
end

-- ─── The float ───────────────────────────────────────────────────────────────
-- The angel hovers in place: a sine of FLOAT_PX pixel rows over FLOAT_MS. Black
-- is the transparency key, so shifting the image moves only the figure.
--
-- Cheap by construction: the resample is memoized per window size, so a frame
-- only re-pairs pixel rows, and a tick repaints only when the integer offset
-- actually changes (a handful of times per cycle). The timer runs only while a
-- dashboard is on screen in the current tab and the editor has focus; it stops
-- itself on the first tick that finds none, and never starts headless.

-- The dashboard windows in the current tab.
local function dashboards()
	local out = {}
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		local buf = vim.api.nvim_win_get_buf(win)
		if vim.bo[buf].filetype == "alpha" then
			out[#out + 1] = { win = win, buf = buf }
		end
	end
	return out
end

-- The float's offset `ms` into the cycle, in whole pixel rows.
function M.float_offset(ms)
	return math.floor(M.FLOAT_PX * math.sin(2 * math.pi * ms / M.FLOAT_MS) + 0.5)
end

-- One frame at time `now` (ms, defaults to the loop clock): move the float and
-- repaint every visible dashboard if the offset changed. Returns false (and
-- stops the loop) when there is nothing to animate.
function M.tick(now)
	local found = dashboards()
	if #found == 0 or not M.enabled() then
		M.stop()
		return false
	end
	if vim.api.nvim_get_mode().mode == "c" then
		return true -- don't repaint under the cmdline
	end
	local off = M.float_offset((now or vim.uv.now()) - (M._t0 or 0))
	if off == M.off then
		return true
	end
	M.off = off
	for _, d in ipairs(found) do
		local grid = M.grid(vim.api.nvim_win_get_width(d.win), vim.api.nvim_win_get_height(d.win))
		if grid then
			pcall(M.paint_grid, d.win, d.buf, grid, M.STRENGTH)
			pcall(vim.api.nvim__redraw, { win = d.win, valid = false, flush = true })
		end
	end
	return true
end

M._headless = function()
	return #vim.api.nvim_list_uis() == 0
end

function M.start()
	if M._running or M._headless() then
		return
	end
	M._running = true
	-- Every (re)start begins the cycle at rest; a float frozen by FocusLost
	-- settles back by at most FLOAT_PX pixel rows on the first tick.
	M._t0 = vim.uv.now()
	M._timer = M._timer or vim.uv.new_timer()
	M._timer:start(
		M.FRAME_MS,
		M.FRAME_MS,
		vim.schedule_wrap(function()
			M.tick()
		end)
	)
end

function M.stop()
	M._running = false
	if M._timer then
		M._timer:stop()
	end
end

local float = vim.api.nvim_create_augroup("nv_wallpaper_float", { clear = true })
vim.api.nvim_create_autocmd("FocusLost", { group = float, callback = M.stop })
vim.api.nvim_create_autocmd("FocusGained", {
	group = float,
	callback = function()
		if #dashboards() > 0 and M.enabled() then
			M.start()
		end
	end,
})

-- Repaint every visible dashboard (after the setting changes).
function M.refresh()
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local buf = vim.api.nvim_win_get_buf(win)
		if vim.bo[buf].filetype == "alpha" then
			pcall(M.paint, win, buf)
		end
	end
end

-- Hook alpha: every draw (start, redraw, resize, the version spinner) clears
-- all namespaces, so repaint right after it. Idempotent.
function M.attach_alpha(alpha)
	if alpha._nvsinner_wallpaper then
		return
	end
	alpha._nvsinner_wallpaper = true
	local draw = alpha.draw
	alpha.draw = function(conf, state)
		draw(conf, state)
		local win = state and state.windows and state.windows[1]
		if win and vim.api.nvim_win_is_valid(win) and state.buffer then
			pcall(M.paint, win, state.buffer)
		end
	end
end

-- ─── :NvSinnerWallpaper [on|off] ─────────────────────────────────────────────

-- No argument toggles. Writes through core/settings, so the command and the
-- :NvSinnerMenu row can never disagree.
function M.command(arg)
	local settings = require("core.settings")
	arg = vim.trim(arg or "")
	if arg ~= "" and arg ~= "on" and arg ~= "off" then
		vim.notify("Usage: :NvSinnerWallpaper [on|off]", vim.log.levels.WARN, { title = "NvSinner" })
		return
	end
	local on = arg == "" and not M.enabled() or arg == "on"
	settings.set("wallpaper_on", on)
end

vim.api.nvim_create_user_command("NvSinnerWallpaper", function(o)
	M.command(o.args)
end, {
	nargs = "?",
	complete = function()
		return { "on", "off" }
	end,
	desc = "Dashboard wallpaper — toggle, or on / off",
})

-- Test seam: forget memoized state.
function M._reset()
	M.stop()
	memo = { img = nil, key = nil, px = nil }
	made = {}
	M.off = 0
end

return M
