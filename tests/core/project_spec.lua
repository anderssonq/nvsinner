-- Tests for the project identity module (lua/core/project.lua).

local project = require("core.project")

-- Build a throwaway directory tree under a temp root and return its path.
local function mktree(spec)
	local root = vim.fn.tempname()
	for path, kind in pairs(spec) do
		local full = root .. "/" .. path
		if kind == "dir" then
			vim.fn.mkdir(full, "p")
		else
			vim.fn.mkdir(vim.fn.fnamemodify(full, ":h"), "p")
			local fd = io.open(full, "w")
			fd:write("")
			fd:close()
		end
	end
	-- Resolve symlinks: on macOS the temp dir is /var/… -> /private/var/…, and
	-- getcwd() reports the resolved form while tempname() does not.
	return vim.fn.resolve(root)
end

describe("core.project", function()
	local origin = vim.fn.getcwd()

	-- Cleanup lives here, not at the end of each `it`: a failing assertion aborts
	-- the block, and a leaked buffer/cwd then cascades into the next test.
	after_each(function()
		vim.bo.modified = false
		pcall(vim.cmd, "silent! %bwipeout!")
		vim.cmd.cd(origin)
		project._reset()
	end)

	it("names the git root, not the cwd, from a subdirectory", function()
		local root = mktree({ [".git"] = "dir", ["src/deep"] = "dir" })
		vim.cmd.cd(root .. "/src/deep")
		project._reset()
		assert.are.equal(vim.fn.fnamemodify(root, ":t"), project.name())
		assert.are.equal(root, project.root())
	end)

	-- The marker order in M.MARKERS is priority, not proximity: vim.fs.root
	-- returns on the first marker that matches anywhere in the upward walk. So a
	-- monorepo package with its own package.json must still report the repo name.
	it("prefers the repo root over an inner manifest in a monorepo", function()
		local root = mktree({ [".git"] = "dir", ["packages/foo/package.json"] = "file" })
		vim.cmd.cd(root .. "/packages/foo")
		project._reset()
		assert.are.equal(vim.fn.fnamemodify(root, ":t"), project.name())
	end)

	it("falls back to a manifest when there is no repo", function()
		local root = mktree({ ["app/package.json"] = "file" })
		vim.cmd.cd(root .. "/app")
		project._reset()
		assert.are.equal("app", project.name())
	end)

	it("falls back to the cwd when no marker exists at all", function()
		local root = mktree({ ["plain"] = "dir" })
		vim.cmd.cd(root .. "/plain")
		project._reset()
		assert.are.equal("plain", project.name())
	end)

	it("re-resolves the root after the cwd changes", function()
		local a = mktree({ [".git"] = "dir" })
		local b = mktree({ [".git"] = "dir" })
		vim.cmd.cd(a)
		project._reset()
		assert.are.equal(vim.fn.fnamemodify(a, ":t"), project.name())
		-- DirChanged fires on :cd and busts the cache — no manual _reset here,
		-- that is the whole point of the autocmd.
		vim.cmd.cd(b)
		assert.are.equal(vim.fn.fnamemodify(b, ":t"), project.name())
	end)

	it("puts the project first and appends the file and modified flag", function()
		local root = mktree({ [".git"] = "dir", ["src/main.lua"] = "file" })
		vim.cmd.cd(root)
		project._reset()
		local name = vim.fn.fnamemodify(root, ":t")

		vim.cmd.edit(root .. "/src/main.lua")
		assert.are.equal(name .. " · src/main.lua", project.title())

		vim.api.nvim_buf_set_lines(0, 0, -1, false, { "dirty" })
		assert.are.equal(name .. " · src/main.lua [+]", project.title())
	end)

	it("shows the name alone for non-file buffers", function()
		local root = mktree({ [".git"] = "dir" })
		vim.cmd.cd(root)
		project._reset()
		vim.cmd("enew")
		vim.bo.buftype = "nofile"
		assert.are.equal(vim.fn.fnamemodify(root, ":t"), project.title())
	end)

	-- M.EXPR is the plain %{…} form, whose result is inserted LITERALLY (only
	-- the %{%…%} form re-parses its result as statusline items). So title()
	-- must emit a raw "%" — escaping it would render a doubled "%%" in the tab.
	it("passes % through unescaped, because %{…} does not re-parse its result", function()
		local root = mktree({ [".git"] = "dir", ["100%done/x.lua"] = "file" })
		vim.cmd.cd(root)
		project._reset()
		-- fnameescape: :edit expands a bare "%" to the current file name.
		vim.cmd.edit(vim.fn.fnameescape(root .. "/100%done/x.lua"))
		assert.matches("100%%done/x%.lua$", project.title())
		-- What actually reaches the terminal: one %, not two.
		assert.matches("100%%done/x%.lua$", vim.api.nvim_eval_statusline(project.EXPR, {}).str)
	end)

	it("renders through a real titlestring evaluation", function()
		local root = mktree({ [".git"] = "dir" })
		vim.cmd.cd(root)
		project._reset()
		local rendered = vim.api.nvim_eval_statusline(project.EXPR, {}).str
		assert.are.equal(vim.fn.fnamemodify(root, ":t"), rendered)
	end)
end)
