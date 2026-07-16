-- ─── Markdown reading view (native) ──────────────────────────────────────────
-- Replaces render-markdown.nvim: an opt-in per-session "Open view" toggle on
-- markdown buffers (<leader>m, or the winbar chip drawn by core/filebadge.lua
-- through the _G.NvMdReader seam below). When ON, the VISIBLE range gets a
-- minimal reading treatment: accent heading bars, • bullets, checkbox glyphs,
-- blockquote bars, a shaded code-fence background, and full-width horizontal
-- rules. Tables / link concealing / inline-code chips are intentionally out of
-- scope — this is a reading aid, not a renderer.
--
-- Everything is plain Lua patterns over the visible lines (same shape as
-- core/colorizer.lua / core/todo.lua). It must NEVER drive the markdown
-- treesitter tree: parsing markdown crashes Neovim 0.12.x (node:range on a
-- nil node in the code-fence language-detection injection — the very bug that
-- forced the query patch below and keeps noice's LSP markdown paths off).
--
-- Indented-code and mixed ```/~~~ fence edge cases are not modeled: any fence
-- delimiter line toggles the shaded-block state.

-- Patch the markdown injections query at STARTUP (core loads before lazy and
-- before any buffer, so no markdown LanguageTree — which caches its injection
-- query at construction — exists yet): keep only the inline injection, drop
-- the code-fence language directive that triggers the 0.12.x crash. Nothing
-- in this config parses the markdown TS tree anymore, so this is insurance
-- for future consumers; deletable once upstream fixes the nil-node crash.
pcall(
	vim.treesitter.query.set,
	"markdown",
	"injections",
	'((inline) @injection.content (#set! injection.language "markdown_inline"))'
)

local M = {}

local ns = vim.api.nvim_create_namespace("nvsinner_markdown")
M._ns = ns -- test seam

-- Per-session global toggle; starts OFF (same as the old plugin) and is not
-- persisted in core/settings on purpose.
M.on = false

-- Fence-parity pre-scan cap: past this many lines above the viewport, skip
-- the scan (fence shading only) instead of reading the whole buffer.
M.MAX_SCAN = 10000

local GROUPS = {
	NvMdH1 = { role = "base10", bold = true }, -- magenta, matches the colorscheme's heading tone
	NvMdH2 = { role = "base09", bold = true }, -- identity accent (follows the accent pack)
	NvMdH3 = { role = "base12", bold = true },
	NvMdH4 = { role = "base14" },
	NvMdH5 = { role = "base08" },
	NvMdH6 = { role = "base07" },
	NvMdBullet = { role = "base09" },
	NvMdTodo = { role = "base09" },
	NvMdDone = { role = "base03" },
	NvMdQuoteBar = { role = "base02" },
	NvMdQuote = { role = "base03", italic = true },
	NvMdRule = { role = "base03" },
}

local function apply_hl()
	local c = require("core.carbon").colors()
	for group, def in pairs(GROUPS) do
		vim.api.nvim_set_hl(0, group, { fg = c[def.role], bold = def.bold, italic = def.italic })
	end
	-- bg-only so the block shades to eol and any fg survives on top.
	vim.api.nvim_set_hl(0, "NvMdCode", { bg = c.blend })
end
apply_hl()

local function eligible(buf)
	return vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == "" and vim.bo[buf].filetype == "markdown"
end

local function is_fence(line)
	return line:match("^%s*```") ~= nil or line:match("^%s*~~~") ~= nil
end

-- Whether line `first` (0-based) starts inside an open fenced block: count
-- fence-delimiter parity from the top of the buffer.
local function fence_open_at(buf, first)
	if first == 0 or first > M.MAX_SCAN then
		return false
	end
	local open = false
	for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, first, false)) do
		if is_fence(line) then
			open = not open
		end
	end
	return open
end

-- A thematic break: ≥3 of one of - * _ with nothing else but whitespace.
local function is_rule(line)
	local ch = line:match("^%s*([-*_])")
	if not ch then
		return false
	end
	local stripped = line:gsub("%s+", "")
	return #stripped >= 3 and stripped:match("^%" .. ch .. "+$") ~= nil
end

local function mark(buf, row, col, opts)
	vim.api.nvim_buf_set_extmark(buf, ns, row, col, opts)
end

