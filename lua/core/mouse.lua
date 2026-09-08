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

-- ─── Click, never drag-select ────────────────────────────────────────────────

--- Mouse gestures that start or extend a Visual selection under `mouse=a`.
--- <2-LeftMouse> is deliberately absent: both explorers already claim it (it is
--- their double-click open), so word-select can never fire there anyway.
M.SELECT_KEYS = {
	"<LeftDrag>",
	"<2-LeftDrag>",
	"<3-LeftDrag>",
	"<4-LeftDrag>",
	"<3-LeftMouse>",
	"<4-LeftMouse>",
}

--- Is the pointer inside `winid`'s TEXT area — not its border, not another
--- window? This is what separates "the user is sweeping across rows" (swallow)
--- from "the user is dragging my edge to resize me" (let the builtin have it).
---
--- BOTH clauses were established by a real-PTY probe (child Neovim driven with
--- SGR mouse escapes), not inferred from :help, and the winid one is the load
--- bearing half — which is NOT obvious:
---
---  * During a separator resize-drag the pointer leaves this window, so
---    getmousepos() reports the NEIGHBOUR's winid (with a perfectly ordinary
---    line number) while this buffer is still the focused one the mapping
---    resolved against. Probe: dragging the separator right resized the window
---    39 -> 54 columns with this predicate in place, and stayed stuck at 39 with
---    a `line == 0` predicate instead. Gating on `line` alone breaks resize.
---  * `line == 0` is still checked because :h getmousepos() documents it for a
---    pointer resting on the status line or the vertical separator right of a
---    window, where `winid` does name this window.
---
--- @param winid integer window the pointer must be over
--- @param mp table|nil a `getmousepos()`-shaped table; defaults to the real
---        pointer position. The override is the test seam, as in clicked_line.
--- @return boolean
function M.in_text_area(winid, mp)
	mp = mp or vim.fn.getmousepos()
	return mp.winid == winid and (mp.line or 0) > 0
end

--- Make `buf` clickable but not drag-selectable — the explorer feel of a GUI
--- file tree, where a press-and-sweep highlights nothing.
---
--- Each gesture becomes an EXPR map returning "" (a clean no-op) only while the
--- pointer is inside the window's text area, and the LITERAL key otherwise. An
--- expr map with `remap = false` that returns its own lhs runs the BUILTIN
--- without recursing (verified), so a drag that began on the window separator
--- still resizes — a blanket <Nop> would have broken that, since drag keys
--- resolve against the focused buffer even when the pointer is on the border.
--- `replace_keycodes` is load-bearing rather than decorative: with it false the
--- returned "<LeftDrag>" is fed through as literal text and the fallthrough
--- silently dies.
---
--- COUPLING, verified by probe: this only works while the consumer's own
--- <LeftRelease> map stays a PLAIN function that consumes the key. Vim finalises
--- a mouse selection on the RELEASE, using the remembered press position — so if
--- <LeftRelease> ever fell through to the builtin (an expr map returning the
--- key, or no map at all), a swept click would re-enter Visual mode even with
--- every drag gesture locked here. Both explorers map it to a plain callback,
--- which is why locking the drag gestures alone is sufficient.
---
--- @param buf integer buffer to lock
function M.lock_selection(buf)
	for _, key in ipairs(M.SELECT_KEYS) do
		vim.keymap.set("n", key, function()
			return M.in_text_area(vim.api.nvim_get_current_win()) and "" or key
		end, {
			buffer = buf,
			expr = true,
			remap = false,
			replace_keycodes = true,
			silent = true,
			desc = "Explorer: click, never drag-select",
		})
	end
end

return M
