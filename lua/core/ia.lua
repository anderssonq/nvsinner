-- ─── :NvSinnerIA — the AI hub modal ──────────────────────────────────────────
-- A Mason-style floating panel that consolidates every AI entry point in one
-- place (so :NvSinnerHelp shows a single "NvSinnerIA" row instead of scattered
-- commands). Two kinds of rows in two sections:
--   SETTINGS — toggle inline completion on/off, and pick the completion model
--              from the live OpenCode Zen "Go" catalogue (recommended ones ✓).
--   ACTIONS  — run :NvSinnerAskAI / :NvSinnerComplete / :NvSinnerPrompts.
-- Keyboard-driven like the other modals (j/k move, <CR>/<Space>/l activate,
-- h back, 1-9 jump, q/<Esc> close) AND mouse-driven (hover moves, click
-- activates). Styling reuses the NvMenu* groups; backdrop dims the editor.
--
-- Each row carries a `kind`: "toggle" flips a boolean setting in place, "select"
-- opens a vim.ui.select model picker, "action" runs a command and closes (same
-- close-first rationale as help.run(): the target opens its own modal).

local M = {}

local settings = require("core.settings")

-- Highlight groups: same names + roles as core/menu.lua and core/help.lua on
-- purpose (identical values, double-applying is harmless). Fg-only so they
-- inherit the float surface and survive transparent mode.
local function apply_hl()
	local c = require("core.carbon").colors()
	local set = vim.api.nvim_set_hl
	set(0, "NvMenuKey", { fg = c.base09, bold = true }) -- the 1-9 shortcut digits
	set(0, "NvMenuLabel", { fg = c.base04 })
	set(0, "NvMenuValue", { fg = c.base09, bold = true }) -- ‹ value ›
	set(0, "NvMenuMuted", { fg = c.base03, italic = true }) -- hints
	set(0, "NvMenuSel", { bg = c.base01 }) -- selected row wash (solid on purpose)
	set(0, "NvMenuSection", { fg = c.base03, bold = true }) -- section rule headers
	set(0, "NvMenuNormal", { fg = c.base04, bg = c.shade })
	set(0, "NvMenuBorder", { fg = c.base02, bg = c.shade })
end
apply_hl()
vim.api.nvim_create_autocmd("ColorScheme", {
	group = vim.api.nvim_create_augroup("nv_ia_hl", { clear = true }),
	pattern = "*",
	callback = apply_hl,
})

-- ─── Rows ────────────────────────────────────────────────────────────────────
local function bool_show(on, off)
	return function(v)
		return v and on or off
	end
end

-- Section display names (order = display order).
local SECTIONS = { settings = "SETTINGS", actions = "ACTIONS" }
local SECTION_ORDER = { "settings", "actions" }

local ROWS = {
	{
		kind = "toggle",
		section = "settings",
		label = "AI completion",
		key = "ai_complete",
		show = bool_show("on", "off"),
	},
	{ kind = "select", section = "settings", label = "Model" },
	{ kind = "action", section = "actions", label = "Ask AI (selection)", cmd = "NvSinnerAskAI" },
	{ kind = "action", section = "actions", label = "Complete at cursor", cmd = "NvSinnerComplete" },
	{ kind = "action", section = "actions", label = "Prompt library", cmd = "NvSinnerPrompts" },
}

function M._rows() -- test seam
	return ROWS
end

-- The value shown for a settings row (nil for actions).
local function row_value(row)
	if row.kind == "toggle" then
		local v = settings.get(row.key)
		return row.show and row.show(v) or tostring(v)
	elseif row.kind == "select" then
		return settings.get("ai_model") or require("core.ai-complete").DEFAULT_MODEL
	end
	return nil
end

local WIDTH = 52
local LABELW = 20 -- widest label + gap
local HINT = "j/k move · ⏎ select · 1-9 jump · q close"
local TOP_PAD = 1
local ns = vim.api.nvim_create_namespace("nvsinner_ia")

