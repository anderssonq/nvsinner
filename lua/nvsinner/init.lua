-- NvSinner distro metadata. This directory doubles as the checkhealth
-- namespace (`health.lua` → `:checkhealth nvsinner`); `require("nvsinner").version`
-- is the SINGLE source of truth for the distro version, surfaced by the
-- :NvSinnerHelp title and the dashboard footer (via lua/core/version.lua).
--
-- core/version.lua also fetches THIS FILE raw from the `main` branch and
-- extracts the version with the Lua pattern `version%s*=%s*"([^"]+)"` — keep
-- the assignment on one line in that exact shape, or the remote check breaks.
-- Bump it as part of shipping a release to main; that is what makes existing
-- installs show "update available".
return {
	version = "1.2.0",
}
