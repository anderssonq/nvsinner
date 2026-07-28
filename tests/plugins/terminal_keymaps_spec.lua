-- Source-level guard for the terminal-mode keymaps in
-- lua/plugins/terminal/toggleterm.lua.
--
-- Those maps are created inside the lazy spec's `config`, which never runs
-- headless (tests/minimal_init.lua loads no plugins), so `maparg("jk", "t")`
-- would report "absent" whatever the file says. Reading the source is the only
-- assertion here that can actually fail when the map comes back.

local function repo_root()
	local f = vim.api.nvim_get_runtime_file("lua/core/ai-activity.lua", false)[1]
	assert(f, "this config must be on the runtimepath (see tests/minimal_init.lua)")
	return vim.fn.fnamemodify(f, ":h:h:h")
end

describe("toggleterm terminal-mode keymaps", function()
	local src
	before_each(function()
		local path = repo_root() .. "/lua/plugins/terminal/toggleterm.lua"
		local fd = assert(io.open(path, "r"), path .. " must exist")
		src = fd:read("*a")
		fd:close()
	end)

	it("maps <esc> as the escape to terminal-normal mode", function()
		assert.matches('vim%.keymap%.set%("t", "<esc>"', src)
	end)

	-- FA-25: `jk` in terminal mode makes every literal `j` a prefix, so each `j`
	-- typed into the AI CLI is withheld one 'timeoutlen' before reaching the
	-- program. The same reasoning rules out any other common typing character.
	it("never maps jk (or another plain letter) in terminal mode", function()
		for lhs in src:gmatch('vim%.keymap%.set%("t", "([^"]+)"') do
			assert.is_false(
				lhs:match("^%a+$") ~= nil,
				'"' .. lhs .. '" is a plain-letter t-mode map: it delays every such character typed into the CLI'
			)
		end
	end)
end)
