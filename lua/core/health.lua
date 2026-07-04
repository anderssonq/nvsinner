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
		used_by = "prettier / eslint_d runtime",
		install = "brew install node  (or your distro's nodejs)",
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

-- Probe each tool with vim.fn.executable (fast, no subprocess). `with_version`
-- shells out for a version string — fine for :checkhealth, skipped for the
-- startup toast where we only care present/absent.
---@param opts? { with_version?: boolean }
function M.check_tools(opts)
	opts = opts or {}
	local results = {}
	for _, t in ipairs(M.tools) do
		local found = vim.fn.executable(t.cmd) == 1
		local version
		if found and opts.with_version then
			local out = vim.fn.system({ t.cmd, "--version" })
			if vim.v.shell_error == 0 then
				version = vim.trim((out or ""):gsub("\n.*$", "")) -- first line only
			end
		end
		results[#results + 1] = {
			name = t.name,
			cmd = t.cmd,
			used_by = t.used_by,
			install = t.install,
			found = found,
			version = version,
		}
	end
	return results
end

-- :checkhealth nvsinner body — uses the native vim.health.* reporter.
function M.report()
	local h = vim.health

	h.start("NvSinner · Neovim")
	if vim.fn.has("nvim-0.11") == 1 then
		h.ok("Neovim " .. tostring(vim.version()))
	else
		h.error("Neovim 0.11+ required (uses vim.uv + the native vim.lsp API); found " .. tostring(vim.version()))
	end

	h.start("NvSinner · external tools")
	for _, r in ipairs(M.check_tools({ with_version = true })) do
		if r.found then
			h.ok(("%s%s — %s"):format(r.name, r.version and (" " .. r.version) or "", r.used_by))
		else
			h.warn(("%s not found — %s"):format(r.name, r.used_by), { "Install: " .. r.install })
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

-- One-time, first-interactive-launch nudge: if any external is missing, point
-- the user at :checkhealth nvsinner. Greets once regardless (writes the marker
-- even when nothing's missing) so it never nags on later launches. The Nerd Font
-- is intentionally NOT counted — it can't be detected from here.
---@param opts? { marker?: string } test seam: override the marker path.
function M.first_run_notify(opts)
	opts = opts or {}
	local marker = opts.marker or marker_path()
	if vim.fn.filereadable(marker) == 1 then
		return
	end

	local missing = {}
	for _, r in ipairs(M.check_tools()) do
		if not r.found then
			missing[#missing + 1] = r.name
		end
	end

	mark_seen(marker) -- greet once regardless of the outcome

	if #missing == 0 then
		return
	end

	vim.notify(
		("%d optional tool%s missing: %s.\nRun  :checkhealth nvsinner  for install hints."):format(
			#missing,
			#missing == 1 and "" or "s",
			table.concat(missing, ", ")
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
