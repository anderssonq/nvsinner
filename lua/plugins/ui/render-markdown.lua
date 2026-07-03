-- Markdown reading view — render-markdown.nvim + a centered, clickable
-- "Open view" button in the window's winbar (top-center of the pane).
--
-- render-markdown renders headings / code blocks / bullets / tables inline for a
-- readable "reading view". It drives off the markdown treesitter parser, which
-- on Neovim 0.12.x crashes (node:range on a nil node — see nvim-treesitter.lua):
-- verified here, render-markdown's parse hit the exact bug in the markdown
-- *code-fence language-detection* injection directive. Mitigation: the init()
-- below overrides the markdown `injections` query to keep ONLY the
-- markdown_inline injection (so inline bold/italic/code/links still render) and
-- drop the crashing code-fence directive (fenced blocks are still styled by
-- render-markdown, just without inner treesitter syntax colors). Nothing else on
-- this config consumes the markdown TS tree (highlight is disabled), so the blast
-- radius is exactly render-markdown. The view also starts OFF (`enabled = false`)
-- and is opt-in via the button / <leader>m.
--
-- The button lives in the winbar (natively clickable via a %@…@ click region);
-- markdown is excluded from barbecue's breadcrumb winbar (see barbacue.lua) so
-- the two don't fight over the same line.
return {
	"MeanderingProgrammer/render-markdown.nvim",
	ft = { "markdown" },
	dependencies = {
		"nvim-treesitter/nvim-treesitter",
		"nvim-tree/nvim-web-devicons",
	},
	-- Patch the markdown injections query at STARTUP (init runs before any buffer
	-- opens): keep the inline injection, drop the code-fence language directive
	-- that triggers the Neovim 0.12.x node:range nil-node crash. It must land
	-- before the buffer's markdown LanguageTree is constructed — a tree caches its
	-- injection query at construction, so setting this from config() (after the
	-- first :edit builds the tree) is too late and still crashes. See the header.
	init = function()
		pcall(
			vim.treesitter.query.set,
			"markdown",
			"injections",
			'((inline) @injection.content (#set! injection.language "markdown_inline"))'
		)
	end,
	config = function()
		require("render-markdown").setup({
			-- Start OFF; the "Open view" button / <leader>m opts in per session.
			enabled = false,
			-- Don't render inside the AI terminal columns etc.
			file_types = { "markdown" },
		})

		local rm = require("render-markdown")

		-- Reader state + winbar button. Exposed on a global so the winbar click
		-- region (%@v:lua.NvMdReader.click@) can reach it.
		local reader = {}
		reader.on = false

		-- Carbon chip for the button (roles from lua/core/carbon.lua): blue
		-- identity accent (base09) on the recessed `blend` float surface.
		local function apply_hl()
			local c = require("core.carbon").colors()
			vim.api.nvim_set_hl(0, "NvMdBtn", { fg = c.base09, bg = c.blend, bold = true })
		end
		apply_hl()
		vim.api.nvim_create_autocmd("ColorScheme", { callback = apply_hl })

		local function label()
			return reader.on and "󰈙 Reading view · on  (click to close)" or "󰈙 Open view"
		end

		-- Centered (%=…%=), highlighted (%#NvMdBtn#), clickable (%@…@ … %X) button.
		local function winbar_str()
			return "%=%@v:lua.NvMdReader.click@%#NvMdBtn# " .. label() .. " %*%X%="
		end

		local function apply_to(win)
			if win and win ~= -1 and vim.api.nvim_win_is_valid(win) then
				vim.wo[win].winbar = winbar_str()
			end
		end

		-- Re-paint the button on every markdown window (label reflects on/off).
		function reader.refresh_all()
			for _, w in ipairs(vim.api.nvim_list_wins()) do
				local b = vim.api.nvim_win_get_buf(w)
				if vim.bo[b].filetype == "markdown" then
					apply_to(w)
				end
			end
		end

		function reader.toggle()
			rm.toggle() -- flips render-markdown globally
			reader.on = not reader.on
			reader.refresh_all()
		end

		-- Winbar click handler: (minwid, clicks, button, mods) — all ignored.
		function reader.click()
			reader.toggle()
		end

		_G.NvMdReader = reader

		-- Paint the button when a markdown buffer gets a filetype or lands in a
		-- window (winbar is window-local, so re-apply on BufWinEnter too).
		local grp = vim.api.nvim_create_augroup("NvMdReaderBar", { clear = true })
		vim.api.nvim_create_autocmd("FileType", {
			group = grp,
			pattern = "markdown",
			callback = function(ev)
				apply_to(vim.fn.bufwinid(ev.buf))
				vim.keymap.set("n", "<leader>m", reader.toggle, {
					buffer = ev.buf,
					silent = true,
					desc = "Markdown reading view (Open view)",
				})
			end,
		})
		vim.api.nvim_create_autocmd("BufWinEnter", {
			group = grp,
			callback = function(ev)
				if vim.bo[ev.buf].filetype == "markdown" then
					apply_to(vim.fn.bufwinid(ev.buf))
				end
			end,
		})

		-- This config runs on the first markdown open (ft-lazy), by which point
		-- the FileType event for that buffer has already fired — so paint the
		-- current window now.
		if vim.bo.filetype == "markdown" then
			apply_to(vim.api.nvim_get_current_win())
			vim.keymap.set("n", "<leader>m", reader.toggle, {
				buffer = true,
				silent = true,
				desc = "Markdown reading view (Open view)",
			})
		end
	end,
}
