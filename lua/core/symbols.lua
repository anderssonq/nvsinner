-- ─── :NvSinnerSymbols — document-symbols modal for the current buffer ────────
-- A Mason-style floating panel (same shell + navigation as :NvSinnerHelp)
-- listing the current buffer's LSP document symbols: the nested symbol tree is
-- flattened into indented rows with a Nerd Font icon per SymbolKind; picking a
-- row closes the modal, jumps the ORIGINAL window to that symbol and centers
-- the view (zz). Keyboard: j/k (or arrows) move, <CR>/<Space>/l jump, 1-9
-- select, q/<Esc> close. Mouse: hover moves the selection, click jumps.
--
-- LSP-only on purpose (this pass): with no client supporting
-- textDocument/documentSymbol attached — or an empty result — it warns via
-- vim.notify and never opens. To extend with a treesitter fallback, branch in
-- M.show_symbols() when `get_clients` comes back empty and feed flatten()-shaped
-- items ({ name, kind, lnum, col, depth }) from a TS query instead.
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
	set(0, "NvMenuMuted", { fg = c.base03, italic = true }) -- kind names, hints
	set(0, "NvMenuSel", { bg = c.base01 }) -- selected row wash (solid on purpose)
	-- Solid modal surface (contrast survives transparent mode — see core/menu.lua).
	set(0, "NvMenuNormal", { fg = c.base04, bg = c.shade })
	set(0, "NvMenuBorder", { fg = c.base02, bg = c.shade })
end
apply_hl()
vim.api.nvim_create_autocmd("ColorScheme", {
	group = vim.api.nvim_create_augroup("nv_symbols_hl", { clear = true }),
	pattern = "*",
	callback = apply_hl,
})

-- ─── Symbol flattening ───────────────────────────────────────────────────────

-- Nerd Font icon per LSP SymbolKind name (codicon set, same family the rest of
-- the UI chrome uses). Anything unlisted falls back to ICON_FALLBACK.
local ICONS = {
	Function = "󰊕",
	Method = "󰆧",
	Variable = "󰀫",
	Constant = "󰏿",
	Class = "󰠱",
	Interface = "",
	Property = "󰜢",
	Field = "󰇽",
	Enum = "",
	Module = "",
	Struct = "󰙅",
}
local ICON_FALLBACK = "󰉻"

-- vim.lsp.protocol.SymbolKind maps number → name ("Function", …).
local function kind_name(kind)
	return vim.lsp.protocol.SymbolKind[kind] or "Unknown"
end

-- Flatten a documentSymbol response into { name, kind, lnum, col, depth }
-- rows (lnum/col 0-based, straight from the LSP range). Handles BOTH shapes:
-- hierarchical DocumentSymbol[] (has .selectionRange + .children) and flat
-- SymbolInformation[] (has .location).
local function flatten(symbols, depth, out)
	out = out or {}
	for _, s in ipairs(symbols or {}) do
		local pos = s.selectionRange and s.selectionRange.start or (s.location and s.location.range.start)
		if pos then
			table.insert(out, {
				name = s.name,
				kind = kind_name(s.kind),
				lnum = pos.line,
				col = pos.character,
				depth = depth,
			})
		end
		if s.children then
			flatten(s.children, depth + 1, out)
		end
	end
	return out
end

local items = {}

-- ─── Rendering ───────────────────────────────────────────────────────────────
-- One buffer line per symbol, so the line→item math is: item i owns line
-- TOP_PAD + i.

local HINT = "j/k move · ⏎ jump · 1-9 select · q close"
local TOP_PAD = 1
local ns = vim.api.nvim_create_namespace("nvsinner_symbols")

local ui = { win = nil, buf = nil, sel = 1, hover_line = -1, src_win = nil, width = 64 }

local function is_open()
	return ui.win and vim.api.nvim_win_is_valid(ui.win)
end

local function title_line(i) -- buffer line (1-based) of item i's row
	return TOP_PAD + i
end

