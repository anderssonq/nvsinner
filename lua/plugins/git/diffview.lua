-- Side-by-side diff viewer for git changes: a `git diff` you can read inside the
-- editor. `<leader>gd` opens the working-tree-vs-index view (a file panel on the
-- left, the two versions of the selected file side by side), `<leader>gh` shows
-- the git history of the current file, and `<leader>gq` closes the tab.
--
-- On top of that, a two-key round trip for reviewing your own work:
--
--   <leader>gi  "into" the diff — from the file you are editing (or the one
--               selected in neo-tree), land straight in the right-hand
--               (working-tree) pane of *that* file, on *that* line. Pressed
--               again it toggles between the diff and the file list on the
--               left, so you can walk the changed files without leaving the
--               view. It never drops you back on the buffer — that is <leader>go.
--   <leader>go  "out" of the diff — back to the real, editable buffer at the
--               line you were reading, and the Diffview tab is closed.
--
-- Diffview's own `gf` does the same jump *without* closing the tab, if you want
-- to keep the view around; it stays bound inside every diff buffer and panel.
local api = vim.api

-- A jump requested by <leader>gi that can't be served synchronously: opening a
-- view and switching entries are async, so the cursor is placed later, from the
-- `diff_buf_win_enter` hook. Shape: { path = <absolute>, lnum = <integer> }.
local pending = nil

---Absolute path of a buffer that is a real, on-disk file (not a panel, terminal,
---`diffview://` blob or scratch buffer).
---@param buf integer
---@return string|nil
local function real_file_path(buf)
	if vim.bo[buf].buftype ~= "" then
		return nil
	end
	local name = api.nvim_buf_get_name(buf)
	-- Any `scheme://` name is virtual — diffview's index/commit blobs included.
	if name == "" or name:match("^%a[%w+.%-]*://") then
		return nil
	end
	return vim.fn.fnamemodify(name, ":p")
end

---The file selected in neo-tree, when the cursor sits in the tree. A directory
---row designates no file, so it answers nil rather than guessing.
---@return string|nil
local function neotree_path()
	if vim.bo.filetype ~= "neo-tree" then
		return nil
	end
	local ok, mgr = pcall(require, "neo-tree.sources.manager")
	if not ok then
		return nil
	end
	local got, node = pcall(function()
		local state = mgr.get_state_for_window(0)
		return state and state.tree and state.tree:get_node()
	end)
	if got and node and node.type == "file" and node.path then
		return vim.fn.fnamemodify(node.path, ":p")
	end
end

---The file (and line) `<leader>gi` means. The current buffer when it IS a file;
---otherwise the intent still has an obvious referent: the entry selected in the
---tree, or the file you were last reading in this tab. Without this, pressing
---the key from neo-tree or a terminal opened the diff on whatever file happened
---to be changed first.
---@return string|nil path, integer lnum
local function target()
	local path = real_file_path(api.nvim_get_current_buf())
	if path then
		return path, api.nvim_win_get_cursor(0)[1]
	end

	path = neotree_path()
	if path then
		return path, 1
	end

	local wins = { vim.fn.win_getid(vim.fn.winnr("#")) }
	vim.list_extend(wins, api.nvim_tabpage_list_wins(0))
	for _, win in ipairs(wins) do
		if win ~= 0 and api.nvim_win_is_valid(win) then
			path = real_file_path(api.nvim_win_get_buf(win))
			if path then
				return path, api.nvim_win_get_cursor(win)[1]
			end
		end
	end

	return nil, 1
end

---An already-open view worth jumping into. A `<leader>gh` file-history tab is a
---FileHistoryView: no `files:iter()`, no `set_file_by_path` — adopting it would
---swallow the jump into a bogus "no changes" toast. Prefer a real DiffView and
---only fall back to whatever else is open.
---@param lib table
---@return table|nil
local function open_view(lib)
	local fallback
	for _, view in ipairs(lib.views) do
		if view.tabpage and api.nvim_tabpage_is_valid(view.tabpage) then
			if view.files and view.set_file then
				return view
			end
			fallback = fallback or view
		end
	end
	return fallback
