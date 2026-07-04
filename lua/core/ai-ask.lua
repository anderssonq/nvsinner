-- ─── Ask AI — action modal over the visual selection ────────────────────────
-- IDE-style "select code → ask the AI": visual <leader>x (or :NvSinnerAskAI on
-- the last selection) opens a Mason-style modal with Fix / Refactor / Explain /
-- Ask custom question. Picking an action builds a prompt — action header with
-- the cwd-relative path and line range, then the selected code — and drops it
-- into an AI column's CLI input via core/ai-sessions (bracketed paste, NEVER
-- auto-submitted). With more than one session registered, a vim.ui.select asks
-- which one; with none, send()'s opener fallback kicks in.
--
-- Capture ordering is load-bearing: the selection/range must be read while
-- visual mode is still active (getregion), THEN visual mode is left
-- synchronously, THEN the modal opens (its buffer-local maps assume normal
-- mode). Styling reuses the NvMenu* groups (re-declared so the module stands
-- alone, same as core/help.lua).

local M = {}

local sessions = require("core.ai-sessions")

-- Highlight groups: same names + roles as core/menu.lua on purpose (identical
-- values, so double-applying is harmless).
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
	group = vim.api.nvim_create_augroup("nv_ai_ask_hl", { clear = true }),
	pattern = "*",
	callback = apply_hl,
})

-- ─── Actions ─────────────────────────────────────────────────────────────────

local ITEMS = {
	{ key = "fix", title = "Fix", desc = "Ask the AI to fix the selected code", header = "Fix this code in %s:" },
	{
		key = "refactor",
		title = "Refactor",
		desc = "Ask the AI to refactor the selected code",
		header = "Refactor this code in %s:",
	},
	{
		key = "explain",
		title = "Explain",
		desc = "Ask the AI to explain the selected code",
		header = "Explain this code in %s:",
	},
	{
		key = "ask",
		title = "Ask custom question",
		desc = "Type your own question about the selection",
	},
}

-- The captured selection the modal operates on: { text, path, l1, l2 }.
-- Module state (not a closure) because vim.ui.input/select continuations run
-- async; cleared after dispatch/cancel.
local ctx

local function location(c)
	if c.l1 == c.l2 then
		return string.format("%s:%d", c.path, c.l1)
	end
	return string.format("%s:%d-%d", c.path, c.l1, c.l2)
end

-- Build the payload for an action over a captured context. Pure (test seam).
-- `question` is only used by the "ask" action (it becomes the header).
function M.build(key, c, question)
	local loc = location(c)
	if key == "ask" then
		return question .. "\n" .. "Code in " .. loc .. ":" .. "\n" .. c.text
	end
	for _, it in ipairs(ITEMS) do
		if it.key == key and it.header then
			return it.header:format(loc) .. "\n" .. c.text
		end
	end
	return nil
end

-- ─── Capture ─────────────────────────────────────────────────────────────────

-- Live capture: MUST run while visual mode is active (selection_text uses
-- getregion over v/. which is only correct there). Returns the ctx or nil.
local function capture_visual()
	local text = sessions.selection_text()
	local l1, l2 = vim.fn.line("v"), vim.fn.line(".")
	if l1 > l2 then
		l1, l2 = l2, l1
	end
	local name = vim.api.nvim_buf_get_name(0)
	if not text then
		vim.notify("Nothing selected", vim.log.levels.WARN)
		return nil
	end
	if name == "" then
		vim.notify("Current buffer has no file path", vim.log.levels.WARN)
		return nil
	end
	return { text = text, path = vim.fn.fnamemodify(name, ":."), l1 = l1, l2 = l2 }
end

-- Command-path capture: the LAST visual selection ('< '> marks), since a user
-- command never runs in visual mode.
local function capture_from_marks()
	local ok, region = pcall(vim.fn.getregion, vim.fn.getpos("'<"), vim.fn.getpos("'>"), { type = vim.fn.visualmode() })
	if not ok or #region == 0 then
		vim.notify("Select some code first (visual mode + <leader>x)", vim.log.levels.WARN)
		return nil
	end
	local name = vim.api.nvim_buf_get_name(0)
	if name == "" then
		vim.notify("Current buffer has no file path", vim.log.levels.WARN)
		return nil
	end
	local l1, l2 = vim.fn.line("'<"), vim.fn.line("'>")
	return { text = table.concat(region, "\n"), path = vim.fn.fnamemodify(name, ":."), l1 = l1, l2 = l2 }
end

-- ─── Rendering (help.lua-derived: two buffer lines per action) ───────────────

local WIDTH = 48
local HINT = "j/k move · ⏎ ask · 1-4 jump · q close"
local DESC_PAD = 6
local TOP_PAD = 1
local ns = vim.api.nvim_create_namespace("nvsinner_ai_ask")

local ui = { win = nil, buf = nil, sel = 1, hover_line = -1 }

local function is_open()
	return ui.win and vim.api.nvim_win_is_valid(ui.win)
end

local function title_line(i)
	return TOP_PAD + (i - 1) * 2 + 1
end

