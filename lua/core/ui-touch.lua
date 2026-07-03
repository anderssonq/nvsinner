-- ─── Touch / focus feedback ────────────────────────────────────────────────
-- Makes the editor feel "alive" to the mouse and to focus, on top of the
-- carbon theme:
--
--   1. Active-window border + glow — the focused window/terminal gets a subtle
--      surface lift and an accent separator, so you can always tell where
--      the focus is (the "borde tenue" cue, strongest on the terminal columns).
--   2. Mouse hover — moving the MOUSE over a symbol shows its LSP doc (or, with
--      no docs, the line's diagnostics) in a float anchored at the pointer, no
--      <K> needed. Symbol-occurrence highlighting lives in the vim-illuminate
--      plugin (lua/plugins/ui/illuminate.lua).
--
-- All native (no plugin) and guarded so special windows — neo-tree, telescope,
-- the dashboard, floats — are left untouched. Required from init.lua (core).

-- Highlight groups. Re-applied on every ColorScheme so they survive a
-- colorscheme (re)load and any lazy-loaded plugin that redefines base groups.
-- Carbon palette roles are resolved INSIDE the applier (single source + design
-- notes: lua/core/carbon.lua) so the background/transparency flags — and a
-- later `:set background=light | colorscheme carbon` — take effect on re-apply.
local function apply_hl()
	local carbon = require("core.carbon")
	local c = carbon.colors()
	-- Transparent mode: full-surface backgrounds (base bg, focused-pane lift,
	-- dim bar strip) go NONE so the terminal shows through; the focus cue then
	-- rides on the separators, the CursorLine and the solid terminal focus bar.
	local transparent = carbon.transparent()
	local base = transparent and c.none or c.base00 -- base editor bg (inactive panes)
	local lift = transparent and c.none or c.lift -- focused-pane surface lift
	local bar_dim = transparent and c.none or c.base01 -- unfocused terminal top strip
	local set = vim.api.nvim_set_hl
	set(0, "WinSeparator", { fg = c.base01, bg = base }) -- near-invisible between unfocused panes
	set(0, "NvFocusNormal", { bg = lift }) -- focused-pane background
	set(0, "NvFocusSeparator", { fg = c.base02, bg = lift }) -- focused code-pane border
	set(0, "NvTermFocusSeparator", { fg = c.base11, bg = lift }) -- focused terminal border (brighter)
	-- Full-width top bar that marks the focused terminal (bright) vs the rest
	-- (dim). base11 is carbon's terminal-mode accent; the dim strip keeps a
	-- readable muted fg so the idle/activity label still shows when unfocused.
	set(0, "NvTermFocusBar", { fg = c.base00, bg = c.base11, bold = true })
	set(0, "NvTermBarDim", { fg = c.base03, bg = bar_dim })
	set(0, "CursorLine", { bg = c.base01 }) -- current-line wash (carbon canonical)
end
apply_hl()
vim.api.nvim_create_autocmd("ColorScheme", { pattern = "*", callback = apply_hl })

-- Continuous box-drawing separators so the pane borders read as clean lines.
vim.opt.fillchars:append({
	vert = "│",
	horiz = "─",
	horizup = "┴",
	horizdown = "┬",
	vertleft = "┤",
	vertright = "├",
	verthoriz = "┼",
})

-- ─── 1. Active-window border + glow ────────────────────────────────────────

-- Windows we never restyle: they manage their own winhighlight or are floats.
local SKIP_FT = {
	["neo-tree"] = true,
	["alpha"] = true,
	["dashboard"] = true,
	["TelescopePrompt"] = true,
	["TelescopeResults"] = true,
	["lazy"] = true,
	["mason"] = true,
	["help"] = true,
	["which-key"] = true,
	["noice"] = true,
}

local FOCUS_WINHL = "Normal:NvFocusNormal,NormalNC:NvFocusNormal,WinSeparator:NvFocusSeparator"
-- Terminals get the glass glow, a brighter accent separator AND a full-width top
-- bar (WinBar) so the focused AI column / horizontal terminal pops in all three
-- layouts (horizontal-only, vertical-only, both at once). A single 1px line was
-- too faint on the near-black bg, so the bar carries the cue and just brightens
-- on focus — it's always present (dim when unfocused) to avoid any reflow.
local FOCUS_WINHL_TERM =
	"Normal:NvFocusNormal,NormalNC:NvFocusNormal,WinSeparator:NvTermFocusSeparator,WinBar:NvTermFocusBar"
local UNFOCUS_WINHL_TERM = "WinBar:NvTermBarDim"
-- Full-width strip; the WinBar highlight supplies the colour. Its CONTENT is a
-- live expression from core/ai-activity.lua: a spinner + "working…" while the
-- terminal (an AI CLI, a build, …) is producing output, "● idle" when quiet.
-- The buffer number is baked into the per-window string because g:statusline_winid
-- is NOT set during winbar evaluation, so the expression must be told its buffer.
local function term_bar(win)
	return string.format("%%{%%v:lua.require'core.ai-activity'.winbar(%d)%%}", vim.api.nvim_win_get_buf(win))
end

local function eligible(win)
	if not vim.api.nvim_win_is_valid(win) then
		return false
	end
	-- Skip floating windows (relative is non-empty for floats).
	if vim.api.nvim_win_get_config(win).relative ~= "" then
		return false
	end
	local buf = vim.api.nvim_win_get_buf(win)
	if SKIP_FT[vim.bo[buf].filetype] then
		return false
	end
	local bt = vim.bo[buf].buftype
	-- Only normal file buffers and terminals get the focus glow.
	return bt == "" or bt == "terminal"
end

local function focus(win)
	if not eligible(win) then
		return
	end
	local is_term = vim.bo[vim.api.nvim_win_get_buf(win)].buftype == "terminal"
	if is_term then
		-- Bright accent: full-width top bar + brighter separator.
		vim.wo[win].winhighlight = FOCUS_WINHL_TERM
		vim.wo[win].winbar = term_bar(win)
	else
		-- Code pane: tenue border + a subtle current-line wash.
		vim.wo[win].winhighlight = FOCUS_WINHL
		vim.wo[win].cursorline = true
	end
end

local function unfocus(win)
	if not eligible(win) then
		return
	end
	if vim.bo[vim.api.nvim_win_get_buf(win)].buftype == "terminal" then
		-- Keep the bar (no reflow); it just dims when the terminal loses focus.
		vim.wo[win].winhighlight = UNFOCUS_WINHL_TERM
		vim.wo[win].winbar = term_bar(win)
	else
		vim.wo[win].winhighlight = ""
		vim.wo[win].cursorline = false
	end
end

local touch_grp = vim.api.nvim_create_augroup("nv_touch", { clear = true })
-- TermOpen is included because a terminal window first fires BufWinEnter while
-- its buffer is still a scratch (buftype ""), so focus() would style it as a code
-- pane and skip the terminal winbar; TermOpen re-runs focus() once the buffer has
-- become a "terminal" so the bar (and its activity spinner) shows on first open.
vim.api.nvim_create_autocmd({ "WinEnter", "BufWinEnter", "TermOpen" }, {
	group = touch_grp,
	callback = function()
		focus(vim.api.nvim_get_current_win())
	end,
})
vim.api.nvim_create_autocmd("WinLeave", {
	group = touch_grp,
	callback = function()
		unfocus(vim.api.nvim_get_current_win())
	end,
})
-- Style whichever window we start in.
vim.schedule(function()
	focus(vim.api.nvim_get_current_win())
end)

-- ─── 2. Mouse hover: LSP doc / diagnostics under the pointer ────────────────
vim.o.mousemoveevent = true -- enables <MouseMove> events

local hover = { win = nil, line = nil, col = nil }
local hover_timer = assert((vim.uv or vim.loop).new_timer())

local function close_hover()
	if hover.win and vim.api.nvim_win_is_valid(hover.win) then
		pcall(vim.api.nvim_win_close, hover.win, true)
	end
	hover.win, hover.line, hover.col = nil, nil, nil
end

local function open_float(lines)
	close_hover()
	if not lines or #lines == 0 then
		return
	end
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	-- NOTE: deliberately NOT set to "markdown". The markdown treesitter
	-- highlighter crashes on Neovim 0.12.x ("attempt to call method 'range'")
	-- when parsing this transient float, so the doc is shown as plain text.
	vim.bo[buf].modifiable = false
	local width = 1
	for _, l in ipairs(lines) do
		width = math.max(width, vim.fn.strdisplaywidth(l))
	end
	local ok, win = pcall(vim.api.nvim_open_win, buf, false, {
		relative = "mouse",
		row = 1,
		col = 1,
		width = math.min(width, 80),
		height = math.min(#lines, 18),
		style = "minimal",
		border = "rounded",
		focusable = false,
		noautocmd = true,
	})
	if ok then
		hover.win = win
		vim.wo[win].winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder"
	end
end

local function supports_hover(buf)
	for _, c in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
		local ok, sup = pcall(function()
			return c:supports_method("textDocument/hover")
		end)
		if ok and sup then
			return true
		end
	end
	return false
end

local function request_hover()
	local mp = vim.fn.getmousepos()
	local win = mp.winid
	if not win or win == 0 or not vim.api.nvim_win_is_valid(win) then
		return close_hover()
	end
	if vim.api.nvim_win_get_config(win).relative ~= "" then
		return -- pointer is over a float (likely our own); leave it.
	end
	local buf = vim.api.nvim_win_get_buf(win)
	if vim.bo[buf].buftype ~= "" then
		return close_hover() -- terminal / special buffer, nothing to hover.
	end
	local line, col = mp.line - 1, mp.column - 1
	if mp.line == 0 or line < 0 then
		return close_hover()
	end
	-- Already showing this exact spot? keep the float steady.
	if hover.win and hover.line == line and hover.col == col then
		return
	end

	if not supports_hover(buf) then
		-- Fall back to the line's diagnostics, if any.
		local diags = vim.diagnostic.get(buf, { lnum = line })
		if #diags > 0 then
			local lines = {}
			for _, d in ipairs(diags) do
				for _, s in ipairs(vim.split(d.message, "\n", { trimempty = true })) do
					table.insert(lines, s)
				end
			end
			hover.line, hover.col = line, col
			open_float(lines)
		else
			close_hover()
		end
		return
	end

	local params = {
		textDocument = { uri = vim.uri_from_bufnr(buf) },
		position = { line = line, character = col },
	}
	vim.lsp.buf_request(buf, "textDocument/hover", params, function(err, result)
		if err or not result or not result.contents then
			return
		end
		local md = vim.lsp.util.convert_input_to_markdown_lines(result.contents)
		md = vim.tbl_filter(function(l)
			return l ~= ""
		end, md)
		if #md == 0 then
			return
		end
		hover.line, hover.col = line, col
		open_float(md)
	end)
end

local function on_move()
	hover_timer:stop()
	hover_timer:start(
		200,
		0,
		vim.schedule_wrap(function()
			if not pcall(request_hover) then
				close_hover()
			end
		end)
	)
end

vim.keymap.set({ "n", "i" }, "<MouseMove>", on_move, { desc = "Mouse hover doc" })

-- Drop the float when focus / mode / layout changes (moving the mouse doesn't
-- move the cursor, so it stays put while you read it).
vim.api.nvim_create_autocmd(
	{ "CursorMoved", "InsertEnter", "WinScrolled", "BufLeave", "FocusLost", "WinLeave" },
	{ group = touch_grp, callback = close_hover }
)
