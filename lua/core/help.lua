-- ─── :NvSinnerHelp — command palette for the distro's own commands ───────────
-- A Mason-style floating panel listing every NvSinner command (title + muted
-- description); picking one RUNS it and auto-closes the modal, so this doubles
-- as the discoverability entry point for the whole :NvSinner* surface.
-- Keyboard-driven like :NvSinnerMenu (j/k move, <CR>/<Space>/l run, 1-9 jump,
-- q/<Esc> close) AND mouse-driven (hover moves the selection, click runs).
--
-- The list is built on every open by scanning nvim_get_commands() for names
-- starting with "NvSinner" (their `definition` carries the desc for Lua
-- commands — verified empirically), so future commands show up here without
-- touching this file; EXTRAS appends non-command entry points (:checkhealth
-- nvsinner). DESCS overrides a discovered desc where a keymap hint helps.
-- Styling reuses the NvMenu* groups (re-declared so the module stands alone).

local M = {}

-- Highlight groups: same names + roles as core/menu.lua on purpose (identical
-- values, so double-applying is harmless). Fg-only, so they inherit the float
-- surface and survive transparent mode.
local function apply_hl()
	local c = require("core.carbon").colors()
	local set = vim.api.nvim_set_hl
	set(0, "NvMenuKey", { fg = c.base09, bold = true }) -- the 1-9 shortcut digits
	set(0, "NvMenuLabel", { fg = c.base04 })
	set(0, "NvMenuMuted", { fg = c.base03, italic = true }) -- descriptions, hints
	set(0, "NvMenuSel", { bg = c.base01 }) -- selected row wash (solid on purpose)
end
apply_hl()
vim.api.nvim_create_autocmd("ColorScheme", {
	group = vim.api.nvim_create_augroup("nv_help_hl", { clear = true }),
	pattern = "*",
	callback = apply_hl,
})

-- ─── The command list ────────────────────────────────────────────────────────

-- Description overrides for discovered commands (keymap hints and phrasing the
-- command's own desc can't carry). Anything not listed falls back to the desc
-- registered with nvim_create_user_command.
local DESCS = {
	NvSinnerMenu = "Settings modal — theme, transparency, accent, panel sides",
	NvSinnerPrompts = "Prompt library → OS clipboard (also <leader>p)",
	NvSinnerSync = "Float plugins + Mason packages to latest (rewrites lockfile)",
	NvSinnerUpdate = "git pull + restore pinned plugins + checkhealth",
}

-- Entry points that are not :NvSinner* user commands but belong in the palette.
local EXTRAS = {
	{
		title = ":checkhealth nvsinner",
		cmd = "checkhealth nvsinner",
		desc = "Report missing external tools (ripgrep, node, stylua, …)",
	},
}

local items = {}

