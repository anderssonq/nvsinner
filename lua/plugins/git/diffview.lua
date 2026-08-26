-- Side-by-side diff viewer for git changes: a `git diff` you can read inside the
-- editor. `<leader>gd` opens the working-tree-vs-index view (a file panel on the
-- left, the two versions of the selected file side by side), `<leader>gh` shows
-- the git history of the current file, and `<leader>gq` closes the tab.
--
-- The review loop is: one way in, one way out, and never more than one tab.
--
--   <leader>gd  the diff, in AT MOST ONE tab. `DiffviewOpen` does not dedupe —
--               every call is a fresh `tab split` — so this adopts the view
--               that is already open (refreshing its file list) instead of
--               stacking a second copy of the same diff in the tabline.
--   <leader>gH  the whole-repo history, under the same one-tab guard.
--               `<leader>gh` (one file's history) deliberately keeps stacking:
--               two files are two legitimate histories.
--   <leader>gi  "into" the diff — from the file you are editing (or the one
--               selected in neo-tree), land straight in the right-hand
--               (working-tree) pane of *that* file, on *that* line. Pressed
--               again it toggles between the diff and the file list on the
--               left, so you can walk the changed files without leaving the
--               view. It never drops you back on the buffer — that is `gf`.
--   gf          "out" of the diff — diffview's own binding, back to the real,
--               editable buffer, leaving the tab standing (`<leader>gd` comes
--               back to it, `<leader>gq` closes it). Wrapped here so the file
--               lands in a code pane and not in neo-tree or the AI column.
--
-- And, in the file panels, one click previews a file's diff — the same gesture
-- and the same `tree_click` setting neo-tree uses (see the mouse section below).
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

---A real DiffView living in a valid tabpage. A `<leader>gh` file-history tab is
---a FileHistoryView: no `files:iter()`, no `set_file_by_path` — adopting it
---would swallow a jump into a bogus "no changes" toast, and it is not what
---`<leader>gd` means either. `lib.views` is the plugin's own registry; it holds
---every view ever opened, including ones whose tabpage the user has since
---closed, hence the validity check.
---@param lib table
---@return table|nil
local function diff_view(lib)
	for _, view in ipairs(lib.views) do
		if view.tabpage and api.nvim_tabpage_is_valid(view.tabpage) then
			if view.files and view.set_file then
				return view
			end
		end
	end
end

---A whole-repo file-history view: a FileHistoryView (the exact complement of
---`diff_view`'s test — only two view types exist) opened with NO path args.
---
---`<leader>gh` passes the current file and `<leader>gH` passes nothing, so the
---path args are what tells the two commands' tabs apart — and scoping the
---adoption to the empty ones is why `<leader>gh` keeps stacking, correctly: two
---files are two legitimate histories. They are read from the view's OWN adapter
---because `vcs.get_adapter` builds a fresh instance per call ("Create a new
---adapter instance"), so `ctx.path_args` is per-view state and not a shared
---last-call-wins field.
---@param lib table
---@return table|nil
local function repo_history_view(lib)
	for _, view in ipairs(lib.views) do
		if view.tabpage and api.nvim_tabpage_is_valid(view.tabpage) then
			if not (view.files and view.set_file) then
				local ctx = view.adapter and view.adapter.ctx
				if ctx and #(ctx.path_args or {}) == 0 then
					return view
				end
			end
		end
	end
end

---An already-open view worth jumping into: a real DiffView first, else whatever
---else is open — a file-history tab still beats opening a second one.
---@param lib table
---@return table|nil
local function open_view(lib)
	local view = diff_view(lib)
	if view then
		return view
	end
	for _, other in ipairs(lib.views) do
		if other.tabpage and api.nvim_tabpage_is_valid(other.tabpage) then
			return other
		end
	end
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

---`gf` — out of the view, onto the real editable file, leaving the Diffview tab
---standing (`<leader>gd` comes back to it, `<leader>gq` closes it).
---
---This wraps diffview's stock `gf` rather than replacing it, for one reason:
---`goto_file_edit` opens the file in the target tab's LAST ACCESSED window,
---which is just as likely to be neo-tree or the AI terminal column as a code
---pane — landing the file there wipes the panel. Point the tab at a real editor
---window first; diffview then edits into it.
local function goto_file()
	local ok, lib = pcall(require, "diffview.lib")
	if not ok then
		return
	end

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
	local ok_actions, actions = pcall(require, "diffview.actions")
	if ok_actions then
		actions.goto_file_edit()
	end
end

---<leader>gd — the working-tree diff, in AT MOST ONE tab.
---
---`DiffviewOpen` does not dedupe: `lib.diffview_open` never inspects
---`lib.views`, and `View:open()` always runs `tab split`. So every press used
---to add a tabline entry carrying its own copy of the same diff — and the
---`gf`-then-`<leader>gd` loop hit it every time, because `gf` leaves you in the
---previous tabpage with the diff tab still open.
local function open_diff()
	local ok, lib = pcall(require, "diffview.lib")
	if not ok then
		return
	end

	local view = diff_view(lib)
	if not view then
		vim.cmd("DiffviewOpen")
		return
	end

	if api.nvim_get_current_tabpage() == view.tabpage then
		-- Already inside it: re-list what changed. `focus_panel` also reopens a
		-- panel that was toggled away with <leader>b, so this is never a no-op.
		focus_panel(view)
	else
		-- Focus lands wherever that tab left it, so this is a true "back to where
		-- I was reading" rather than a reset.
		api.nvim_set_current_tabpage(view.tabpage)
	end

	-- An adopted tab must never show a stale file list.
	pcall(vim.cmd, "DiffviewRefresh")
end

---<leader>gH — the whole-repo history, in AT MOST ONE tab. Same defect as
---`open_diff` guards: `lib.file_history` never inspects `lib.views` either, so
---every press was another `tab split` over the same log.
local function open_repo_history()
	local ok, lib = pcall(require, "diffview.lib")
	if not ok then
		return
	end

	local view = repo_history_view(lib)
	if not view then
		vim.cmd("DiffviewFileHistory")
		return
	end

	if api.nvim_get_current_tabpage() == view.tabpage then
		focus_panel(view)
	else
		api.nvim_set_current_tabpage(view.tabpage)
	end

	-- Both view types listen for `refresh_files`, and `emit` dispatches to the
	-- view of the CURRENT tabpage — so this refreshes the one we just adopted.
	pcall(vim.cmd, "DiffviewRefresh")
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
			-- Never out to the buffer — that is `gf`'s job.
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

-- ─── Mouse: click-to-preview in the file panels ──────────────────────────────
-- diffview's ONLY stock mouse binding is `{ "n", "<2-LeftMouse>", select_entry }`
-- (diffview/config.lua), so seeing a file's diff cost two clicks while neo-tree
-- opens on one. The maps below add the single-click path behind the SAME
-- persisted `tree_click` setting (:NvSinnerMenu → "Explorer click"), so both
-- explorers agree on what a click costs.

local function single_click()
	return require("core.settings").get("tree_click") == "single"
end

--- Preview the entry under the pointer. `select_entry` is `view:set_file(item,
--- false)` — the diff panes update and focus STAYS in the list, so you can walk
--- the changed files by clicking; descending into the diff stays <leader>gi's
--- job. On a directory row it toggles the fold. Silent no-op when the click
--- missed a row (core.mouse guards getmousepos' clamp to the last line) or
--- before the plugin has loaded.
local function select_clicked()
	if not require("core.mouse").clicked_line(api.nvim_get_current_win()) then
		return
	end
	local ok, dv = pcall(require, "diffview.actions")
	if ok then
		dv.select_entry()
	end
end

-- Shared by both panels. They MERGE with the stock bindings: `config.setup`
-- rebuilds its keymap tables from pristine defaults and then extends them keyed
-- by "<mode> <lhs>", so these two override the stock <2-LeftMouse> and every
-- other default survives. `keymaps.disable_defaults` must never be set.
local CLICK_MAPS = {
	-- <LeftRelease>, not <LeftMouse>: the press still positions the cursor
	-- first, and the handler acts on the row that press selected.
	{
		"n",
		"<LeftRelease>",
		function()
			if single_click() then
				select_clicked()
			end
		end,
		{ desc = "Open the diff for the entry under the pointer" },
	},
	-- While single-click is active, swallow the second click of a reflexive
	-- double-click: on a directory row it would re-collapse the folder the
	-- first click just expanded. In "double" mode this is the stock binding
	-- (plus the missed-row guard).
	{
		"n",
		"<2-LeftMouse>",
		function()
			if not single_click() then
				select_clicked()
			end
		end,
		{ desc = "Open the diff for the entry under the pointer" },
	},
}

-- Our `gf` (see `goto_file`) overrides the stock `actions.goto_file_edit` in the
-- three groups diffview binds it in: the diff windows and both panels.
local GOTO_FILE_MAPS = {
	{ "n", "gf", goto_file, { desc = "Open the file in the previous tabpage (keeps the diff tab)" } },
}

---The panel keymaps: the two mouse gestures plus `gf`. Built per call so the two
---panels never share one mutable table.
---@return table
local function panel_maps()
	local maps = {}
	vim.list_extend(maps, CLICK_MAPS)
	vim.list_extend(maps, GOTO_FILE_MAPS)
	return maps
end

return {
	"sindrets/diffview.nvim",
	-- Lazy: only pulled in when one of its commands or keymaps is used.
	cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewFileHistory", "DiffviewToggleFiles" },
	keys = {
		{ "<leader>gd", open_diff, desc = "Diff: working tree vs index" },
		{ "<leader>gh", "<cmd>DiffviewFileHistory %<cr>", desc = "Diff: history of current file" },
		{ "<leader>gH", open_repo_history, desc = "Diff: history of whole repo" },
		{ "<leader>gq", "<cmd>DiffviewClose<cr>", desc = "Diff: close view" },
		{ "<leader>gi", into_diff, desc = "Diff: into the diff (toggle diff/file list)" },
	},
	opts = {
		-- Brighter, word-level diff highlights so changes stand out clearly.
		enhanced_diff_hl = true,
		keymaps = {
			view = GOTO_FILE_MAPS, -- the diff windows themselves
			file_panel = panel_maps(), -- <leader>gd / <leader>gi — the changed-files list
			file_history_panel = panel_maps(), -- <leader>gh / <leader>gH — the history list
		},
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
