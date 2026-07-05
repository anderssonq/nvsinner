-- Native per-window file badge — the in-repo replacement for incline.nvim.
-- Tells the user WHICH file each window holds and WHERE the focus is:
-- a right-aligned "● <icon> <filename> ●" badge (focus dot · filetype icon ·
-- name · modified dot) rendered in the WINBAR, so it owns its own line and
-- never floats over buffer text. One renderer, two delivery paths:
--
--   * code windows — barbecue's `custom_section` (lua/plugins/ui/barbacue.lua)
--     calls M.section(), so the badge rides the right end of the existing
--     breadcrumb winbar;
--   * markdown windows (excluded from barbecue) — this module sets the winbar
--     itself: the badge plus the clickable "Open view" reading-view chip.
--     The chip is a native %@…%X statusline click region driving
--     _G.NvMdReader.click; the state and the label live in
--     lua/plugins/ui/render-markdown.lua.
--
-- All colors are carbon roles from lua/core/carbon.lua (re-applied on
-- ColorScheme); the filetype icon keeps devicons' own color as foreground
-- only (no colored block), matching the gray-dominant chrome doctrine.
local M = {}

local api = vim.api

-- Badge highlights from carbon roles: base09 blue = focus/identity (dot +
-- chip), base04 body / base03 muted for the name, base10 magenta = modified.
local function apply_hl()
	local c = require("core.carbon").colors()
	api.nvim_set_hl(0, "NvBadgeDot", { fg = c.base09 })
	api.nvim_set_hl(0, "NvBadgeFile", { fg = c.base04, bold = true })
	api.nvim_set_hl(0, "NvBadgeFileNC", { fg = c.base03 })
	api.nvim_set_hl(0, "NvBadgeMod", { fg = c.base10 })
	api.nvim_set_hl(0, "NvBadgeChip", { fg = c.base09, bold = true })
	api.nvim_set_hl(0, "NvBadgeSep", { fg = c.base03 })
end

-- The filetype icon keeps devicons' color as fg: one derived group per icon
-- color, created on demand (a :colorscheme clears them, so the cache is
-- dropped on ColorScheme and the groups are re-created lazily).
local icon_groups = {}
local function icon_hl(color)
	if not color then
		return "NvBadgeFileNC"
	end
	local name = "NvBadgeIcon" .. color:gsub("[^%w]", "")
	if not icon_groups[name] then
		api.nvim_set_hl(0, name, { fg = color })
		icon_groups[name] = true
	end
	return name
end

--- Badge segments for a buffer as { text, highlight-group } pairs.
--- `focused` marks the badge of the window the user is standing in.
function M.parts(buf, focused)
	local name = vim.fn.fnamemodify(api.nvim_buf_get_name(buf), ":t")
	if name == "" then
		name = "[No Name]"
	end
	local parts = {}
	if focused then
		parts[#parts + 1] = { "● ", "NvBadgeDot" }
	end
	-- devicons is a plugin (this module loads before lazy.nvim) — optional.
	local ok, devicons = pcall(require, "nvim-web-devicons")
	if ok then
		local icon, color = devicons.get_icon_color(name)
		if icon then
			parts[#parts + 1] = { icon .. " ", icon_hl(color) }
		end
	end
	parts[#parts + 1] = { name, focused and "NvBadgeFile" or "NvBadgeFileNC" }
	if vim.bo[buf].modified then
		parts[#parts + 1] = { " ●", "NvBadgeMod" }
	end
	return parts
end

--- Statusline fragment ("%#grp#text…") for the badge of the window being
--- DRAWN. Focus is decided here, at draw time: during winbar evaluation
--- curwin is the window being drawn and g:actual_curwin holds the
--- really-focused window. "%" in the filename is escaped.
function M.fragment()
	local buf = api.nvim_get_current_buf()
	local focused = api.nvim_get_current_win() == tonumber(vim.g.actual_curwin or "-1")
	local out = {}
	for _, p in ipairs(M.parts(buf, focused)) do
		out[#out + 1] = "%#" .. p[2] .. "#" .. p[1]:gsub("%%", "%%%%")
	end
	return table.concat(out)
end

-- Badge for barbecue's `custom_section`: a DYNAMIC %{%…%} expression, not
-- prebuilt text — barbecue only rebuilds the winbar string of the window an
-- event touched, so a build-time focus check left stale focus dots on every
-- other window. The expression re-evaluates on each redraw instead.
M.SECTION_EXPR = "%{%v:lua.require'core.filebadge'.fragment()%}"

function M.section()
	return M.SECTION_EXPR
end

-- Winbar expression for the windows this module owns (markdown). %{%…%} is
-- re-evaluated on every redraw, so focus changes, renames, the modified flag
-- and the chip label stay current without re-applying the winbar.
M.EXPR = "%{%v:lua.require'core.filebadge'.winbar()%}"

--- Evaluator behind M.EXPR: right-aligned "Open view" chip (when
--- render-markdown has registered the reader) + the badge fragment.
function M.winbar()
	local out = "%="
	local reader = vim.bo[api.nvim_get_current_buf()].filetype == "markdown" and _G.NvMdReader or nil
	if reader then
		out = out .. "%@v:lua.NvMdReader.click@%#NvBadgeChip#" .. reader.label() .. "%X%#NvBadgeSep# │ "
	end
	return out .. M.fragment() .. "%* "
end

local function attach(win)
	if win and win ~= -1 and api.nvim_win_is_valid(win) then
		vim.wo[win].winbar = M.EXPR
	end
end

local grp = api.nvim_create_augroup("NvFileBadge", { clear = true })
apply_hl()
vim.api.nvim_create_autocmd("ColorScheme", {
	group = grp,
	pattern = "*",
	callback = function()
		icon_groups = {}
		apply_hl()
	end,
})
-- Own the winbar of markdown windows ('winbar' is window-local, so re-apply
-- when the buffer lands in a window too).
vim.api.nvim_create_autocmd("FileType", {
	group = grp,
	pattern = "markdown",
	callback = function(ev)
		attach(vim.fn.bufwinid(ev.buf))
	end,
})
vim.api.nvim_create_autocmd("BufWinEnter", {
	group = grp,
	callback = function(ev)
		if vim.bo[ev.buf].filetype == "markdown" then
			attach(vim.fn.bufwinid(ev.buf))
		end
	end,
})

return M
