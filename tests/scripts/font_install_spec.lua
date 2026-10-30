-- Font steps of install.sh / uninstall.sh, run in a temp HOME with
-- NVSINNER_FONT_DIR. The `>>> fonts` .. `<<< fonts` blocks are extracted from
-- the real scripts (so the spec tests the shipped code, not a copy), their
-- bare trailing call lines are dropped, and the functions are driven from bash.
-- Never touches the real HOME, Ghostty config or font directories.

describe("install.sh / uninstall.sh font steps", function()
	local repo = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")
	local root, home, fontdir, data

	local function extract(script)
		local lines, on = {}, false
		for line in io.lines(repo .. "/" .. script) do
			if line:find("<<< fonts", 1, true) then
				on = false
			end
			if on and line ~= "install_fonts" and line ~= "offer_ghostty_include" then
				lines[#lines + 1] = line
			end
			if line:find(">>> fonts", 1, true) then
				on = true
			end
		end
		return table.concat(lines, "\n")
	end

	local function write(path, text)
		vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
		local fd = assert(io.open(path, "wb"))
		fd:write(text)
		fd:close()
	end

	local function read(path)
		local fd = io.open(path, "rb")
		if not fd then
			return nil
		end
		local s = fd:read("*a")
		fd:close()
		return s
	end

	-- Run `body` in bash with the extracted script block + a sandboxed env.
	local function run(script, body, env)
		local prelude = table.concat({
			"set -euo pipefail",
			"info() { :; }; ok() { :; }; warn() { :; }",
			'CONFIG_DIR="' .. repo .. '"',
			'DATA_DIR="' .. data .. '"',
			'FONT_DIR="' .. fontdir .. '"',
			'FONT_MANIFEST="' .. data .. '/installed-fonts.txt"',
			'GHOSTTY_MARK="' .. data .. '/ghostty-include.txt"',
			'GHOSTTY_FONT_FILE="' .. home .. '/.config/ghostty/nvsinner-font"',
			extract(script),
			body,
		}, "\n")
		local file = root .. "/run.sh"
		write(file, prelude)
		local envs = { "HOME=" .. home, "XDG_CONFIG_HOME=" .. home .. "/.config", "NVSINNER_FONT_DIR=" .. fontdir }
		for k, v in pairs(env or {}) do
			envs[#envs + 1] = k .. "=" .. v
		end
		local cmd = { "env", "-u", "NVSINNER_INCLUDE_ANSWER" }
		vim.list_extend(cmd, envs)
		vim.list_extend(cmd, { "bash", file })
		local out = vim.fn.system(cmd, "")
		return vim.v.shell_error, out
	end

	local function ttfs()
		local names = {}
		for _, f in ipairs(vim.fn.glob(repo .. "/fonts/*.ttf", false, true)) do
			names[#names + 1] = vim.fn.fnamemodify(f, ":t")
		end
		return names
	end

	before_each(function()
		root = vim.fn.tempname()
		home = root .. "/home"
		fontdir = root .. "/fonts"
		data = home .. "/.local/share/nvsinner"
		vim.fn.mkdir(home, "p")
	end)

	after_each(function()
		vim.fn.delete(root, "rf")
	end)

	it("copies every bundled .ttf and records exactly those in the manifest", function()
		local code, out = run("install.sh", "install_fonts")
		assert.are.equal(0, code, out)
		local names = ttfs()
		assert.is_true(#names >= 7)
		local manifest = {}
		for line in (read(data .. "/installed-fonts.txt") or ""):gmatch("[^\n]+") do
			manifest[#manifest + 1] = line
		end
		assert.are.equal(#names, #manifest)
		for _, n in ipairs(names) do
			assert.are.equal(1, vim.fn.filereadable(fontdir .. "/" .. n), n)
			assert.is_true(vim.tbl_contains(manifest, fontdir .. "/" .. n))
		end
	end)

	it("skips a pre-existing font, leaves it untouched and does not list it", function()
		local first = ttfs()[1]
		write(fontdir .. "/" .. first, "MINE")
		local code, out = run("install.sh", "install_fonts")
		assert.are.equal(0, code, out)
		assert.are.equal("MINE", read(fontdir .. "/" .. first))
		assert.is_nil(read(data .. "/installed-fonts.txt"):find(first, 1, true))
	end)

	it("uninstall removes only manifest files, never a font the user already had", function()
		local first = ttfs()[1]
		write(fontdir .. "/" .. first, "MINE")
		write(fontdir .. "/Other.ttf", "OTHER")
		assert.are.equal(0, (run("install.sh", "install_fonts")))
		local code, out = run("uninstall.sh", "cleanup_fonts")
		assert.are.equal(0, code, out)
		assert.are.equal("MINE", read(fontdir .. "/" .. first))
		assert.are.equal("OTHER", read(fontdir .. "/Other.ttf"))
		for _, n in ipairs(ttfs()) do
			if n ~= first then
				assert.are.equal(0, vim.fn.filereadable(fontdir .. "/" .. n), n)
			end
		end
	end)

	it("the include offer prints a hint when no Ghostty config exists, and writes nothing", function()
		local code, out = run("install.sh", "info() { printf '%s\\n' \"$1\"; }; offer_ghostty_include")
		assert.are.equal(0, code, out)
		assert.matches("config-file = ?", out, nil, true)
		assert.are.equal(0, vim.fn.isdirectory(home .. "/.config/ghostty"))
	end)

	it("a commented-out nvsinner-font line does not count as included", function()
		local cfg = home .. "/.config/ghostty/config"
		write(cfg, "# config-file = ?/x/nvsinner-font\ntheme = x\n")
		local code, out = run("install.sh", "offer_ghostty_include", { NVSINNER_INCLUDE_ANSWER = "y" })
		assert.are.equal(0, code, out)
		assert.matches("config-file = ?" .. home .. "/.config/ghostty/nvsinner-font", read(cfg), nil, true)
	end)

	it("EOF on the prompt does not abort (read || reply='')", function()
		local cfg = home .. "/.config/ghostty/config"
		write(cfg, "theme = x\n")
		-- No tty under busted, so drive the read directly with the same idiom.
		local code = run("install.sh", 'read -r reply < /dev/null || reply=""; [ -z "$reply" ]')
		assert.are.equal(0, code)
		assert.matches("read %-r reply || reply=", read(repo .. "/install.sh"))
		assert.matches("read %-r reply || reply=", read(repo .. "/uninstall.sh"))
	end)

	it("uninstall removes the include line AND its blank separator, nothing else", function()
		local cfg = home .. "/.config/ghostty/config"
		local original = "theme = x\n\nfont-size = 13\n\n"
		write(cfg, original)
		local code, out = run("install.sh", "offer_ghostty_include", { NVSINNER_INCLUDE_ANSWER = "y" })
		assert.are.equal(0, code, out)
		assert.are_not.equal(original, read(cfg))
		code, out = run("uninstall.sh", "cleanup_fonts")
		assert.are.equal(0, code, out)
		assert.are.equal(original, read(cfg))
	end)

	it("uninstall leaves the config alone when the installer recorded nothing", function()
		local cfg = home .. "/.config/ghostty/config"
		local text = "theme = x\nconfig-file = ?" .. home .. "/.config/ghostty/nvsinner-font\n"
		write(cfg, text)
		local code, out = run("uninstall.sh", "cleanup_fonts")
		assert.are.equal(0, code, out)
		assert.are.equal(text, read(cfg))
	end)

	it("uninstall cleans the owned font file even with no other state (the early-exit path)", function()
		write(home .. "/.config/ghostty/nvsinner-font", 'font-family = "x"\n')
		local code, out = run("uninstall.sh", "cleanup_fonts")
		assert.are.equal(0, code, out)
		assert.are.equal(0, vim.fn.filereadable(home .. "/.config/ghostty/nvsinner-font"))
		-- and the script really calls it before the "Nothing to remove" exit
		local src = read(repo .. "/uninstall.sh")
		local call = src:find("cleanup_fonts\n  if [ ${#kept", 1, true) or src:find("  cleanup_fonts\n", 1, true)
		local early = src:find("Nothing to remove", 1, true)
		assert.is_truthy(call)
		assert.is_true(call < early)
	end)
end)
