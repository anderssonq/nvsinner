-- NvSinner health — surface missing external tools instead of letting features
-- silently no-op. Two entry points share one tool table:
--   • :checkhealth nvsinner  → M.report(), wired via lua/nvsinner/health.lua so
--     Neovim discovers it by the module path `nvsinner.health`.
--   • a one-time first-run toast on the first INTERACTIVE launch (M.setup()),
--     nudging the user to run :checkhealth nvsinner when something's missing.
--
-- A Nerd Font can't be probed from inside Neovim (it's a terminal/GUI font
-- setting), so it's reported as an informational note — not a pass/fail — and is
-- left out of the "missing tools" count that drives the toast.

local M = {}

local TITLE = "NvSinner health check"

-- Each external the config leans on: the binary to probe (`cmd`), what breaks
-- without it (`used_by`), and how to get it (`install`). Order = report order.
-- Exposed on M so tests can swap it for a deterministic set.
M.tools = {
	{
		name = "ripgrep",
		cmd = "rg",
		used_by = "Telescope live grep",
		install = "brew install ripgrep  (apt/dnf/pacman: ripgrep)",
	},
	{
		name = "node",
		cmd = "node",
		used_by = "JS/TS/Vue LSPs and prettier / eslint_d runtime",
		install = "install Node 20+ with brew, nvm, or your distro's nodejs package",
		minimum_major = 20,
		show_path = true,
	},
	{
		name = "curl",
		cmd = "curl",
		used_by = "inline AI completion (core.ai-complete)",
		install = "brew install curl  (ships by default on macOS/most Linux)",
	},
	-- stylua/prettier/eslint_d are auto-installed by Mason on first boot
	-- (mason-tool-installer); the hints below are the manual fallback if that
	-- install failed or hasn't run yet (:MasonToolsInstall retries it).
	{
		name = "stylua",
		cmd = "stylua",
		used_by = "Lua formatting (none-ls)",
		install = "auto via Mason (:MasonToolsInstall)  — or brew install stylua",
	},
	{
		name = "prettier",
		cmd = "prettier",
		used_by = "JS/TS/HTML formatting (none-ls)",
		install = "auto via Mason (:MasonToolsInstall)  — or npm install -g prettier",
	},
	{
		name = "eslint_d",
		cmd = "eslint_d",
		used_by = "JS/TS linting (none-ls)",
		install = "auto via Mason (:MasonToolsInstall)  — or npm install -g eslint_d",
	},
	{
		name = "shfmt",
		cmd = "shfmt",
		used_by = "shell-script formatting (none-ls)",
		install = "auto via Mason (:MasonToolsInstall)  — or brew install shfmt",
	},
}

-- Test seam around the only subprocess used by tool probing.
function M._run_version(cmd)
	local out = vim.fn.system({ cmd, "--version" })
	return out, vim.v.shell_error
end

local function version_major(version)
	return version and tonumber(version:match("^v?(%d+)")) or nil
end

-- Probe each tool with vim.fn.executable. `with_version` shows versions for the
-- full report; tools with a minimum version are always queried so the one-time
-- startup check catches an executable that exists but cannot run its clients.
---@param opts? { with_version?: boolean }
function M.check_tools(opts)
	opts = opts or {}
	local results = {}
	for _, t in ipairs(M.tools) do
		local found = vim.fn.executable(t.cmd) == 1
		local version
		if found and (opts.with_version or t.minimum_major) then
			local out, exit_code = M._run_version(t.cmd)
			if exit_code == 0 then
				version = vim.trim((out or ""):gsub("\n.*$", "")) -- first line only
			end
		end
		local major = version_major(version)
		local compatible = t.minimum_major == nil or (major ~= nil and major >= t.minimum_major)
		results[#results + 1] = {
			name = t.name,
			cmd = t.cmd,
			used_by = t.used_by,
			install = t.install,
			found = found,
			version = version,
			path = found and vim.fn.exepath(t.cmd) or nil,
			minimum_major = t.minimum_major,
			compatible = compatible,
			show_path = t.show_path,
		}
	end
	return results
