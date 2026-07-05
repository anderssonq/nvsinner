-- ─── :NvSinnerMenu — settings modal ──────────────────────────────────────────
-- A Mason-style floating panel over lua/core/settings.lua: pick the theme
-- variant, transparency, accent pack, neo-tree folder color, the single-role
-- color slots (info toasts, variables, strings, functions), panel sides and
-- notification muting, and watch each change apply live (every change also
-- persists). Keyboard-driven like Mason (j/k move, h/l or <CR>/<Space> cycle,
-- 1-9 jump, q/<Esc> close) AND mouse-clickable (click a row to cycle its value).
--
-- Styling is carbon roles only (lua/core/carbon.lua): recessed float on
-- NormalFloat/blend, base09 identity accent for values, base03 muted hints.
-- The NvMenu* groups defined here are also reused by the AI CLI picker in
-- lua/plugins/terminal/toggleterm.lua, so both surfaces read as one component.

local M = {}

local settings = require("core.settings")

-- Highlight groups, re-applied on ColorScheme (fg-only so they inherit the
-- float surface — solid backgrounds would break transparent mode).
local function apply_hl()
	local c = require("core.carbon").colors()
	local set = vim.api.nvim_set_hl
	set(0, "NvMenuKey", { fg = c.base09, bold = true }) -- the 1-9 shortcut digits
	set(0, "NvMenuLabel", { fg = c.base04 })
	set(0, "NvMenuValue", { fg = c.base09, bold = true })
	set(0, "NvMenuMuted", { fg = c.base03, italic = true }) -- hints, ‹ › arrows
	set(0, "NvMenuSel", { bg = c.base01 }) -- selected row wash (solid on purpose)
	-- Solid modal surface, darker than the editor AND the regular floats, so
	-- the modal reads as its own layer (solid on purpose — same rationale as
	-- NvMenuSel: contrast must survive transparent mode).
	set(0, "NvMenuNormal", { fg = c.base04, bg = c.shade })
	set(0, "NvMenuBorder", { fg = c.base02, bg = c.shade })
end
apply_hl()
vim.api.nvim_create_autocmd("ColorScheme", {
	group = vim.api.nvim_create_augroup("nv_menu_hl", { clear = true }),
	pattern = "*",
	callback = apply_hl,
})

-- ─── The option rows ─────────────────────────────────────────────────────────
-- Each row cycles through `values`; `show` renders a value for display.
local function bool_show(on, off)
	return function(v)
		return v and on or off
	end
end

-- Choices shared by the single-role color slots (carbon.slot_choices +
-- "default" = the stock carbon look).
local SLOT_VALUES = { "default", "accent", "teal", "aqua", "magenta", "pink", "green", "purple", "plain" }

local ITEMS = {
	{ key = "background", label = "Theme", values = { "dark", "light" } },
	{ key = "transparent", label = "Transparency", values = { false, true }, show = bool_show("on", "off") },
	{ key = "accent", label = "Accent", values = { "blue", "magenta", "green", "purple" } },
	{
		key = "folder",
		label = "Folder color",
		values = { "accent", "teal", "aqua", "pink", "green", "purple", "gray" },
	},
	{ key = "notif", label = "Notif color", values = SLOT_VALUES },
	{ key = "variables", label = "Variables", values = SLOT_VALUES },
	{ key = "strings", label = "Strings", values = SLOT_VALUES },
	{ key = "functions", label = "Functions", values = SLOT_VALUES },
	{ key = "tree_side", label = "Neo-tree side", values = { "left", "right" } },
	{ key = "ai_side", label = "AI column side", values = { "left", "right" } },
	{ key = "quiet", label = "Notifications", values = { false, true }, show = bool_show("hidden", "shown") },
}

local WIDTH = 46
local HINT = "j/k move · h/l change · 1-9 jump · q close"
local TOP_PAD = 1 -- blank line above the first row
local ns = vim.api.nvim_create_namespace("nvsinner_menu")

-- Modal state (one instance at a time). hover_line tracks the last pointer
-- row so <MouseMove> only re-renders when the hovered row actually changes.
local ui = { win = nil, buf = nil, sel = 1, hover_line = -1 }

local function is_open()
	return ui.win and vim.api.nvim_win_is_valid(ui.win)
end

local function item_line(i) -- buffer line (1-based) of item i
	return TOP_PAD + i
end

