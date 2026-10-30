-- :NvSinnerUpdate — in-editor updater for the NvSinner distro (à la
-- :NvChadUpdate / :AstroUpdate). Pulls the latest config from git, then restores
-- plugins to the committed lazy-lock.json so the plugin set matches the versions
-- the distro was tested with (reproducible — see the lazy-lock story in
-- README/NVSINNER.md), and finally runs :checkhealth.
--
-- No-op-with-warning when the config dir isn't a git clone: on the dev machine
-- ~/.config/nvsinner is a symlink to this repo, and a manual/copied install has
-- no remote to pull from — either way there's nothing to `git pull`.
--
-- Before pulling it aborts with a warning on a dirty tracked tree, and it
-- decides "updated" vs "no-op" by comparing HEAD before/after the pull (never
-- by git's localised message).
--
-- NOTE: the pull rewrites the Lua files on disk, but the RUNNING Neovim keeps the
-- old modules loaded, so the update only fully takes effect after a restart. The
-- final toast says so.

local M = {}

local TITLE = "🔥 NvSinner"

-- True when `dir` is a git working tree (a plain clone has a .git DIRECTORY; a
-- worktree/submodule has a .git FILE pointing elsewhere — accept both).
function M.is_git_repo(dir)
	return vim.fn.isdirectory(dir .. "/.git") == 1 or vim.fn.filereadable(dir .. "/.git") == 1
end

-- Restore plugins to the lockfile, then checkhealth once it settles. `restore`
-- (not `sync`) keeps installs reproducible: it checks every plugin out to the
-- commit pinned in lazy-lock.json instead of floating to latest.
local function restore_and_check()
	local runner = require("lazy").restore()
	runner:wait(function()
		vim.schedule(function()
			vim.notify("Updated. Restart Neovim to load the new config.", vim.log.levels.INFO, { title = TITLE })
			vim.cmd("checkhealth")
		end)
	end)
end

-- Test seams (swapped by table field in the spec): the job runner and the
-- restore step, so the suite never touches git remotes or lazy.
M._system = vim.system
M._restore = restore_and_check

---@param opts? { dir?: string } test seam: override the config dir to pull.
function M.update(opts)
	local dir = (opts and opts.dir) or vim.fn.stdpath("config")

	if not M.is_git_repo(dir) then
		vim.notify(
			("%s is not a git clone, so there's nothing to pull.\n"):format(dir)
				.. "If you installed manually, re-run install.sh or update by hand.",
			vim.log.levels.WARN,
			{ title = TITLE }
		)
		return
	end

	-- Run one git command in `dir`, then call back on the main loop. Every call
	-- goes through M._system (a table field, so specs swap it) and is async so
	-- the editor stays responsive.
	local function git(args, cb)
		local cmd = { "git", "-C", dir }
		vim.list_extend(cmd, args)
		M._system(cmd, { text = true }, vim.schedule_wrap(cb))
	end

	local function fail(what, res)
		vim.notify(
			what .. " failed:\n" .. vim.trim((res.stderr ~= "" and res.stderr) or res.stdout or ""),
			vim.log.levels.ERROR,
			{ title = TITLE }
		)
	end

	-- A dirty TRACKED tree makes `pull --ff-only` fail with a cryptic message, so
	-- check first and say what to do. Untracked files are ignored: they only
	-- matter on a path collision, which git itself reports.
	git({ "status", "--porcelain", "--untracked-files=no" }, function(st)
		if st.code ~= 0 then
			return fail("git status", st)
		end
		if vim.trim(st.stdout or "") ~= "" then
			vim.notify(
				("%s has uncommitted changes, so the update was not started.\n"):format(dir)
					.. ("Commit or stash them (git -C %s stash), then run :NvSinnerUpdate again."):format(dir),
				vim.log.levels.WARN,
				{ title = TITLE }
			)
			return
		end

		vim.notify("Pulling latest…", vim.log.levels.INFO, { title = TITLE })

		git({ "rev-parse", "HEAD" }, function(before)
			-- --ff-only never invents a merge commit and fails loudly if the
			-- local clone has diverged.
			git({ "pull", "--ff-only" }, function(res)
				if res.code ~= 0 then
					return fail("git pull", res)
				end

				-- Decide "changed?" by comparing HEAD, never by matching git's
				-- (localised) "Already up to date" text.
				git({ "rev-parse", "HEAD" }, function(after)
					local b, a = vim.trim(before.stdout or ""), vim.trim(after.stdout or "")
					if before.code == 0 and after.code == 0 and b ~= "" and b == a then
						vim.notify("Already up to date.", vim.log.levels.INFO, { title = TITLE })
						return
					end

					local out = vim.trim(res.stdout or "")
					vim.notify(
						(out ~= "" and out or "Pulled.") .. "\nRestoring plugins…",
						vim.log.levels.INFO,
						{ title = TITLE }
					)
					M._restore()
				end)
			end)
		end)
	end)
end

vim.api.nvim_create_user_command("NvSinnerUpdate", function()
	M.update()
end, { desc = "Update NvSinner: git pull + restore plugins to lockfile + checkhealth" })

return M
