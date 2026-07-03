-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
	local lazyrepo = "https://github.com/folke/lazy.nvim.git"
	local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
	if vim.v.shell_error ~= 0 then
		vim.api.nvim_echo({
			{ "Failed to clone lazy.nvim:\n", "ErrorMsg" },
			{ out, "WarningMsg" },
			{ "\nPress any key to exit..." },
		}, true, {})
		vim.fn.getchar()
		os.exit(1)
	end
end
vim.opt.rtp:prepend(lazypath)

-- Core config: options FIRST (sets the leaders before lazy reads `keys` specs),
-- then keymaps, the AI-workflow autoreload, and the native touch/focus layer.
require("core.options")
require("core.keymaps")
require("core.autoreload")
require("core.ui-touch")
require("core.ai-activity") -- start polling so the terminal winbar shows agent activity
require("core.update") -- defines :NvSinnerUpdate (git pull + restore plugins + checkhealth)
require("core.health") -- :checkhealth nvsinner + a one-time first-run "missing tools" toast
require("core.image-open") -- open images in macOS Quick Look instead of showing binary bytes
-- Setup lazy.nvim
require("lazy").setup({
	spec = {
		-- Categorized plugin specs. lazy.nvim's import does NOT recurse into
		-- subfolders, so each category folder must be imported explicitly.
		{ import = "plugins.ui" },
		{ import = "plugins.lsp" },
		{ import = "plugins.git" },
		{ import = "plugins.editor" },
		{ import = "plugins.navigation" },
		{ import = "plugins.terminal" },
	},
	-- Colorscheme that will be used when installing plugins
	install = { colorscheme = { "habamax" } },
	-- Automatically check for plugin updates
	checker = { enabled = true },
})
