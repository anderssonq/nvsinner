-- Tests for the native sessions (lua/core/sessions.lua): sessionoptions,
-- save/load roundtrip for the cwd session, last-session pick by mtime, the
-- autosave gate (only after a real file opened, paused by stop()), and the
-- commands + <leader>S maps existing.

require("core.options") -- leaders must be set before the module maps <leader>S*
local sessions = require("core.sessions")

describe("core.sessions", function()
	local dir

	before_each(function()
		dir = vim.fn.tempname() .. "_sessions/"
		sessions._reset({ dir = dir })
	end)

	it("sets the persistence-parity sessionoptions", function()
		assert.are.equal("buffers,curdir,tabpages,winsize", vim.o.sessionoptions)
	end)

	it("save()/load() roundtrips the cwd session", function()
		local file = vim.fn.tempname() .. "_roundtrip.txt"
		vim.fn.writefile({ "hello" }, file)
		vim.cmd("edit " .. vim.fn.fnameescape(file))
		sessions.save()

		vim.cmd("bwipeout!")
		assert.are_not.equal(file, vim.api.nvim_buf_get_name(0))

		assert.is_true(sessions.load())
		-- resolve() both sides: macOS tempdirs live under the /var → /private/var
		-- symlink and mksession may record either spelling.
		assert.are.equal(vim.fn.resolve(file), vim.fn.resolve(vim.api.nvim_buf_get_name(0)))

		vim.cmd("bwipeout!")
		os.remove(file)
	end)

	it("load() returns false when no session exists", function()
		assert.is_false(sessions.load())
		assert.is_false(sessions.load({ last = true }))
	end)

	it("last() picks the newest session file by mtime", function()
		vim.fn.mkdir(dir, "p")
		vim.fn.writefile({ "old" }, dir .. "old.vim")
		vim.fn.system({ "sh", "-c", "sleep 1" }) -- distinct mtimes (second granularity)
		vim.fn.writefile({ "new" }, dir .. "new.vim")
		assert.are.equal(dir .. "new.vim", sessions.last())
	end)

	it("gates the autosave: armed by a real file, paused by stop()", function()
		local armed, paused = sessions._started()
		assert.is_false(armed, "fresh state: nothing to autosave yet")
		assert.is_false(paused)

		local file = vim.fn.tempname() .. "_gate.txt"
		vim.fn.writefile({ "x" }, file)
		vim.cmd("edit " .. vim.fn.fnameescape(file))
		armed = sessions._started()
		assert.is_true(armed, "opening a real file arms the autosave")

		sessions.stop()
		local _, stopped = sessions._started()
		assert.is_true(stopped, "stop() pauses the exit autosave")

		vim.cmd("bwipeout!")
		os.remove(file)
	end)

	it("registers the :NvSinnerSession* commands and <leader>S maps", function()
		local cmds = vim.api.nvim_get_commands({})
		assert.is_not_nil(cmds["NvSinnerSessionLoad"])
		assert.is_not_nil(cmds["NvSinnerSessionLast"])
		assert.is_not_nil(cmds["NvSinnerSessionStop"])

		assert.are_not.equal("", vim.fn.maparg("<leader>Sc", "n"), "<leader>Sc must exist")
		assert.are_not.equal("", vim.fn.maparg("<leader>Sl", "n"), "<leader>Sl must exist")
		assert.are_not.equal("", vim.fn.maparg("<leader>SQ", "n"), "<leader>SQ must exist")
	end)
end)
