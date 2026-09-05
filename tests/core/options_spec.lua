-- Tests for core editor options + leaders (lua/core/options.lua).

describe("core.options", function()
	require("core.options")

	it("sets Space as <leader> and \\ as <localleader>", function()
		assert.are.equal(" ", vim.g.mapleader)
		assert.are.equal("\\", vim.g.maplocalleader)
	end)

	it("uses 2-space, expandtab indentation", function()
		assert.is_true(vim.o.expandtab)
		assert.are.equal(2, vim.o.shiftwidth)
		assert.are.equal(2, vim.o.tabstop)
		assert.are.equal(2, vim.o.softtabstop)
	end)

	it("enables numbers, relative numbers and true colour", function()
		assert.is_true(vim.o.number)
		assert.is_true(vim.o.relativenumber)
		assert.is_true(vim.o.termguicolors)
	end)

	-- Regression guard for FA-25: unset means Neovim's 1000ms default, which is
	-- the full pause a bare <leader>t / <leader>j / <leader>jx / <leader>f pays
	-- for being a prefix of a longer map.
	it("calibrates the prefix-key wait well below Neovim's 1000ms default", function()
		assert.are.equal(300, vim.o.timeoutlen)
	end)

	-- The terminal tab is the only place several nvsinner windows are tellable
	-- apart; unset 'title' means the terminal picks its own text.
	it("names the terminal tab after the project", function()
		assert.is_true(vim.o.title)
		assert.are.equal(require("core.project").EXPR, vim.o.titlestring)
		assert.are.equal(require("core.project").name(), vim.api.nvim_eval_statusline(vim.o.titlestring, {}).str)
	end)

	it("splits below/right and enables the mouse", function()
		assert.is_true(vim.o.splitbelow)
		assert.is_true(vim.o.splitright)
		assert.matches("a", vim.o.mouse)
	end)

	-- Neovim ships both at 0, which glues the cursor to the viewport edge.
	it("keeps a margin of context around the cursor", function()
		assert.is_true(vim.o.scrolloff > 0, "scrolloff 0 means the cursor rides the edge")
		assert.is_true(vim.o.sidescrolloff > 0)
	end)
end)
