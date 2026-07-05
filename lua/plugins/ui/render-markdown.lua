-- render-markdown.nvim is **disabled**: replaced by the native reading view in
-- lua/core/markdown.lua (pattern-based visible-range scan — heading bars,
-- bullets, checkboxes, quote bars, fence shading, rules — same _G.NvMdReader
-- seam, same <leader>m / winbar "Open view" chip). Kept as a revert path, but
-- NOTE: reverting is NOT a one-liner — flipping `enabled = true` must be
-- paired with removing the `require("core.markdown")` line from init.lua, or
-- _G.NvMdReader and <leader>m double-register (the ft-lazy config() below
-- would overwrite the global while the core module's autocmds keep firing).
--
-- Historical context kept for the revert: render-markdown drives the markdown
-- treesitter parser, which on Neovim 0.12.x crashes (node:range on a nil node
-- — see nvim-treesitter.lua) in the markdown *code-fence language-detection*
-- injection directive. Mitigation: the init() below overrides the markdown
-- `injections` query to keep ONLY the markdown_inline injection and drop the
-- crashing directive. That patch now lives at the top of lua/core/markdown.lua
-- (core loads pre-lazy, preserving the "before the first LanguageTree" timing).
--
-- markdown stays excluded from barbecue's breadcrumb winbar (see barbacue.lua)
-- so core/filebadge.lua can own that winbar line.
return {
	"MeanderingProgrammer/render-markdown.nvim",
	enabled = false,
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
