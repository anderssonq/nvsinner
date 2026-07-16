-- ─── Current-scope indent guide (native) ────────────────────────────────────
-- Replaces indentmini.nvim (which ran with `only_current = true`): a single
-- vertical guide on the indent level that encloses the cursor line, drawn in
-- the carbon panel gray (IndentLineCurrent, base02).
--
-- Shape: a cursor autocmd computes the enclosing scope (top/bottom line + the
-- guide column) into per-buffer state, and a DECORATION PROVIDER paints it
-- with ephemeral overlay extmarks at redraw time — nothing to clear, nothing
-- stale. The scan is clamped to the visible range (the guide only needs to
-- render what's on screen), so a huge file costs the same as a small one.
--
-- Columns are DISPLAY columns: `vim.fn.indent()` expands tabs, and
-- `virt_text_win_col` positions in screen cells, so tab-indented files (this
-- repo) and space-indented files both line up.

local M = {}

local ns = vim.api.nvim_create_namespace("nvsinner_indent")
M._ns = ns -- test seam

M.CHAR = "│"
M.DENYLIST = {
	["neo-tree"] = true,
	alpha = true,
	dashboard = true,
	TelescopePrompt = true,
	toggleterm = true,
	lazy = true,
	mason = true,
	help = true,
	markdown = true, -- prose: indent scopes are meaningless there
}

-- Per-buffer scope: { win, col, top, bot } (lines 1-based, col 0-based cells).
local scopes = {}

function M._scope(buf)
	return scopes[buf]
end

-- Carbon panel gray for the guide (same role the old indentmini spec used).
local function apply_hl()
	local c = require("core.carbon").colors()
	vim.api.nvim_set_hl(0, "IndentLineCurrent", { fg = c.base02 })
end
apply_hl()
vim.api.nvim_create_autocmd("ColorScheme", { pattern = "*", callback = apply_hl })

local function eligible(buf)
	return vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == "" and not M.DENYLIST[vim.bo[buf].filetype]
end

local function blank(lnum)
	return vim.fn.getline(lnum):match("^%s*$") ~= nil
end

-- Recompute the enclosing scope for the cursor position. Runs on cursor
-- movement (normal autocmd context, so vim.fn.indent on the CURRENT buffer is
-- safe); the decoration provider only reads the result.
function M.refresh(buf, win)
	buf = buf or vim.api.nvim_get_current_buf()
	win = win or vim.api.nvim_get_current_win()
	scopes[buf] = nil
	if not eligible(buf) or vim.api.nvim_win_get_buf(win) ~= buf then
		return
	end

	local lnum = vim.api.nvim_win_get_cursor(win)[1]
	local ind = vim.fn.indent(lnum)
	if blank(lnum) then
		-- A blank line belongs to the deeper of its neighboring blocks.
		ind = math.max(vim.fn.indent(vim.fn.prevnonblank(lnum)), vim.fn.indent(vim.fn.nextnonblank(lnum)))
	end
	local col = ind - vim.fn.shiftwidth()
	if ind <= 0 or col < 0 then
		return -- top-level line: no enclosing scope to mark
	end

	-- Members of the scope are the contiguous lines indented PAST the guide
	-- column (blanks ride along). Clamped to the visible range: offscreen
	-- lines never render, so scanning them is waste.
	local vtop = vim.fn.line("w0", win)
	local vbot = vim.fn.line("w$", win)
	local function member(l)
		return blank(l) or vim.fn.indent(l) > col
	end
	local top, bot = lnum, lnum
	while top > vtop and member(top - 1) do
		top = top - 1
	end
	while bot < vbot and member(bot + 1) do
		bot = bot + 1
	end
	-- Trim blank edges — a trailing empty line after a block is not "inside".
	while top < lnum and blank(top) do
		top = top + 1
	end
	while bot > lnum and blank(bot) do
		bot = bot - 1
	end

	scopes[buf] = { win = win, col = col, top = top, bot = bot }
end

-- Paint at redraw time: ephemeral overlay marks, only for the window the
-- scope was computed against (the "current" scope is a cursor concept).
vim.api.nvim_set_decoration_provider(ns, {
	on_win = function(_, win, buf)
		local s = scopes[buf]
		return s ~= nil and s.win == win
	end,
	on_line = function(_, _, buf, row)
		local s = scopes[buf]
		if not s or row + 1 < s.top or row + 1 > s.bot then
			return
		end
		pcall(vim.api.nvim_buf_set_extmark, buf, ns, row, 0, {
			virt_text = { { M.CHAR, "IndentLineCurrent" } },
			virt_text_pos = "overlay",
			virt_text_win_col = s.col,
			hl_mode = "combine",
			ephemeral = true,
			priority = 1,
		})
	end,
})

-- Same-position early-exit: the scope is a pure function of (buffer content,
-- cursor line, viewport, shiftwidth), so when none of those changed since the
-- last recompute — a column-only cursor move (h/l, the hottest CursorMoved
-- case) or a duplicate event — the recompute is skipped. Keyed per buffer;
-- M.refresh itself stays unconditional (the specs call it directly).
local seen = {}

local grp = vim.api.nvim_create_augroup("nv_indent", { clear = true })
vim.api.nvim_create_autocmd(
	{ "CursorMoved", "CursorMovedI", "TextChanged", "TextChangedI", "BufEnter", "WinScrolled" },
	{
		group = grp,
		callback = function(args)
			local buf = args.buf
			local win = vim.api.nvim_get_current_win()
			local key = {
				win = win,
				lnum = vim.api.nvim_win_get_buf(win) == buf and vim.api.nvim_win_get_cursor(win)[1] or 0,
				top = vim.fn.line("w0", win),
				bot = vim.fn.line("w$", win),
				tick = vim.api.nvim_buf_get_changedtick(buf),
			}
			local s = seen[buf]
			if
				s
				and s.win == key.win
				and s.lnum == key.lnum
				and s.top == key.top
				and s.bot == key.bot
				and s.tick == key.tick
			then
				return
			end
			seen[buf] = key
			M.refresh(buf)
		end,
	}
)

-- Test seam: drop cached scopes between specs.
function M._reset()
	scopes = {}
	seen = {}
end

return M