-- Decorate one non-fence line. First match wins:
-- heading → rule → checkbox → bullet → quote.
local function decorate(buf, win, row, line)
	local hashes = line:match("^(#+)%s")
	if hashes and #hashes <= 6 then
		local group = "NvMdH" .. #hashes
		-- The overlay covers the "#… " marker run cell-for-cell, so the title
		-- keeps its column.
		mark(buf, row, 0, {
			virt_text = { { "▎" .. string.rep(" ", #hashes), group } },
			virt_text_pos = "overlay",
			line_hl_group = group,
		})
		return
	end

	if is_rule(line) then
		mark(buf, row, 0, {
			virt_text = { { ("─"):rep(vim.api.nvim_win_get_width(win)), "NvMdRule" } },
			virt_text_pos = "overlay",
		})
		return
	end

	local ws, state = line:match("^(%s*)[-*+]%s%[([ xX])%]")
	if ws then
		local done = state ~= " "
		local glyph = done and "󰱒" or "󰄱"
		-- One overlay covering "- [x]" (5 cells): bullet + glyph over the box.
		mark(buf, row, #ws, {
			virt_text = { { "• " .. glyph .. "  ", done and "NvMdDone" or "NvMdTodo" } },
			virt_text_pos = "overlay",
			line_hl_group = done and "NvMdDone" or nil,
		})
		return
	end

	ws = line:match("^(%s*)[-*+]%s")
	if ws then
		mark(buf, row, #ws, {
			virt_text = { { #ws >= 2 and "◦" or "•", "NvMdBullet" } },
			virt_text_pos = "overlay",
		})
		return
	end

	local qws, arrows = line:match("^(%s*)(>+)")
	if qws then
		mark(buf, row, #qws, {
			virt_text = { { ("▍"):rep(#arrows), "NvMdQuoteBar" } },
			virt_text_pos = "overlay",
			line_hl_group = "NvMdQuote",
		})
	end
end

-- Rescan the window's visible range. No-op while the view is off (toggling
-- off already cleared every markdown buffer).
function M.refresh(buf, win)
	if not M.on then
		return
	end
	buf = buf or vim.api.nvim_get_current_buf()
	win = win or vim.api.nvim_get_current_win()
	if not eligible(buf) or vim.api.nvim_win_get_buf(win) ~= buf then
		return
	end
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	local first = vim.fn.line("w0", win) - 1
	local last = vim.fn.line("w$", win)

	-- The line being typed on stays raw (render-markdown parity): overlays
	-- under the cursor while inserting read as fighting the user.
	local skip = -1
	if buf == vim.api.nvim_get_current_buf() and vim.api.nvim_get_mode().mode:find("^i") then
		skip = vim.api.nvim_win_get_cursor(win)[1] - 1
	end

	local in_fence = fence_open_at(buf, first)
	for i, line in ipairs(vim.api.nvim_buf_get_lines(buf, first, last, false)) do
		local row = first + i - 1
		local fence_line = is_fence(line)
		if fence_line or in_fence then
			-- Fence delimiters and everything between them get only the shade;
			-- a "# heading" inside a fence is code, not a heading.
			if row ~= skip then
				mark(buf, row, 0, { line_hl_group = "NvMdCode" })
			end
			if fence_line then
				in_fence = not in_fence
			end
		elseif row ~= skip then
			decorate(buf, win, row, line)
		end
	end
end

-- ─── The reader seam (consumed by core/filebadge.lua's winbar chip) ─────────

function M.label()
	return M.on and "󰈙 Reading view · on" or "󰈙 Open view"
end

function M.toggle()
	M.on = not M.on
	if M.on then
		for _, win in ipairs(vim.api.nvim_list_wins()) do
			M.refresh(vim.api.nvim_win_get_buf(win), win)
		end
	else
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == "markdown" then
				vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
			end
		end
	end
end

-- Winbar click handler: (minwid, clicks, button, mods) — all ignored.
function M.click()
	M.toggle()
end

-- Exposed on a global so core/filebadge.lua's winbar evaluator can read the
-- label and wire the %@…%X click region.
_G.NvMdReader = M

-- Debounced rescans: same shape as colorizer.lua/todo.lua. The M.on guard
-- comes FIRST in both callbacks — the reading view is off by default, so
-- markdown edit/scroll events must cost one boolean (no call, no timer
-- churn) while it is off. BufWinEnter and InsertLeave stay immediate: first
-- paint, and InsertLeave must promptly restore the insert-skipped cursor
-- line. Handles anchored on M._debounce against luv GC.
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

local grp = vim.api.nvim_create_augroup("nv_markdown", { clear = true })
vim.api.nvim_create_autocmd({ "BufWinEnter", "InsertLeave" }, {
	group = grp,
	callback = function(args)
		if not M.on then
			return
		end
		M.refresh(args.buf)
	end,
})
vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "WinScrolled" }, {
	group = grp,
	callback = function(args)
		if not M.on then
			return
		end
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
vim.api.nvim_create_autocmd("FileType", {
	group = grp,
	pattern = "markdown",
	callback = function(ev)
		vim.keymap.set("n", "<leader>m", M.toggle, {
			buffer = ev.buf,
			silent = true,
			desc = "Markdown reading view (Open view)",
		})
	end,
})
vim.api.nvim_create_autocmd("ColorScheme", { group = grp, pattern = "*", callback = apply_hl })

return M
