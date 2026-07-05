-- Markdown reading view — render-markdown.nvim + a clickable "Open view"
-- action chip rendered by the native file badge (lua/core/filebadge.lua) at
-- the right end of the markdown winbar, in the same component as the
-- filename: "󰈙 Open view │ ● 󰍔 file.md". The chip is a native %@…%X winbar
-- click region driving _G.NvMdReader.click; this file owns the reader state,
-- the label, and the <leader>m toggle.
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
-- markdown stays excluded from barbecue's breadcrumb winbar (see barbacue.lua)
-- so core/filebadge.lua can own that winbar line.
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

		-- Reader state. Exposed on a global so core/filebadge.lua's winbar
		-- evaluator can read the label and wire the %@…%X click region.
		local reader = {}
		reader.on = false

		function reader.label()
			return reader.on and "󰈙 Reading view · on" or "󰈙 Open view"
		end

		function reader.toggle()
			rm.toggle() -- flips render-markdown globally
			reader.on = not reader.on
		end

		-- Winbar click handler: (minwid, clicks, button, mods) — all ignored.
		function reader.click()
			reader.toggle()
		end

		_G.NvMdReader = reader

		local function map_buffer(buf)
			vim.keymap.set("n", "<leader>m", reader.toggle, {
				buffer = buf,
				silent = true,
				desc = "Markdown reading view (Open view)",
			})
		end

		vim.api.nvim_create_autocmd("FileType", {
			group = vim.api.nvim_create_augroup("NvMdReaderBar", { clear = true }),
			pattern = "markdown",
			callback = function(ev)
				map_buffer(ev.buf)
			end,
		})

		-- This config runs on the first markdown open (ft-lazy), by which point
		-- the FileType event for that buffer has already fired — map it now.
		if vim.bo.filetype == "markdown" then
			map_buffer(vim.api.nvim_get_current_buf())
		end
	end,
}
