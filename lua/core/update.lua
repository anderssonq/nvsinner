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
-- Before pulling it aborts with a warning on a dirty tracked tree (lazy-lock.json
-- alone is machine-managed drift and is discarded instead), and it
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
-- Where a discarded lockfile is saved: outside the repo, overwritten each time.
M._backup_path = function()
	return vim.fn.stdpath("state") .. "/nvsinner-lazy-lock.drift.json"
end

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
	--
	-- lazy-lock.json is the one exception: lazy rewrites it from the installed
	-- state, so it is machine-managed and drifts on its own. When it is the ONLY
	-- modified file it is discarded (the restore below re-applies the pinned
	-- set); alongside any other modified file the guard still aborts and the
	-- lockfile is left untouched.
	local LOCK = "lazy-lock.json"

	-- `discarded` = a drifted lockfile was just thrown away, which forces a restore.
	local function pull(discarded)
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
						if not discarded then
							vim.notify("Already up to date.", vim.log.levels.INFO, { title = TITLE })
							return
						end
						-- The drifted lockfile was thrown away, so the installed
						-- plugins no longer match the lockfile now on disk: restore
						-- even though HEAD did not move.
						vim.notify(
							"Already up to date.\nRestoring plugins to the pinned lockfile…",
							vim.log.levels.INFO,
							{ title = TITLE }
						)
						M._restore()
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
	end

	git({ "status", "--porcelain", "--untracked-files=no" }, function(st)
		if st.code ~= 0 then
			return fail("git status", st)
		end
		-- Do not trim the whole output: a porcelain line starts with a status
		-- column that may be a space (" M path"), and `sub(4)` relies on it.
		local lines = vim.split(st.stdout or "", "\n", { trimempty = true })
		if #lines == 0 then
			return pull(false)
		end

		local function abort()
			vim.notify(
				("%s has uncommitted changes, so the update was not started.\n"):format(dir)
					.. ("Commit or stash them (git -C %s stash), then run :NvSinnerUpdate again."):format(dir),
				vim.log.levels.WARN,
				{ title = TITLE }
			)
		end

		-- Porcelain paths are relative to the REPO ROOT. When the config dir is a
		-- subdirectory of a bigger repo (dotfiles), the lockfile shows up as
		-- "<prefix>lazy-lock.json". Only ask git for the prefix when some path
		-- could be that (same basename), so ordinary dirty trees cost no extra call.
		local paths, maybe_prefixed = {}, false
		for _, l in ipairs(lines) do
			local p = vim.trim(l:sub(4))
			paths[#paths + 1] = p
			if p ~= LOCK then
				if p:sub(-#LOCK - 1) == "/" .. LOCK then
					maybe_prefixed = true
				else
					return abort()
				end
			end
		end

		local function discard(prefix)
			for _, p in ipairs(paths) do
				if p ~= prefix .. LOCK then
					return abort()
				end
			end
			-- Keep a copy outside the repo first: an uncommitted :NvSinnerSync result
			-- lives only in this file. Never discard without the copy.
			local backup = M._backup_path()
			local fh = io.open(dir .. "/" .. LOCK, "rb")
			local data = fh and fh:read("*a")
			if fh then
				fh:close()
			end
			local ok = false
			if data then
				vim.fn.mkdir(vim.fn.fnamemodify(backup, ":h"), "p")
				local out = io.open(backup, "wb")
				if out then
					ok = out:write(data) ~= nil
					out:close()
				end
			end
			if not ok then
				return vim.notify(
					("Could not save a copy of %s to %s, so it was left untouched and the update was not started."):format(
						LOCK,
						backup
					),
					vim.log.levels.WARN,
					{ title = TITLE }
				)
			end
			-- `HEAD` makes git restore the index AND the worktree; plain
			-- `checkout -- file` copies from the index and would keep a staged drift.
			-- (-C dir + the plain name: the path is relative to dir, like the status
			-- paths are to the root, so both sides agree.)
			git({ "checkout", "HEAD", "--", LOCK }, function(co)
				if co.code ~= 0 then
					return fail("git checkout " .. LOCK, co)
				end
				vim.notify(
					("local lockfile drift discarded (copy saved to %s); Lazy restore re-applies the pinned set"):format(
						backup
					),
					vim.log.levels.INFO,
					{ title = TITLE }
				)
				pull(true)
			end)
		end

		if not maybe_prefixed then
			return discard("")
		end
		git({ "rev-parse", "--show-prefix" }, function(pre)
			if pre.code ~= 0 then
				return fail("git rev-parse --show-prefix", pre)
			end
			discard(vim.trim(pre.stdout or ""))
		end)
	end)
end

vim.api.nvim_create_user_command("NvSinnerUpdate", function()
	M.update()
end, { desc = "Update NvSinner: git pull + restore plugins to lockfile + checkhealth" })

return M
