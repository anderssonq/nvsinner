-- ─── :NvSinnerAgents — the agent cockpit ─────────────────────────────────────
-- One list of every AI column (the toggleterm sessions behind <leader>j /
-- <leader>j2…j9), with a LIVE preview of the selected agent's chat and the two
-- actions the <leader>ja picker never had: focus it, or close it for good.
--
-- Toggling an AI column HIDES it without killing the CLI, so after a while you
-- can have several agents alive that you cannot see, cannot tell apart, and
-- cannot remember what you asked. This is the cockpit for that: pick a row and
-- the preview reminds you what that agent is working on.
--
-- Keyboard (like the other NvSinner modals): j/k move, 1-9 jump, <CR>/<Space>/l
-- focus, d close the agent, r refresh, <C-d>/<C-u> scroll the preview,
-- q/<Esc> close. Mouse: hover moves the selection, click focuses.
--
-- ─── Status detection ───
-- Two layers, because no CLI ships a mechanism that maps to a SPECIFIC column
-- (claude's JSONL transcripts, kiro's session dir and opencode's sqlite are all
-- keyed by session, and several columns can run the same CLI in the same cwd):
--   1. core/ai-activity's status(bufnr) — the nvim_buf_attach output heuristic
--      plus OSC-133 prompt marks. CLI-agnostic, already correct for "is it
--      producing output".
--   2. M.SIGNS — per-CLI signatures matched against the TAIL of the terminal
--      buffer, because each CLI's TUI *is* its status protocol. This is what
--      catches a permission prompt: it produces no output, so layer 1 alone
--      flips it to "idle" after 1.2s when it is really waiting on the user.
-- The SIGNS strings are field-verified, not test-verified (running the real
-- CLIs in CI would burn API credit) — M._scan, the matcher, is fully specced,
-- so a wrong string is a one-line data fix, never a logic bug.
--
-- ─── Two couplings worth knowing ───
-- * Previewing a HIDDEN column works only because core/ai-activity attaches to
--   every terminal buffer on TermOpen: Neovim does not materialise a terminal
--   buffer's lines unless something is attached or it is rendered (see the
--   header of ai-activity.lua). Drop that attachment and hidden previews go
--   blank.
-- * ai-activity's poll timer is busy-gated and stopped while idle, and its
--   on_lines runs in a FAST event context — so this module sweeps invalid
--   buffers itself and runs its OWN vim.uv timer while the modal is open.

local M = {}

local uv = vim.uv or vim.loop

-- ─── Tunables ────────────────────────────────────────────────────────────────

M.SCAN_LINES = 40 -- how much of the terminal tail M.SIGNS is matched against
M.PREVIEW_LINES = 400 -- how much of the chat the preview pane carries
M.POLL_MS = 700 -- live-refresh cadence while the modal is open
-- Height is a share of the screen, NOT of the row count: the list is at most
-- nine sessions, so a content-sized box left the preview — the pane you
-- actually read — two or three lines tall. Sizing off the screen makes the
-- spare height preview room, which is the point of the second pane.
M.HEIGHT_RATIO = 0.8

-- Per-CLI screen signatures, keyed by the command toggleterm spawned
-- (`term.cmd` — exactly the string from the CLI picker). Lua patterns.
-- Adding a CLI is one entry here; an unknown CLI just falls through to
-- ai-activity's signal, so a plain-terminal session never misreports.
M.SIGNS = {
	["claude"] = {
		awaiting = { "Do you want", "❯%s*1%.", "%(y/n%)" },
		working = { "esc to interrupt" },
	},
	["kiro-cli"] = {
		awaiting = { "Allow this action", "%[y/n/t%]" },
		working = { "esc to interrupt", "Thinking" },
	},
	["opencode"] = {
		awaiting = { "❯%s*1%.", "%[y/n%]" },
		working = { "esc to interrupt", "working" },
	},
}

-- ─── Highlights ──────────────────────────────────────────────────────────────
-- Same NvMenu* names + roles as core/menu.lua on purpose (identical values, so
-- double-applying is harmless) — re-declared so this module stands alone. The
-- status chips deliberately REUSE ai-activity's NvAiBusy / NvAiAwait, so a row
-- here and the terminal winbar read as the same component.
local function apply_hl()
	local c = require("core.carbon").colors()
	local set = vim.api.nvim_set_hl
	set(0, "NvMenuKey", { fg = c.base09, bold = true }) -- the 1-9 shortcut digits
	set(0, "NvMenuLabel", { fg = c.base04 })
	set(0, "NvMenuMuted", { fg = c.base03, italic = true }) -- second row, hints
	set(0, "NvMenuSel", { bg = c.base01 }) -- selected row wash (solid on purpose)
	set(0, "NvMenuNormal", { fg = c.base04, bg = c.shade })
	set(0, "NvMenuBorder", { fg = c.base02, bg = c.shade })
	set(0, "NvMenuWarn", { fg = c.base10 }) -- an exited session (attention accent)
	-- Idle chip: muted, non-italic — a chip, not a description.
	set(0, "NvAgentIdle", { fg = c.base03 })
