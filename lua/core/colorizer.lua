-- ─── Hex color chips (native) ────────────────────────────────────────────────
-- Replaces nvim-colorizer.lua: every `#rgb` / `#rrggbb` / `#rrggbbaa` literal
-- in the visible range gets a background chip in its own color. That is the
-- whole used surface — the plugin's css-function/tailwind/name machinery was
-- dead weight (see docs/native-roadmap.md).
--
-- The chip backgrounds are BY DEFINITION the buffer's literal colors, not
-- palette roles (they preview user data); the chip TEXT color is a carbon
-- role — base00 on light chips, base06 on dark ones — so the "no off-palette
-- colors" rule still holds for everything the config chooses itself.
--
-- Highlight groups (`NvColorRRGGBB`) are created on demand and the cache is
-- dropped on ColorScheme (a colorscheme apply starts from `hi clear`).

local M = {}

local ns = vim.api.nvim_create_namespace("nvsinner_colorizer")
M._ns = ns -- test seam

local groups = {} -- hex6 -> hl group name, rebuilt lazily after ColorScheme
vim.api.nvim_create_autocmd("ColorScheme", {
	pattern = "*",
	callback = function()
		groups = {}
	end,
})

local function eligible(buf)
	return vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == ""
end

-- #rgb → rrggbb; #rrggbbaa → rrggbb (alpha can't render in a highlight).
local function normalize(hex)
	if #hex == 3 then
		return hex:gsub("%x", "%0%0")
	end
	return hex:sub(1, 6)
end

local function group_for(hex)
	local key = normalize(hex):upper()
	if not groups[key] then
		local r = tonumber(key:sub(1, 2), 16)
		local g = tonumber(key:sub(3, 4), 16)
		local b = tonumber(key:sub(5, 6), 16)
		local c = require("core.carbon").colors()
		-- Perceived luminance decides the text tone: dark text on light
		-- chips, white text on dark ones.
		local fg = (0.299 * r + 0.587 * g + 0.114 * b) > 140 and c.base00 or c.base06
		local name = "NvColor" .. key
		vim.api.nvim_set_hl(0, name, { bg = "#" .. key, fg = fg })
		groups[key] = name
	end
	return groups[key]
end

-- Rescan the window's visible range: wipe our marks, re-mark every literal.
function M.refresh(buf, win)
	buf = buf or vim.api.nvim_get_current_buf()
	win = win or vim.api.nvim_get_current_win()
	if not eligible(buf) or vim.api.nvim_win_get_buf(win) ~= buf then
		return
	end
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	local first = vim.fn.line("w0", win) - 1
	local last = vim.fn.line("w$", win)
	for i, line in ipairs(vim.api.nvim_buf_get_lines(buf, first, last, false)) do
		for s, hex in line:gmatch("()#(%x+)") do
			-- Boundary: reject `##fff` and `abc#fff`-style runs; the gmatch
			-- run is maximal, so only exact 3/6/8-digit literals qualify.
			local before = s > 1 and line:sub(s - 1, s - 1) or ""
			if (#hex == 3 or #hex == 6 or #hex == 8) and not before:match("[%w#]") then
				vim.api.nvim_buf_set_extmark(buf, ns, first + i - 1, s - 1, {
					end_col = s + #hex,
					hl_group = group_for(hex),
				})
			end
		end
	end
end

-- Debounced rescans: typing and scrolling fire TextChanged(I)/WinScrolled in
-- bursts (neoscroll emits one WinScrolled per animation frame), so those
-- events coalesce into a single rescan DEBOUNCE_MS after the burst settles.
-- First paint (BufWinEnter) and insert-exit (InsertLeave) stay immediate. The
-- old marks persist until the rescan runs (the clear happens inside refresh),
-- so nothing flickers while the timer counts down. Handles are anchored on
-- M._debounce so luv can't GC an active timer.
M.DEBOUNCE_MS = 50
M._debounce = {} -- bufnr -> one-shot uv timer

local function debounced_refresh(buf)
	local t = M._debounce[buf]
	if not t then
		t = assert(vim.uv.new_timer())
		M._debounce[buf] = t
	end
	t:stop()
	t:start(
		M.DEBOUNCE_MS,
		0,
		vim.schedule_wrap(function()
			M.refresh(buf)
		end)
	)
end

local grp = vim.api.nvim_create_augroup("nv_colorizer", { clear = true })
vim.api.nvim_create_autocmd({ "BufWinEnter", "InsertLeave" }, {
	group = grp,
	callback = function(args)
		M.refresh(args.buf)
	end,
})
vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "WinScrolled" }, {
	group = grp,
	callback = function(args)
		debounced_refresh(args.buf)
	end,
})
vim.api.nvim_create_autocmd("BufWipeout", {
	group = grp,
	callback = function(args)
		local t = M._debounce[args.buf]
		if t then
			t:stop()
			t:close()
			M._debounce[args.buf] = nil
		end
	end,
})

return M
