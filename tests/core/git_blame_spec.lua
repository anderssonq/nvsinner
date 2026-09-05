-- Tests for the native inline git blame (lua/core/git-blame.lua): the
-- NvGitBlame comment-tone group, porcelain parsing, a real committed file
-- getting an eol annotation for the cursor line, uncommitted lines staying
-- unannotated, and untracked/non-repo buffers being skipped quietly. Plus the
-- merged-from ref: the subject parser, the rendered second chunk, a real
-- two-branch repo proving a branch commit is attributed and a mainline one is
-- not, and the in-flight case — a commit on a branch that has NOT been merged
-- yet, which no merge-descendant search can ever find.

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

	it("_parse_ref() reads the merge subjects that actually occur", function()
		-- Shapes collected from the merge history of every repo on this machine.
		local cases = {
			{ "Merge pull request #22 from anderssonq/release/v3.1.0", "release/v3.1.0", "22" },
			-- A branch name carries slashes: only the owner may be cut.
			{ "Merge pull request #496 from github/digitarald/exotic-raven", "digitarald/exotic-raven", "496" },
			{ "Merge branch 'add-lws' of https://github.com/x/y into add-lws", "add-lws", nil },
			{ "Merge branch 'main' into add-agent-skills", "main", nil },
			{ "Merge remote-tracking branch 'origin/hotfix/x'", "hotfix/x", nil },
			{ "Merge branch 'nyoom-engineering:main' into main", "main", nil },
		}
		for _, c in ipairs(cases) do
			local branch, pr = blame._parse_ref(c[1])
			assert.are.equal(c[2], branch, c[1])
			assert.are.equal(c[3], pr, c[1])
		end

		local branch, pr = blame._parse_ref("a plain commit subject")
		assert.is_nil(branch)
		assert.is_nil(pr)
		assert.is_nil((blame._parse_ref(nil)))
	end)

	it("_parse_branches() separates local from remote, and finds the current one", function()
		local out = blame._parse_branches(
			"*\trefs/heads/feature/wip\n \trefs/heads/main\n \trefs/remotes/origin/main\n \trefs/remotes/origin/HEAD\n"
		)
		assert.are.equal("feature/wip", out.current, "the * marks the branch we are standing on")
		assert.are.same({ "feature/wip", "main" }, out.locals)
		-- origin/main must reduce to main so the trunk check sees it; the
		-- symbolic origin/HEAD is not a branch and must be dropped.
		assert.are.same({ "feature/wip", "main", "main" }, out.names)

		-- A local branch really called feature/main must NOT reduce to main.
		local tricky = blame._parse_branches(" \trefs/heads/feature/main\n")
		assert.are.same({ "feature/main" }, tricky.names)
		assert.is_nil(blame._parse_branches("").current)
	end)

	it("_on_trunk() decides 'has it landed' by name", function()
		assert.is_true(blame._on_trunk({ "feature/wip", "main" }))
		assert.is_true(blame._on_trunk({ "master" }))
		assert.is_false(blame._on_trunk({ "feature/wip" }))
		assert.is_false(blame._on_trunk({}))
		assert.is_false(blame._on_trunk(nil))
	end)

	it("_ref_text() renders branch and PR, and nothing when there is neither", function()
		assert.is_truthy(blame._ref_text({ branch = "feature/x", pr = "7" }):find("feature/x", 1, true))
		assert.is_truthy(blame._ref_text({ branch = "feature/x", pr = "7" }):find("#7", 1, true))
		assert.is_truthy(blame._ref_text({ pr = "7" }):find("#7", 1, true))
		assert.is_nil(blame._ref_text(nil))
		assert.is_nil(blame._ref_text({}), "a ref with neither field must not render an empty chunk")
	end)

	it("names the merged-from branch, and only for commits that came through it", function()
		-- A real two-branch history: one commit on main, one on a branch, joined
		-- by a --no-ff merge. The branch commit must be attributed; the mainline
		-- commit must NOT be, even though it is an ancestor of the same merge.
		repo = vim.fn.tempname() .. "_merge_repo"
		vim.fn.mkdir(repo, "p")
		path = repo .. "/file.txt"
		local function git(...)
			return vim.fn.system({ "git", "-C", repo, "-c", "user.name=Spec Author", "-c", "user.email=spec@test", ... })
		end
		vim.fn.system({ "git", "-C", repo, "init", "-q", "-b", "main" })
		vim.fn.writefile({ "on main" }, path)
		git("add", "file.txt")
		git("commit", "-q", "-m", "base commit")
		git("checkout", "-q", "-b", "feature/x")
		vim.fn.writefile({ "on main", "from the branch" }, path)
		git("commit", "-q", "-am", "branch commit")
		git("checkout", "-q", "main")
		git("merge", "--no-ff", "-q", "-m", "Merge pull request #7 from someone/feature/x", "feature/x")

		vim.cmd("edit " .. vim.fn.fnameescape(path))
		buf = vim.api.nvim_get_current_buf()

		local function chunks_at(line)
			vim.api.nvim_win_set_cursor(0, { line, 0 })
			blame._reset()
			blame.clear(buf)
			blame.refresh(buf)
			vim.wait(6000, function()
				return #marks() > 0
			end, 100)
			-- The ref is a second round-trip: give it its own settle window.
			vim.wait(4000, function()
				local m = marks()[1]
				return m and #m[4].virt_text > 1
			end, 100)
			local m = marks()[1]
			return m and m[4].virt_text or {}
		end

		local branch_line = chunks_at(2)
		assert.are.equal(2, #branch_line, "a merged-in commit gets the ref chunk")
		assert.are.equal("NvGitBlame", branch_line[1][2], "chunk 1 stays the blame contract")
		assert.are.equal("NvGitBlameRef", branch_line[2][2])
		assert.is_truthy(branch_line[2][1]:find("feature/x", 1, true), branch_line[2][1])
		assert.is_truthy(branch_line[2][1]:find("#7", 1, true), branch_line[2][1])

		local main_line = chunks_at(1)
		assert.are.equal(1, #main_line, "a commit already on the mainline must not borrow the branch")

		vim.cmd("bwipeout!")
		vim.fn.delete(repo, "rf")
	end)

	it("names the branch of work that is not merged yet", function()
		-- The everyday case, and the one a merge-descendant search structurally
		-- cannot answer: you are ON the branch, nothing has been merged, so no
		-- merge commit exists to read a subject from. Before this was handled
		-- the line you had just written reported no branch at all.
		repo = vim.fn.tempname() .. "_inflight_repo"
		vim.fn.mkdir(repo, "p")
		path = repo .. "/file.txt"
		local function git(...)
			return vim.fn.system({ "git", "-C", repo, "-c", "user.name=Spec Author", "-c", "user.email=spec@test", ... })
		end
		vim.fn.system({ "git", "-C", repo, "init", "-q", "-b", "main" })
		vim.fn.writefile({ "on main" }, path)
		git("add", "file.txt")
		git("commit", "-q", "-m", "base commit")
		git("checkout", "-q", "-b", "feature/wip")
		vim.fn.writefile({ "on main", "not merged anywhere" }, path)
		git("commit", "-q", "-am", "wip commit")

		vim.cmd("edit " .. vim.fn.fnameescape(path))
		buf = vim.api.nvim_get_current_buf()

		local function chunks_at(line)
			vim.api.nvim_win_set_cursor(0, { line, 0 })
			blame._reset()
			blame.clear(buf)
			blame.refresh(buf)
			vim.wait(6000, function()
				return #marks() > 0
			end, 100)
			vim.wait(4000, function()
				local m = marks()[1]
				return m and #m[4].virt_text > 1
			end, 100)
			local m = marks()[1]
			return m and m[4].virt_text or {}
		end

		local wip = chunks_at(2)
		assert.are.equal(2, #wip, "an unmerged commit must still name its branch")
		assert.is_truthy(wip[2][1]:find("feature/wip", 1, true), wip[2][1])
		assert.is_truthy(
			wip[2][1]:find(blame.REF_ICON_LOCAL, 1, true),
			"in-flight work carries its own glyph, so it does not read as 'merged from'"
		)

		-- The trunk commit is landed, so it stays unattributed — the guard that
		-- keeps this from labelling every line in a single-branch repo.
		assert.are.equal(1, #chunks_at(1), "a commit on the trunk must not be labelled")

		vim.cmd("bwipeout!")
		vim.fn.delete(repo, "rf")
	end)
end)
