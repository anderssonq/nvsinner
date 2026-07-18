-- ─── NvSinner version check ──────────────────────────────────────────────────
-- Current-version access (require("nvsinner").version is the single source of
-- truth) plus a once-per-session async check against the remote. The remote
-- source is the SAME metadata file, fetched raw from the `main` branch: the
-- repo has no tags/releases on purpose, and :NvSinnerUpdate is `git pull` of
-- main — so "remote main carries a newer semver" is exactly "updating would
-- deliver a newer version".
--
-- Consumers: the dashboard footer (lua/plugins/ui/dashboard.lua swaps the
-- quote for an update prompt) and the :NvSinnerHelp title (lua/core/help.lua
-- appends the status). Both subscribe via M.on_change and guard their own UI
-- validity. Triggers: the first dashboard draw and :NvSinnerHelp's open() —
-- whichever comes first wins; the once-guard makes later triggers free.

local M = {}

-- The raw distro-metadata file on `main` (its `version = "x.y.z"` line shape
-- is load-bearing — documented in lua/nvsinner/init.lua itself).
M.URL = "https://raw.githubusercontent.com/anderssonq/nvsinner/main/lua/nvsinner/init.lua"

M._state = { status = "idle", latest = nil } -- status ∈ idle|checking|latest|outdated|error
M._checked = false -- once per session
M._subs = {} -- on_change callbacks

function M.current()
	return require("nvsinner").version
end

-- "v1.0.0" for semver strings, verbatim otherwise (an old "beta" must not
-- read as "vbeta"). `v` defaults to the local version.
function M.display(v)
	v = v or M.current()
	local ok, parsed = pcall(vim.version.parse, v, { strict = false })
	if ok and parsed then
		return "v" .. v
	end
	return v
end

function M.status()
	return M._state.status
end

function M.latest()
	return M._state.latest
end

-- Subscribe to state changes. A plain list on purpose: both consumers live
-- for the session and guard their own UI validity, so unsubscribe machinery
-- would be dead weight.
function M.on_change(fn)
	table.insert(M._subs, fn)
end

-- Always scheduled: the dashboard footer function calls check() from INSIDE
-- alpha's draw, so a synchronous emit → alpha.redraw() would recurse into a
-- draw mid-draw. Scheduling breaks the re-entrancy.
function M._emit()
	vim.schedule(function()
		for _, fn in ipairs(M._subs) do
			pcall(fn)
		end
	end)
end

-- Interactive-only guard (same pattern as health.lua): the installer's
-- headless boot and the test suite must never hit the network. Seam.
function M._headless()
	return #vim.api.nvim_list_uis() == 0
end

-- One warning in :messages (echo with history), NOT a vim.notify toast — a
-- toast would nag on every offline launch. Fires at most once per session
-- (the once-guard). Seam.
function M._warn(msg)
	vim.api.nvim_echo({ { "NvSinner: " .. msg, "WarningMsg" } }, true, {})
end

-- Extract the version from the raw lua/nvsinner/init.lua body. Seam.
function M._parse_remote(body)
	if type(body) ~= "string" then
		return nil
	end
	return body:match('version%s*=%s*"([^"]+)"')
end

local function parse(v)
	local ok, parsed = pcall(vim.version.parse, v, { strict = false })
	return ok and parsed or nil
end

-- Pure semver policy (seam):
--   remote > local → "outdated"; otherwise → "latest".
--   Unparseable REMOTE → "latest": until a semver lands on main the remote
--   says "beta" — it can never be declared newer, and it must not warn on
--   every launch in the interim.
--   Unparseable LOCAL vs a semver remote → "outdated": an old "beta" install
--   pulling main WOULD get a newer version, so the prompt is correct.
function M._compare(local_v, remote_v)
	local remote = parse(remote_v)
	if not remote then
		return "latest"
	end
	local current = parse(local_v)
	if not current then
		return "outdated"
	end
	return vim.version.cmp(remote, current) == 1 and "outdated" or "latest"
end

-- The ONLY function that touches the network — called by table field so the
-- specs swap it (mirrors ai-complete.M._request). on_done receives
-- { ok = true, body = <string> } or { ok = false, kind = "nocurl"|"curl"|
-- "http"|"parse" }. curl via vim.system, callback re-entered on the main
-- loop; the HTTP status rides a -w tail split off the body (same idiom as
-- ai-complete._classify).
function M._fetch(on_done)
	if vim.fn.executable("curl") == 0 then
		on_done({ ok = false, kind = "nocurl" })
		return
	end
	local argv = {
		"curl",
		"-sS",
		"--connect-timeout",
		"3",
		"--max-time",
		"10",
		"-w",
		"\n%{http_code}",
		M.URL,
	}
	local ok = pcall(
		vim.system,
		argv,
		{ text = true },
		vim.schedule_wrap(function(res)
			if res.code ~= 0 then
				on_done({ ok = false, kind = "curl" })
				return
			end
			local body, status = (res.stdout or ""):match("^(.*)\n(%d%d%d)%s*$")
			if not status then
				on_done({ ok = false, kind = "parse" })
			elseif status ~= "200" then
				on_done({ ok = false, kind = "http" })
			else
				on_done({ ok = true, body = body })
			end
		end)
	)
	if not ok then
		on_done({ ok = false, kind = "curl" })
	end
end

-- Once per session, interactive only. "checking" is set synchronously so the
-- draw that triggered the check already renders the spinner state. Failures
-- degrade to status "error" (consumers fall back to the plain quote / no
-- suffix) plus one :messages warning — never a crash, never a UI freeze.
function M.check()
	if M._checked or M._headless() then
		return
	end
	M._checked = true
	M._state.status = "checking"
	M._emit()
	M._fetch(function(res)
		if not res.ok then
			M._state.status = "error"
			M._warn("version check failed (" .. (res.kind or "network") .. ")")
		else
			local remote = M._parse_remote(res.body)
			if not remote then
				M._state.status = "error"
				M._warn("version check failed (unexpected response)")
			else
				M._state.latest = remote
				M._state.status = M._compare(M.current(), remote)
			end
		end
		M._emit()
	end)
end

-- Test seam. Keeps _subs: subscriber registration is load-time wiring (the
-- dashboard and help register exactly once), not per-session state.
function M._reset()
	M._checked = false
	M._state = { status = "idle", latest = nil }
end

return M
