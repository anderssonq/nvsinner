-- ─── Mouse geometry helpers ──────────────────────────────────────────────────
-- A pure library (no autocmds, no commands, nothing to set up), so it is NOT
-- required from init.lua — consumers `require` it inside their click handlers.
-- Shared by the two NvSinner "explorers" that open a row on click: neo-tree
-- (lua/plugins/navigation/neo-tree.lua) and diffview's file panels
-- (lua/plugins/git/diffview.lua).

local M = {}

--- Buffer line actually under the pointer, or nil when the click missed a row.
---
--- `getmousepos().line` CLAMPS to the last buffer line, so a click on the empty
--- space below the last row reports that row — which would open the last file.
--- The true row is recovered from the window's own geometry instead:
--- `topline` + the screen row inside the text area. Exact for both consumers:
--- neo-tree and diffview's panels (diffview/ui/panel.lua) all run `wrap = false`
--- and `foldenable = false`, so screen rows map 1:1 onto buffer lines.
---
--- @param winid integer window the click must belong to
--- @param mp table|nil a `getmousepos()`-shaped table; defaults to the real
---        pointer position. The override is the test seam — mouse events cannot
---        be synthesized headless (same shape as core/neotree-hover's update()).
--- @return integer|nil line 1-based buffer line
function M.clicked_line(winid, mp)
	mp = mp or vim.fn.getmousepos()
	if mp.winid ~= winid then
		return nil
	end
	local wi = vim.fn.getwininfo(winid)[1]
	if not wi then
		return nil
	end
	local row = mp.winrow - (wi.winbar or 0)
	if row < 1 then
		-- The winbar itself; it owns its own %@…@ click regions (neo-tree's
		-- source selector, filebadge's "Open view" chip).
		return nil
	end
	local line = wi.topline + row - 1
	if line > vim.api.nvim_buf_line_count(wi.bufnr) then
		return nil
	end
	return line
end

return M
