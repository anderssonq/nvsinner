-- core/version.lua — current-version access, semver display/compare, and the
-- once-per-session async remote check. The network lives behind the swapped
-- _fetch seam (the suite never makes a real request), and the suite being
-- headless makes the interactive-only guard itself testable.
local version = require("core.version")

describe("core.version", function()
	before_each(function()
		version._reset()
	end)

	-- Swap the seams for one check() run. The fake fetch defers its callback
	-- (like the real curl one), so the synchronous "checking" state stays
	-- observable. Callers restore() BEFORE asserting (house rule: a failed
	-- assert must not leak stubbed seams).
	local function checked_env(fetch_result)
		local env = {}
		local orig_headless, orig_fetch, orig_warn = version._headless, version._fetch, version._warn
		env.fetches, env.fired, env.warns = 0, 0, {}
		version._headless = function()
			return false
		end
		version._fetch = function(on_done)
			env.fetches = env.fetches + 1
			vim.schedule(function()
				on_done(fetch_result)
			end)
		end
		version._warn = function(msg)
			table.insert(env.warns, msg)
		end
		version.on_change(function()
			env.fired = env.fired + 1
		end)
		env.restore = function()
			version._headless, version._fetch, version._warn = orig_headless, orig_fetch, orig_warn
		end
		return env
	end

	it("current() reads the nvsinner module and pins the 1.2.0 release", function()
		assert.are.equal(require("nvsinner").version, version.current())
		assert.are.equal("1.2.0", version.current())
	end)

	it("display() prefixes v for semver strings only", function()
		assert.are.equal("v1.1.0", version.display("1.1.0"))
		assert.are.equal("beta", version.display("beta"))
		assert.are.equal("v" .. version.current(), version.display())
	end)

	it("_parse_remote extracts the version from a raw init.lua body", function()
		local body = '-- NvSinner distro metadata.\nreturn {\n\tversion = "1.2.0",\n}\n'
		assert.are.equal("1.2.0", version._parse_remote(body))
		assert.is_nil(version._parse_remote("<html>404 moved</html>"))
		assert.is_nil(version._parse_remote(nil))
	end)

	it("_compare maps the semver matrix (unparseable remote never nags)", function()
		assert.are.equal("outdated", version._compare("1.0.0", "1.1.0"))
		assert.are.equal("latest", version._compare("1.0.0", "1.0.0"))
		assert.are.equal("latest", version._compare("1.1.0", "1.0.0"))
		-- Pre-merge main still says "beta": never declared newer, never warns.
		assert.are.equal("latest", version._compare("1.0.0", "beta"))
		-- An old "beta" install pulling main WOULD get a newer version.
		assert.are.equal("outdated", version._compare("beta", "1.0.0"))
	end)

	it("check() shows checking first, then resolves outdated via the seam", function()
		local env = checked_env({ ok = true, body = 'return {\n\tversion = "9.9.9",\n}\n' })
		version.check()
		local mid = version.status()
		vim.wait(500, function()
			return version.status() == "outdated" and env.fired >= 2
		end)
		env.restore()
		assert.are.equal("checking", mid)
		assert.are.equal("outdated", version.status())
		assert.are.equal("9.9.9", version.latest())
		assert.is_true(env.fired >= 2) -- one emit for checking, one for the result
	end)

	it("check() resolves latest when the remote carries the current version", function()
		local env = checked_env({ ok = true, body = 'return { version = "' .. version.current() .. '" }' })
		version.check()
		vim.wait(500, function()
			return version.status() == "latest"
		end)
		env.restore()
		assert.are.equal("latest", version.status())
		assert.are.equal(version.current(), version.latest())
	end)

	it("a failed fetch degrades to error with one warning", function()
		local env = checked_env({ ok = false, kind = "curl" })
		version.check()
		vim.wait(500, function()
			return version.status() == "error"
		end)
		env.restore()
		assert.are.equal("error", version.status())
		assert.are.equal(1, #env.warns)
		assert.matches("curl", env.warns[1], nil, true)
		assert.is_nil(version.latest())
	end)

	it("an unparseable body degrades to error", function()
		local env = checked_env({ ok = true, body = "<html>moved</html>" })
		version.check()
		vim.wait(500, function()
			return version.status() == "error"
		end)
		env.restore()
		assert.are.equal("error", version.status())
		assert.are.equal(1, #env.warns)
	end)

	it("checks once per session: repeat triggers reuse the result", function()
		local env = checked_env({ ok = true, body = 'return { version = "9.9.9" }' })
		version.check()
		vim.wait(500, function()
			return version.status() == "outdated"
		end)
		version.check() -- dashboard redraws / help reopens re-trigger freely
		version.check()
		vim.wait(50)
		env.restore()
		assert.are.equal(1, env.fetches)
		assert.are.equal("outdated", version.status())
	end)

	it("headless sessions never check (the suite itself is headless)", function()
		-- _headless is left stock on purpose: this spec runs headless, so the
		-- guard is exercised for real.
		local orig_fetch = version._fetch
		local fetches = 0
		version._fetch = function(on_done)
			fetches = fetches + 1
			on_done({ ok = false, kind = "curl" })
		end
		version.check()
		version._fetch = orig_fetch
		assert.are.equal("idle", version.status())
		assert.are.equal(0, fetches)
	end)
end)
