-- Carbon cmdline + message UI (noice.nvim).
--
-- Moves the `:` command line and search into a centered floating box
-- (command-palette style), routes messages through nvim-notify, and gives the
-- popup-menu a matching surface — so the whole bottom-left noise becomes a
-- clean recessed panel that matches the carbon theme (borderless, on `blend`).
--
-- NOTE: LSP hover/signature are LEFT OFF — but the reason on the tin was wrong
-- for months. It said "the markdown treesitter highlighter crashes on 0.12.x";
-- that crash was nvim-treesitter's frozen master misreading 0.12's list-valued
-- `match[id]`, and lua/core/ts-compat.lua fixes it. So the TS-crash rationale
-- is VOID and these could probably be re-enabled. They stay off pending their
-- own evaluation: turning them on is a UX change to a different subsystem
-- (bordered noice floats replacing the native handler, different scrolling,
-- `override` of the vim.lsp markdown helpers) and it deletes a CLAUDE.md
-- non-negotiable — that deserves its own evidence, not a drive-by flip.
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
				-- Left empty with the rest of the lsp block — see the header: the
				-- 0.12 "markdown crash" that justified this is fixed in
				-- core/ts-compat, so this is pending re-evaluation, not required.
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

		-- Tie the noice surfaces to the carbon palette (lua/core/carbon.lua):
		-- recessed `blend` panels with invisible borders (the oxocarbon
		-- telescope look). Re-applied on ColorScheme so it
		-- survives a colorscheme reload (mirrors ui-touch.lua).
		local function carbon_hl()
			local c = require("core.carbon").colors()
			local set = vim.api.nvim_set_hl
			set(0, "NoiceCmdlinePopup", { bg = c.blend, fg = c.base05 })
			set(0, "NoiceCmdlinePopupBorder", { bg = c.blend, fg = c.blend })
			set(0, "NoicePopupmenu", { bg = c.blend, fg = c.base04 })
			set(0, "NoicePopupmenuBorder", { bg = c.blend, fg = c.blend })
			set(0, "NoicePopupmenuSelected", { bg = c.base02, fg = c.base08, bold = true })
			set(0, "NoiceCmdlineIcon", { fg = c.base09 }) -- the prompt glyph in accent blue
		end
		carbon_hl()
		vim.api.nvim_create_autocmd("ColorScheme", { pattern = "*", callback = carbon_hl })
	end,
}
