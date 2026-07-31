-- Side-by-side diff viewer for git changes: a `git diff` you can read inside the
-- editor. `<leader>gd` opens the working-tree-vs-index view (a file panel on the
-- left, the two versions of the selected file side by side), `<leader>gh` shows
-- the git history of the current file, and `<leader>gq` closes the tab.
--
-- On top of that, a two-key round trip for reviewing your own work:
--
--   <leader>gi  "into" the diff — from the file you are editing, land straight
--               in the right-hand (working-tree) pane of *that* file, on *that*
--               line. Pressed again inside the view it toggles focus between
--               the file panel and the diff, so you can walk the changes.
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

---<leader>gi — into the diff.
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
			focus_main(view)
		else
			require("diffview").emit("focus_files")
		end
		return
	end

	local path = real_file_path(api.nvim_get_current_buf())
	local lnum = api.nvim_win_get_cursor(0)[1]

	for _, open in ipairs(lib.views) do
		if open.tabpage and api.nvim_tabpage_is_valid(open.tabpage) then
			api.nvim_set_current_tabpage(open.tabpage)
			if path and open.set_file then
				jump_to(open, path, lnum)
			else
				focus_main(open)
			end
			return
		end
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

	local tabpage = view.tabpage
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
		local target = lib.tabpage_to_view(tabpage)
		if target then
			pcall(function()
				target:close()
			end)
			lib.dispose_view(target)
		end
	end)
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
		{ "<leader>gi", into_diff, desc = "Diff: into the diff (toggle panel/diff)" },
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