local function line_to_item(line) -- inverse of title_line
	local i = line - TOP_PAD
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
		-- marker and the icons are multi-byte, so fixed columns would drift).
		local head = string.format(" %s %s ", (i == ui.sel) and "▸" or " ", i <= 9 and tostring(i) or " ")
		local icon = ICONS[it.kind] or ICON_FALLBACK
		local body = string.rep("  ", it.depth) .. icon .. " " .. it.name
		local tail = " · " .. it.kind
		body = fit(body, ui.width - vim.fn.strdisplaywidth(head) - vim.fn.strdisplaywidth(tail) - 1)
		spans[i] = { head = #head, body = #head + #body, total = #head + #body + #tail }
		table.insert(lines, head .. body .. tail)
	end
	table.insert(lines, "")
	local pad = math.max(0, math.floor((ui.width - vim.fn.strdisplaywidth(HINT)) / 2))
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
		ext(ui.buf, ns, row, s.head, { end_col = s.body, hl_group = "NvMenuLabel" })
		ext(ui.buf, ns, row, s.body, { end_col = s.total, hl_group = "NvMenuMuted" })
		if i == ui.sel then
			ext(ui.buf, ns, row, 0, { line_hl_group = "NvMenuSel" })
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

-- Jump to the selected symbol: close the float FIRST (so the cursor lands in a
-- real window), return to the original window, move to the symbol and center.
-- Returns the item it jumped to (test seam; nil when nothing selected or the
-- source window is gone).
function M.run()
	local it = items[ui.sel]
	local src = ui.src_win
	M.close()
	if not it or not (src and vim.api.nvim_win_is_valid(src)) then
		return nil
	end
	vim.api.nvim_set_current_win(src)
	local last = vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(src))
	pcall(vim.api.nvim_win_set_cursor, src, { math.min(it.lnum + 1, last), it.col })
	vim.cmd("normal! zz")
	return it
end

-- Mouse: click a symbol row → select it and jump.
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

-- Mouse hover: move the selection pill onto the row under the pointer (same
-- feel as :NvSinnerHelp; the buffer-local map also shadows ui-touch's
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

local function open_modal()
	ui.sel = 1
	ui.hover_line = -1
	ui.buf = vim.api.nvim_create_buf(false, true)
	vim.bo[ui.buf].buftype = "nofile"
	vim.bo[ui.buf].bufhidden = "wipe"
	vim.bo[ui.buf].filetype = "nvsinner_symbols"

	ui.width = math.min(64, vim.o.columns - 4)
	local height = math.min(TOP_PAD + #items + 2, vim.o.lines - 4)
	ui.win = vim.api.nvim_open_win(ui.buf, true, {
		relative = "editor",
		style = "minimal",
		border = "rounded",
		title = " Symbols ",
		title_pos = "center",
		width = ui.width,
		height = height,
		row = math.max(1, math.floor((vim.o.lines - height) / 2) - 1),
		col = math.max(0, math.floor((vim.o.columns - ui.width) / 2)),
	})
	vim.wo[ui.win].winhighlight = "Normal:NvMenuNormal,FloatBorder:NvMenuBorder"
	vim.wo[ui.win].cursorline = true
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

-- Request the current buffer's document symbols and open the modal with the
-- flattened result. Warns (never errors) with no capable client or no symbols.
function M.show_symbols()
	if is_open() then
		vim.api.nvim_set_current_win(ui.win)
		return
	end
	local buf = vim.api.nvim_get_current_buf()
	local clients = vim.lsp.get_clients({ bufnr = buf, method = "textDocument/documentSymbol" })
	if #clients == 0 then
		vim.notify("Symbols: no LSP client with documentSymbol attached", vim.log.levels.WARN)
		return
	end
	local src_win = vim.api.nvim_get_current_win()
	local params = { textDocument = vim.lsp.util.make_text_document_params(buf) }
	vim.lsp.buf_request_all(buf, "textDocument/documentSymbol", params, function(results)
		-- One response per client; take the first non-empty result.
		local symbols
		for _, r in pairs(results or {}) do
			if r.result and #r.result > 0 then
				symbols = r.result
				break
			end
		end
		items = flatten(symbols, 0)
		if #items == 0 then
			vim.notify("Symbols: no document symbols returned", vim.log.levels.WARN)
			return
		end
		ui.src_win = src_win
		open_modal()
	end)
end

-- Test seams (mirror the other core modals).
function M._items()
	return items
end
function M._set_items(list, src_win)
	items = list or {}
	ui.src_win = src_win
end
M._open_modal = open_modal
M._flatten = flatten

vim.api.nvim_create_user_command("NvSinnerSymbols", M.show_symbols, {
	desc = "Document symbols modal — jump to a symbol (also <leader>cs)",
})

return M