local function line_to_item(line)
	local rel = line - TOP_PAD
	if rel < 1 then
		return nil
	end
	local i = math.floor((rel - 1) / 2) + 1
	return (i >= 1 and i <= #ITEMS) and i or nil
end

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
	for i, it in ipairs(ITEMS) do
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
	for i in ipairs(ITEMS) do
		local row = title_line(i) - 1
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

	if is_open() then
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

function M.move(delta)
	ui.sel = math.min(#ITEMS, math.max(1, ui.sel + delta))
	render()
end

-- ─── Dispatch ────────────────────────────────────────────────────────────────

-- Send the payload: auto-target with 0-1 sessions (send()'s opener fallback
-- covers the 0 case); with >1 ask which session first (same label formula as
-- the <leader>ja picker).
local function dispatch(payload)
	local sess = sessions.sessions()
	if #sess <= 1 then
		sessions.send(payload)
		return
	end
	local activity = require("core.ai-activity")
	vim.ui.select(sess, {
		prompt = "Send to AI session",
		format_item = function(s)
			local label = (s.bufnr and vim.api.nvim_buf_is_valid(s.bufnr) and vim.b[s.bufnr].nv_term_label)
				or ("AI · " .. s.n)
			local status = (activity.status and activity.status(s.bufnr)) or (s.open and "idle" or "hidden")
			return string.format("%s — %s", label, status)
		end,
	}, function(s)
		if s then
			sessions.send_to(s, payload)
		end
	end)
end

-- Run the selected action and auto-close. Closing FIRST matters: the send
-- focuses the AI column + startinserts, and vim.ui.input/select may open their
-- own floats — none of that must happen inside this modal. Returns the action
-- key (test seam; nil when there is no captured context).
function M.run()
	local it = ITEMS[ui.sel]
	local c = ctx
	M.close()
	if not it or not c then
		return nil
	end
	if it.key == "ask" then
		vim.ui.input({ prompt = "Ask AI about " .. location(c) .. ": " }, function(q)
			ctx = nil
			if not q or q == "" then
				return
			end
			dispatch(M.build("ask", c, q))
		end)
		return it.key
	end
	ctx = nil
	dispatch(M.build(it.key, c))
	return it.key
end

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

-- Open the modal over an already-captured context (call capture first; the
-- title shows the location so you know what you're asking about).
function M.open(c)
	if c then
		ctx = c
	end
	if not ctx then
		vim.notify("Select some code first (visual mode + <leader>x)", vim.log.levels.WARN)
		return
	end
	if is_open() then
		vim.api.nvim_set_current_win(ui.win)
		return
	end
	ui.sel = 1
	ui.hover_line = -1
	ui.buf = vim.api.nvim_create_buf(false, true)
	vim.bo[ui.buf].buftype = "nofile"
	vim.bo[ui.buf].bufhidden = "wipe"
	vim.bo[ui.buf].filetype = "nvsinner-ai-ask"

	local height = math.min(TOP_PAD + #ITEMS * 2 + 2, vim.o.lines - 4)
	ui.win = vim.api.nvim_open_win(ui.buf, true, {
		relative = "editor",
		style = "minimal",
		border = "rounded",
		title = "  Ask AI · " .. fit(location(ctx), WIDTH - 12) .. " ",
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
	for i = 1, #ITEMS do
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

-- ─── Entry points ────────────────────────────────────────────────────────────

-- Visual <leader>x: capture FIRST (still in visual mode), leave visual mode
-- SYNCHRONOUSLY ("nx" processes the escape now, not via typeahead — a queued
-- <Esc> could land on the AI terminal after the send focuses it), THEN open.
vim.keymap.set("x", "<leader>x", function()
	local c = capture_visual()
	vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
	if c then
		M.open(c)
	end
end, { desc = "Ask AI about selection" })

vim.api.nvim_create_user_command("NvSinnerAskAI", function()
	local c = capture_from_marks()
	if c then
		M.open(c)
	end
end, { desc = "Ask AI about the last visual selection (also <leader>x in visual mode)" })

-- Double-click: IDE-style "click a word → ask the AI". The first click of the
-- pair already moved the cursor into the clicked window, so the handler works
-- on the current window/buffer (getmousepos is useless headless anyway). In
-- normal mode it selects the word under the pointer (superset of the default
-- double-click word-select); with a visual selection active it uses that.
-- Special windows are left alone: floats and non-file buftypes bail silently,
-- and plugins that map <2-LeftMouse> buffer-locally (neo-tree, …) win over
-- this global map. Public (not local) as the test seam — mouse events can't
-- be synthesized headless.
function M.double_click()
	if vim.api.nvim_win_get_config(0).relative ~= "" or vim.bo.buftype ~= "" then
		return
	end
	if vim.api.nvim_buf_get_name(0) == "" then
		return -- casual double-clicks in scratch buffers shouldn't toast
	end
	if not vim.fn.mode():match("[vV\22]") then
		vim.cmd("normal! viw") -- select the clicked word (like the default double-click)
	end
	local c = capture_visual()
	vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
	if c and not c.text:match("^%s*$") then
		M.open(c)
	end
end

vim.keymap.set({ "n", "x" }, "<2-LeftMouse>", M.double_click, { desc = "Ask AI about the word under the pointer" })

-- Test seams.
function M._reset()
	M.close()
	ctx = nil
	ui.sel = 1
end

function M._ctx()
	return ctx
end

return M
