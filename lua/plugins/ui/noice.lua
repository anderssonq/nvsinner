-- Glass cmdline + message UI (noice.nvim).
--
-- Moves the `:` command line and search into a centered floating glass box
-- (command-palette style), routes messages through nvim-notify, and gives the
-- popup-menu a matching border — so the whole bottom-left noise becomes a clean
-- floating surface that matches the kanagawa glass theme.
--
-- NOTE: LSP hover/signature are deliberately LEFT OFF. The markdown treesitter
-- highlighter crashes on Neovim 0.12.x when parsing transient floats (same bug
-- documented in lua/ui-touch.lua), so we keep noice away from markdown floats.
-- `K` hover keeps the native handler; mouse-hover docs stay in ui-touch.lua.
return {
	"folke/noice.nvim",
	event = "VeryLazy",
	dependencies = {
		"MunifTanjim/nui.nvim",
		"rcarriga/nvim-notify",
	},
	config = function()
		require("noice").setup({
			cmdline = {
				view = "cmdline_popup",
			},
			-- Let nvim-notify own `vim.notify` directly. noice's notify routing
			-- intercepted every toast, rendered it with a persistent timestamp
			-- (e.g. "00:48:51"), and ignored the per-call `timeout`, so toasts
			-- (Neo-tree, lazy.nvim, save/undo, AI-edit) never faded at 250ms.
			-- Disabling it leaves vim.notify pointing at nvim-notify, whose
			-- global `timeout = 250` (notify.lua) + per-call opts are honored.
			-- noice still owns the glass cmdline / popupmenu below.
			notify = { enabled = false },
			lsp = {
				hover = { enabled = false },
				signature = { enabled = false },
				progress = { enabled = true },
				-- Do NOT override vim.lsp markdown helpers (keeps the 0.12 markdown
				-- treesitter crash out of cmp docs / hover paths).
				override = {},
			},
			presets = {
				bottom_search = true, -- `/` search stays as a classic bottom box
				command_palette = true, -- `:` cmdline + popupmenu together, centered top
				long_message_to_split = true, -- big :messages open in a split, not a wall
				inc_rename = false,
				lsp_doc_border = true,
			},
			routes = {
				-- Drop the noisy "search hit BOTTOM/TOP" + recording spam.
				{ filter = { event = "msg_show", kind = "search_count" }, opts = { skip = true } },
				{ filter = { event = "msg_show", find = "written" }, opts = { skip = true } },
			},
		})

		-- Tie the noice surfaces to the glass palette (theme.lua):
		-- bg #111118 glass, border #333345. Re-applied on ColorScheme so it
		-- survives a kanagawa reload (mirrors theme.lua / ui-touch.lua).
		local function glass_hl()
			local set = vim.api.nvim_set_hl
			set(0, "NoiceCmdlinePopup", { bg = "#111118", fg = "#c5c9d5" })
			set(0, "NoiceCmdlinePopupBorder", { bg = "#111118", fg = "#333345" })
			set(0, "NoicePopupmenu", { bg = "#111118", fg = "#c5c9d5" })
			set(0, "NoicePopupmenuBorder", { bg = "#111118", fg = "#333345" })
			set(0, "NoicePopupmenuSelected", { bg = "#1c1c26", fg = "#c4746e", bold = true })
			set(0, "NoiceCmdlineIcon", { fg = "#c4746e" }) -- the prompt glyph in crimson
		end
		glass_hl()
		vim.api.nvim_create_autocmd("ColorScheme", { pattern = "*", callback = glass_hl })
	end,
}
