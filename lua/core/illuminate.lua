-- ─── Symbol-occurrence highlight (native) ───────────────────────────────────
-- Replaces vim-illuminate: every occurrence of the symbol under the cursor
-- gets a subtle panel-gray underline — the "this text is actionable" cue.
--
-- Two providers, no plugin:
--   1. LSP — the builtin `vim.lsp.buf.document_highlight()` (renders through
--      the LspReferenceText/Read/Write groups, so writes read one step
--      brighter, same as illuminate did).
--   2. Fallback — for buffers without a capable client: a word-boundary scan
--      of the VISIBLE range only (extmarks in our namespace), gated to
--      buffers that have a treesitter parser so prose and plain text don't
--      light up. illuminate's regex provider covered the same ground.
--
-- Debounce discipline matches core/git-blame.lua: movement clears instantly,
-- a vim.uv timer (anchored on M._timer) re-highlights once the cursor
-- settles.

local M = {}

local ns = vim.api.nvim_create_namespace("nvsinner_illuminate")
M._ns = ns -- test seam: specs read the fallback extmarks here

M.DELAY = 120 -- ms after the cursor settles (illuminate's delay)
M.MAX_LINES = 4000 -- illuminate's large_file_cutoff
M.DENYLIST = {
	["neo-tree"] = true,
	alpha = true,
	dashboard = true,
	TelescopePrompt = true,
	toggleterm = true,
	lazy = true,
	mason = true,
	help = true,
}

-- Same tones the illuminate spec used: panel-gray underline, writes one step
-- brighter. LspReference* doubles as the builtin document-highlight styling.
local function apply_hl()
	local c = require("core.carbon").colors()
	local set = vim.api.nvim_set_hl
	set(0, "LspReferenceText", { underline = true, bg = c.base01 })
	set(0, "LspReferenceRead", { underline = true, bg = c.base01 })
	set(0, "LspReferenceWrite", { underline = true, bg = c.base02 })
end
apply_hl()
vim.api.nvim_create_autocmd("ColorScheme", { pattern = "*", callback = apply_hl })

local function eligible(buf)
	return vim.api.nvim_buf_is_valid(buf)
		and vim.bo[buf].buftype == ""
		and not M.DENYLIST[vim.bo[buf].filetype]
		and vim.api.nvim_buf_line_count(buf) <= M.MAX_LINES
end

function M.clear(buf)
	if not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	pcall(vim.lsp.util.buf_clear_references, buf)
end

local function lsp_capable(buf)
	for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
		if client:supports_method("textDocument/documentHighlight", buf) then
			return true
		end
	end
	return false
end

-- Word-boundary scan of the visible range. Only reached for parser-backed
-- buffers (checked in refresh); the frontier pattern keeps `foo` from
-- matching inside `foobar`.
local function fallback(buf, win)
	local word = vim.fn.expand("<cword>")
	if word == "" or word:match("^%W") then
		return
	end
	local first = vim.fn.line("w0", win) - 1
	local last = vim.fn.line("w$", win)
	local pat = "%f[%w_]" .. vim.pesc(word) .. "%f[^%w_]"
	for i, line in ipairs(vim.api.nvim_buf_get_lines(buf, first, last, false)) do
		local from = 1
		while true do
			local s, e = line:find(pat, from)
			if not s then
				break
			end
			-- The cursor's own occurrence is marked too (illuminate's
			-- under_cursor behavior); read/write distinction is LSP-only.
			vim.api.nvim_buf_set_extmark(buf, ns, first + i - 1, s - 1, {
				end_col = e,
				hl_group = "LspReferenceText",
			})
			from = e + 1
		end
	end
end

-- Highlight now (tests call this directly — cursor autocmds don't fire
-- headless).
function M.refresh(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	if not eligible(buf) then
		return
	end
	local win = vim.api.nvim_get_current_win()
	if vim.api.nvim_win_get_buf(win) ~= buf then
		return
	end
	M.clear(buf)
	if lsp_capable(buf) then
		vim.lsp.buf.document_highlight()
	elseif pcall(vim.treesitter.get_parser, buf) then
		fallback(buf, win)
	end
end

M._timer = nil -- anchored on the module table so luv can't GC a live timer
local function schedule(buf)
	M.clear(buf)
	if not eligible(buf) then
		return
	end
	if M._timer then
		M._timer:stop()
	else
		M._timer = vim.uv.new_timer()
	end
	M._timer:start(
		M.DELAY,
		0,
		vim.schedule_wrap(function()
			M.refresh(buf)
		end)
	)
end

local grp = vim.api.nvim_create_augroup("nv_illuminate", { clear = true })

vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "BufEnter" }, {
	group = grp,
	callback = function(args)
		schedule(args.buf)
	end,
})

vim.api.nvim_create_autocmd("BufLeave", {
	group = grp,
	callback = function(args)
		M.clear(args.buf)
	end,
})

-- Test seam: drop pending work between specs.
function M._reset()
	if M._timer then
		M._timer:stop()
	end
end

return M
