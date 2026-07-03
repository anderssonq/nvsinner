-- Tests for the carbon palette + its feature flags (lua/core/carbon.lua) and
-- the colorscheme honoring them (colors/carbon.lua).

describe("core.carbon", function()
	local carbon = require("core.carbon")

	-- Every spec restores the flag/option state it touches.
	before_each(function()
		vim.g.nvsinner_background = nil
		vim.g.nvsinner_transparent = nil
		vim.env.NVSINNER_BACKGROUND = nil
		vim.env.NVSINNER_TRANSPARENT = nil
		vim.o.background = "dark"
	end)

	it("resolves the dark role table by default and light via vim.o.background", function()
		assert.are.equal("#161616", carbon.colors().base00)
		vim.o.background = "light"
		assert.are.equal("#ffffff", carbon.colors().base00)
	end)

	it("background(): defaults to dark, honors the vim.g flag and the env var", function()
		assert.are.equal("dark", carbon.background())
		vim.env.NVSINNER_BACKGROUND = "light"
		assert.are.equal("light", carbon.background())
		-- vim.g wins over the environment; invalid values fall back to dark.
		vim.g.nvsinner_background = "dark"
		assert.are.equal("dark", carbon.background())
		vim.g.nvsinner_background = "solarized"
		assert.are.equal("dark", carbon.background())
	end)

	it("transparent(): defaults to false, honors the vim.g flag and the env var", function()
		assert.is_false(carbon.transparent())
		vim.g.nvsinner_transparent = true
		assert.is_true(carbon.transparent())
		vim.g.nvsinner_transparent = nil
		vim.env.NVSINNER_TRANSPARENT = "1"
		assert.is_true(carbon.transparent())
		vim.env.NVSINNER_TRANSPARENT = "0"
		assert.is_false(carbon.transparent())
	end)

	it("colorscheme carbon paints opaque surfaces by default", function()
		vim.cmd.colorscheme("carbon")
		assert.are.equal("carbon", vim.g.colors_name)
		local normal = vim.api.nvim_get_hl(0, { name = "Normal" })
		assert.are.equal(0x161616, normal.bg)
		assert.are.equal(0x131313, vim.api.nvim_get_hl(0, { name = "NormalFloat" }).bg)
	end)

	it("colorscheme carbon drops surface backgrounds in transparent mode", function()
		vim.g.nvsinner_transparent = true
		vim.cmd.colorscheme("carbon")
		assert.is_nil(vim.api.nvim_get_hl(0, { name = "Normal" }).bg)
		assert.is_nil(vim.api.nvim_get_hl(0, { name = "NormalFloat" }).bg)
		-- Chips stay solid so the UI remains legible on any terminal bg.
		assert.are.equal(0x33b1ff, vim.api.nvim_get_hl(0, { name = "StatusTerminal" }).bg)
		-- Restore the opaque scheme for any spec running after this one.
		vim.g.nvsinner_transparent = nil
		vim.cmd.colorscheme("carbon")
	end)

	it("light variant resolves through the same colorscheme", function()
		vim.o.background = "light"
		vim.cmd.colorscheme("carbon")
		assert.are.equal(0xffffff, vim.api.nvim_get_hl(0, { name = "Normal" }).bg)
		vim.o.background = "dark"
		vim.cmd.colorscheme("carbon")
	end)
end)
