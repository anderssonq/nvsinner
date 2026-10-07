-- Tests for herdr-style copy-on-select (lua/core/copy-on-select.lua): a mouse
-- drag, double-click or triple-click copies the selection to the + register on
-- release, the selection stays active, a plain click copies nothing, a
-- keyboard-made selection copies nothing, and the `copy_on_select` setting
-- turns it off.
--
-- Every case runs in an `--embed` child over RPC: nvim_input_mouse only QUEUES
-- the event and a spec never yields to its own main loop (the diffview wheel
-- spec's harness, same reason). The child's + register goes to an in-memory
-- vim.g.clipboard provider, so the suite never touches the OS clipboard.

local function repo_root()
	return vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")
end

describe("core.copy-on-select", function()
	local chan

	local function child(code, ...)
		return vim.rpcrequest(chan, "nvim_exec_lua", code, { ... })
	end

	local function mouse(action, row, col)
		vim.rpcrequest(chan, "nvim_input_mouse", "left", action, "", 0, row, col)
		vim.wait(20)
	end

	-- What landed in the fake clipboard (nil = nothing was copied).
	local function copied()
		vim.wait(500, function()
			return child("return _G.clip ~= nil")
		end, 10)
		return child("return _G.clip or false") or nil
	end

	before_each(function()
		chan = vim.fn.jobstart({
			vim.v.progpath,
			"--embed",
			"--headless",
			"--noplugin",
			"-u",
			repo_root() .. "/tests/minimal_init.lua",
		}, { rpc = true })
		assert.is_true(chan > 0, "could not start the child nvim")
		child(
			[[
			local settings_file = ...
			vim.o.mouse = "a"
			vim.g.clipboard = {
				name = "spec",
				copy = {
					["+"] = function(lines, regtype) _G.clip = { lines = lines, regtype = regtype } end,
					["*"] = function() end,
				},
				paste = { ["+"] = function() return {} end, ["*"] = function() return {} end },
			}
			-- Never the user's real settings file.
			require("core.settings").load({ file = settings_file })
			_G.toasts = {}
			vim.notify = function(msg) table.insert(_G.toasts, msg) end
			require("core.copy-on-select")
			vim.api.nvim_buf_set_lines(0, 0, -1, false, { "hello world foo", "second line here", "third" })
		]],
			vim.fn.tempname() .. "_settings.json"
		)
	end)

	after_each(function()
		vim.fn.jobstop(chan)
	end)

	it("copies a drag selection charwise and keeps it active", function()
		mouse("press", 0, 0)
		mouse("drag", 0, 3)
		mouse("drag", 0, 4)
		mouse("release", 0, 4)
		local clip = copied()
		assert.are.same({ "hello" }, clip.lines)
		assert.are.equal("v", clip.regtype)
		assert.are.equal("v", child("return vim.api.nvim_get_mode().mode"), "the selection must stay on screen")
		assert.are.same({ "📋 Copied 5 chars" }, child("return _G.toasts"))
	end)

	it("copies a multi-line drag", function()
		mouse("press", 0, 6)
		mouse("drag", 1, 2)
		mouse("release", 1, 5)
		assert.are.same({ "world foo", "second" }, copied().lines)
		assert.are.same({ "📋 Copied 2 lines" }, child("return _G.toasts"))
	end)

	it("copies a double-clicked word (released as <2-LeftRelease>)", function()
		mouse("press", 1, 2)
		mouse("release", 1, 2)
		mouse("press", 1, 2)
		mouse("release", 1, 2)
		assert.are.same({ "second" }, copied().lines)
	end)

	it("copies a triple-clicked line linewise", function()
		for _ = 1, 3 do
			mouse("press", 1, 2)
			mouse("release", 1, 2)
		end
		local clip = copied()
		-- A linewise register reaches the provider with a trailing "" (the final
		-- newline) — the same shape `yy` hands it.
		assert.are.same({ "second line here", "" }, clip.lines)
		assert.are.equal("V", clip.regtype)
		assert.are.equal("V", child("return vim.api.nvim_get_mode().mode"))
	end)

	it("copies nothing on a plain click", function()
		mouse("press", 2, 1)
		mouse("release", 2, 1)
		vim.wait(150)
		assert.is_false(child("return _G.clip or false"))
		assert.are.equal("n", child("return vim.api.nvim_get_mode().mode"))
	end)

	it("copies nothing for a keyboard-made selection", function()
		vim.rpcrequest(chan, "nvim_input", "vee")
		vim.wait(150)
		assert.are.equal("v", child("return vim.api.nvim_get_mode().mode"))
		assert.is_false(child("return _G.clip or false"))
	end)

	it("copies nothing while the copy_on_select setting is off", function()
		child([[require("core.settings").set("copy_on_select", false)]])
		mouse("press", 0, 0)
		mouse("drag", 0, 4)
		mouse("release", 0, 4)
		vim.wait(150)
		assert.are.equal("v", child("return vim.api.nvim_get_mode().mode"), "the drag itself still selects")
		assert.is_false(child("return _G.clip or false"))
	end)
end)
