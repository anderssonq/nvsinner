-- Guards the tombstone revert path.
--
-- House rule: a plugin replaced by a native module keeps its spec with
-- `enabled = false`, as a one-line revert. What was NOT written down is that the
-- revert has a second half — its `lazy-lock.json` entry.
--
-- Verified in lazy's own source: `Manage.restore` is `update` with
-- `lockfile = true`, and BOTH the update and install pipelines run
-- `{ "git.checkout", lockfile = opts.lockfile }`
-- (lazy.nvim/lua/lazy/manage/init.lua:85 and :117). So flipping a tombstone back
-- to `enabled = true` and running the normal `Lazy! restore` path — which is what
-- install.sh and :NvSinnerUpdate do — checks that plugin out at the **tested**
-- commit. Delete the lock entry and the same revert silently lands on upstream
-- HEAD instead, which is the exact drift the restore-not-sync doctrine exists to
-- prevent.
--
-- Those 11 entries look like cruft in a lockfile diff. They are not. This spec
-- exists so nobody "tidies" them away.

local function tombstones()
	local out = {}
	for _, file in ipairs(vim.fn.glob("lua/plugins/**/*.lua", false, true)) do
		for _, line in ipairs(vim.fn.readfile(file)) do
			-- A tombstone sets `enabled = false` at the TOP level of the returned
			-- spec — exactly one tab. Nested `enabled = false` are plugin options
			-- (noice's notify/hover/signature, render-markdown's own default) and
			-- must not be mistaken for a disabled spec.
			if line == "\tenabled = false," then
				local src = table.concat(vim.fn.readfile(file), "\n")
				-- The lock is keyed on lazy's plugin NAME, which is the repo's
				-- last path segment UNLESS the spec overrides it — window-picker
				-- does exactly that, so deriving from the URL alone reports a
				-- false missing pin. (It did, the first time this was run.)
				local name = src:match('\n\tname = "([^"]+)"')
				if not name then
					local repo = src:match('"([%w%.%-_]+/[%w%.%-_]+)"')
					name = repo and repo:match("[^/]+$")
				end
				if name then
					out[name] = file
				end
				break
			end
		end
	end
	return out
end

describe("tombstoned plugins", function()
	local lock = vim.json.decode(table.concat(vim.fn.readfile("lazy-lock.json"), "\n"))
	local dead = tombstones()

	it("finds the tombstones without tripping on nested options", function()
		-- Sanity check on the detector itself: noice is ACTIVE but its config
		-- contains three `enabled = false` option lines, and a looser match
		-- reports it as disabled. (It did, the first time this was written.)
		assert.is_true(vim.tbl_count(dead) > 5, "expected the tombstone set, got " .. vim.inspect(dead))
		assert.is_nil(dead["noice.nvim"], "noice is active — its `enabled = false` lines are options")
		assert.is_truthy(dead["incline.nvim"], "incline is a known tombstone")
		assert.is_truthy(dead["window-picker"], "the spec's explicit `name` must win over the repo path")
	end)

	it("keeps a lazy-lock entry for every tombstone, so reverts land on the tested commit", function()
		local missing = {}
		for name, file in pairs(dead) do
			if not lock[name] then
				missing[#missing + 1] = ("%s (%s)"):format(name, file)
			end
		end
		assert.are.equal(
			0,
			#missing,
			"these tombstones lost their pin, so re-enabling them would float to upstream HEAD: "
				.. table.concat(missing, ", ")
		)
	end)
end)
