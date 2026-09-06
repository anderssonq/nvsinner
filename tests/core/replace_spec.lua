-- Tests for the word replace modal (lua/core/replace.lua).

local function mktree(spec)
	local root = vim.fn.tempname()
	for path, contents in pairs(spec) do
		local full = root .. "/" .. path
		vim.fn.mkdir(vim.fn.fnamemodify(full, ":h"), "p")
		vim.fn.writefile(contents, full)
	end
	-- Resolve symlinks: on macOS the temp dir is /var/… -> /private/var/…, and
	-- getcwd() reports the resolved form while tempname() does not.
	return vim.fn.resolve(root)
end

describe("core.replace", function()
	local replace = require("core.replace")
	local project = require("core.project")

	after_each(function()
		replace._reset()
		vim.bo.modified = false
		pcall(vim.cmd, "silent! %bwipeout!")
	end)

	it("defines the :NvSinnerReplace command and the <leader>rw maps", function()
		assert.is_not_nil(vim.api.nvim_get_commands({})["NvSinnerReplace"])
		for _, mode in ipairs({ "n", "x" }) do
			local m = vim.fn.maparg("<leader>rw", mode, false, true)
			assert.is_true(type(m) == "table" and next(m) ~= nil, "<leader>rw must be mapped in " .. mode)
		end
	end)

	it("gives every action a unique shortcut that misses the modal's own maps", function()
		local seen, reserved = {}, { j = true, k = true, q = true, l = true }
		for _, it_ in ipairs(replace._items()) do
			assert.is_string(it_.sc)
			assert.are.equal(1, #it_.sc, "shortcuts are single letters")
			assert.is_nil(seen[it_.sc], "shortcut " .. it_.sc .. " is used twice")
			assert.is_nil(reserved[it_.sc], "shortcut " .. it_.sc .. " collides with a navigation key")
			seen[it_.sc] = true
		end
	end)

	-- The escaping is the correctness core: a pattern that leaks regex magic
	-- rewrites lines the user never targeted.
	it("builds \\V patterns, with word boundaries only for keyword tokens", function()
		assert.are.equal("\\V\\<foo\\>", replace.pattern("foo"))
		assert.are.equal("\\V\\<foo_bar2\\>", replace.pattern("foo_bar2"))
		-- Punctuation can't sit next to \< \>, so those targets stay unanchored.
		assert.are.equal("\\Va.b", replace.pattern("a.b"))
		assert.are.equal("\\V$5", replace.pattern("$5"))
		assert.are.equal("\\Vpath\\/to", replace.pattern("path/to"))
		assert.are.equal("\\Va\\\\b", replace.pattern("a\\b"))
	end)

	it("escapes \\ / & ~ in the replacement", function()
		assert.are.equal("plain", replace.replacement("plain"))
		assert.are.equal("X\\&Y", replace.replacement("X&Y"))
		assert.are.equal("\\~10", replace.replacement("~10"))
		assert.are.equal("a\\/b", replace.replacement("a/b"))
	end)

	it("parses ripgrep match lines, including paths containing a colon", function()
		local m = replace._parse_match("/tmp/x/foo.lua:12:5:local foo = 1")
		assert.are.same({ filename = "/tmp/x/foo.lua", lnum = 12, col = 5, text = "local foo = 1" }, m)

		-- The filename capture is greedy, so it backtracks past the colon.
		local odd = replace._parse_match("/tmp/a:b/foo.lua:3:1:foo")
		assert.are.equal("/tmp/a:b/foo.lua", odd.filename)
		assert.are.equal(3, odd.lnum)

		assert.is_nil(replace._parse_match("not a match line"))
	end)

	it("summarises matches per file", function()
		local text, files = replace._summary({
			{ filename = "a.lua" },
			{ filename = "a.lua" },
			{ filename = "b.lua" },
		})
		assert.are.equal("3 matches in 2 files", text)
		assert.are.equal(2, files)

		local one = replace._summary({ { filename = "a.lua" } })
		assert.are.equal("1 match in 1 file", one)
	end)

	it("renders one titled row per action with the target in the border title", function()
		local buf = vim.api.nvim_get_current_buf()
		replace.open({ word = "widget", buf = buf, win = vim.api.nvim_get_current_win() })

		local mbuf = vim.api.nvim_get_current_buf()
		local body = table.concat(vim.api.nvim_buf_get_lines(mbuf, 0, -1, false), "\n")
		for _, it_ in ipairs(replace._items()) do
			assert.is_truthy(body:find(it_.title, 1, true), "modal must list " .. it_.title)
		end

		local title = vim.api.nvim_win_get_config(vim.api.nvim_get_current_win()).title
		assert.is_truthy(vim.inspect(title):find("widget", 1, true), "the border title must name the target")
		replace.close()
	end)

	it("replaces every exact match in the buffer, leaving longer words alone", function()
		vim.cmd("enew!")
		local buf = vim.api.nvim_get_current_buf()
		local win = vim.api.nvim_get_current_win()
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "foo foobar", "x_foo foo" })

		local orig_input = vim.ui.input
		vim.ui.input = function(_, cb)
			cb("BAR")
		end

		replace.open({ word = "foo", buf = buf, win = win })
		local key = replace.run() -- selection 1 = Replace in file

		vim.ui.input = orig_input

		assert.are.equal("file", key)
		assert.are.same({ "BAR foobar", "x_foo BAR" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
	end)

	it("warns instead of editing when the word is not in the buffer", function()
		vim.cmd("enew!")
		local buf = vim.api.nvim_get_current_buf()
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "nothing here" })

		local orig_input, captured = vim.ui.input, {}
		vim.ui.input = function(_, cb)
			cb("BAR")
		end
		local orig_notify = vim.notify
		vim.notify = function(msg, level)
			captured[#captured + 1] = { msg = msg, level = level }
		end

		replace.open({ word = "absent", buf = buf, win = vim.api.nvim_get_current_win() })
		replace.run()

		vim.notify = orig_notify -- restore BEFORE asserting so a failure can't leak it
		vim.ui.input = orig_input

		assert.are.equal(1, #captured)
		assert.are.equal(vim.log.levels.WARN, captured[1].level)
		assert.matches("No matches", captured[1].msg)
		assert.are.same({ "nothing here" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
	end)

	it("search() finds word-exact matches under a root and skips substrings", function()
		local root = mktree({
			["src/a.lua"] = { "local target = 1", "targetish = 2" },
			["src/b.lua"] = { "print(target)" },
			["src/c.lua"] = { "unrelated" },
		})

		local got, err
		replace.search("target", root, function(items, e)
			got, err = items, e
		end)
		assert.is_true(
			vim.wait(5000, function()
				return got ~= nil or err ~= nil
			end, 50),
			"search must call back"
		)

		assert.is_nil(err)
		local summary, files = replace._summary(got)
		assert.are.equal(2, files, "targetish must not count: " .. summary)
		assert.are.equal(2, #got)

		vim.fn.delete(root, "rf")
	end)

	it("replaces across the project and writes every file in one cfdo step", function()
		local root = mktree({
			["a.lua"] = { "local target = 1", "targetish stays" },
			["nested/b.lua"] = { "print(target)" },
			["c.lua"] = { "untouched" },
		})
		local origin = vim.fn.getcwd()
		vim.cmd.cd(root)
		project._reset()

		local orig_input, orig_select = vim.ui.input, vim.ui.select
		local prompt
		vim.ui.input = function(_, cb)
			cb("renamed")
		end
		vim.ui.select = function(_, opts, cb)
			prompt = opts.prompt
			cb("Replace")
		end

		vim.cmd("enew!")
		replace.open({
			word = "target",
			buf = vim.api.nvim_get_current_buf(),
			win = vim.api.nvim_get_current_win(),
		})
		replace.move(3) -- selection 4 = Replace in project
		local key = replace.run()

		local done = vim.wait(10000, function()
			return vim.fn.readfile(root .. "/nested/b.lua")[1] == "print(renamed)"
		end, 100)

		vim.ui.input, vim.ui.select = orig_input, orig_select
		local a = vim.fn.readfile(root .. "/a.lua")
		local c = vim.fn.readfile(root .. "/c.lua")
		vim.cmd.cd(origin)
		project._reset()
		vim.fn.delete(root, "rf")

		assert.are.equal("project", key)
		assert.is_true(done, "the nested file must be rewritten on disk")
		assert.are.same({ "local renamed = 1", "targetish stays" }, a)
		assert.are.same({ "untouched" }, c)
		assert.is_truthy(
			prompt and prompt:find("2 matches in 2 files", 1, true),
			"the confirm must name the blast radius"
		)
	end)

	it("cancelling the project confirmation leaves every file untouched", function()
		local root = mktree({ ["a.lua"] = { "local target = 1" } })
		local origin = vim.fn.getcwd()
		vim.cmd.cd(root)
		project._reset()

		local orig_input, orig_select = vim.ui.input, vim.ui.select
		local asked = false
		vim.ui.input = function(_, cb)
			cb("renamed")
		end
		vim.ui.select = function(_, _, cb)
			asked = true
			cb(nil) -- user pressed <Esc>
		end

		vim.cmd("enew!")
		replace.open({
			word = "target",
			buf = vim.api.nvim_get_current_buf(),
			win = vim.api.nvim_get_current_win(),
		})
		replace.move(3)
		replace.run()

		assert.is_true(
			vim.wait(5000, function()
				return asked
			end, 50),
			"the confirmation must be offered"
		)

		vim.ui.input, vim.ui.select = orig_input, orig_select
		local a = vim.fn.readfile(root .. "/a.lua")
		vim.cmd.cd(origin)
		project._reset()
		vim.fn.delete(root, "rf")

		assert.are.same({ "local target = 1" }, a)
	end)
end)
