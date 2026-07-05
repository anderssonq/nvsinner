-- Tests for the native inline git blame (lua/core/git-blame.lua): the
-- NvGitBlame comment-tone group, porcelain parsing, a real committed file
-- getting an eol annotation for the cursor line, uncommitted lines staying
-- unannotated, and untracked/non-repo buffers being skipped quietly.

local blame = require("core.git-blame")

describe("core.git-blame", function()
	local repo, path, buf

	-- A real one-commit repo: blame output comes from git itself, not a mock.
	local function make_repo(lines)
		repo = vim.fn.tempname() .. "_blame_repo"
		vim.fn.mkdir(repo, "p")
		path = repo .. "/file.txt"
		vim.fn.writefile(lines, path)
		vim.fn.system({ "git", "-C", repo, "init", "-q" })
		vim.fn.system({ "git", "-C", repo, "add", "file.txt" })
		vim.fn.system({
			"git",
			"-C",
			repo,
			"-c",
			"user.name=Spec Author",
			"-c",
			"user.email=spec@test",
			"commit",
			"-q",
			"-m",
			"spec commit",
		})
		vim.cmd("edit " .. vim.fn.fnameescape(path))
		buf = vim.api.nvim_get_current_buf()
	end

	local function marks()
		return vim.api.nvim_buf_get_extmarks(buf, blame._ns, 0, -1, { details = true })
	end

	before_each(function()
		blame._reset()
	end)

	it("defines the NvGitBlame comment-tone highlight", function()
		local hl = vim.api.nvim_get_hl(0, { name = "NvGitBlame" })
		assert.is_not_nil(hl.fg, "NvGitBlame needs a muted fg")
		assert.is_true(hl.italic == true, "blame reads as an aside — italic like comments")
		local c = require("core.carbon").colors()
		assert.are.equal(tonumber(c.base03:sub(2), 16), hl.fg, "must use the carbon comment role")
	end)

	it("_format() renders summary • date • author • sha and skips uncommitted", function()
		local porcelain = "abcdef1234567890abcdef1234567890abcdef12 1 1 1\n"
			.. "author Spec Author\n"
			.. "author-mail <spec@test>\n"
			.. "author-time 1700000000\n"
			.. "author-tz +0000\n"
			.. "summary spec commit\n"
			.. "filename file.txt\n"
			.. "\tone\n"
		local text = blame._format(porcelain)
		assert.is_not_nil(text)
		assert.is_truthy(text:find("spec commit", 1, true))
		assert.is_truthy(text:find("Spec Author", 1, true))
		assert.is_truthy(text:find("<abcdef1>", 1, true))

		local uncommitted = porcelain:gsub("^%x+", string.rep("0", 40))
		assert.is_nil(blame._format(uncommitted), "all-zero sha means uncommitted — no annotation")
	end)

	it("annotates the cursor line of a committed file", function()
		make_repo({ "one", "two" })
		vim.api.nvim_win_set_cursor(0, { 2, 0 })
		blame.refresh(buf)

		local got = vim.wait(4000, function()
			return #marks() > 0
		end, 100)
		assert.is_true(got, "the cursor line should get a blame extmark")

		local m = marks()[1]
		assert.are.equal(1, m[2], "annotation must sit on the cursor line (row 1)")
		local chunk = m[4].virt_text[1]
		assert.is_truthy(chunk[1]:find("spec commit", 1, true))
		assert.are.equal("NvGitBlame", chunk[2])

		vim.cmd("bwipeout!")
		vim.fn.delete(repo, "rf")
	end)

	it("leaves uncommitted lines unannotated (buffer contents are blamed)", function()
		make_repo({ "one" })
		vim.api.nvim_buf_set_lines(buf, 1, 1, false, { "new unsaved line" })
		vim.api.nvim_win_set_cursor(0, { 2, 0 })
		blame.refresh(buf)

		-- The async blame must come back; give it the same window as above and
		-- assert nothing was painted for the not-committed line.
		vim.wait(1500, function()
			return false
		end, 100)
		assert.are.equal(0, #marks(), "an uncommitted line must not get a fake annotation")

		vim.cmd("bwipeout!")
		vim.fn.delete(repo, "rf")
	end)

	it("skips non-file buffers and files outside a repo", function()
		-- Outside any repo: refresh must mark the buffer dead, not error.
		local loose = vim.fn.tempname() .. "_loose.txt"
		vim.fn.writefile({ "alone" }, loose)
		vim.cmd("edit " .. vim.fn.fnameescape(loose))
		buf = vim.api.nvim_get_current_buf()
		blame.refresh(buf)
		vim.wait(1500, function()
			return false
		end, 100)
		assert.are.equal(0, #marks())
		vim.cmd("bwipeout!")
		os.remove(loose)

		-- Special buftype: refresh is a no-op.
		vim.cmd("terminal")
		buf = vim.api.nvim_get_current_buf()
		blame.refresh(buf)
		assert.are.equal(0, #marks())
		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	it("registers :NvSinnerBlameToggle and toggling clears annotations", function()
		assert.is_not_nil(vim.api.nvim_get_commands({})["NvSinnerBlameToggle"])
		make_repo({ "one" })
		blame.refresh(buf)
		vim.wait(4000, function()
			return #marks() > 0
		end, 100)

		blame.toggle() -- off: wipes every annotation
		assert.is_false(blame.enabled())
		assert.are.equal(0, #marks())
		blame.toggle() -- back on for the other specs
		assert.is_true(blame.enabled())

		vim.cmd("bwipeout!")
		vim.fn.delete(repo, "rf")
	end)
end)