end

---Focus the layout's main window — `.b`, the right/working-tree side for the
---default `diff2_horizontal`. Layout-agnostic: Diff1 has only `.b`, Diff3/4 add
---more, and `get_main_win()` picks the right one for each.
---@param view table
---@return integer|nil winid
local function focus_main(view)
	local layout = view and view.cur_layout
	local win = layout and layout.get_main_win and layout:get_main_win()
	if win and win.id and api.nvim_win_is_valid(win.id) then
		api.nvim_set_current_win(win.id)
		return win.id
	end
end

---@param winid integer|nil
---@param lnum integer|nil
local function place_cursor(winid, lnum)
	if not (winid and lnum and api.nvim_win_is_valid(winid)) then
		return
	end
	local last = api.nvim_buf_line_count(api.nvim_win_get_buf(winid))
	pcall(api.nvim_win_set_cursor, winid, { math.max(1, math.min(lnum, last)), 0 })
end

---The entry for `path` in this view, if the file is part of the diff.
---(`set_file_by_path` matches on the *repo-relative* path, so match ourselves.)
---@param view table
---@param path string
---@return table|nil
local function find_entry(view, path)
	if not (view.files and view.files.iter) then
		return nil
	end
	for _, entry in view.files:iter() do
		if entry.absolute_path == path then
			return entry
		end
	end
end

local function notify_no_changes(path)
	vim.notify(
		("Diff: no changes in %s — showing the first change"):format(vim.fn.fnamemodify(path, ":.")),
		vim.log.levels.INFO
	)
end

---Point an already-open view at `path` and put the cursor on `lnum`.
local function jump_to(view, path, lnum)
	local entry = path and find_entry(view, path)

	if not entry then
		pending = nil
		focus_main(view)
		if path then
			notify_no_changes(path)
		end
		return
	end

	if entry == view.cur_entry then
		-- No buffer swap will happen, so no `diff_buf_win_enter` would fire.
		pending = nil
		place_cursor(focus_main(view), lnum)
	else
		pending = { path = path, lnum = lnum }
		view:set_file(entry, true)
	end
end

---Focus the file panel — the list of changed files. Called directly rather than
---through `emit("focus_files")`: the event is dropped while the view is closing
---and depends on the listener table being wired, and the listener itself is
---exactly this call. `Panel:focus()` opens the panel when it was toggled away.
---@param view table
---@return boolean focused
local function focus_panel(view)
	local panel = view and view.panel
	if not (panel and panel.focus) then
		return false
	end
	local ok = pcall(function()
		panel:focus()
	end)
	return ok and panel:is_focused()
end

