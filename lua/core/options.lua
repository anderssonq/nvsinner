-- Core editor options + the leaders. Required FIRST from init.lua (before
-- lazy.setup) so that <leader>/<localleader> are defined before any plugin
-- `keys` spec is evaluated.

-- Set up mapleader and maplocalleader early
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- Set vim options
vim.cmd([[
  set relativenumber
  set foldmethod=manual
  set mouse=a
  set number
  set expandtab
  set shiftwidth=2
  set softtabstop=2
  set tabstop=2
  set fileencoding=utf-8
  set splitbelow
  set splitright
  set linebreak
  set wrap
  set clipboard+=unnamedplus
]])

vim.opt.termguicolors = true

-- This config is Lua-only and drives AI via a CLI in a terminal column, so the
-- python3/ruby/perl/node remote-plugin host providers are never used. Disabling
-- them removes provider-probe work at startup and silences the matching
-- :checkhealth warnings.
vim.g.loaded_python3_provider = 0
vim.g.loaded_ruby_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_node_provider = 0

-- Subtle "glass" completion popup: blend the pum with the terminal background.
-- pumblend is self-contained to the completion menu, so it does not touch the
-- NvSinner modals (solid on purpose) or other floats — a global winblend would.
vim.opt.pumblend = 10

-- Remote clipboard via OSC 52: inside an SSH session there is no local
-- pbcopy/xclip to reach, so route the + and * registers through the terminal's
-- OSC 52 escape (Ghostty supports it). Gated on $SSH_TTY so local sessions keep
-- using pbcopy/pbpaste. (Paste falls back to the register when the terminal does
-- not answer the OSC 52 read — the documented behavior.)
if vim.env.SSH_TTY then
	local osc52 = require("vim.ui.clipboard.osc52")
	vim.g.clipboard = {
		name = "OSC 52",
		copy = { ["+"] = osc52.copy("+"), ["*"] = osc52.copy("*") },
		paste = { ["+"] = osc52.paste("+"), ["*"] = osc52.paste("*") },
	}
end
