-- Every file under lua/plugins/ must load cleanly and return a valid lazy.nvim
-- spec (a single spec table, a list of them, or a dir/url/import spec).

local function repo_root()
	local f = vim.api.nvim_get_runtime_file("lua/core/ai-activity.lua", false)[1]
	assert(f, "this config must be on the runtimepath (see tests/minimal_init.lua)")
	return vim.fn.fnamemodify(f, ":h:h:h")
end

-- A lazy spec is: a string-headed table ({ "owner/repo", ... }), a dir/url/name/
-- import spec, or a LIST whose every element is itself a spec.
local function is_spec(t)
	if type(t) ~= "table" then
		return false
	end
	if type(t[1]) == "string" then
		return true
	end
	if t.url or t.dir or t.name or t.import then
		return true
	end
	if #t > 0 then
		for _, v in ipairs(t) do
			if not is_spec(v) then
				return false
			end
		end
		return true
	end
	return false
end

describe("plugin specs", function()
	local root = repo_root()
	local files = vim.fn.glob(root .. "/lua/plugins/**/*.lua", false, true)

	it("finds the plugin spec files", function()
		assert.is_true(#files > 0, "expected to find lua/plugins/**/*.lua")
	end)

	for _, file in ipairs(files) do
		local rel = file:sub(#root + 2)
		it("loads and returns a valid spec: " .. rel, function()
			local ok, spec = pcall(dofile, file)
			assert.is_true(ok, "should load without error: " .. tostring(spec))
			assert.is_true(is_spec(spec), rel .. " must return a lazy.nvim spec")
		end)
	end
end)