local function render()
	local lines, spans = {}, {}
	for _ = 1, TOP_PAD do
		table.insert(lines, "")
	end
	for i, it in ipairs(ITEMS) do
		local v = settings.get(it.key)
		local shown = it.show and it.show(v) or tostring(v)
		-- Built in segments so the highlight byte offsets are exact (the ▸
		-- marker is multi-byte, so fixed columns would drift).
		-- %-2d keeps the label column aligned once the list passes 9 rows.
		local head = string.format(" %s %-2d ", (i == ui.sel) and "▸" or " ", i)
		local label = string.format("%-16s", it.label)
		local value = string.format("‹ %s ›", shown)
		spans[i] = { head = #head, label = #head + #label, total = #head + #label + #value }
		table.insert(lines, head .. label .. value)
	end
	table.insert(lines, "")
	-- Center the hint line.
	local pad = math.max(0, math.floor((WIDTH - vim.fn.strdisplaywidth(HINT)) / 2))
	table.insert(lines, string.rep(" ", pad) .. HINT)

	vim.bo[ui.buf].modifiable = true
	vim.api.nvim_buf_set_lines(ui.buf, 0, -1, false, lines)
	vim.bo[ui.buf].modifiable = false

	vim.api.nvim_buf_clear_namespace(ui.buf, ns, 0, -1)
	local ext = vim.api.nvim_buf_set_extmark
	for i in ipairs(ITEMS) do
		local row = item_line(i) - 1 -- extmarks are 0-based
		local s = spans[i]
		ext(ui.buf, ns, row, 0, { end_col = s.head, hl_group = "NvMenuKey" })
		ext(ui.buf, ns, row, s.head, { end_col = s.label, hl_group = "NvMenuLabel" })
		ext(ui.buf, ns, row, s.label, { end_col = s.total, hl_group = "NvMenuValue" })
		if i == ui.sel then
			ext(ui.buf, ns, row, 0, { line_hl_group = "NvMenuSel" })
		end
	end
	ext(ui.buf, ns, #lines - 1, 0, { end_col = #lines[#lines], hl_group = "NvMenuMuted" })

	if is_open() then
		vim.api.nvim_win_set_cursor(ui.win, { item_line(ui.sel), 1 })
	end
end

function M.close()
	if is_open() then
		pcall(vim.api.nvim_win_close, ui.win, true)
	end
	if ui.buf and vim.api.nvim_buf_is_valid(ui.buf) then
		pcall(vim.api.nvim_buf_delete, ui.buf, { force = true })
	end
	ui.win, ui.buf = nil, nil
end

-- Move the selection by delta (clamped).
function M.move(delta)
	ui.sel = math.min(#ITEMS, math.max(1, ui.sel + delta))
	render()
end

-- Cycle the selected row's value by delta, apply + persist it live.
function M.cycle(delta)
	local it = ITEMS[ui.sel]
	local cur = settings.get(it.key)
	local idx = 1
	for i, v in ipairs(it.values) do
		if v == cur then
			idx = i
		end
	end
	idx = ((idx - 1 + delta) % #it.values) + 1
	settings.set(it.key, it.values[idx])
	render()
end

-- Mouse: click a row → select it and cycle its value.
local function on_click()
	local mp = vim.fn.getmousepos()
	if mp.winid ~= ui.win then
		return
	end
	local i = mp.line - TOP_PAD
	if i >= 1 and i <= #ITEMS then
		ui.sel = i
		M.cycle(1)
	end
end

-- Mouse hover: move the selection pill onto the row under the pointer (the
-- same hover feel as the dashboard menu); rows outside the list keep the
-- current selection. The buffer-local <MouseMove> map also shadows
-- ui-touch's global LSP-hover handler while the pointer is over the modal.
local function on_hover()
	local mp = vim.fn.getmousepos()
	if mp.winid ~= ui.win or mp.line == ui.hover_line then
		return
	end
	ui.hover_line = mp.line
	local i = mp.line - TOP_PAD
	if i >= 1 and i <= #ITEMS and i ~= ui.sel then
		ui.sel = i
		render()
	end
end

function M.open()
	if is_open() then
		vim.api.nvim_set_current_win(ui.win)
		return
	end
	ui.hover_line = -1
	ui.buf = vim.api.nvim_create_buf(false, true)
	vim.bo[ui.buf].buftype = "nofile"
	vim.bo[ui.buf].bufhidden = "wipe"
	vim.bo[ui.buf].filetype = "nvsinner-menu"

	local height = TOP_PAD + #ITEMS + 2
	ui.win = vim.api.nvim_open_win(ui.buf, true, {
		relative = "editor",
		style = "minimal",
		border = "rounded",
		title = "  NvSinner ",
		title_pos = "center",
		width = WIDTH,
		height = height,
		row = math.max(1, math.floor((vim.o.lines - height) / 2) - 1),
		col = math.max(0, math.floor((vim.o.columns - WIDTH) / 2)),
	})
	vim.wo[ui.win].winhighlight = "Normal:NvMenuNormal,FloatBorder:NvMenuBorder"
	vim.wo[ui.win].cursorline = false
	require("core.backdrop").attach(ui.win) -- dim the editor behind the modal

	local function map(lhs, rhs)
		vim.keymap.set("n", lhs, rhs, { buffer = ui.buf, nowait = true, silent = true })
	end
	map("j", function()
		M.move(1)
	end)
	map("k", function()
		M.move(-1)
	end)
	map("<Down>", function()
		M.move(1)
	end)
	map("<Up>", function()
		M.move(-1)
	end)
	map("l", function()
		M.cycle(1)
	end)
	map("h", function()
		M.cycle(-1)
	end)
	map("<Right>", function()
		M.cycle(1)
	end)
	map("<Left>", function()
		M.cycle(-1)
	end)
	map("<CR>", function()
		M.cycle(1)
	end)
	map("<Space>", function()
		M.cycle(1)
	end)
	-- Only 1-9 are reachable as single keys ("1" is nowait, so a "10" mapping
	-- could never fire); rows past 9 are reached with j/k or the mouse.
	for i = 1, math.min(9, #ITEMS) do
		map(tostring(i), function()
			ui.sel = i
			render()
		end)
	end
	map("<LeftRelease>", on_click)
	map("<MouseMove>", on_hover)
	map("q", M.close)
	map("<Esc>", M.close)
	-- NOTE: no WinLeave auto-close on purpose — changing "AI column side" makes
	-- toggleterm re-assert its layout (window jumps), which would tear the
	-- modal down mid-interaction. q/<Esc> (or a click outside + q) close it.

	render()
end

vim.api.nvim_create_user_command("NvSinnerMenu", M.open, {
	desc = "NvSinner settings (theme, accent, panel sides, notifications)",
})

return M
