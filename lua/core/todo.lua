-- ─── TODO-comment keyword highlights (native) ────────────────────────────────
-- Replaces todo-comments.nvim (and drops a plenary consumer): `TODO:` /
-- `FIXME:` / `HACK:` … keywords get a solid accent chip (dark base00 text on
-- a carbon accent bg, bold), scanned with plain Lua patterns over the
-- VISIBLE range only. The colon is required — same as the plugin's default
-- pattern — so prose mentions of "todo" never light up; an optional
-- `(author)` tag is included in the chip (`TODO(andersson):`).
--
-- Search integration (`:TodoTelescope`) is intentionally NOT replicated:
-- telescope live-grep covers it until the native NvSinnerFind picker exists
-- (see docs/native-roadmap.md).

local M = {}

local ns = vim.api.nvim_create_namespace("nvsinner_todo")
M._ns = ns -- test seam

-- Keyword families → carbon roles, semantic like the rest of the chrome:
-- green base13 is carbon's Todo tone, magenta base10 is attention/error,
-- purple base14 is the DiagnosticWarn tone.
local FAMILIES = {
	{ group = "NvTodoTodo", role = "base13", kws = { "TODO" } },
	{ group = "NvTodoFix", role = "base10", kws = { "FIX", "FIXME", "BUG", "FIXIT", "ISSUE" } },
	{ group = "NvTodoWarn", role = "base14", kws = { "HACK", "WARN", "WARNING", "XXX" } },
	{ group = "NvTodoPerf", role = "base15", kws = { "PERF", "OPTIM", "PERFORMANCE", "OPTIMIZE" } },
	{ group = "NvTodoNote", role = "base08", kws = { "NOTE", "INFO" } },
	{ group = "NvTodoTest", role = "base07", kws = { "TEST", "TESTING", "PASSED", "FAILED" } },
}

M.KEYWORDS = {} -- keyword -> hl group (public: the recognized set)
for _, fam in ipairs(FAMILIES) do
	for _, kw in ipairs(fam.kws) do
		M.KEYWORDS[kw] = fam.group
	end
end

local function apply_hl()
	local c = require("core.carbon").colors()
	for _, fam in ipairs(FAMILIES) do
		vim.api.nvim_set_hl(0, fam.group, { fg = c.base00, bg = c[fam.role], bold = true })
	end
end
apply_hl()
vim.api.nvim_create_autocmd("ColorScheme", { pattern = "*", callback = apply_hl })

local function eligible(buf)
	return vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == ""
end

-- Rescan the window's visible range.
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
		for s, word in line:gmatch("()(%u+)") do
			local group = M.KEYWORDS[word]
			local before = s > 1 and line:sub(s - 1, s - 1) or ""
			if group and not before:match("[%w_]") then
				-- The chip spans keyword [+ optional "(author)"] + colon.
				local rest = line:sub(s + #word)
				local tail = rest:match("^%s*:") or rest:match("^%([^)]*%)%s*:")
				if tail then
					vim.api.nvim_buf_set_extmark(buf, ns, first + i - 1, s - 1, {
						end_col = s - 1 + #word + #tail,
						hl_group = group,
					})
				end
			end
		end
	end
end

-- Debounced rescans: same shape as colorizer.lua (duplicated locally on
-- purpose — these modules stand alone). TextChanged(I)/WinScrolled bursts
-- coalesce into one rescan DEBOUNCE_MS after they settle; BufWinEnter and
-- InsertLeave stay immediate. Old marks persist until the rescan runs, so
-- nothing flickers. Handles anchored on M._debounce against luv GC.
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

local grp = vim.api.nvim_create_augroup("nv_todo", { clear = true })
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
