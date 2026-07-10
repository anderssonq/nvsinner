-- ─── Neo-tree hover row wash ───────────────────────────────────────────────
-- The row under the mouse pointer in a neo-tree window gets a full-line
-- background wash — the same hover feel as the NvSinner modals (menu.lua's
-- selection follows the pointer). Driven from ui-touch.lua's single global
-- <MouseMove> handler (only one global map per mode can exist, and <MouseMove>
-- resolves against the FOCUSED buffer's maps — so a buffer-local map on the
-- tree would only fire while the tree itself is focused; hovering it from the
-- code pane is the common case). Native (no plugin), required from init.lua.
--
-- Known limits, accepted on purpose:
--   * <MouseMove> is mapped in n+i only — while focus sits in a terminal
--     (t mode, e.g. the AI column) the wash freezes at its last row. A t-mode
--     map was deliberately NOT added: terminal mode forwards mouse events to
--     the program's own mouse reporting, which the AI-column TUIs rely on.
--   * A focused modal shadows the global map with its buffer-local one — the
--     wash pauses, and the backdrop covers the tree anyway.
--   * getmousepos() clamps `line` to the last buffer line when the pointer is
--     in the empty area below the tree, so the last row stays washed there —
--     matching what a click in that area acts on.

local M = {}

local NS = vim.api.nvim_create_namespace("nvsinner_neotree_hover")

-- Last washed row. The win/line cache makes a pointer sliding within one row
-- cost nothing (no buffer reads, no extmark churn).
local state = { buf = nil, win = nil, line = nil }

-- Solid base01 on purpose (same role as NvMenuSel and CursorLine — the carbon
-- canonical row wash): chips and washes stay legible in transparent mode,
-- where the full surfaces go NONE.
local function apply_hl()
	local c = require("core.carbon").colors()
	vim.api.nvim_set_hl(0, "NvTreeHover", { bg = c.base01 })
end
apply_hl()

local grp = vim.api.nvim_create_augroup("nv_neotree_hover", { clear = true })
vim.api.nvim_create_autocmd("ColorScheme", { group = grp, pattern = "*", callback = apply_hl })

function M.clear()
	if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
		vim.api.nvim_buf_clear_namespace(state.buf, NS, 0, -1)
	end
	state.buf, state.win, state.line = nil, nil, nil
end

-- The whole mechanism. `mp` is a getmousepos()-shaped table ({ winid, line });
-- it is a parameter because mouse events can't be synthesized headless — the
-- spec drives this seam directly.
function M.update(mp)
	local win = mp.winid
	if not win or win == 0 or not vim.api.nvim_win_is_valid(win) then
		return M.clear()
	end
	if vim.api.nvim_win_get_config(win).relative ~= "" then
		return M.clear() -- pointer is over a float (toast, hover doc, modal)
	end
	local buf = vim.api.nvim_win_get_buf(win)
	if vim.bo[buf].filetype ~= "neo-tree" then
		return M.clear()
	end
	if win == state.win and mp.line == state.line then
		return -- same row as last time: nothing to repaint
	end
	if mp.line < 1 or mp.line > vim.api.nvim_buf_line_count(buf) then
		return M.clear()
	end
	local text = vim.api.nvim_buf_get_lines(buf, mp.line - 1, mp.line, false)[1] or ""
	if text == "" then
		return M.clear() -- blank padding rows carry no node, so no wash
	end
	if state.buf and state.buf ~= buf and vim.api.nvim_buf_is_valid(state.buf) then
		-- A second tree window (git_status/buffers source): drop the old mark.
		vim.api.nvim_buf_clear_namespace(state.buf, NS, 0, -1)
	end
	vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
	vim.api.nvim_buf_set_extmark(buf, NS, mp.line - 1, 0, { line_hl_group = "NvTreeHover" })
	state.buf, state.win, state.line = buf, win, mp.line
end

-- The live entry point ui-touch's <MouseMove> handler calls on every event.
function M.on_mouse()
	M.update(vim.fn.getmousepos())
end

-- Teardown the on_move clear-branch can't cover: the tree window closing
-- (neo-tree KEEPS its buffer, so a stale extmark would resurface on the next
-- open) and its content scrolling under a stationary pointer (extmarks track
-- buffer lines, not screen rows — the next <MouseMove> re-washes the right
-- row). ev.match carries the window id for both events.
vim.api.nvim_create_autocmd({ "WinClosed", "WinScrolled" }, {
	group = grp,
	callback = function(ev)
		if state.win and ev.match == tostring(state.win) then
			M.clear()
		end
	end,
})
-- Pointer left the application entirely: <MouseMove> stops firing, so the
-- last row would stay washed until the pointer comes back.
vim.api.nvim_create_autocmd("FocusLost", { group = grp, callback = M.clear })

-- Test seams.
M._ns = NS
M._reset = M.clear

return M
