-- Guards the agent-facing docs in .claude/ against the drift class that FA-27
-- documents.
--
-- History: 12 of the 13 skills carried `Facts verified: 2026-07-02`. The carbon
-- migration landed 2026-07-03. Nothing re-checked them, so for months the docs
-- quoted dead kanagawa hexes as current values, described tombstoned plugins as
-- the live implementation, and told six of the eight owner agents to validate
-- with `nvim --headless "+Lazy! sync" +qa` — the one command the restore-not-sync
-- non-negotiable forbids, because it rewrites lazy-lock.json. An agent obeying
-- its own contract would have floated the plugin set off the tested commits.
--
-- Re-verifying by hand is what already failed. These are the mechanical parts of
-- that failure, so they are a test instead.
--
-- `nvsinner-failure-archaeology` is EXEMPT from the content checks by design: it
-- is the incident registry, so it must be able to quote the dead hex and the
-- forbidden command that caused an incident. Everything else may not.

local REGISTRY = "nvsinner-failure-archaeology"

local function claude_md_files()
	local out = {}
	for _, f in ipairs(vim.fn.glob(".claude/**/*.md", false, true)) do
		out[#out + 1] = f
	end
	table.sort(out)
	return out
end

local function read(path)
	return table.concat(vim.fn.readfile(path), "\n")
end

describe(".claude docs", function()
	local files = claude_md_files()

	it("finds the agent and skill docs", function()
		assert.is_true(#files >= 15, "expected the .claude doc set, found " .. #files)
	end)

	it("quotes no hex literal outside the incident registry", function()
		-- Every color is a role in lua/core/carbon.lua, which now carries 10
		-- themes x 4 accent packs: a literal in prose is wrong for at least nine
		-- of them, and cannot be checked by palette-audit.sh (that one only scans
		-- lua/). Name the role and the file instead.
		local offenders = {}
		for _, file in ipairs(files) do
			if not file:find(REGISTRY, 1, true) then
				for nr, line in ipairs(vim.fn.readfile(file)) do
					local hex = line:match("#%x%x%x%x%x%x")
					if hex then
						offenders[#offenders + 1] = ("%s:%d (%s)"):format(file, nr, hex)
					end
				end
			end
		end
		assert.are.equal(
			0,
			#offenders,
			"hex literals in agent docs rot silently — use a carbon role: " .. table.concat(offenders, ", ")
		)
	end)

	it("never prescribes `Lazy! sync` as a validation step", function()
		-- Prose may forbid it ("Never `+Lazy! sync`"); a runnable command form
		-- may not appear at all outside the registry.
		local offenders = {}
		for _, file in ipairs(files) do
			if not file:find(REGISTRY, 1, true) then
				for nr, line in ipairs(vim.fn.readfile(file)) do
					if line:find("nvim%s+%-%-headless.*Lazy!?%s+sync") then
						offenders[#offenders + 1] = ("%s:%d"):format(file, nr)
					end
				end
			end
		end
		assert.are.equal(
			0,
			#offenders,
			"a validation step must never rewrite lazy-lock.json: " .. table.concat(offenders, ", ")
		)
	end)

	it("runs no command against a path that has been deleted", function()
		-- Only paths inside fenced code blocks are checked, because those are
		-- RUNNABLE: a dead path there is unambiguously broken. The old playbook
		-- shipped `grep -n "markdown" ... after/ftplugin/markdown.lua` in a bash
		-- fence for months after that file was deleted, and the command errored
		-- out for anyone who followed it.
		--
		-- Prose is deliberately NOT checked: a doc must stay free to say "there
		-- is no after/ftplugin/markdown.lua any more", and guessing at negation
		-- in prose produces false failures, which is how a guard gets deleted.
		local offenders = {}
		for _, file in ipairs(files) do
			if not file:find(REGISTRY, 1, true) then
				local fenced = false
				for nr, line in ipairs(vim.fn.readfile(file)) do
					if line:find("^```") then
						fenced = not fenced
					elseif fenced then
						for path in line:gmatch("([%w%._%-/]+%.lua)") do
							if
								(
									path:find("^lua/")
									or path:find("^after/")
									or path:find("^colors/")
									or path:find("^tests/")
								)
								and not path:find("<")
								-- Convention: an illustrative path in a worked example is
								-- named `example-*` so it reads as a placeholder and this
								-- guard can skip it.
								and not path:find("example[%-_]")
								and vim.fn.filereadable(path) == 0
							then
								offenders[#offenders + 1] = ("%s:%d -> %s"):format(file, nr, path)
							end
						end
					end
				end
			end
		end
		assert.are.equal(
			0,
			#offenders,
			"a documented command targets a file that does not exist: " .. table.concat(offenders, ", ")
		)
	end)

	it("references no diagnostic script that has been moved or unshipped", function()
		local offenders = {}
		for _, file in ipairs(files) do
			for nr, line in ipairs(vim.fn.readfile(file)) do
				for path in line:gmatch("(%.claude/skills/[%w%-/]+%.sh)") do
					if vim.fn.executable(path) == 0 then
						offenders[#offenders + 1] = ("%s:%d -> %s"):format(file, nr, path)
					end
				end
			end
		end
		assert.are.equal(
			0,
			#offenders,
			"docs point at a script that is missing or not executable: " .. table.concat(offenders, ", ")
		)
	end)
end)

describe(".claude skills", function()
	local skills = vim.fn.glob(".claude/skills/*/SKILL.md", false, true)

	it("each carries a Facts verified date", function()
		assert.is_true(#skills > 0, "no skills found")
		local missing = {}
		for _, file in ipairs(skills) do
			if not read(file):find("Facts verified") then
				missing[#missing + 1] = file
			end
		end
		assert.are.equal(
			0,
			#missing,
			"a skill without a verification date cannot be trusted: " .. table.concat(missing, ", ")
		)
	end)

	it("each declares a frontmatter name matching its directory", function()
		local wrong = {}
		for _, file in ipairs(skills) do
			local dir = file:match("%.claude/skills/([^/]+)/")
			local name = read(file):match("^%-%-%-\nname:%s*([%w%-_]+)")
			if name ~= dir then
				wrong[#wrong + 1] = ("%s (name=%s)"):format(file, tostring(name))
			end
		end
		assert.are.equal(
			0,
			#wrong,
			"skill name must match its directory or it will not resolve: " .. table.concat(wrong, ", ")
		)
	end)
end)

describe(".claude agents", function()
	local agents = vim.fn.glob(".claude/agents/*.md", false, true)

	it("each declares a frontmatter name matching its filename", function()
		assert.is_true(#agents >= 8, "expected the owner-agent set, found " .. #agents)
		local wrong = {}
		for _, file in ipairs(agents) do
			local base = vim.fn.fnamemodify(file, ":t:r")
			local name = read(file):match("^%-%-%-\nname:%s*([%w%-_]+)")
			if name ~= base then
				wrong[#wrong + 1] = ("%s (name=%s)"):format(file, tostring(name))
			end
		end
		assert.are.equal(0, #wrong, "agent name must match its filename: " .. table.concat(wrong, ", "))
	end)

	it("describes no tombstoned plugin as the live implementation", function()
		-- The `description:` is the routing text. While it named git-blame.nvim
		-- as the inline-blame owner, anything touching blame routed to a plugin
		-- that has been disabled since Wave 1.
		local dead = {
			["git%-blame%.nvim"] = "lua/core/git-blame.lua",
			["todo%-comments%.nvim"] = "lua/core/todo.lua",
			["persistence%.nvim"] = "lua/core/sessions.lua",
			["vim%-illuminate"] = "lua/core/illuminate.lua",
			["incline"] = "lua/core/filebadge.lua",
			["nvim%-window%-picker"] = "lua/core/window-picker.lua",
		}
		local offenders = {}
		for _, file in ipairs(agents) do
			for nr, line in ipairs(vim.fn.readfile(file)) do
				-- A mention is fine when the same line marks it as retired.
				local marks_dead = line:find("tombstone")
					or line:find("NOT for")
					or line:find("replaced")
					or line:find("→")
				for pat, native in pairs(dead) do
					if line:find(pat) and not marks_dead then
						offenders[#offenders + 1] = ("%s:%d (%s is now %s)"):format(
							file,
							nr,
							pat:gsub("%%", ""),
							native
						)
					end
				end
			end
		end
		assert.are.equal(0, #offenders, "agent docs present a tombstone as live: " .. table.concat(offenders, ", "))
	end)
end)