-- Rebuild the list: every NvSinner* user command (except this modal's own),
-- sorted by name, then the EXTRAS. Returns it (test seam).
function M.refresh()
	items = {}
	local names = {}
	for name, def in pairs(vim.api.nvim_get_commands({})) do
		if name:match("^NvSinner") and name ~= "NvSinnerHelp" then
			names[#names + 1] = { name = name, def = def }
		end
	end
	table.sort(names, function(a, b)
		return a.name < b.name
	end)
	for _, c in ipairs(names) do
		table.insert(items, {
			title = ":" .. c.name,
			cmd = c.name,
			desc = DESCS[c.name] or c.def.definition or "",
		})
	end
	vim.list_extend(items, EXTRAS)
	return items
end

-- ─── Rendering ───────────────────────────────────────────────────────────────
-- Two buffer lines per command (title row + muted description row), so the
-- line→item math everywhere is: item i owns lines TOP_PAD+2i-1 and TOP_PAD+2i.

local WIDTH = 64
local HINT = "j/k move · ⏎ run · 1-9 jump · q close"
local DESC_PAD = 6 -- indent under the title, past the "  ▸ N  " head
local TOP_PAD = 1
local ns = vim.api.nvim_create_namespace("nvsinner_help")

local ui = { win = nil, buf = nil, sel = 1, hover_line = -1 }

local function is_open()
	return ui.win and vim.api.nvim_win_is_valid(ui.win)
end

local function title_line(i) -- buffer line (1-based) of item i's title row
	return TOP_PAD + (i - 1) * 2 + 1
end

local function line_to_item(line) -- inverse of title_line, both rows map back
	local rel = line - TOP_PAD
	if rel < 1 then
		return nil
	end
	local i = math.floor((rel - 1) / 2) + 1
	return (i >= 1 and i <= #items) and i or nil
end

-- Truncate to the modal width without splitting a multi-byte char.
local function fit(s, max)
	if vim.fn.strdisplaywidth(s) <= max then
		return s
	end
	return vim.fn.strcharpart(s, 0, max - 1) .. "…"
end

local function render()
	local lines, spans = {}, {}
	for _ = 1, TOP_PAD do
		table.insert(lines, "")
	end
	for i, it in ipairs(items) do
		-- Built in segments so the highlight byte offsets are exact (the ▸
		-- marker is multi-byte, so fixed columns would drift).
		local head = string.format(" %s %d  ", (i == ui.sel) and "▸" or " ", i)
		local title = fit(it.title, WIDTH - vim.fn.strdisplaywidth(head) - 1)
		spans[i] = { head = #head, total = #head + #title }
		table.insert(lines, head .. title)
		table.insert(lines, string.rep(" ", DESC_PAD) .. fit(it.desc, WIDTH - DESC_PAD - 1))
	end
	table.insert(lines, "")
	local pad = math.max(0, math.floor((WIDTH - vim.fn.strdisplaywidth(HINT)) / 2))
	table.insert(lines, string.rep(" ", pad) .. HINT)

	vim.bo[ui.buf].modifiable = true
	vim.api.nvim_buf_set_lines(ui.buf, 0, -1, false, lines)
	vim.bo[ui.buf].modifiable = false

	vim.api.nvim_buf_clear_namespace(ui.buf, ns, 0, -1)
	local ext = vim.api.nvim_buf_set_extmark
	for i in ipairs(items) do
		local row = title_line(i) - 1 -- extmarks are 0-based
		local s = spans[i]
		ext(ui.buf, ns, row, 0, { end_col = s.head, hl_group = "NvMenuKey" })
		ext(ui.buf, ns, row, s.head, { end_col = s.total, hl_group = "NvMenuLabel" })
		ext(ui.buf, ns, row + 1, 0, { end_col = #lines[row + 2], hl_group = "NvMenuMuted" })
		if i == ui.sel then
			ext(ui.buf, ns, row, 0, { line_hl_group = "NvMenuSel" })
			ext(ui.buf, ns, row + 1, 0, { line_hl_group = "NvMenuSel" })
		end
	end
	ext(ui.buf, ns, #lines - 1, 0, { end_col = #lines[#lines], hl_group = "NvMenuMuted" })

	if is_open() and #items > 0 then
		vim.api.nvim_win_set_cursor(ui.win, { title_line(ui.sel), 1 })
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
	if #items == 0 then
		return
	end
	ui.sel = math.min(#items, math.max(1, ui.sel + delta))
	render()
end

-- Run the selected command and auto-close. Closing FIRST matters: the target
-- may open its own modal (:NvSinnerMenu, :NvSinnerPrompts) or window
-- (:checkhealth) and must not land inside this float. Returns the command it
-- ran (test seam; nil when nothing selected).
function M.run()
	local it = items[ui.sel]
	if not it then
		return nil
	end
	M.close()
	vim.cmd(it.cmd)
	return it.cmd
end

-- Mouse: click a command (either of its two rows) → select it and run.
local function on_click()
	local mp = vim.fn.getmousepos()
	if mp.winid ~= ui.win then
		return
	end
	local i = line_to_item(mp.line)
	if i then
		ui.sel = i
		M.run()
	end
end

-- Mouse hover: move the selection pill onto the command under the pointer
-- (same feel as :NvSinnerMenu; the buffer-local map also shadows ui-touch's
-- LSP-hover handler over the modal).
local function on_hover()
	local mp = vim.fn.getmousepos()
	if mp.winid ~= ui.win or mp.line == ui.hover_line then
		return
	end
	ui.hover_line = mp.line
	local i = line_to_item(mp.line)
	if i and i ~= ui.sel then
		ui.sel = i
		render()
	end
end

function M.open()
	if is_open() then
		vim.api.nvim_set_current_win(ui.win)
		return
	end
	M.refresh() -- re-scan so commands registered after boot show up
	ui.sel = math.min(ui.sel, math.max(1, #items))
	ui.hover_line = -1
	ui.buf = vim.api.nvim_create_buf(false, true)
	vim.bo[ui.buf].buftype = "nofile"
	vim.bo[ui.buf].bufhidden = "wipe"
	vim.bo[ui.buf].filetype = "nvsinner-help"

	local height = math.min(TOP_PAD + #items * 2 + 2, vim.o.lines - 4)
	ui.win = vim.api.nvim_open_win(ui.buf, true, {
		relative = "editor",
		style = "minimal",
		border = "rounded",
		title = "  NvSinner commands ",
		title_pos = "center",
		width = WIDTH,
		height = height,
		row = math.max(1, math.floor((vim.o.lines - height) / 2) - 1),
		col = math.max(0, math.floor((vim.o.columns - WIDTH) / 2)),
	})
	vim.wo[ui.win].winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder"
	vim.wo[ui.win].cursorline = false

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
	map("<CR>", M.run)
	map("<Space>", M.run)
	map("l", M.run)
	map("<Right>", M.run)
	for i = 1, math.min(9, #items) do
		map(tostring(i), function()
			ui.sel = i
			render()
		end)
	end
	map("<LeftRelease>", on_click)
	map("<MouseMove>", on_hover)
	map("q", M.close)
	map("<Esc>", M.close)

	render()
end

vim.api.nvim_create_user_command("NvSinnerHelp", M.open, {
	desc = "NvSinner command palette (pick a command to run it)",
})

return M