---Leave the view for the real, editable file, closing the Diffview tab.
---@param lib table
---@param view table the current view (caller has already resolved it)
local function leave_diff(lib, view)
	local tabpage = view.tabpage

	-- `goto_file_edit` opens the file in the target tab's LAST ACCESSED window,
	-- which is just as likely to be neo-tree or the AI terminal column as a code
	-- pane — landing the file there wipes the panel. Point the tab at a real
	-- editor window first; diffview then edits into it.
	local target_tab = lib.get_prev_non_view_tabpage()
	if target_tab and api.nvim_tabpage_set_win then
		local ok_wp, picker = pcall(require, "core.window-picker")
		local win = ok_wp and picker.editable_win(target_tab) or nil
		if win then
			pcall(api.nvim_tabpage_set_win, target_tab, win)
		end
	end

	-- Resolves the file from the diff pane *or* the file panel, carries the
	-- cursor across, and restores the window options (diff/scrollbind/foldmethod)
	-- before editing — so the buffer arrives as a plain, editable file.
	require("diffview.actions").goto_file_edit()

	vim.schedule(function()
		-- Only tear the view down if we actually left it (goto_file_edit bails
		-- when the file isn't on disk).
		if api.nvim_get_current_tabpage() == tabpage then
			return
		end
		local stale = lib.tabpage_to_view(tabpage)
		if stale then
			pcall(function()
				stale:close()
			end)
			lib.dispose_view(stale)
		end
	end)
end

---<leader>gi — into the diff, and back to the file list.
local function into_diff()
	local ok, lib = pcall(require, "diffview.lib")
	if not ok then
		return
	end

	-- `get_current_view()` is tabpage-keyed: non-nil only inside the Diffview tab.
	local view = lib.get_current_view()
	if view then
		local panel = view.panel
		if panel and panel.is_focused and panel:is_focused() then
			-- In the file list: down into the selected entry's diff.
			focus_main(view)
		else
			-- In the diff: back up to the file list, so you can walk the changes.
			-- Never out to the buffer — that is <leader>go's job.
			focus_panel(view)
		end
		return
	end

	local path, lnum = target()

	local open = open_view(lib)
	if open then
		api.nvim_set_current_tabpage(open.tabpage)
		if path and open.files and open.set_file then
			jump_to(open, path, lnum)
		else
			focus_main(open)
		end
		return
	end

	if not path then
		vim.cmd("DiffviewOpen")
		return
	end

	-- `--selected-file` makes diffview open on this file itself; the hooks below
	-- move focus into the diff pane and restore the cursor line once it lands.
	pending = { path = path, lnum = lnum }
	vim.cmd("DiffviewOpen --selected-file=" .. vim.fn.fnameescape(path))
end

---<leader>go — out of the diff, editing.
local function out_of_diff()
	local ok, lib = pcall(require, "diffview.lib")
	if not ok then
		return
	end

	local view = lib.get_current_view()
	if not view then
		vim.notify("Diff: not inside a Diffview tab", vim.log.levels.WARN)
		return
	end

	leave_diff(lib, view)
end

return {
	"sindrets/diffview.nvim",
	-- Lazy: only pulled in when one of its commands or keymaps is used.
	cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewFileHistory", "DiffviewToggleFiles" },
	keys = {
		{ "<leader>gd", "<cmd>DiffviewOpen<cr>", desc = "Diff: working tree vs index" },
		{ "<leader>gh", "<cmd>DiffviewFileHistory %<cr>", desc = "Diff: history of current file" },
		{ "<leader>gH", "<cmd>DiffviewFileHistory<cr>", desc = "Diff: history of whole repo" },
		{ "<leader>gq", "<cmd>DiffviewClose<cr>", desc = "Diff: close view" },
		{ "<leader>gi", into_diff, desc = "Diff: into the diff (toggle diff/file list)" },
		{ "<leader>go", out_of_diff, desc = "Diff: out to the editable file" },
	},
	opts = {
		-- Brighter, word-level diff highlights so changes stand out clearly.
		enhanced_diff_hl = true,
		hooks = {
			-- Fired once per diff window as it opens. `symbol` is the layout slot:
			-- "a" is the index/old side, "b" the working-tree/new side.
			diff_buf_win_enter = function(bufnr, winid, ctx)
				if not pending then
					return
				end
				if ctx and ctx.symbol and ctx.symbol ~= "b" then
					return
				end

				local landed = api.nvim_buf_get_name(bufnr)
				local want, lnum = pending.path, pending.lnum
				pending = nil

				if landed ~= want then
					-- Diffview fell back to another entry: our file has no changes.
					vim.schedule(function()
						local view = require("diffview.lib").get_current_view()
						if view then
							focus_main(view)
						end
						notify_no_changes(want)
					end)
					return
				end

				-- Deferred: this fires from inside diffview's own `nvim_win_call`,
				-- and focus settles on the file panel once the update finishes.
				vim.schedule(function()
					if api.nvim_win_is_valid(winid) then
						api.nvim_set_current_win(winid)
						place_cursor(winid, lnum)
					end
				end)
			end,
			-- Never let a stale jump leak into the next view.
			view_closed = function()
				pending = nil
			end,
		},
	},
}
