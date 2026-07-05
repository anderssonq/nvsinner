-- ─── :NvSinnerPrompts — prompt library modal ─────────────────────────────────
-- A Mason-style floating panel over settings/prompts.json (the distro's
-- settings/ folder): each row is a reusable AI prompt (title + muted
-- description); picking one copies its full content to the OS clipboard, ready
-- to paste into the AI column's CLI. Keyboard-driven like :NvSinnerMenu
-- (j/k move, <CR>/<Space>/l copy, 1-9 jump, e edit the JSON, q/<Esc> close)
-- AND mouse-driven (hover moves the selection, click copies).
--
-- The library is plain JSON so users add/edit prompts by hand (`e` opens it);
-- `content` may be a string or an array of lines (arrays are easier to edit).
-- The file is re-read on every open, so edits show up without a restart.
-- Styling reuses the NvMenu* groups (defined in lua/core/menu.lua, re-declared
-- here so this module stands alone in tests) — both modals read as one
-- component.

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
	-- Solid modal surface (contrast survives transparent mode — see core/menu.lua).
	set(0, "NvMenuNormal", { fg = c.base04, bg = c.shade })
	set(0, "NvMenuBorder", { fg = c.base02, bg = c.shade })
end
apply_hl()
vim.api.nvim_create_autocmd("ColorScheme", {
	group = vim.api.nvim_create_augroup("nv_prompts_hl", { clear = true }),
	pattern = "*",
	callback = apply_hl,
})

-- ─── The library file ────────────────────────────────────────────────────────
-- Lives in the distro's settings/ folder next to the :NvSinnerMenu cache
-- (core/settings.lua) so all user-tweakable state sits in one place. Committed
-- (it ships the default prompts), unlike the gitignored settings cache.

local file = vim.fn.stdpath("config") .. "/settings/prompts.json"
local items = {}

-- Load + validate the JSON (missing/corrupt → empty library, never an error).
-- Accepts { prompts = [...] } or a bare top-level array. `opts.file` is a test
-- seam (mirrors core/settings.lua).
function M.load(opts)
	if opts and opts.file then
		file = opts.file
	end
	items = {}
	local fd = io.open(file, "r")
	if not fd then
		return items
	end
	local raw = fd:read("*a")
	fd:close()
	local ok, decoded = pcall(vim.json.decode, raw)
	if not ok or type(decoded) ~= "table" then
		return items
	end
	local list = type(decoded.prompts) == "table" and decoded.prompts or decoded
	for _, p in ipairs(list) do
		if type(p) == "table" and type(p.title) == "string" then
			local content
			if type(p.content) == "string" then
				content = p.content
			elseif type(p.content) == "table" then
				content = table.concat(p.content, "\n")
			end
			if content then
				table.insert(items, {
					title = p.title,
					description = type(p.description) == "string" and p.description or "",
					content = content,
				})
			end
		end
	end
	return items
end

-- ─── Rendering ───────────────────────────────────────────────────────────────
-- Two buffer lines per prompt (title row + muted description row), so the
-- line→item math everywhere is: item i owns lines TOP_PAD+2i-1 and TOP_PAD+2i.

local WIDTH = 64
local HINT = "j/k move · ⏎ copy · e edit · 1-9 jump · q close"
local EMPTY = { "No prompts found.", "Press e to edit settings/prompts.json" }
local DESC_PAD = 6 -- indent under the title, past the "  ▸ N  " head
local TOP_PAD = 1
local ns = vim.api.nvim_create_namespace("nvsinner_prompts")

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
	if #items == 0 then
		for _, msg in ipairs(EMPTY) do
			local pad = math.max(0, math.floor((WIDTH - vim.fn.strdisplaywidth(msg)) / 2))
			table.insert(lines, string.rep(" ", pad) .. msg)
		end
	end
	for i, it in ipairs(items) do
		-- Built in segments so the highlight byte offsets are exact (the ▸
		-- marker is multi-byte, so fixed columns would drift).
		local head = string.format(" %s %d  ", (i == ui.sel) and "▸" or " ", i)
		local title = fit(it.title, WIDTH - vim.fn.strdisplaywidth(head) - 1)
		spans[i] = { head = #head, total = #head + #title }
		table.insert(lines, head .. title)
		table.insert(lines, string.rep(" ", DESC_PAD) .. fit(it.description, WIDTH - DESC_PAD - 1))
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
	if #items == 0 then
		for r = TOP_PAD, TOP_PAD + #EMPTY - 1 do
			ext(ui.buf, ns, r, 0, { end_col = #lines[r + 1], hl_group = "NvMenuMuted" })
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

-- Copy the selected prompt to the OS clipboard (+ and * registers), toast,
-- and close — the fzf-library flow: pick → it's on the clipboard → paste into
-- the AI CLI. Returns the copied text (test seam; nil when nothing to copy).
function M.copy()
	local it = items[ui.sel]
	if not it then
		return nil
	end
	local text = it.content
	if not text:match("\n$") then
		text = text .. "\n"
	end
	-- pcall: a headless Neovim without a clipboard provider must not error.
	pcall(vim.fn.setreg, "+", text)
	pcall(vim.fn.setreg, "*", text)
	M.close()
	vim.notify("📋 Prompt copied · " .. it.title, vim.log.levels.INFO)
	return text
end

-- Close the modal and open the library JSON for editing.
function M.edit()
	M.close()
	vim.fn.mkdir(vim.fn.fnamemodify(file, ":h"), "p")
	vim.cmd.edit(file)
end

-- Mouse: click a prompt (either of its two rows) → select it and copy.
local function on_click()
	local mp = vim.fn.getmousepos()
	if mp.winid ~= ui.win then
		return
	end
	local i = line_to_item(mp.line)
	if i then
		ui.sel = i
		M.copy()
	end
end

-- Mouse hover: move the selection pill onto the prompt under the pointer
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
	M.load() -- re-read the JSON so hand edits show up without a restart
	ui.sel = math.min(ui.sel, math.max(1, #items))
	ui.hover_line = -1
	ui.buf = vim.api.nvim_create_buf(false, true)
	vim.bo[ui.buf].buftype = "nofile"
	vim.bo[ui.buf].bufhidden = "wipe"
	vim.bo[ui.buf].filetype = "nvsinner-prompts"

	local body = (#items > 0) and (#items * 2) or #EMPTY
	local height = math.min(TOP_PAD + body + 2, vim.o.lines - 4)
	ui.win = vim.api.nvim_open_win(ui.buf, true, {
		relative = "editor",
		style = "minimal",
		border = "rounded",
		title = "  Prompts ",
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
	map("<CR>", M.copy)
	map("<Space>", M.copy)
	map("l", M.copy)
	map("<Right>", M.copy)
	for i = 1, math.min(9, #items) do
		map(tostring(i), function()
			ui.sel = i
			render()
		end)
	end
	map("e", M.edit)
	map("<LeftRelease>", on_click)
	map("<MouseMove>", on_hover)
	map("q", M.close)
	map("<Esc>", M.close)

	render()
end

vim.api.nvim_create_user_command("NvSinnerPrompts", M.open, {
	desc = "NvSinner prompt library (copy a reusable AI prompt to the clipboard)",
})

return M
