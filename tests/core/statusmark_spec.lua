-- Tests for the statusline shimmer + identity mark (lua/core/statusmark.lua).

local mark = require("core.statusmark")
local project = require("core.project")

-- A throwaway git root; resolve() because macOS temp dirs are symlinked.
local function mkrepo(name)
	local root = vim.fn.resolve(vim.fn.tempname()) .. "/" .. name
	vim.fn.mkdir(root .. "/.git", "p")
	return root
end

-- Every `%#Group#` the markup switches to, in order.
local function groups_of(markup)
	local out = {}
	for g in markup:gmatch("%%#([%w_]+)#") do
		out[#out + 1] = g
	end
	return out
end

-- What the screen shows for a statusline string.
local function eval(stl)
	return vim.api.nvim_eval_statusline(stl, {})
end

-- Band-centre time: the moment the band sits on cell `i` of an `n`-cell bar.
local function t_at(i)
	return (i + mark.BAND) / mark.SPEED * 1000
end

describe("core.statusmark", function()
	local origin = vim.fn.getcwd()

	after_each(function()
		vim.cmd.cd(origin)
		project._reset()
		mark._reset()
	end)

	it("frames the project root's name", function()
		vim.cmd.cd(mkrepo("acme"))
		assert.are.equal("‹ NvSinner ▏acme ›", mark.text())
	end)

	it("fmt stashes the text and hands lualine the segment expression", function()
		assert.are.equal(mark.expr(1), mark.fmt(1)("main"))
		assert.are.equal("main", eval(mark.expr(1)).str)
	end)

	it("renders a resting segment as ONE group around the whole text", function()
		mark.fmt(1)("‹ NvSinner ▏acme ›")
		assert.are.same({ mark.group(1) }, groups_of(mark.seg(1)))
	end)

	-- lualine hands fmt already-escaped text (filename/branch go through its
	-- stl_escape), and %{%…%} re-parses its result — so the stash must be
	-- un-escaped once and the markup escaped again: one "%" on screen.
	it("round-trips a % through lualine's escaping and the re-parse", function()
		mark.fmt(3)("100%%done.lua")
		assert.matches("100%%%%done", mark.seg(3))
		local rendered = eval(mark.expr(3))
		assert.are.equal("100%done.lua", rendered.str)
		assert.are.equal(12, rendered.width)
	end)

	-- progress is the statusline item `%3P`, not text: the stash must hold what
	-- it resolves to, or the bar would print a literal "%3P".
	it("resolves components that are statusline items", function()
		mark.fmt(6)("%3P")
		assert.are.equal(eval("%3P").str, eval(mark.expr(6)).str)
	end)

	it("peaks at the band centre and rests far from it", function()
		local n, c = 30, 15
		local levels = mark._levels(n, t_at(c))
		assert.are.equal(mark.LEVELS, levels[c])
		assert.are.equal(1, levels[1])
		assert.are.equal(1, levels[n])
		for i = c, c + mark.BAND - 1 do
			assert.is_true(levels[i] >= levels[i + 1])
		end
		for i = c, c - mark.BAND + 1, -1 do
			assert.is_true(levels[i] >= levels[i - 1])
		end
	end)

	it("rests everywhere outside a sweep", function()
		local resting = { 1, 1, 1, 1, 1, 1 }
		assert.are.same(resting, mark._levels(6, nil))
		for _, t in ipairs({ -1, mark.sweep_ms(6), mark.sweep_ms(6) + 500 }) do
			assert.are.same(resting, mark._levels(6, t))
		end
	end)

	it("scales the sweep with the bar's width", function()
		assert.is_true(mark.sweep_ms(80) > mark.sweep_ms(20))
	end)

	-- The whole point of segments: ONE band across the bar. With the band
	-- parked inside the SECOND segment, the first must rest and the second
	-- peak — which only holds if the second is positioned after the first.
	it("stitches segments into one line so a single band sweeps the bar", function()
		mark.fmt(1)(string.rep("a", 20))
		mark.fmt(2)(string.rep("b", 20))
		local bar = mark.expr(1) .. " | " .. mark.expr(2)
		eval(bar) -- first pass measures the total width
		mark._sweep_t0 = vim.uv.now() - t_at(30) -- band centre on cell 30
		assert.are.same({ mark.group(1) }, groups_of(mark.seg(1)))
		local second = groups_of(mark.seg(2))
		assert.is_true(#second > 1)
		assert.is_true(vim.tbl_contains(second, mark.group(mark.LEVELS)))
		-- Grouping changes the markup, never the text.
		assert.are.equal(string.rep("a", 20) .. " | " .. string.rep("b", 20), eval(bar).str)
	end)

	it("opens :NvSinnerHelp on a left click only", function()
		local ran = 0
		vim.api.nvim_create_user_command("NvSinnerHelp", function()
			ran = ran + 1
		end, { force = true })
		mark.click(1, "r", "    ")
		assert.are.equal(0, ran)
		mark.click(1, "l", "    ")
		assert.are.equal(1, ran)
	end)

	it("runs the <leader>t mapping on a left click of the terminal icon", function()
		local ran = 0
		vim.keymap.set("n", "<leader>t", function()
			ran = ran + 1
		end)
		mark.terminal_click(1, "r", "    ")
		assert.are.equal(0, ran)
		mark.terminal_click(1, "l", "    ")
		assert.are.equal(1, ran)
		vim.keymap.del("n", "<leader>t")
		assert.has_no.errors(function()
			mark.terminal_click(1, "l", "    ")
		end)
	end)

	it("runs a <cmd> string map on a left click of the agents icon", function()
		local ran = 0
		vim.api.nvim_create_user_command("NvSinnerAgentsProbe", function()
			ran = ran + 1
		end, { force = true })
		vim.keymap.set("n", "<leader>zz", "<cmd>NvSinnerAgentsProbe<cr>")
		mark.map_click("<leader>zz")(1, "l", "    ")
		assert.are.equal(1, ran)
		vim.keymap.del("n", "<leader>zz")
		assert.is_function(mark.agents_click)
	end)

	it("paints subtle carbon roles: italic on base00, peak == base04", function()
		local c = require("core.carbon").colors()
		local function hl(level)
			return vim.api.nvim_get_hl(0, { name = mark.group(level) })
		end
		for level = 1, mark.LEVELS do
			local h = hl(level)
			assert.is_true(h.italic)
			assert.are.equal(tonumber(c.base00:sub(2), 16), h.bg)
		end
		assert.are.equal(tonumber(c.base04:sub(2), 16), hl(mark.LEVELS).fg)
		assert.are_not.equal(hl(1).fg, hl(mark.LEVELS).fg)
	end)

	it("re-applies its groups on ColorScheme", function()
		vim.api.nvim_set_hl(0, mark.group(1), {})
		vim.api.nvim_exec_autocmds("ColorScheme", { pattern = "carbon" })
		assert.is_not_nil(vim.api.nvim_get_hl(0, { name = mark.group(1) }).fg)
	end)

	-- The suite is headless, so this exercises the real bail.
	it("never starts its timer headless", function()
		mark.start()
		assert.is_false(mark._running)
	end)
end)
