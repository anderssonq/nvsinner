-- :NvSinnerSync — opt-in "float to latest" updater for plugins + Mason packages.
--
-- NOT the distro updater: :NvSinnerUpdate (core/update.lua) is the reproducible
-- path (git pull + restore to the committed lazy-lock.json). This command is the
-- explicit developer opt-in: it runs `:Lazy sync` (install missing + update to
-- latest + clean removed — REWRITES lazy-lock.json) and then updates every
-- outdated Mason package. After syncing, retest and commit the new
-- lazy-lock.json so restore-based installs reproduce the set you actually run.
--
-- Chaining: lazy's `sync()` returns nothing (unlike `restore()`, which returns
-- a waitable runner — verified in lazy/manage/init.lua); it fires the
-- `User LazySync` autocmd when the whole clean+install+update pipeline settles,
-- so the Mason phase hooks that event (one-shot).
--
-- Branch-jump guard: a spec without a `branch` pin follows the UPSTREAM DEFAULT
-- branch, and sync re-resolves it — so an upstream default-branch flip silently
-- swaps the plugin for whatever lives there (incident 2026-07-03:
-- nvim-treesitter flipped master → main, a full rewrite; the parser rebuilds
-- failed to link and the config module no longer existed). The lockfile records
-- each plugin's branch, so sync snapshots it before and diffs it after,
-- WARN-ing loudly about any jump with the rollback recipe.

local M = {}

local TITLE = "🔥 NvSinner"

-- Decode lazy-lock.json into { plugin = { branch, commit } }; nil on any
-- failure (missing file, bad JSON) — the guard then just stays quiet.
local function read_lock()
	local path = vim.fn.stdpath("config") .. "/lazy-lock.json"
	local ok, lines = pcall(vim.fn.readfile, path)
	if not ok then
		return nil
	end
	local ok2, lock = pcall(vim.json.decode, table.concat(lines, "\n"))
	return ok2 and lock or nil
end

-- Pure helper (test seam): diff two decoded lockfiles and return every plugin
-- whose branch changed, as { name, from, to }, sorted by name. Plugins added
-- or removed by the sync are not jumps and are ignored.
function M.branch_jumps(before, after)
	local jumps = {}
	for name, b in pairs(before) do
		local a = after[name]
		if a and b.branch and a.branch and b.branch ~= a.branch then
			jumps[#jumps + 1] = { name = name, from = b.branch, to = a.branch }
		end
	end
	table.sort(jumps, function(x, y)
		return x.name < y.name
	end)
	return jumps
end

-- Pure helper (test seam): given Package-like objects exposing
-- get_installed_version() / get_latest_version(), return the outdated ones.
-- Both getters are pcall-guarded — get_latest_version() throws on a malformed
-- purl, and get_installed_version() reads the install receipt from disk. A nil
-- installed version (no receipt) is skipped: there is nothing to compare.
function M.outdated(pkgs)
	local out = {}
	for _, pkg in ipairs(pkgs) do
		local ok_latest, latest = pcall(pkg.get_latest_version, pkg)
		local ok_installed, installed = pcall(pkg.get_installed_version, pkg)
		if ok_latest and ok_installed and latest and installed and latest ~= installed then
			out[#out + 1] = pkg
		end
	end
	return out
end

-- Update every outdated Mason package (async). Refreshes the registry first so
-- "latest" is current (a failed refresh just means the cached specs are used),
-- then installs the outdated set, counting completions via the install
-- callback (success, receipt|error).
function M.mason_update()
	-- mason.nvim is lazy-loaded (cmd = "Mason" in the lsp spec); load it so the
	-- registry has its sources configured. pcall both steps: on a plugin-less
	-- boot (tests, bare install) neither lazy nor mason is on the rtp.
	local loaded = pcall(function()
		require("lazy").load({ plugins = { "mason.nvim" } })
	end)
	local ok, registry = pcall(require, "mason-registry")
	if not (loaded and ok) then
		vim.notify("mason.nvim is not available — skipped Mason packages.", vim.log.levels.WARN, { title = TITLE })
		return
	end

	registry.refresh(vim.schedule_wrap(function()
		local todo = M.outdated(registry.get_installed_packages())
		if #todo == 0 then
			vim.notify("Mason packages are up to date.", vim.log.levels.INFO, { title = TITLE })
			return
		end

		local names = vim.tbl_map(function(p)
			return p.name
		end, todo)
		vim.notify("Updating Mason packages: " .. table.concat(names, ", "), vim.log.levels.INFO, { title = TITLE })

		local remaining, failed = #todo, {}
		for _, pkg in ipairs(todo) do
			pkg:install(
				nil,
				vim.schedule_wrap(function(success)
					if not success then
						failed[#failed + 1] = pkg.name
					end
					remaining = remaining - 1
					if remaining == 0 then
						if #failed > 0 then
							vim.notify(
								"Mason updates failed: " .. table.concat(failed, ", ") .. " (see :Mason)",
								vim.log.levels.ERROR,
								{ title = TITLE }
							)
						else
							vim.notify(
								("Updated %d Mason package(s)."):format(#todo),
								vim.log.levels.INFO,
								{ title = TITLE }
							)
						end
					end
				end)
			)
		end
	end))
end

-- The full sync: :Lazy sync (plugins → latest, rewrites lazy-lock.json), then
-- the Mason phase once the `User LazySync` autocmd says the pipeline settled.
function M.sync()
	local ok, lazy = pcall(require, "lazy")
	if not ok then
		vim.notify("lazy.nvim is not available.", vim.log.levels.WARN, { title = TITLE })
		return
	end

	local before = read_lock()

	vim.api.nvim_create_autocmd("User", {
		pattern = "LazySync",
		once = true,
		callback = function()
			local jumps = M.branch_jumps(before or {}, read_lock() or {})
			if #jumps > 0 then
				local lines = { "⚠ Plugins JUMPED BRANCH (upstream default changed):" }
				for _, j in ipairs(jumps) do
					lines[#lines + 1] = ("  %s: %s → %s"):format(j.name, j.from, j.to)
				end
				lines[#lines + 1] = "A default-branch flip usually means a rewrite — review before restarting."
				lines[#lines + 1] =
					"Roll back: git restore lazy-lock.json + :Lazy restore (and pin `branch` in the spec)."
				vim.notify(table.concat(lines, "\n"), vim.log.levels.WARN, { title = TITLE })
			end
			vim.notify(
				"Plugins synced — lazy-lock.json rewritten (retest + commit it).\nChecking Mason packages…",
				vim.log.levels.INFO,
				{ title = TITLE }
			)
			M.mason_update()
		end,
	})

	vim.notify("Syncing plugins to latest…", vim.log.levels.INFO, { title = TITLE })
	lazy.sync()
end

vim.api.nvim_create_user_command("NvSinnerSync", function()
	M.sync()
end, { desc = "Float plugins to latest (:Lazy sync) + update Mason packages" })

return M
