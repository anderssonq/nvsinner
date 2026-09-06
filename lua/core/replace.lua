-- ─── Replace — word search-and-replace modal (buffer + project) ─────────────
-- The discoverable face of :s. <leader>rw (or :NvSinnerReplace) over a word
-- opens a Mason-style modal titled with the target, offering four flavours:
-- replace every match in the buffer, replace asking one by one, the native
-- cgn/dot flow for "some yes, some no", and a VSCode-style project-wide
-- replace under the project root.
--
-- Capture ordering follows ai-ask.lua: the target word is read BEFORE the
-- modal opens (in visual mode getregion is only valid there), visual mode is
-- left synchronously, and the ctx lives in module state rather than a closure
-- because the vim.ui.input continuation runs async.
--
-- Two rules the substitution paths must not break:
--   * Patterns are built with \V (very nomagic) so a word like "a.b" matches
--     literally; \<..\> boundaries are added ONLY for bare keyword tokens,
--     since they mean nothing next to punctuation.
--   * The project path writes each file in the SAME :cfdo step that edits it
--     (`| update`). core/autoreload.lua runs an unconditional checktime every
--     second and reloads on FileChangedShell without looking at 'modified' —
--     a buffer left modified-but-unwritten across a tick loses its edits.

local M = {}

-- Highlight groups: same names + roles as core/menu.lua on purpose (identical
-- values, so double-applying is harmless).
local function apply_hl()
	local c = require("core.carbon").colors()
	local set = vim.api.nvim_set_hl
	set(0, "NvMenuKey", { fg = c.base09, bold = true })
	set(0, "NvMenuLabel", { fg = c.base04 })
	set(0, "NvMenuMuted", { fg = c.base03, italic = true })
	set(0, "NvMenuSel", { bg = c.base01 })
	set(0, "NvMenuNormal", { fg = c.base04, bg = c.shade })
	set(0, "NvMenuBorder", { fg = c.base02, bg = c.shade })
end
apply_hl()
vim.api.nvim_create_autocmd("ColorScheme", {
	group = vim.api.nvim_create_augroup("nv_replace_hl", { clear = true }),
	pattern = "*",
	callback = apply_hl,
})

-- ─── Actions ─────────────────────────────────────────────────────────────────

-- `sc` is the letter that runs the row; it is data rather than derived from
-- `key` so a title can be reworded without silently moving a shortcut. None of
-- f/c/o/p collides with the modal's own j/k/q/digit maps.
local ITEMS = {
	{
		key = "file",
		sc = "f",
		title = "Replace in file",
		desc = "Every exact match in this buffer, no questions",
	},
	{
		key = "confirm",
		sc = "c",
		title = "Replace asking",
		desc = "Confirm each match — y yes · n no · a all · q stop",
	},
	{
		key = "step",
		sc = "o",
		title = "One by one (cgn)",
		desc = "Change the first, then . repeats and n skips",
	},
	{
		key = "project",
		sc = "p",
		title = "Replace in project",
		desc = "Every file under the project root (ripgrep, asks first)",
	},
}

-- The captured target: { word, buf, win }. Module state (not a closure)
-- because the vim.ui.input continuation runs async; cleared after dispatch.
local ctx

-- ─── Pure helpers (test seams) ───────────────────────────────────────────────

--- Build the :s search pattern for a literal target.
--- \V (very nomagic) makes everything but "\" and the delimiter literal, so
--- "a.b" cannot match "axb". Word boundaries are added only for a bare keyword
--- token: \< and \> anchor between keyword and non-keyword characters, so on a
--- target like "$5" or "path/to/x" they would either never match or match in
--- surprising places.
function M.pattern(word)
	local escaped = vim.fn.escape(word, "\\/")
	if word:match("^[%w_]+$") then
		return "\\V\\<" .. escaped .. "\\>"
	end
	return "\\V" .. escaped
end

--- Escape a replacement for the RHS of :s, where "\", "&" and "~" are magic
--- ("&" = whole match, "~" = previous replacement) and "/" is our delimiter.
function M.replacement(text)
	return vim.fn.escape(text, "\\/&~")
end

