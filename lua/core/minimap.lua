-- ─── Code minimap (native) ──────────────────────────────────────────────────
-- A VS Code-style overview of the file on the right edge of the focused
-- window, drawn with BRAILLE DOTS: every cell packs 2 dot columns × 4 dot rows
-- into one U+28xx glyph, so the map is genuinely smaller than the code instead
-- of being a second copy of it.
--
-- ROWS_PER_CELL is the vertical zoom, and 2 (each source line lighting two of
-- the cell's four dot rows) was picked over 4 by measuring: at 4 lines per row
-- the OR of four lines fills ~70% of the cells and the map reads as a heat
-- smear; at 2 it drops to ~57% and indentation blocks and line-length falloff
-- are legible — the thing an overview is actually for.
--
-- Shape: ONE non-focusable float (`relative = "win"`) that follows focus, not
-- one window per split. A real right-hand split was rejected on purpose —
-- toggleterm's restore_layout() runs `wincmd L` on every AI-panel open and
-- would shove it around, and a split would have to be denylisted in
-- window-picker, ui-touch, indent, illuminate and satellite. A float is
-- already skipped by every one of those guards.
--
-- It leaves M.GUTTER columns free at the window's right edge so satellite's
-- overview ruler (hunks/diagnostics/cursor) stays visible BESIDE the map —
-- the same pairing VS Code uses. zindex sits below core/backdrop.lua's
-- dimming layer (modal zindex - 10 = 40) so the NvSinner modals still dim it.
--
-- Off by default (it covers ~WIDTH columns of text): the persisted `minimap`
-- setting owns the state, so :NvSinnerMinimap and the :NvSinnerMenu row can
-- never disagree — the command writes through core/settings, which calls back
-- into M.set_enabled.

local M = {}

local bor = require("bit").bor

local ns = vim.api.nvim_create_namespace("nvsinner_minimap")
M._ns = ns -- test seam

-- ─── Tunables ────────────────────────────────────────────────────────────────

M.WIDTH = 18 -- minimap cells (× 2 = dot columns)
M.SPAN = 100 -- source columns mapped across the full width
M.ROWS_PER_CELL = 2 -- source lines per braille row (vertical zoom: 1, 2 or 4)
M.MIN_WIDTH = 80 -- host window must be at least this wide…
M.MIN_HEIGHT = 10 -- …and this tall
M.GUTTER = 2 -- columns left free at the edge for satellite's bar
M.DEBOUNCE_MS = 40
M.ZINDEX = 35 -- below backdrop.lua's dimming layer (40)

-- Same base list as indent.lua, plus the panels that are technically normal
-- buffers but are not code (trouble, quickfix, the undotree browser, the
-- diffview panels, the AI CLI picker).
M.DENYLIST = {
	["neo-tree"] = true,
	alpha = true,
	dashboard = true,
	TelescopePrompt = true,
	toggleterm = true,
	lazy = true,
	mason = true,
	help = true,
	trouble = true,
	qf = true,
	undotree = true,
	DiffviewFiles = true,
	DiffviewFileHistory = true,
	["nvsinner-picker"] = true,
	["nvsinner-minimap"] = true,
}

M.on = false

-- ─── Braille encoding ────────────────────────────────────────────────────────
-- Dot bits inside one cell: column 1 = left, column 2 = right; the four rows
-- of a cell are the sub-line index 1-4 (U+2800's dot 7/8 are the 0x40/0x80
-- bottom row, which is why they are not sequential).
local DOTS = {
	{ 0x01, 0x02, 0x04, 0x40 }, -- left dot column
	{ 0x08, 0x10, 0x20, 0x80 }, -- right dot column
}

-- U+2800 + mask, precomputed: the 256 glyphs are all 3-byte UTF-8 sequences
-- starting 0xE2 0xA0/0xA1/0xA2/0xA3, so no nr2char() call in the render loop.
local GLYPH = {}
for mask = 0, 255 do
	local cp = 0x2800 + mask
	GLYPH[mask] = string.char(0xE0 + math.floor(cp / 0x1000), 0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
end
local BLANK_CELL = GLYPH[0]

--- Encode source lines into braille rows.
--- Pure (no vim.*) so the specs can exercise it directly.
--- @param lines string[] source lines, in order
--- @param opts table|nil { width, span, tabstop, per }
--- @return string[] rows each exactly `width` cells wide
function M._encode(lines, opts)
	opts = opts or {}
	local width = opts.width or M.WIDTH
	local span = opts.span or M.SPAN
	local tabstop = opts.tabstop or 8
	local per = opts.per or M.ROWS_PER_CELL
	local dot_cols = width * 2

	-- How many of the cell's four dot rows one source line lights: 4 lines per
	-- cell = one row each, 2 = two rows each (thicker strokes, half the file
	-- per screen — closer to VS Code's default zoom).
	local reps = 4 / per

	local rows, cells = {}, nil
	for i = 1, #lines do
		local sub = (i - 1) % per + 1
		if sub == 1 then
			cells = {}
			for c = 1, width do
				cells[c] = 0
			end
			rows[#rows + 1] = cells
		end
		local line = lines[i]
		local col = 0 -- DISPLAY column, so tab-indented files line up
		for b = 1, #line do
			local byte = line:byte(b)
			if byte == 9 then
				col = col + tabstop - col % tabstop
			elseif byte == 32 then
				col = col + 1
			elseif byte >= 0x80 and byte < 0xC0 then -- UTF-8 continuation: same char, same column
				local _ = byte
			else
				local dc = math.floor(col * dot_cols / span)
				if dc < dot_cols then
					-- Past SPAN the character is CLIPPED, not clamped onto the
					-- last column: clamping paints a fake solid right edge for
					-- any file with long lines, which is the opposite of what
					-- an overview is for.
					local cell = math.floor(dc / 2) + 1
					local column = DOTS[dc % 2 + 1]
					for r = (sub - 1) * reps + 1, sub * reps do
						cells[cell] = bor(cells[cell], column[r])
					end
				end
				col = col + 1
			end
		end
	end

	local out = {}
	for r = 1, #rows do
		local parts = {}
		for c = 1, width do
			parts[c] = GLYPH[rows[r][c]]
		end
		out[r] = table.concat(parts)
	end
	return out
end

--- First source line of the slice the minimap renders.
--- The whole file when it fits; otherwise the viewport centred in the slice
--- and clamped to both ends, so scrolling moves the band smoothly and only
--- re-centres when the viewport would leave the slice. Pure.
--- @param total integer buffer line count
--- @param w0 integer first visible source line
--- @param ws integer last visible source line
--- @param rows integer minimap rows (= host window height)
--- @param per integer|nil source lines per row (default M.ROWS_PER_CELL)
--- @return integer first 1-based source line
function M._slice(total, w0, ws, rows, per)
	local span = rows * (per or M.ROWS_PER_CELL)
	if total <= span then
		return 1
	end
	local view = math.max(1, ws - w0 + 1)
	local first = w0 - math.floor((span - view) / 2)
	local max = total - span + 1
	if first > max then
		first = max
	end
	if first < 1 then
		first = 1
	end
	return first
end

-- ─── Highlights ──────────────────────────────────────────────────────────────
-- Roles only (core/carbon.lua is the single palette source of truth). The two
-- BAND groups keep solid backgrounds even in transparent mode — like
-- NvMenuSel, the viewport band only reads if it contrasts with the map.
local function apply_hl()
	local carbon = require("core.carbon")
	local c = carbon.colors()
	local base = carbon.transparent() and c.none or c.blend
	vim.api.nvim_set_hl(0, "NvMinimap", { fg = c.base03, bg = base })
	vim.api.nvim_set_hl(0, "NvMinimapView", { fg = c.base04, bg = c.lift })
	vim.api.nvim_set_hl(0, "NvMinimapCursor", { fg = c.base09, bg = c.base02 })
end
apply_hl()

-- ─── The pane ────────────────────────────────────────────────────────────────

local ui = { win = nil, buf = nil, host = nil, first = nil }

-- Text rows of `win`, WITHOUT the winbar. nvim_win_get_height() counts the
-- winbar row (measured: 28 vs 27 on a window carrying core/filebadge's badge),
-- and a pane sized from it hangs one row past the text area — straight over
-- the statusline. getwininfo() is the one that excludes it.
local function text_height(win)
	local wi = vim.fn.getwininfo(win)[1]
	return wi and wi.height or vim.api.nvim_win_get_height(win)
end
local seen = nil -- same-position early-exit key (indent.lua's trick)

function M._win()
	return ui.win
end

local function eligible(win)
	if not win or not vim.api.nvim_win_is_valid(win) then
		return false
	end
	-- Floats (telescope, the NvSinner modals, our own pane) are never hosts.
	if vim.api.nvim_win_get_config(win).relative ~= "" then
		return false
	end
	if vim.wo[win].diff then
		return false -- a diff pane's right edge carries the change column
	end
	local buf = vim.api.nvim_win_get_buf(win)
	if vim.bo[buf].buftype ~= "" then
		return false -- terminals, prompts, nofile panels
	end
	if M.DENYLIST[vim.bo[buf].filetype] then
		return false
	end
	return vim.api.nvim_win_get_width(win) >= M.MIN_WIDTH and text_height(win) >= M.MIN_HEIGHT
end
M._eligible = eligible

local function ensure_buf()
	if ui.buf and vim.api.nvim_buf_is_valid(ui.buf) then
		return ui.buf
	end
	ui.buf = vim.api.nvim_create_buf(false, true)
	vim.bo[ui.buf].buftype = "nofile"
	vim.bo[ui.buf].bufhidden = "hide" -- survives a hide, so focus churn costs nothing
	vim.bo[ui.buf].swapfile = false
	vim.bo[ui.buf].filetype = "nvsinner-minimap"
	return ui.buf
end

-- Open the pane over `host`, or re-anchor the existing one (focus moved to
-- another window, the host resized).
local function place(host, width, height)
	local cfg = {
		relative = "win",
		win = host,
		width = M.WIDTH,
		height = height,
		row = 0,
		col = math.max(0, width - M.WIDTH - M.GUTTER),
		style = "minimal",
		focusable = false,
		zindex = M.ZINDEX,
	}
	if ui.win and vim.api.nvim_win_is_valid(ui.win) then
		pcall(vim.api.nvim_win_set_config, ui.win, cfg)
	else
		cfg.noautocmd = true
		local ok, win = pcall(vim.api.nvim_open_win, ensure_buf(), false, cfg)
		if not ok then
			ui.win = nil
			return false
		end
		ui.win = win
		-- EndOfBuffer must be remapped too: carbon gives it an explicit
		-- editor-ground bg, so remapping only Normal yields a two-tone box.
		vim.wo[ui.win].winhighlight = "Normal:NvMinimap,EndOfBuffer:NvMinimap,CursorLine:NvMinimap"
		vim.wo[ui.win].wrap = false
		vim.wo[ui.win].cursorline = false
		vim.wo[ui.win].winfixwidth = true
	end
	ui.host = host
	return true
end

--- Close the pane but stay enabled (focus moved somewhere ineligible).
function M.hide()
	if ui.win and vim.api.nvim_win_is_valid(ui.win) then
		pcall(vim.api.nvim_win_close, ui.win, true)
	end
	ui.win, ui.host, ui.first = nil, nil, nil
	seen = nil
end

--- Re-render for `host` (defaults to the current window). Immediate — the
--- debounce lives in the autocmds, so specs can call this directly.
function M.refresh(host)
	if not M.on then
		return
	end
	host = host or vim.api.nvim_get_current_win()
	if ui.win and host == ui.win then
		return -- events from our own pane
	end
	if not eligible(host) then
		-- The map belongs to the EDITOR GROUP, not to whatever has focus right
		-- now (VS Code behaves the same). Anything that is not itself a code
		-- window — a cmdline/telescope/hover float, neo-tree, the AI terminal
		-- column — leaves the pane where it is, as long as its host is still a
		-- live code window. Measured: without this, every ":" command in a
		-- noice-equipped session tore the pane down and it never came back.
		if ui.host and ui.host ~= host and eligible(ui.host) then
			return
		end
		M.hide()
		return
	end

	local buf = vim.api.nvim_win_get_buf(host)
	local width = vim.api.nvim_win_get_width(host)
	local height = math.max(1, text_height(host))
	local total = vim.api.nvim_buf_line_count(buf)
	local w0 = vim.fn.line("w0", host)
	local ws = vim.fn.line("w$", host)
	local cur = vim.api.nvim_win_get_cursor(host)[1]
	local first = M._slice(total, w0, ws, height)
	local tick = vim.api.nvim_buf_get_changedtick(buf)

	-- Nothing that feeds the render changed (column-only cursor moves are the
	-- hottest case): skip the whole thing.
	local k = seen
	if
		k
		and ui.win
		and vim.api.nvim_win_is_valid(ui.win)
		and k.host == host
		and k.buf == buf
		and k.first == first
		and k.w0 == w0
		and k.ws == ws
		and k.cur == cur
		and k.tick == tick
		and k.width == width
		and k.height == height
	then
		return
	end
	seen = {
		host = host,
		buf = buf,
		first = first,
		w0 = w0,
		ws = ws,
		cur = cur,
		tick = tick,
		width = width,
		height = height,
	}

	if not place(host, width, height) then
		return
	end
	ui.first = first

	local last = math.min(total, first + height * M.ROWS_PER_CELL - 1)
	local rows = M._encode(vim.api.nvim_buf_get_lines(buf, first - 1, last, false), { tabstop = vim.bo[buf].tabstop })
	local pad = BLANK_CELL:rep(M.WIDTH)
	for r = #rows + 1, height do
		rows[r] = pad
	end

	vim.bo[ui.buf].modifiable = true
	vim.api.nvim_buf_set_lines(ui.buf, 0, -1, false, rows)
	vim.bo[ui.buf].modifiable = false

	-- The viewport band + the cursor's row. Whole-line groups, so the band
	-- reads as a slider even where the code is blank.
	vim.api.nvim_buf_clear_namespace(ui.buf, ns, 0, -1)
	for r = 1, height do
		local rtop = first + (r - 1) * M.ROWS_PER_CELL
		local rbot = rtop + M.ROWS_PER_CELL - 1
		local group
		if cur >= rtop and cur <= rbot then
			group = "NvMinimapCursor"
		elseif rbot >= w0 and rtop <= ws then
			group = "NvMinimapView"
		end
		if group then
			pcall(vim.api.nvim_buf_set_extmark, ui.buf, ns, r - 1, 0, { line_hl_group = group })
		end
	end
end

-- ─── Click to jump ───────────────────────────────────────────────────────────
-- The pane is NOT focusable (it must never join <C-w> cycling or the window
-- picker), so a buffer-local map could never fire on it. The click is caught by
-- GLOBAL expr maps installed only while the minimap is on, using core/mouse's
-- verified fallthrough idiom: return "" over the pane (swallow), return the
-- literal key everywhere else so every other window keeps builtin mouse
-- behaviour. Buffer-local maps (the modals, the explorers) still win over
-- these, and the pane is only ever visible while an eligible window is focused.
--
-- The hit test goes through SCREEN coordinates, not getmousepos().winid: a
-- non-focusable float is not guaranteed to be reported as the mouse window,
-- and win_screenpos() is exact either way.

--- Source line under the pointer, or nil when the pointer is not on the pane.
--- @param mp table getmousepos()-shaped (the test seam — mouse events cannot
---        be synthesized headless)
--- @param rect table|nil { row, col, height } 1-based screen rect of the pane
--- @return integer|nil
function M._clicked_line(mp, rect)
	if not ui.first then
		return nil
	end
	if not rect then
		if not (ui.win and vim.api.nvim_win_is_valid(ui.win)) then
			return nil
		end
		local pos = vim.fn.win_screenpos(ui.win)
		rect = { row = pos[1], col = pos[2], height = vim.api.nvim_win_get_height(ui.win) }
	end
	local row = (mp.screenrow or 0) - rect.row + 1
	local col = (mp.screencol or 0) - rect.col + 1
	if row < 1 or row > rect.height or col < 1 or col > M.WIDTH then
		return nil
	end
	-- A row covers ROWS_PER_CELL source lines; land on the first of them.
	return ui.first + (row - 1) * M.ROWS_PER_CELL
end

--- Put the host window's cursor on `line` and centre it.
function M.jump(line)
	if not (ui.host and vim.api.nvim_win_is_valid(ui.host)) then
		return
	end
	local buf = vim.api.nvim_win_get_buf(ui.host)
	line = math.max(1, math.min(line, vim.api.nvim_buf_line_count(buf)))
	pcall(vim.api.nvim_win_set_cursor, ui.host, { line, 0 })
	pcall(vim.api.nvim_win_call, ui.host, function()
		vim.cmd("normal! zz")
	end)
	if vim.api.nvim_get_current_win() ~= ui.host then
		pcall(vim.api.nvim_set_current_win, ui.host)
	end
	M.refresh(ui.host)
end

-- The PRESS is claimed too, not just the release: unmapped, Vim's builtin
-- moves the cursor to whatever text sits UNDER the pane before the release is
-- ever delivered. <LeftDrag> rides along, so a press-and-sweep scrubs the file.
M.MOUSE_KEYS = {
	{ key = "<LeftMouse>", jump = true },
	{ key = "<LeftDrag>", jump = true },
	{ key = "<LeftRelease>", jump = false }, -- already jumped on the press
}

local function on_mouse(key, jump)
	local line = M._clicked_line(vim.fn.getmousepos())
	if not line then
		return key -- not our pane: hand the click back to Vim
	end
	if jump then
		-- An expr mapping is evaluated under TEXTLOCK: moving the cursor or
		-- switching windows inside it raises E565 and the whole mapping dies
		-- silently — measured in a real PTY, where the click kept landing on
		-- the text under the pane. Scheduling runs the jump after the mapping
		-- has been evaluated, where window changes are legal again.
		vim.schedule(function()
			M.jump(line)
		end)
	end
	return ""
end

local function install_mouse()
	for _, m in ipairs(M.MOUSE_KEYS) do
		vim.keymap.set({ "n", "i" }, m.key, function()
			return on_mouse(m.key, m.jump)
		end, {
			expr = true,
			remap = false,
			replace_keycodes = true, -- without it the returned key is inserted as text
			silent = true,
			desc = "Minimap: click to jump",
		})
	end
end

local function remove_mouse()
	for _, m in ipairs(M.MOUSE_KEYS) do
		pcall(vim.keymap.del, { "n", "i" }, m.key)
	end
end

-- ─── Enable / disable ────────────────────────────────────────────────────────

function M.enable()
	M.on = true
	install_mouse()
	M.refresh()
end

function M.disable()
	M.on = false
	remove_mouse()
	M.hide()
	if ui.buf and vim.api.nvim_buf_is_valid(ui.buf) then
		pcall(vim.api.nvim_buf_delete, ui.buf, { force = true })
	end
	ui.buf = nil
	if M._timer then
		M._timer:stop()
	end
end

--- What core/settings.lua's applier calls.
function M.set_enabled(v)
	if v then
		M.enable()
	else
		M.disable()
	end
end

--- :NvSinnerMinimap / <leader>xn. Writes through core/settings so the menu row
--- and the command can never disagree (the <leader>lh / inlay_hints pattern).
function M.toggle()
	local ok = pcall(function()
		require("core.settings").set("minimap", not M.on)
	end)
	if not ok then
		M.set_enabled(not M.on)
	end
end

-- Test seam: drop the pane and every cache between specs.
function M._reset()
	M.disable()
	seen = nil
end

-- ─── Events ──────────────────────────────────────────────────────────────────
-- The M.on guard comes FIRST in every callback: the minimap is off by default,
-- so scroll/typing events must cost one boolean — no call, no timer churn.
-- One timer for the whole module (there is only ever one pane), anchored on M
-- against luv GC.

local function debounced()
	if not M._timer then
		M._timer = assert(vim.uv.new_timer())
	end
	M._timer:stop()
	M._timer:start(
		M.DEBOUNCE_MS,
		0,
		vim.schedule_wrap(function()
			M.refresh()
		end)
	)
end

local grp = vim.api.nvim_create_augroup("nv_minimap", { clear = true })

vim.api.nvim_create_autocmd({ "WinEnter", "BufWinEnter", "WinResized", "VimResized", "TabEnter" }, {
	group = grp,
	callback = function()
		if not M.on then
			return
		end
		M.refresh()
	end,
})

vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "TextChanged", "TextChangedI", "WinScrolled" }, {
	group = grp,
	callback = function()
		if not M.on then
			return
		end
		debounced()
	end,
})

vim.api.nvim_create_autocmd("WinClosed", {
	group = grp,
	callback = function(args)
		local win = tonumber(args.match)
		if ui.win and win == ui.win then
			ui.win, ui.host, ui.first, seen = nil, nil, nil, nil
			return
		end
		if not M.on or not ui.host or win ~= ui.host then
			return
		end
		-- The host is going away: re-home onto whatever gets focus next.
		vim.schedule(function()
			M.refresh()
		end)
	end,
})

vim.api.nvim_create_autocmd("ColorScheme", { group = grp, pattern = "*", callback = apply_hl })

-- Seed from the persisted setting (core/settings is required before us in
-- init.lua). The first paint waits for VimEnter — at require time there is no
-- file buffer to map yet.
local ok_settings, settings = pcall(require, "core.settings")
if ok_settings and settings.get("minimap") then
	vim.api.nvim_create_autocmd("VimEnter", {
		group = grp,
		once = true,
		callback = function()
			M.enable() -- enable(), not `M.on = true`: the click maps install there
		end,
	})
end

vim.api.nvim_create_user_command("NvSinnerMinimap", M.toggle, {
	desc = "Toggle the code minimap — braille overview on the right edge",
})

return M
