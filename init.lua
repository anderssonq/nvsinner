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
require("core.settings") -- persisted :NvSinnerMenu settings; seeds the carbon flags BEFORE lazy/theme
require("core.keymaps")
require("core.autoreload")
require("core.ai-edits") -- underline AI-written lines after a disk reload, until the user takes over
require("core.ui-touch")
require("core.ai-activity") -- start polling so the terminal winbar shows agent activity
require("core.ai-sessions") -- AI session registry + send-to-AI bridge (<leader>as/ab/ad, <leader>ja)
require("core.ai-ask") -- :NvSinnerAskAI + visual <leader>x — Ask-AI action modal over the selection
require("core.update") -- defines :NvSinnerUpdate (git pull + restore plugins + checkhealth)
require("core.sync") -- defines :NvSinnerSync (opt-in :Lazy sync + Mason package updates)
require("core.health") -- :checkhealth nvsinner + a one-time first-run "missing tools" toast
require("core.image-open") -- open images in macOS Quick Look instead of showing binary bytes
require("core.menu") -- :NvSinnerMenu — the settings modal over core/settings.lua
require("core.prompts") -- :NvSinnerPrompts — prompt library modal (settings/prompts.json → clipboard)
require("core.help") -- :NvSinnerHelp — command palette listing every NvSinner command (pick → run)
require("core.symbols") -- :NvSinnerSymbols — document-symbols modal (<leader>cs, pick → jump)
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
	-- Colorscheme that will be used when installing plugins (carbon ships in
	-- this repo's colors/, so it's available even on a fresh install).
	install = { colorscheme = { "carbon", "habamax" } },
	-- No background update checker: plugin versions are pinned to the committed
	-- lazy-lock.json (:NvSinnerUpdate restores to it; :NvSinnerSync is the
	-- explicit opt-in float-to-latest path), so a boot-time "updates available"
	-- check would only run network fetches this config never acts on.
	checker = { enabled = false },
})
