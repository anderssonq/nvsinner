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