end
apply_hl()
vim.api.nvim_create_autocmd("ColorScheme", {
	group = vim.api.nvim_create_augroup("nv_agents_hl", { clear = true }),
	pattern = "*",
	callback = apply_hl,
})

-- ─── Layout constants ────────────────────────────────────────────────────────

local LIST_WIDTH = 34
local MAX_WIDTH = 120
local MIN_HEIGHT = 10
local MIN_PREVIEW_WIDTH = 24 -- below this the preview is dropped, not squeezed
local TOP_PAD = 1
local HINT = "j/k · ⏎ focus · d close · q"
local ns = vim.api.nvim_create_namespace("nvsinner_agents")

local CHIP = {
	working = " working… ",
	awaiting = " needs input ",
	idle = " idle ",
	exited = " exited ",
}
local CHIP_HL = {
	working = "NvAiBusy",
	awaiting = "NvAiAwait",
	idle = "NvAgentIdle",
	exited = "NvMenuWarn",
}

-- ─── Data ────────────────────────────────────────────────────────────────────

local items = {}
local line_map = {} -- buffer line → item index (both of an item's rows)
local content_lines = 0

-- Last SCAN/PREVIEW lines of a terminal buffer, trailing blanks trimmed.
-- Terminal buffers pad the screen with empty rows, so an untrimmed tail is
-- mostly whitespace.
local function tail(buf, n)
	if not (buf and vim.api.nvim_buf_is_valid(buf)) then
		return {}
	end
	local ok, lines = pcall(vim.api.nvim_buf_get_lines, buf, -n - 1, -1, false)
	if not ok then
		return {}
	end
	while #lines > 0 and lines[#lines]:match("^%s*$") do
		table.remove(lines)
	end
	return lines
end

-- Match a CLI's screen signatures against a tail. Returns "awaiting" (checked
-- first — a permission prompt outranks a stale spinner), "working", or nil for
-- an unknown CLI / no match. Pure: the test seam for the whole detection idea.
function M._scan(cmd, lines)
	local sig = cmd and M.SIGNS[cmd]
	if not sig or type(lines) ~= "table" or #lines == 0 then
		return nil
	end
	local hay = table.concat(lines, "\n")
	for _, p in ipairs(sig.awaiting or {}) do
		if hay:find(p) then
			return "awaiting"
		end
	end
	for _, p in ipairs(sig.working or {}) do
		if hay:find(p) then
			return "working"
		end
	end
	return nil
end

-- The precedence ladder: a screen "awaiting" wins (the CLI is silent while it
-- waits, so ai-activity would call it idle), then ai-activity's "working" (the
-- live output signal), then a screen "working", then whatever ai-activity says.
function M.status_of(row)
	if not row.alive then
		return "exited"
	end
	local buf = row.bufnr
	local base = (buf and vim.api.nvim_buf_is_valid(buf)) and require("core.ai-activity").status(buf) or nil
	local screen = M._scan(row.kind, tail(buf, M.SCAN_LINES))
	if screen == "awaiting" then
		return "awaiting"
	end
	if base == "working" or screen == "working" then
		return "working"
	end
	return base or "idle"
end

-- One row. `term` is nil for a panel the registry no longer knows (its CLI
-- exited — ai-sessions' on_exit unregistered it while toggleterm's memo
-- survived); those are exactly the ones worth clearing, so they must be listed.
local function make_row(n, term, open, alive)
	local bufnr = term and term.bufnr or nil
	if bufnr and not vim.api.nvim_buf_is_valid(bufnr) then
		bufnr = nil
	end
	-- The label formula ai-sessions' clear picker and <leader>ja already use,
	-- so all three surfaces name a session identically.
	local ok, label = pcall(function()
		return bufnr and vim.b[bufnr].nv_term_label or nil
	end)
	-- The CLI is the interesting identity; "shell" is a session the picker
	-- launched as a plain terminal, "session" one whose CLI is gone (a dead
	-- memo carries no Terminal, so there is nothing left to name it by).
	local kind = "session"
	if term then
		kind = term.cmd or "shell"
	end
	local row = {
		n = n,
		term = term,
		bufnr = bufnr,
		open = open and true or false,
		alive = alive and true or false,
		label = (ok and label) or ("AI · " .. n),
		kind = kind,
	}
	row.status = M.status_of(row)
	return row