-- ─── Layout + rendering ──────────────────────────────────────────────────────
local headers = {} -- { line = <1-based>, text = "SETTINGS" }
local row_line = {} -- row index → buffer line (1-based)
local line_map = {} -- buffer line → row index
local content_lines = 0

local function compute_layout()
	headers, row_line, line_map = {}, {}, {}
	local line = TOP_PAD
	local prev
	for i, row in ipairs(ROWS) do
		if row.section ~= prev then
			line = line + 1
			table.insert(headers, { line = line, text = SECTIONS[row.section] or row.section:upper() })
			prev = row.section
		end
		line = line + 1
		row_line[i] = line
		line_map[line] = i
	end
	content_lines = line
end

local ui = { win = nil, buf = nil, sel = 1, hover_line = -1 }

local function is_open()
	return ui.win and vim.api.nvim_win_is_valid(ui.win)
end

local function render()
	local lines, spans = {}, {}
	for l = 1, content_lines do
		lines[l] = ""
	end
	for _, h in ipairs(headers) do
		local label = " ─ " .. h.text .. " "
		lines[h.line] = label .. string.rep("─", math.max(0, WIDTH - vim.fn.strdisplaywidth(label) - 2))
	end
	for i, row in ipairs(ROWS) do
		-- Segments so highlight byte offsets are exact (the ▸ marker is multi-byte).
		local head = string.format(" %s %d  ", (i == ui.sel) and "▸" or " ", i)
		local label = string.format("%-" .. LABELW .. "s", row.label)
		local val = row_value(row)
		local value = val and ("‹ " .. val .. " ›") or ""
		spans[i] = { head = #head, label = #head + #label, total = #head + #label + #value }
		lines[row_line[i]] = head .. label .. value
	end
	table.insert(lines, "")
	local pad = math.max(0, math.floor((WIDTH - vim.fn.strdisplaywidth(HINT)) / 2))
	table.insert(lines, string.rep(" ", pad) .. HINT)

	vim.bo[ui.buf].modifiable = true
	vim.api.nvim_buf_set_lines(ui.buf, 0, -1, false, lines)
	vim.bo[ui.buf].modifiable = false

	vim.api.nvim_buf_clear_namespace(ui.buf, ns, 0, -1)
	local ext = vim.api.nvim_buf_set_extmark
	for _, h in ipairs(headers) do
		ext(ui.buf, ns, h.line - 1, 0, { end_col = #lines[h.line], hl_group = "NvMenuSection" })
	end
	for i in ipairs(ROWS) do
		local r = row_line[i] - 1
		local s = spans[i]
		ext(ui.buf, ns, r, 0, { end_col = s.head, hl_group = "NvMenuKey" })
		ext(ui.buf, ns, r, s.head, { end_col = s.label, hl_group = "NvMenuLabel" })
		if s.total > s.label then
			ext(ui.buf, ns, r, s.label, { end_col = s.total, hl_group = "NvMenuValue" })
		end
		if i == ui.sel then
			ext(ui.buf, ns, r, 0, { line_hl_group = "NvMenuSel" })
		end
	end
	ext(ui.buf, ns, #lines - 1, 0, { end_col = #lines[#lines], hl_group = "NvMenuMuted" })

	if is_open() then
		vim.api.nvim_win_set_cursor(ui.win, { row_line[ui.sel], 1 })
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

function M.move(delta)
	ui.sel = math.min(#ROWS, math.max(1, ui.sel + delta))
	render()
end

-- ─── Model picker ────────────────────────────────────────────────────────────
-- Build the ordered option list: recommended ✓ first (in RECOMMENDED order),
-- then the rest of the catalogue. `catalog` is the fetched id list or the
-- curated fallback. Returns { { id, display }, … } (test seam via _model_items).
function M._model_items(catalog)
	local ai = require("core.ai-complete")
	local ids = catalog or ai.FALLBACK_MODELS
	local rec, seen = {}, {}
	for _, r in ipairs(ai.RECOMMENDED) do
		rec[r] = true
	end
	local items = {}
	local function add(id)
		if not seen[id] then
			seen[id] = true
			items[#items + 1] = { id = id, display = (rec[id] and "✓ " or "  ") .. id }
		end
	end
	for _, r in ipairs(ai.RECOMMENDED) do
		if vim.tbl_contains(ids, r) then
			add(r)
		end
	end
	for _, id in ipairs(ids) do
		add(id)
	end
	return items
end

-- Persist the chosen model + re-render (test seam — the vim.ui.select callback
-- routes here so the pick logic is exercised without a real popup).
function M._choose_model(id)
	if type(id) == "string" and id ~= "" then
		settings.set("ai_model", id)
	end
	if is_open() then
		render()
	end
end

local function open_model_picker()
	require("core.ai-complete").fetch_models(function(ids)
		local items = M._model_items(ids)
		local current = settings.get("ai_model")
		vim.ui.select(items, {
			prompt = "AI completion model" .. (ids and "" or " (offline — curated list)"),
			format_item = function(it)
				return it.display .. (it.id == current and "  (current)" or "")
			end,
		}, function(choice)
			if choice then
				M._choose_model(choice.id)
			end
		end)
	end)
end

-- ─── Activation ──────────────────────────────────────────────────────────────
-- Dispatch by row kind: toggle flips in place, select opens the picker, action
-- runs the command and closes (close FIRST — the target opens its own modal).
function M.activate()
	local row = ROWS[ui.sel]
	if not row then
		return
	end
	if row.kind == "toggle" then
		settings.set(row.key, not settings.get(row.key))
		render()
	elseif row.kind == "select" then
		open_model_picker()
	elseif row.kind == "action" then
		M.close()
		vim.cmd(row.cmd)
	end
end

-- h / <Left>: same as activate for settings rows (a boolean flip / the picker);
-- a no-op on action rows (there's nothing to go "back" to).
function M.activate_back()
	local row = ROWS[ui.sel]
	if row and (row.kind == "toggle" or row.kind == "select") then
		M.activate()
	end
end

-- ─── Mouse ───────────────────────────────────────────────────────────────────
local function on_click()
	local mp = vim.fn.getmousepos()
	if mp.winid ~= ui.win then
		return
	end
	local i = line_map[mp.line]
	if i then
		ui.sel = i
		M.activate()
	end
end

local function on_hover()
	local mp = vim.fn.getmousepos()
	if mp.winid ~= ui.win or mp.line == ui.hover_line then
		return
	end
	ui.hover_line = mp.line
	local i = line_map[mp.line]
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
	compute_layout()
	ui.sel = math.min(ui.sel, #ROWS)
	ui.hover_line = -1
	ui.buf = vim.api.nvim_create_buf(false, true)
	vim.bo[ui.buf].buftype = "nofile"
	vim.bo[ui.buf].bufhidden = "wipe"
	vim.bo[ui.buf].filetype = "nvsinner-ia"

	local height = content_lines + 2
	ui.win = vim.api.nvim_open_win(ui.buf, true, {
		relative = "editor",
		style = "minimal",
		border = "rounded",
		title = "  NvSinner · AI ",
		title_pos = "center",
		width = WIDTH,
		height = height,
		row = math.max(1, math.floor((vim.o.lines - height) / 2) - 1),
		col = math.max(0, math.floor((vim.o.columns - WIDTH) / 2)),
	})
	vim.wo[ui.win].winhighlight = "Normal:NvMenuNormal,FloatBorder:NvMenuBorder"
	vim.wo[ui.win].cursorline = false
	require("core.backdrop").attach(ui.win)

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
	map("<CR>", M.activate)
	map("<Space>", M.activate)
	map("l", M.activate)
	map("<Right>", M.activate)
	map("h", M.activate_back)
	map("<Left>", M.activate_back)
	for i = 1, math.min(9, #ROWS) do
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

vim.api.nvim_create_user_command("NvSinnerIA", M.open, {
	desc = "AI hub — completion on/off, model, Ask-AI, prompts",
})

return M