--- Parse one ripgrep --vimgrep-style line into a quickfix item.
--- The filename capture is greedy on purpose: it backtracks until the
--- ":<line>:<col>:" tail matches, so a path that itself contains a colon still
--- splits correctly. Returns nil for anything that isn't a match line.
function M._parse_match(line)
	local file, lnum, col, text = line:match("^(.+):(%d+):(%d+):(.*)$")
	if not file then
		return nil
	end
	return { filename = file, lnum = tonumber(lnum), col = tonumber(col), text = text }
end

--- Summarise quickfix items as "N matches in M files" plus the file count.
function M._summary(items)
	local files, n = {}, 0
	for _, it in ipairs(items) do
		if not files[it.filename] then
			files[it.filename] = true
			n = n + 1
		end
	end
	return string.format("%d match%s in %d file%s", #items, #items == 1 and "" or "es", n, n == 1 and "" or "s"), n
end

-- ─── Capture ─────────────────────────────────────────────────────────────────

local function eligible_buf()
	if vim.api.nvim_win_get_config(0).relative ~= "" or vim.bo.buftype ~= "" then
		vim.notify("Replace works in a normal file window", vim.log.levels.WARN)
		return false
	end
	return true
end

--- Normal mode: the word under the cursor.
local function capture_word()
	if not eligible_buf() then
		return nil
	end
	local word = vim.fn.expand("<cword>")
	if word == "" or word:match("^%s*$") then
		vim.notify("No word under the cursor", vim.log.levels.WARN)
		return nil
	end
	return { word = word, buf = vim.api.nvim_get_current_buf(), win = vim.api.nvim_get_current_win() }
end

--- Visual mode: the selection. MUST run while visual mode is still active
--- (getregion is only correct there). Multi-line selections are refused —
--- a :s pattern spanning lines is a different feature.
local function capture_selection()
	if not eligible_buf() then
		return nil
	end
	local ok, region = pcall(vim.fn.getregion, vim.fn.getpos("v"), vim.fn.getpos("."), { type = vim.fn.mode() })
	if not ok or #region == 0 then
		vim.notify("Nothing selected", vim.log.levels.WARN)
		return nil
	end
	if #region > 1 then
		vim.notify("Select text on a single line to replace it", vim.log.levels.WARN)
		return nil
	end
	if region[1] == "" or region[1]:match("^%s*$") then
		vim.notify("Selection is empty", vim.log.levels.WARN)
		return nil
	end
	return { word = region[1], buf = vim.api.nvim_get_current_buf(), win = vim.api.nvim_get_current_win() }
end

-- ─── Buffer-scoped substitution ──────────────────────────────────────────────

--- Focus the captured window so the substitution (and, with `confirm`, its
--- interactive prompt) runs where the user was. Returns false when the window
--- is gone.
local function focus_source(c)
	if not (c.win and vim.api.nvim_win_is_valid(c.win)) then
		vim.notify("The window this started in is gone", vim.log.levels.WARN)
		return false
	end
	vim.api.nvim_set_current_win(c.win)
	return true
end

--- Count matches in the current buffer without touching it. The `n` flag makes
--- :s report instead of substituting, and — unlike the substitution's own
--- message — it reports regardless of 'report' (default 2, so a one-line
--- replace would otherwise print nothing to parse).
local function count_matches(pat)
	local ok, out = pcall(vim.fn.execute, string.format("keeppatterns %%s/%s//gn", pat))
	if not ok then
		return 0
	end
	return tonumber(tostring(out):match("(%d+) match")) or 0
end

--- :%s over the captured buffer. `confirm` adds the `c` flag, which makes the
--- command interactive (y/n/a/q per match). keeppatterns keeps the user's
--- search register intact.
local function replace_in_file(c, new, confirm)
	if not focus_source(c) then
		return
	end
	local pat = M.pattern(c.word)
	local n = count_matches(pat)
	if n == 0 then
		vim.notify("No matches for " .. c.word .. " in this file", vim.log.levels.WARN)
		return
	end
	local cmd = string.format("keeppatterns %%s/%s/%s/g%s", pat, M.replacement(new), confirm and "c" or "")
	local ok, err = pcall(vim.cmd, cmd)
	if not ok then
		vim.notify("Replace failed: " .. tostring(err), vim.log.levels.ERROR)
		return
	end
	if confirm then
		vim.notify(string.format("󰛔 %s → %s", c.word, new))
	else
		vim.notify(string.format("󰛔 %d replacement%s · %s → %s", n, n == 1 and "" or "s", c.word, new))
	end
end

--- Prime the search register and start the cgn flow: this one change is
--- dot-repeatable, so `.` applies it to the next match and `n` skips one.
--- Setting @/ is the point here, so this action does NOT keeppatterns.
local function replace_stepwise(c, new)
	if not focus_source(c) then
		return
	end
	vim.fn.setreg("/", M.pattern(c.word))
	vim.o.hlsearch = true
	local keys = "cgn" .. new .. vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
	vim.api.nvim_feedkeys(keys, "n", false)
	vim.notify("󰛔 Now: . repeats on the next match · n skips it", vim.log.levels.INFO)
end

-- ─── Project-wide replace ────────────────────────────────────────────────────

--- Search the project root for the literal word, async. Calls `cb(items, err)`
--- with quickfix-shaped items. Word-boundary matching is asked of ripgrep only
--- for bare keyword tokens, mirroring M.pattern.
---
--- Deliberately NOT :grep — Neovim 0.12 auto-detects `rg --vimgrep -uu`, and
--- -uu means --no-ignore --hidden, which would walk .git/ and node_modules/.
--- Calling rg directly keeps .gitignore in force.
function M.search(word, root, cb)
	if vim.fn.executable("rg") ~= 1 then
		cb(nil, "ripgrep (rg) is not installed — see :checkhealth nvsinner")
		return
	end
	local cmd = {
		"rg",
		"--line-number",
		"--column",
		"--no-heading",
		"--color=never",
		"--fixed-strings",
	}
	if word:match("^[%w_]+$") then
		table.insert(cmd, "--word-regexp")
	end
	vim.list_extend(cmd, { "--", word, root })
	vim.system(cmd, { text = true }, function(res)
		vim.schedule(function()
			-- rg exits 1 when there are simply no matches; only 2+ is an error.
			if res.code and res.code > 1 then
				cb(nil, (res.stderr ~= "" and res.stderr) or ("ripgrep failed (exit " .. res.code .. ")"))
				return
			end
			local items = {}
			for line in tostring(res.stdout or ""):gmatch("[^\n]+") do
				local item = M._parse_match(line)
				if item then
					table.insert(items, item)
				end
			end
			cb(items, nil)
		end)
	end)
end

--- Apply the replacement across every file in the quickfix list.
--- `| update` writes inside the same :cfdo step on purpose (see the header):
--- leaving buffers modified-but-unwritten lets autoreload's disk-wins reload
--- discard them. The `e` flag keeps a file without matches from aborting the run.
local function apply_project(c, new)
	local cur_win = vim.api.nvim_get_current_win()
	local cur_buf = vim.api.nvim_get_current_buf()
	-- `silent` only mutes the per-file "(3 of 12): …" / "N lines written" echo;
	-- a real error still raises and is caught by the pcall below.
	local cmd = string.format("silent cfdo keeppatterns %%s/%s/%s/ge | update", M.pattern(c.word), M.replacement(new))
	local ok, err = pcall(vim.cmd, cmd)
	if vim.api.nvim_win_is_valid(cur_win) then
		vim.api.nvim_set_current_win(cur_win)
		if vim.api.nvim_buf_is_valid(cur_buf) then
			vim.api.nvim_win_set_buf(cur_win, cur_buf)
		end
	end
	if not ok then
		vim.notify("Project replace failed: " .. tostring(err), vim.log.levels.ERROR)
	end
	return ok
end

local function replace_in_project(c, new)
	local root = require("core.project").root()
	M.search(c.word, root, function(items, err)
		if err then
			vim.notify(err, vim.log.levels.ERROR)
			return
		end
		if #items == 0 then
			vim.notify("No matches for " .. c.word .. " under " .. vim.fn.fnamemodify(root, ":t"), vim.log.levels.WARN)
			return
		end
		local summary, files = M._summary(items)
		vim.fn.setqflist({}, "r", { title = "NvSinner replace: " .. c.word, items = items })
		-- Writing many files is destructive and hard to undo — never without a
		-- confirmation naming the blast radius.
		vim.ui.select({ "Replace", "Cancel" }, {
			prompt = string.format("%s → %s · %s. Replace?", c.word, new, summary),
		}, function(choice)
			if choice ~= "Replace" then
				vim.notify("Cancelled · quickfix holds the " .. summary, vim.log.levels.INFO)
				return
			end
			if apply_project(c, new) then
				vim.notify(string.format("󰛔 %s → %s in %d file%s", c.word, new, files, files == 1 and "" or "s"))
			end
		end)
	end)
end

-- ─── Rendering (ai-ask.lua-derived: two buffer lines per action) ─────────────

-- 64 matches help.lua, and is the narrowest width at which none of the four
-- descriptions truncates (the longest is 55 display cells + DESC_PAD).
local WIDTH = 64
local HINT = "j/k move · ⏎ run · f/c/o/p pick · q close"
local DESC_PAD = 6
local TOP_PAD = 1
local ns = vim.api.nvim_create_namespace("nvsinner_replace")

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
		local head = string.format(" %s %s  ", (i == ui.sel) and "▸" or " ", it.sc)
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

--- Run the selected action and auto-close. Closing FIRST matters: every action
--- prompts with vim.ui.input and then jumps back to the source window, and the
--- backdrop's focus trap would fight both. Returns the action key (test seam).
function M.run()
	local it = ITEMS[ui.sel]
	local c = ctx
	M.close()
	if not it or not c then
		return nil
	end
	ctx = nil
	vim.ui.input({ prompt = string.format("Replace %s with: ", c.word), default = c.word }, function(new)
		if not new or new == "" or new == c.word then
			return
		end
		if it.key == "project" then
			replace_in_project(c, new)
		elseif it.key == "step" then
			replace_stepwise(c, new)
		else
			replace_in_file(c, new, it.key == "confirm")
		end
	end)
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

-- ─── Modal ───────────────────────────────────────────────────────────────────

--- Open the modal over an already-captured target (capture first — the title
--- shows the word so you know what you are about to rewrite).
function M.open(c)
	if c then
		ctx = c
	end
	if not ctx then
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
	vim.bo[ui.buf].filetype = "nvsinner-replace"

	local height = math.min(TOP_PAD + #ITEMS * 2 + 2, vim.o.lines - 4)
	ui.win = vim.api.nvim_open_win(ui.buf, true, {
		relative = "editor",
		style = "minimal",
		border = "rounded",
		title = " 󰛔 Replace · " .. fit(ctx.word, WIDTH - 16) .. " ",
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
	map("<CR>", M.run)
	map("<Space>", M.run)
	map("<Right>", M.run)
	-- Unlike the other modals, the letter shortcuts RUN their row instead of
	-- only selecting it — the rows are verbs, and the whole point of the modal
	-- is one keystroke from "I want to rename this" to the input prompt. The
	-- digits keep the house behaviour (select only).
	for i, it in ipairs(ITEMS) do
		map(it.sc, function()
			ui.sel = i
			M.run()
		end)
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

vim.keymap.set("n", "<leader>rw", function()
	local c = capture_word()
	if c then
		M.open(c)
	end
end, { desc = "Replace word under cursor" })

-- Visual: capture FIRST (still in visual mode — getregion is only valid
-- there), leave visual mode SYNCHRONOUSLY, THEN open (the modal's maps assume
-- normal mode). Same dance as ai-ask.lua's <leader>x.
vim.keymap.set("x", "<leader>rw", function()
	local c = capture_selection()
	vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
	if c then
		M.open(c)
	end
end, { desc = "Replace the selected text" })

vim.api.nvim_create_user_command("NvSinnerReplace", function()
	local c = capture_word()
	if c then
		M.open(c)
	end
end, { desc = "Replace a word in this file or across the project (<leader>rw)" })

-- Test seams.
function M._reset()
	M.close()
	ctx = nil
	ui.sel = 1
end

function M._ctx()
	return ctx
end

function M._items()
	return ITEMS
end

return M