end

-- Rebuild the rows AND the layout in one pass (two buffer lines per item, so
-- rows are non-uniform and hover/click need an explicit line → item map).
-- Returns the items (test seam, like help.refresh()).
function M.refresh()
	local sessions = require("core.ai-sessions")
	items = {}
	local seen = {}
	for _, s in ipairs(sessions.sessions()) do
		seen[s.n] = true
		items[#items + 1] = make_row(s.n, s.term, s.open, true)
	end
	for _, n in ipairs(sessions.panel_numbers()) do
		if not seen[n] then
			items[#items + 1] = make_row(n, nil, false, false)
		end
	end
	table.sort(items, function(a, b)
		return a.n < b.n
	end)

	line_map = {}
	local line = TOP_PAD
	for i, it in ipairs(items) do
		line = line + 1
		it.line = line
		line_map[line] = i
		line = line + 1
		line_map[line] = i
	end
	content_lines = line
	return items
end

function M._items() -- test seam
	return items
end

-- Inject a row list directly (test seam: real AI columns can't be spawned in
-- bulk headless). Recomputes the layout so render() stays valid.
function M._set_items(list)
	items = list or {}
	line_map = {}
	local line = TOP_PAD
	for i, it in ipairs(items) do
		line = line + 1
		it.line = line
		line_map[line] = i
		line = line + 1
		line_map[line] = i
	end
	content_lines = line
	return items
end

-- The preview pane's content: the selected agent's chat tail. Trailing blanks
-- are already trimmed by tail(); an empty/dead buffer gets a placeholder.
function M._preview_lines(it)
	if not it then
		return { "", "  no session selected" }
	end
	local lines = tail(it.bufnr, M.PREVIEW_LINES)
	if #lines == 0 then
		return { "", "  " .. (it.alive and "no output yet" or "session exited — press d to clear it") }
	end
	return lines
end

-- ─── Geometry ────────────────────────────────────────────────────────────────
-- Two side-by-side floats. nvim_open_win's `width` is the INNER width and the
-- rounded border adds one column each side, so the screen span of the pair is
-- list + preview + 5 (two borders each, one column of gap). The preview is
-- dropped rather than squeezed when the terminal is too narrow.

local function geometry()
	local outer_max = math.min(MAX_WIDTH, vim.o.columns - 4)
	local list_w = math.min(LIST_WIDTH, math.max(20, outer_max - 2))
	local prev_w = outer_max - list_w - 5
	local has_preview = prev_w >= MIN_PREVIEW_WIDTH
	local height = math.max(MIN_HEIGHT, math.floor(vim.o.lines * M.HEIGHT_RATIO))
	height = math.min(height, math.max(5, vim.o.lines - 4))
	local outer = has_preview and (list_w + prev_w + 5) or (list_w + 2)
	local col = math.max(0, math.floor((vim.o.columns - outer) / 2) + 1)
	local row = math.max(1, math.floor((vim.o.lines - height) / 2) - 1)
	return {
		list_w = list_w,
		prev_w = prev_w,
		has_preview = has_preview,
		height = height,
		row = row,
		col = col,
	}
end

-- ─── Rendering ───────────────────────────────────────────────────────────────

local ui = { win = nil, buf = nil, pwin = nil, pbuf = nil, sel = 1, hover_line = -1, follow = true, sig = nil }

local function is_open()
	return ui.win and vim.api.nvim_win_is_valid(ui.win)
end

local function preview_open()
	return ui.pwin and vim.api.nvim_win_is_valid(ui.pwin)
end

-- Truncate to a display width without splitting a multi-byte char.
local function fit(s, max)
	if vim.fn.strdisplaywidth(s) <= max then
		return s
	end
	return vim.fn.strcharpart(s, 0, math.max(1, max - 1)) .. "…"
end

-- Border title: the aggregate the cockpit exists to answer at a glance.
local function list_title()
	local working, awaiting = 0, 0
	for _, it in ipairs(items) do
		if it.status == "working" then
			working = working + 1
		elseif it.status == "awaiting" then
			awaiting = awaiting + 1
		end
	end
	local t = "  Agents · " .. #items
	if working > 0 then
		t = t .. " · " .. working .. " working"
	end
	if awaiting > 0 then
		t = t .. " · " .. awaiting .. " needs input"
	end
	return t .. " "
end

local function preview_title(it)
	if not it then
		return "  Preview "
	end
	return "  " .. it.label .. " · " .. it.kind .. " "
end

-- Repaint the preview pane. The buffer is only rewritten when its content
-- actually changed (cheap signature), so a user reading a still chat is not
-- yanked back to the bottom twice a second by the poll timer.
local function render_preview()
	if not preview_open() then
		return
	end
	local it = items[ui.sel]
	local lines = M._preview_lines(it)
	local sig = ui.sel .. "|" .. #lines .. "|" .. (lines[#lines] or "")
	pcall(vim.api.nvim_win_set_config, ui.pwin, { title = preview_title(it), title_pos = "center" })
	if sig == ui.sig then
		return
	end
	ui.sig = sig
	vim.bo[ui.pbuf].modifiable = true
	vim.api.nvim_buf_set_lines(ui.pbuf, 0, -1, false, lines)
	vim.bo[ui.pbuf].modifiable = false
	if ui.follow then
		-- Park the view on the tail — the newest turn is the one you want.
		pcall(vim.api.nvim_win_set_cursor, ui.pwin, { #lines, 0 })
	end
end

local function render()
	if not is_open() then
		return
	end
	local g = geometry()
	local lines, spans = {}, {}
	for l = 1, content_lines do
		lines[l] = ""
	end
	for i, it in ipairs(items) do
		-- Built in segments so the extmark byte offsets are exact (the ▸ marker
		-- and the chip glyphs are multi-byte, so fixed columns would drift).
		local head = string.format(" %s %d  ", (i == ui.sel) and "▸" or " ", i)
		local chip = CHIP[it.status] or CHIP.idle
		local room = g.list_w - vim.fn.strdisplaywidth(head) - vim.fn.strdisplaywidth(chip)
		local name = fit(it.kind, math.max(3, room - 1))
		local pad = string.rep(" ", math.max(0, room - vim.fn.strdisplaywidth(name)))
		spans[i] = {
			head = #head,
			name = #head + #name + #pad,
			total = #head + #name + #pad + #chip,
		}
		lines[it.line] = head .. name .. pad .. chip
		local where = it.alive and (it.open and "column open" or "hidden") or "CLI exited"
		lines[it.line + 1] = "      " .. fit(it.label .. " · " .. where, g.list_w - 7)
	end
	table.insert(lines, "")
	local pad = math.max(0, math.floor((g.list_w - vim.fn.strdisplaywidth(HINT)) / 2))
	table.insert(lines, string.rep(" ", pad) .. HINT)

	vim.bo[ui.buf].modifiable = true
	vim.api.nvim_buf_set_lines(ui.buf, 0, -1, false, lines)
	vim.bo[ui.buf].modifiable = false

	vim.api.nvim_buf_clear_namespace(ui.buf, ns, 0, -1)
	local ext = vim.api.nvim_buf_set_extmark
	for i, it in ipairs(items) do
		local row = it.line - 1 -- extmarks are 0-based
		local s = spans[i]
		ext(ui.buf, ns, row, 0, { end_col = s.head, hl_group = "NvMenuKey" })
		ext(ui.buf, ns, row, s.head, { end_col = s.name, hl_group = "NvMenuLabel" })
		ext(ui.buf, ns, row, s.name, { end_col = s.total, hl_group = CHIP_HL[it.status] or "NvAgentIdle" })
		ext(ui.buf, ns, row + 1, 0, { end_col = #lines[row + 2], hl_group = "NvMenuMuted" })
		if i == ui.sel then
			ext(ui.buf, ns, row, 0, { line_hl_group = "NvMenuSel" })
			ext(ui.buf, ns, row + 1, 0, { line_hl_group = "NvMenuSel" })
		end
	end
	ext(ui.buf, ns, #lines - 1, 0, { end_col = #lines[#lines], hl_group = "NvMenuMuted" })

	pcall(vim.api.nvim_win_set_config, ui.win, { title = list_title(), title_pos = "center" })
	if #items > 0 and items[ui.sel] then
		pcall(vim.api.nvim_win_set_cursor, ui.win, { items[ui.sel].line, 1 })
	end
	render_preview()
end

-- Keep both floats at the size the current row count wants (sessions can start
-- or die while the modal is open).
local function sync_size()
	if not is_open() then
		return
	end
	local g = geometry()
	local cfg = vim.api.nvim_win_get_config(ui.win)
	if cfg.height ~= g.height or cfg.row ~= g.row then
		pcall(vim.api.nvim_win_set_config, ui.win, { relative = "editor", row = g.row, col = g.col, height = g.height })
		if preview_open() then
			pcall(vim.api.nvim_win_set_config, ui.pwin, {
				relative = "editor",
				row = g.row,
				col = g.col + g.list_w + 3,
				height = g.height,
			})
		end
	end
end

-- ─── Live refresh ────────────────────────────────────────────────────────────
-- Our OWN timer: ai-activity's is busy-gated (zero ticks while every agent is
-- idle) and its on_lines is a fast event context, so neither can drive a modal.
-- The handle lives on M so luv can't GC-reap an active timer (the rule
-- ai-activity / git-blame / autoreload all document).

M._timer = assert(uv.new_timer())
M._ticking = false

local function stop_timer()
	if not M._ticking then
		return
	end
	M._timer:stop()
	M._ticking = false
end

local function start_timer()
	if M._ticking then
		return
	end
	M._ticking = true
	M._timer:start(
		M.POLL_MS,
		M.POLL_MS,
		vim.schedule_wrap(function()
			if not is_open() then
				stop_timer()
				return
			end
			-- Repainting under a cmdline is disruptive (same guard as
			-- ai-activity.tick()).
			if vim.fn.mode() == "c" then
				return
			end
			M.refresh()
			ui.sel = math.min(ui.sel, math.max(1, #items))
			sync_size()
			render()
		end)
	)
end

-- ─── Actions ─────────────────────────────────────────────────────────────────

function M.close()
	stop_timer()
	if preview_open() then
		pcall(vim.api.nvim_win_close, ui.pwin, true)
	end
	if ui.pbuf and vim.api.nvim_buf_is_valid(ui.pbuf) then
		pcall(vim.api.nvim_buf_delete, ui.pbuf, { force = true })
	end
	ui.pwin, ui.pbuf, ui.sig = nil, nil, nil
	if is_open() then
		pcall(vim.api.nvim_win_close, ui.win, true)
	end
	if ui.buf and vim.api.nvim_buf_is_valid(ui.buf) then
		pcall(vim.api.nvim_buf_delete, ui.buf, { force = true })
	end
	ui.win, ui.buf = nil, nil
end

function M.move(delta)
	if #items == 0 then
		return
	end
	ui.sel = math.min(#items, math.max(1, ui.sel + delta))
	ui.follow = true -- a new selection always starts at the tail
	render()
end

-- Focus the selected agent's column, opening it first when it is hidden.
-- Closing the modal FIRST is mandatory, not cosmetic: the backdrop's WinEnter
-- focus trap would bounce us straight back out, and toggleterm's opener runs
-- restore_layout(), which shuffles focus across windows. Returns the row.
function M.focus()
	local it = items[ui.sel]
	if not it then
		return nil
	end
	M.close()
	local win = it.term and it.term.window
	if it.open and win and vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_set_current_win(win)
		vim.cmd("startinsert!")
	else
		require("core.ai-sessions").open_session(it.n)
	end
	return it
end

-- Close the selected agent for good — ai-sessions.clear kills the CLI, drops
-- toggleterm's memo (so the next open re-asks which CLI to run) and toasts.
-- The modal STAYS open so you can clear several in a row; it closes itself
-- once nothing is left to list. Returns the session number.
function M.kill()
	local it = items[ui.sel]
	if not it then
		return nil
	end
	require("core.ai-sessions").clear(it.n)
	M.refresh()
	if #items == 0 then
		M.close()
		return it.n
	end
	ui.sel = math.min(ui.sel, #items)
	ui.follow = true
	sync_size()
	render()
	return it.n
end

-- Scroll the preview pane without leaving the list (it is non-focusable).
function M.scroll(delta)
	if not preview_open() then
		return
	end
	ui.follow = false -- stop the poll timer yanking the view back to the tail
	local key = vim.api.nvim_replace_termcodes(delta > 0 and "<C-d>" or "<C-u>", true, false, true)
	pcall(vim.api.nvim_win_call, ui.pwin, function()
		vim.cmd("normal! " .. key)
	end)
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
		M.focus()
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
		ui.follow = true
		render()
	end
end

-- ─── Open ────────────────────────────────────────────────────────────────────

function M.open()
	if is_open() then
		vim.api.nvim_set_current_win(ui.win)
		return
	end
	M.refresh()
	if #items == 0 then
		vim.notify("No AI sessions yet — open one with <leader>j", vim.log.levels.WARN)
		return
	end
	ui.sel = math.min(math.max(ui.sel, 1), #items)
	ui.hover_line = -1
	ui.follow = true
	ui.sig = nil

	local g = geometry()
	ui.buf = vim.api.nvim_create_buf(false, true)
	vim.bo[ui.buf].buftype = "nofile"
	vim.bo[ui.buf].bufhidden = "wipe"
	vim.bo[ui.buf].filetype = "nvsinner-agents"

	ui.win = vim.api.nvim_open_win(ui.buf, true, {
		relative = "editor",
		style = "minimal",
		border = "rounded",
		title = list_title(),
		title_pos = "center",
		width = g.list_w,
		height = g.height,
		row = g.row,
		col = g.col,
	})
	vim.wo[ui.win].winhighlight = "Normal:NvMenuNormal,FloatBorder:NvMenuBorder"
	vim.wo[ui.win].cursorline = false

	if g.has_preview then
		ui.pbuf = vim.api.nvim_create_buf(false, true)
		vim.bo[ui.pbuf].buftype = "nofile"
		vim.bo[ui.pbuf].bufhidden = "wipe"
		vim.bo[ui.pbuf].filetype = "nvsinner-agents-preview"
		-- focusable = false keeps the backdrop's WinEnter trap out of it (and
		-- the list keeps the keyboard); noautocmd so opening it can't fire the
		-- editor-wide Win/Buf events the modals guard against.
		local ok, pwin = pcall(vim.api.nvim_open_win, ui.pbuf, false, {
			relative = "editor",
			style = "minimal",
			border = "rounded",
			title = preview_title(items[ui.sel]),
			title_pos = "center",
			width = g.prev_w,
			height = g.height,
			row = g.row,
			col = g.col + g.list_w + 3,
			focusable = false,
			noautocmd = true,
		})
		if ok then
			ui.pwin = pwin
			vim.wo[ui.pwin].winhighlight = "Normal:NvMenuNormal,FloatBorder:NvMenuBorder"
			-- Wrap, but break on word boundaries: an agent's prose is the
			-- point, and a mid-word split makes a narrow pane unreadable.
			vim.wo[ui.pwin].wrap = true
			vim.wo[ui.pwin].linebreak = true
			vim.wo[ui.pwin].cursorline = false
		end
	end

	require("core.backdrop").attach(ui.win) -- dim + interaction guard
	-- The backdrop tears itself down on the list window's WinClosed; the
	-- preview float is ours, so mirror that teardown for a close by any route
	-- (:q, a window command) rather than only through M.close().
	vim.api.nvim_create_autocmd("WinClosed", {
		group = vim.api.nvim_create_augroup("nv_agents_win", { clear = true }),
		pattern = tostring(ui.win),
		once = true,
		callback = function()
			stop_timer()
			if preview_open() then
				pcall(vim.api.nvim_win_close, ui.pwin, true)
			end
			ui.pwin, ui.pbuf, ui.sig = nil, nil, nil
		end,
	})

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
	map("<CR>", M.focus)
	map("<Space>", M.focus)
	map("l", M.focus)
	map("<Right>", M.focus)
	map("d", M.kill)
	map("r", function()
		M.refresh()
		ui.sel = math.min(ui.sel, math.max(1, #items))
		sync_size()
		render()
	end)
	map("<C-d>", function()
		M.scroll(1)
	end)
	map("<C-u>", function()
		M.scroll(-1)
	end)
	-- All nine digits are mapped (not just the ones that exist right now):
	-- rows appear and disappear while the modal is open.
	for i = 1, 9 do
		map(tostring(i), function()
			if items[i] then
				ui.sel = i
				ui.follow = true
				render()
			end
		end)
	end
	map("<LeftRelease>", on_click)
	map("<MouseMove>", on_hover)
	map("q", M.close)
	map("<Esc>", M.close)

	render()
	start_timer()
end

-- Test seam: wipe the modal + row state between specs.
function M._reset()
	M.close()
	items, line_map, content_lines = {}, {}, 0
	ui.sel, ui.hover_line, ui.follow = 1, -1, true
end

vim.api.nvim_create_user_command("NvSinnerAgents", M.open, {
	desc = "Agent cockpit — every AI column with its status, a chat preview, focus + close (<leader>xa)",
})

return M