end

-- :checkhealth nvsinner body — uses the native vim.health.* reporter.
function M.report()
	local h = vim.health

	h.start("NvSinner · Neovim")
	if vim.fn.has("nvim-0.12") == 1 then
		h.ok("Neovim " .. tostring(vim.version()))
	else
		h.error(
			"Neovim 0.12+ required (bundled packages + the 0.12 treesitter query API); found "
				.. tostring(vim.version())
		)
	end

	h.start("NvSinner · external tools")
	for _, r in ipairs(M.check_tools({ with_version = true })) do
		if not r.found then
			h.warn(("%s not found — %s"):format(r.name, r.used_by), { "Install: " .. r.install })
		elseif not r.compatible then
			h.error(
				("%s %s is incompatible — %s requires version %d+"):format(
					r.name,
					r.version or "(version unknown)",
					r.used_by,
					r.minimum_major
				),
				{
					"Executable: " .. (r.path or r.cmd),
					"Install: " .. r.install,
					"Restart Neovim after changing PATH.",
				}
			)
		else
			local path = r.show_path and r.path and (" (" .. r.path .. ")") or ""
			h.ok(("%s%s%s — %s"):format(r.name, r.version and (" " .. r.version) or "", path, r.used_by))
		end
	end

	h.start("NvSinner · Nerd Font")
	h.info("Icons need a Nerd Font (FiraCode Nerd Font is bundled in fonts/).")
	h.info('Set your terminal (or GUI) font to a "… Nerd Font" — this can\'t be auto-detected.')
end

-- First-run marker lives under stdpath("state") so it's per-app (nvsinner) and
-- survives across sessions. Absent = we haven't greeted this install yet.
local function marker_path()
	return vim.fn.stdpath("state") .. "/nvsinner-health-checked"
end

local function mark_seen(path)
	vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
	local fd = io.open(path, "w")
	if fd then
		fd:write(os.date("%Y-%m-%dT%H:%M:%S") .. "\n")
		fd:close()
	end
end

-- One-time, first-interactive-launch nudge: if any external is missing or
-- incompatible, point
-- the user at :checkhealth nvsinner. Greets once regardless (writes the marker
-- even when everything is healthy) so it never nags on later launches. The Nerd Font
-- is intentionally NOT counted — it can't be detected from here.
---@param opts? { marker?: string } test seam: override the marker path.
function M.first_run_notify(opts)
	opts = opts or {}
	local marker = opts.marker or marker_path()
	if vim.fn.filereadable(marker) == 1 then
		return
	end

	local issues = {}
	for _, r in ipairs(M.check_tools()) do
		if not r.found then
			issues[#issues + 1] = r.name .. " missing"
		elseif not r.compatible then
			issues[#issues + 1] = ("%s %s (need %d+)"):format(r.name, r.version or "version unknown", r.minimum_major)
		end
	end

	mark_seen(marker) -- greet once regardless of the outcome

	if #issues == 0 then
		return
	end

	vim.notify(
		("%d tool problem%s: %s.\nRun  :checkhealth nvsinner  for details."):format(
			#issues,
			#issues == 1 and "" or "s",
			table.concat(issues, ", ")
		),
		vim.log.levels.WARN,
		{ title = TITLE }
	)
end

-- Wire the first-run toast to the first INTERACTIVE launch only. Headless runs
-- (the installer's `Lazy! restore`, the test harness) have no UI and must NOT
-- consume the first-run marker, or the user's real first launch would stay quiet.
function M.setup()
	if #vim.api.nvim_list_uis() == 0 then
		return
	end
	vim.api.nvim_create_autocmd("User", {
		pattern = "VeryLazy",
		once = true,
		callback = function()
			-- Defer so nvim-notify (also VeryLazy) is ready to render the toast.
			vim.defer_fn(function()
				pcall(M.first_run_notify)
			end, 800)
		end,
	})
end

M.setup()

return M
