-- ─── Mouse: click-to-open ────────────────────────────────────────────────────
-- neo-tree's ONLY stock mouse binding is `["<2-LeftMouse>"] = "open"`
-- (neo-tree/defaults.lua). The maps below add a single-click path behind the
-- persisted `tree_click` setting (:NvSinnerMenu → "Explorer click"). They MERGE
-- with the stock mapping table — neo-tree discards the defaults only when
-- `use_default_mappings = false` — so all ~40 built-in bindings survive.

--- Open the clicked node. `open` already routes a directory to `toggle_node`
--- (neo-tree/sources/common/commands.lua), so one call covers files and folders;
--- resolving through `state.commands` keeps any per-source override.
---
--- `core.mouse.clicked_line` is the missed-row guard: `getmousepos().line`
--- CLAMPS to the last buffer line, so without it a click on the empty space
--- below the tree would open the last file. (The tree's winbar carries the
--- Files/Buffers/Git selector, so the helper's winbar offset is always in play
--- here.) diffview's file panels share the same guard.
local function open_clicked(state)
	if not require("core.mouse").clicked_line(state.winid) then
		return
	end
	local cmd = state.commands and state.commands.open
	if cmd then
		cmd(state)
	end
end

local function single_click()
	return require("core.settings").get("tree_click") == "single"
end

return {
	"nvim-neo-tree/neo-tree.nvim",
	branch = "v3.x",
	-- Lazy: loads on the :Neotree command or the <leader>e keymap.
	cmd = "Neotree",
	dependencies = {
		"nvim-lua/plenary.nvim",
		"nvim-tree/nvim-web-devicons", -- not strictly required, but recommended
		"MunifTanjim/nui.nvim",
		"3rd/image.nvim", -- Optional image support in preview window: See `# Preview Mode` for more information
	},
	keys = {
		{
			"<leader>e",
			function()
				-- Check whether Neo-tree is currently visible
				local manager = require("neo-tree.sources.manager")
				local renderer = require("neo-tree.ui.renderer")
				local state = manager.get_state("filesystem")

				if renderer.window_exists(state) then
					-- Neo-tree is open, just close it
					vim.cmd("Neotree close")
				else
					-- Open it focused on the file you're editing/reading: `reveal`
					-- jumps to and highlights the current buffer's file in the tree.
					-- For non-file buffers (dashboard, terminals) fall back to a
					-- plain open at the cwd root. The side comes from the persisted
					-- `tree_side` setting (:NvSinnerMenu), read on every open so a
					-- change applies to the next toggle.
					local side = require("core.settings").get("tree_side")
					local file = vim.api.nvim_buf_get_name(0)
					if file ~= "" and vim.bo.buftype == "" and vim.fn.filereadable(file) == 1 then
						vim.cmd("Neotree reveal " .. side)
					else
						vim.cmd("Neotree focus " .. side)
					end
					vim.notify(
						" a add · r rename · d delete · y copy · x cut · p paste · ? help",
						vim.log.levels.INFO,
						{ title = "Neo-tree", timeout = 250 }
					)
				end
			end,
			desc = "Toggle Neo-tree",
		},
	},
	config = function()
		require("neo-tree").setup({
			-- Source tabs in the tree's winbar: Files / Buffers / Git. The
			-- tree's winbar is unowned (ui-touch's SKIP_FT lists "neo-tree",
			-- filebadge only claims markdown), so this takes it uncontested.
			-- git_status needs no enabling — it is already in neo-tree's
			-- default `sources`, and `enable_git_status` defaults to true.
			source_selector = {
				winbar = true,
				statusline = false,
				-- The display names match neo-tree's own built-in defaults;
				-- stated explicitly to pin the labels against upstream drift.
				sources = {
					{ source = "filesystem", display_name = " 󰉓 Files " },
					{ source = "buffers", display_name = " 󰈚 Buffers " },
					{ source = "git_status", display_name = " 󰊢 Git " },
				},
				content_layout = "start",
				tabs_layout = "equal",
				show_scrolled_off_parent_node = false,
				-- Carbon defines these (colors/carbon.lua); neo-tree's own
				-- defaults are hardcoded near-black hexes that ignore the theme.
				highlight_tab = "NeoTreeTabInactive",
				highlight_tab_active = "NeoTreeTabActive",
			},
			window = {
				mappings = {
					-- <LeftRelease>, not <LeftMouse>: the press still positions the
					-- cursor first (the choice every NvSinner modal makes), and the
					-- handler then acts on the row that press selected.
					["<LeftRelease>"] = function(state)
						if single_click() then
							open_clicked(state)
						end
					end,
					-- While single-click is active, swallow the second click of a
					-- reflexive double-click: it would immediately re-collapse a
					-- folder the first click just expanded. In "double" mode this
					-- is the stock binding (plus the missed-row guard).
					["<2-LeftMouse>"] = function(state)
						if not single_click() then
							open_clicked(state)
						end
					end,
				},
			},
			buffers = {
				-- PERF. neo-tree's buffers source subscribes a BEFORE_RENDER handler
				-- that calls the SYNCHRONOUS git.status (`vim.fn.system`, at
				-- neo-tree/git/init.lua:251) on EVERY render — and `git_status_async`
				-- does NOT cover it: only the filesystem source reads that option.
				-- On a repo with a large ignored/untracked tree that blocks the UI
				-- each time the Buffers tab draws.
				-- The subscription sits in an `elseif config.before_render` branch
				-- (neo-tree/sources/buffers/init.lua), so defining before_render here
				-- means it is never registered at all.
				-- Trade-off, accepted deliberately: buffer rows lose their git
				-- symbols. Files keeps its git state — that source uses the
				-- genuinely async path.
				before_render = function() end,
			},
			filesystem = {
				filtered_items = {
					visible = true, -- If true, all "hide" rules just dim items out instead of hiding them
					hide_dotfiles = false,
					hide_gitignored = true,
				},
				window = {
					-- 38, not the old 30: the source_selector's "equal" layout
					-- splits the width into fixed thirds, and " 󰈚 Buffers " (11
					-- cells + separator) truncates to "Buffer…" below 38.
					-- Measured — drop this to 32 if you ever switch to "start".
					width = 38, -- columns
					-- Default side for a bare :Neotree; the <leader>e keymap passes
					-- the side explicitly on every open (persisted via :NvSinnerMenu).
					position = require("core.settings").get("tree_side"),
				},
			},
		})
	end,
}
