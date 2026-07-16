-- NvSinner distro metadata. This directory doubles as the checkhealth
-- namespace (`health.lua` → `:checkhealth nvsinner`); this module makes
-- `require("nvsinner").version` resolve for UI that surfaces the version
-- (the :NvSinnerHelp title).
--
-- "beta" is deliberate, not a stale placeholder: no release has been tagged
-- yet — see TODO.md "Versioned releases / tags", still an open maintainer
-- decision. Set a real semver here when one is published.
return {
	version = "beta",
}
