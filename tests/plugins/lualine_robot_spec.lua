-- Behavioural guard for the statusline robot in lua/plugins/ui/lualine.lua.
--
-- Runs the spec's REAL config() against a FAKE `lualine` module (captures the
-- setup() config, counts refresh() calls). core.statusmark and core.carbon are
-- native and load for real; statusmark.start() bails headless.

local ROBOT = "\u{f06a9}"

local function repo_root()
	local f = vim.api.nvim_get_runtime_file("lua/core/ai-activity.lua", false)[1]
	assert(f, "this config must be on the runtimepath (see tests/minimal_init.lua)")
	return vim.fn.fnamemodify(f, ":h:h:h")
end

local function fire(reason)
	vim.api.nvim_exec_autocmds("User", {
		pattern = "NvSinnerAgentState",
		data = { n = 1, reason = reason },
	})
	-- let the scheduled refresh (if any) run
	vim.wait(50, function()
		return false
	end)
end

describe("lualine agent robot", function()
	local saved, cfg, refreshes
	local jobs, registered

	before_each(function()
		saved = package.loaded["lualine"]
		cfg, refreshes = nil, 0
		package.loaded["lualine"] = {
			setup = function(c)
				cfg = c
			end,
			refresh = function()
				refreshes = refreshes + 1
			end,
		}
		jobs, registered = {}, {}
		local spec = dofile(repo_root() .. "/lua/plugins/ui/lualine.lua")
		spec.config()
		assert(cfg, "config() must call lualine.setup")
	end)

	after_each(function()
		for _, n in ipairs(registered) do
			require("core.ai-sessions").unregister(n)
		end
		for _, j in ipairs(jobs) do
			pcall(vim.fn.jobstop, j)
		end
		pcall(vim.api.nvim_del_augroup_by_name, "nv_lualine_agent_count")
		pcall(vim.api.nvim_del_augroup_by_name, "nv_lualine_carbon")
		package.loaded["lualine"] = saved
	end)

	local function robot()
		for _, comp in ipairs(cfg.sections.lualine_b) do
			if type(comp) == "table" and comp.on_click == require("core.statusmark").agents_click then
				return comp[1]
			end
		end
		error("robot component (agents_click) not found in lualine_b")
	end

	local function live_session(n)
		local job = vim.fn.jobstart({ "sleep", "30" })
		jobs[#jobs + 1] = job
		require("core.ai-sessions").register(n, { job_id = job })
		registered[#registered + 1] = n
	end

	it("ignores the high-frequency 'activity' reason", function()
		fire("activity")
		assert.are.equal(0, refreshes)
	end)

	it("repaints once on register and once on unregister", function()
		fire("register")
		assert.are.equal(1, refreshes)
		fire("unregister")
		assert.are.equal(2, refreshes)
	end)

	it("renders the bare glyph with no live sessions", function()
		assert.are.equal(ROBOT, robot()())
	end)

	it("renders '<glyph> N' with N live sessions", function()
		live_session(91)
		live_session(92)
		assert.are.equal(ROBOT .. " 2", robot()())
	end)
end)
