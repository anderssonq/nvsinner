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

	it("splits below/right and enables the mouse", function()
		assert.is_true(vim.o.splitbelow)
		assert.is_true(vim.o.splitright)
		assert.matches("a", vim.o.mouse)
	end)
end)
