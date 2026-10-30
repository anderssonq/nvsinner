-- Tests for lua/core/font.lua: the Font-family switch behind :NvSinnerMenu.
-- HARD RULE: nothing here may run osascript or touch a real Ghostty config.
-- Every spec swaps the runner (M._run), the env (M._getenv) and the path bases
-- (M._home / M._config_home) for stubs + a temp dir.

describe("core.font", function()
	local font = require("core.font")
	local orig = {
		run = font._run,
		getenv = font._getenv,
		is_mac = font._is_mac,
		home = font._home,
		config_home = font._config_home,
		notify = vim.notify,
		neovide = vim.g.neovide,
		guifont = vim.o.guifont,
	}
	local root, calls, notes, env

	local function read(path)
		local fd = io.open(path, "r")
		if not fd then
			return nil
		end
		local s = fd:read("*a")
		fd:close()
		return s
	end

	local function write(path, text)
		vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
		local fd = assert(io.open(path, "w"))
		fd:write(text)
		fd:close()
	end

	before_each(function()
		root = vim.fn.tempname()
		vim.fn.mkdir(root, "p")
		calls, notes = {}, {}
		env = { TERM_PROGRAM = "ghostty" }
		font._home = root .. "/home"
		font._config_home = root .. "/home/.config"
		font._is_mac = function()
			return true
		end
		font._getenv = function(name)
			return env[name]
		end
		font._run = function(cmd, cb)
			calls[#calls + 1] = cmd
			cb(true, "")
		end
		vim.notify = function(msg, level)
			notes[#notes + 1] = { msg = msg, level = level }
		end
		vim.g.neovide = nil
	end)

	after_each(function()
		font._run, font._getenv, font._home, font._config_home = orig.run, orig.getenv, orig.home, orig.config_home
		font._is_mac = orig.is_mac
		vim.notify = orig.notify
		vim.g.neovide = orig.neovide
		vim.o.guifont = orig.guifont
		vim.fn.delete(root, "rf")
	end)

	local function include_config()
		write(font._home .. "/.config/ghostty/config.ghostty", "theme = x\n" .. font.include_line() .. "\n")
	end

	it("only ever offers the three documented families", function()
		assert.are.same({ "terminal", "FiraCode Nerd Font", "Maple Mono NF" }, font.FAMILIES)
	end)

	it("the menu's Font row offers exactly font.FAMILIES", function()
		local menu = require("core.menu")
		local row
		for _, r in ipairs(menu._items) do
			if r.key == "font_family" then
				row = r
			end
		end
		assert.is_not_nil(row, "menu exposes its rows")
		assert.are.same(font.FAMILIES, row.values)
	end)

	it("refuses a family outside FAMILIES: nothing written, nothing spawned (no key injection)", function()
		include_config()
		local evil = 'x"\ncommand = /bin/sh'
		assert.is_nil(font.render(evil))
		font.apply(evil)
		assert.are.equal(0, #calls)
		assert.is_nil(read(font.owned_file()))
		assert.are.equal(vim.log.levels.WARN, notes[1].level)
	end)

	it("a relative include in another directory does not count as the owned file", function()
		write(
			font._home .. "/Library/Application Support/com.mitchellh.ghostty/config",
			"config-file = ?nvsinner-font\n"
		)
		assert.is_false((font.includes_owned_file()))
		write(font._home .. "/.config/ghostty/config", "config-file = ?nvsinner-font\n")
		assert.is_true((font.includes_owned_file()), "relative next to the owned file is the owned file")
	end)

	it("ignores a commented-out include and expands ~", function()
		write(font._home .. "/.config/ghostty/config", "# config-file = ?" .. font.owned_file() .. "\n")
		assert.is_false((font.includes_owned_file()))
		font._getenv = function(name)
			return name == "HOME" and font._home or env[name]
		end
		write(font._home .. "/.config/ghostty/config", "config-file = ~/.config/ghostty/nvsinner-font\n")
		assert.is_true((font.includes_owned_file()))
	end)

	it("Neovide: 'terminal' restores the guifont from before NvSinner, keeping fractional sizes", function()
		vim.g.neovide = true
		env = {}
		font._orig_guifont = nil
		vim.o.guifont = "Mine:h13.5"
		font.apply("Maple Mono NF")
		assert.matches(":h13.5", vim.o.guifont, nil, true)
		font.apply("FiraCode Nerd Font")
		font.apply("terminal")
		assert.are.equal("Mine:h13.5", vim.o.guifont)
	end)

	it("renders a reset + the family, and an empty file for 'terminal'", function()
		assert.are.equal('font-family = ""\nfont-family = "Maple Mono NF"\n', font.render("Maple Mono NF"))
		assert.are.equal("", font.render("terminal"))
	end)

	it("writes the owned file and reloads Ghostty for each bundled family", function()
		include_config()
		for _, family in ipairs({ "FiraCode Nerd Font", "Maple Mono NF" }) do
			calls = {}
			font.apply(family)
			assert.are.equal(font.render(family), read(font.owned_file()))
			assert.are.equal(font._config_home .. "/ghostty/nvsinner-font", font.owned_file())
			assert.are.equal(1, #calls)
			assert.are.equal("osascript", calls[1][1])
			assert.matches('perform action "reload_config"', calls[1][3], nil, true)
		end
	end)

	it("says the family applies to all Ghostty windows", function()
		include_config()
		font.apply("Maple Mono NF")
		assert.are.equal(1, #notes)
		assert.matches("all Ghostty windows", notes[1].msg, nil, true)
	end)

	it("'terminal' empties the owned file and still reloads", function()
		include_config()
		font.apply("Maple Mono NF")
		calls = {}
		font.apply("terminal")
		assert.are.equal("", read(font.owned_file()))
		assert.are.equal(1, #calls)
	end)

	it("detects Ghostty via GHOSTTY_RESOURCES_DIR when TERM_PROGRAM is rewritten", function()
		env = { TERM_PROGRAM = "tmux", GHOSTTY_RESOURCES_DIR = "/x" }
		include_config()
		font.apply("Maple Mono NF")
		assert.are.equal(1, #calls)
	end)

	it("never writes outside the owned file (the user's Ghostty config is untouched)", function()
		local cfg = font._home .. "/.config/ghostty/config.ghostty"
		write(cfg, "theme = x\n" .. font.include_line() .. "\n")
		local before = read(cfg)
		font.apply("Maple Mono NF")
		assert.are.equal(before, read(cfg))
		local files = vim.fn.globpath(root, "**/*", false, true)
		for _, f in ipairs(files) do
			if vim.fn.isdirectory(f) == 0 then
				assert.is_true(f == cfg or f == font.owned_file(), "unexpected file written: " .. f)
			end
		end
	end)

	it("shows the exact include line (and the config path) when the config lacks it", function()
		local cfg = font._home .. "/Library/Application Support/com.mitchellh.ghostty/config.ghostty"
		write(cfg, "theme = x\n")
		font.apply("Maple Mono NF")
		assert.are.equal(0, #calls, "no reload until the include exists")
		assert.are.equal(1, #notes)
		assert.are.equal(vim.log.levels.WARN, notes[1].level)
		assert.matches(font.include_line(), notes[1].msg, nil, true)
		assert.matches(cfg, notes[1].msg, nil, true)
		assert.are.equal("theme = x\n", read(cfg), "the config must not be edited")
	end)

	it("recognises a quoted or ?-prefixed include of the owned file", function()
		write(font._home .. "/.config/ghostty/config", 'config-file = "' .. font.owned_file() .. '"\n')
		assert.is_true((font.includes_owned_file()))
	end)

	it("off macOS it writes the file and asks for a manual reload without spawning", function()
		include_config()
		font._is_mac = function()
			return false
		end
		font.apply("Maple Mono NF")
		assert.are.equal(0, #calls)
		assert.are.equal(font.render("Maple Mono NF"), read(font.owned_file()))
		assert.matches("reload", notes[1].msg, nil, true)
	end)

	it("warns once, without throwing, when the reload fails", function()
		include_config()
		font._run = function(cmd, cb)
			calls[#calls + 1] = cmd
			cb(false, "not authorised")
		end
		font.apply("Maple Mono NF")
		assert.are.equal(1, #notes)
		assert.are.equal(vim.log.levels.WARN, notes[1].level)
		assert.matches("not authorised", notes[1].msg, nil, true)
	end)

	it("sets 'guifont' in Neovide and spawns nothing", function()
		vim.g.neovide = true
		env = {}
		vim.o.guifont = ""
		font.apply("Maple Mono NF")
		assert.are.equal(vim.fn.escape("Maple Mono NF", " ,\\"), vim.o.guifont)
		assert.are.equal(0, #calls)
		vim.o.guifont = "Old:h18"
		font.apply("FiraCode Nerd Font")
		assert.matches(":h18", vim.o.guifont, nil, true)
		assert.is_nil(read(font.owned_file()), "Neovide never writes the Ghostty file")
	end)

	it("gives one INFO notice and spawns nothing in any other terminal", function()
		env = { TERM_PROGRAM = "iTerm.app" }
		font.apply("Maple Mono NF")
		assert.are.equal(0, #calls)
		assert.are.equal(1, #notes)
		assert.are.equal(vim.log.levels.INFO, notes[1].level)
		assert.matches("Ghostty and Neovide only", notes[1].msg, nil, true)
		assert.is_nil(read(font.owned_file()))
	end)

	it("boot() only touches 'guifont', and only in Neovide", function()
		vim.o.guifont = ""
		font.boot("Maple Mono NF")
		assert.are.equal("", vim.o.guifont)
		vim.g.neovide = true
		font.boot("terminal")
		assert.are.equal("", vim.o.guifont)
		font.boot("Maple Mono NF")
		assert.are.equal(vim.fn.escape("Maple Mono NF", " ,\\"), vim.o.guifont)
		assert.are.equal(0, #calls)
	end)
end)

describe("bundled fonts", function()
	local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")

	it("ships FiraCode Nerd Font and Maple Mono NF (regular/bold/italic/bold-italic) + the OFL", function()
		for _, f in ipairs({
			"FiraCodeNerdFont-Regular.ttf",
			"MapleMono-NF-Regular.ttf",
			"MapleMono-NF-Bold.ttf",
			"MapleMono-NF-Italic.ttf",
			"MapleMono-NF-BoldItalic.ttf",
			"OFL.txt",
		}) do
			assert.are.equal(1, vim.fn.filereadable(root .. "/fonts/" .. f), f)
		end
	end)

	it("health names both bundled families", function()
		vim.cmd("checkhealth nvsinner")
		local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
		assert.matches("FiraCode Nerd Font", text, nil, true)
		assert.matches("Maple Mono NF", text, nil, true)
	end)
end)
