-- Tests for the native code minimap (lua/core/minimap.lua): the pure braille
-- encoder (2 source columns x 4 source lines per cell, display columns, clip
-- past SPAN), the slice math that decides which part of the file is mapped,
-- the host-window eligibility guards, the pane's float config, the viewport /
-- cursor bands, and the settings write-through that keeps :NvSinnerMinimap and
-- the :NvSinnerMenu row in agreement.

local minimap = require("core.minimap")
local settings = require("core.settings")

describe("core.minimap", function()
	local path

	-- Codepoints of a rendered row — clearer to assert than braille literals.
	local function points(row)
		return vim.fn.str2list(row)
	end

	local function open_file(lines)
		path = vim.fn.tempname() .. "_minimap.lua"
		vim.fn.writefile(lines, path)
		vim.cmd("edit " .. vim.fn.fnameescape(path))
		return vim.api.nvim_get_current_buf()
	end

	before_each(function()
		minimap._reset()
		-- The host must clear MIN_WIDTH/MIN_HEIGHT for the pane to show.
		vim.o.columns = 140
		vim.o.lines = 40
	end)

	after_each(function()
		minimap._reset()
		if path then
			pcall(vim.cmd, "bwipeout!")
			os.remove(path)
			path = nil
		end
	end)

	-- ─── The encoder ─────────────────────────────────────────────────────────

	it("renders blank lines as blank braille cells", function()
		local rows = minimap._encode({ "", "", "", "" }, { width = 3, span = 6, per = 4 })
		assert.are.equal(1, #rows, "four source lines pack into one row")
		assert.are.same({ 0x2800, 0x2800, 0x2800 }, points(rows[1]))
	end)

	it("places a character in the cell its display column falls in", function()
		-- span == width * 2 → one source column per dot column.
		local rows = minimap._encode({ "a" }, { width = 2, span = 4, per = 4 })
		assert.are.same({ 0x2801, 0x2800 }, points(rows[1]), "column 0 is the top-left dot")

		rows = minimap._encode({ "  a" }, { width = 2, span = 4, per = 4 })
		assert.are.same({ 0x2800, 0x2801 }, points(rows[1]), "indentation moves the dot right")
	end)

	it("packs four source lines into the four dot rows of one cell", function()
		local rows = minimap._encode({ "a", "a", "a", "a" }, { width = 1, span = 2, per = 4 })
		assert.are.equal(1, #rows)
		-- dots 1+2+3+7 = 0x01|0x02|0x04|0x40
		assert.are.same({ 0x2800 + 0x47 }, points(rows[1]))
	end)

	it("lights two dot rows per source line at the default vertical zoom", function()
		assert.are.equal(2, minimap.ROWS_PER_CELL, "the measured default: 4 smears, 2 stays legible")
		local rows = minimap._encode({ "a", "a" }, { width = 1, span = 2, per = 2 })
		assert.are.equal(1, #rows)
		-- line 1 lights dots 1+2, line 2 lights dots 3+7 — a full left column.
		assert.are.same({ 0x2800 + 0x47 }, points(rows[1]))
	end)

	it("expands tabs to display columns", function()
		local rows = minimap._encode({ "\tx" }, { width = 4, span = 8, tabstop = 4, per = 4 })
		assert.are.same({ 0x2800, 0x2800, 0x2801, 0x2800 }, points(rows[1]), "the tab is 4 display columns")
	end)

	it("clips past SPAN instead of clamping onto the last column", function()
		-- "abc" with two dot columns: 'c' falls outside and must vanish, or the
		-- right edge would read as a solid bar in any file with long lines.
		local rows = minimap._encode({ "abc" }, { width = 1, span = 2, per = 4 })
		assert.are.same({ 0x2800 + 0x09 }, points(rows[1]), "only the first two columns survive")
	end)

	it("emits rows of exactly WIDTH cells", function()
		local rows = minimap._encode({ "x", "y", "z", "w", "v" }, { width = 7, span = 14, per = 4 })
		assert.are.equal(2, #rows)
		for _, row in ipairs(rows) do
			assert.are.equal(7, vim.fn.strchars(row))
		end
	end)

	-- ─── The slice ───────────────────────────────────────────────────────────

	it("maps the whole file when it fits the pane", function()
		assert.are.equal(1, minimap._slice(30, 1, 24, 10, 4), "30 lines fit in 10 rows x 4")
	end)

	it("centres the viewport in the slice and clamps at both ends", function()
		assert.are.equal(492, minimap._slice(1000, 500, 523, 10, 4), "viewport centred in the 40-line slice")
		assert.are.equal(1, minimap._slice(1000, 1, 24, 10, 4), "clamped at the top of the file")
		assert.are.equal(961, minimap._slice(1000, 990, 1000, 10, 4), "clamped at the bottom")
	end)

	-- ─── Guards ──────────────────────────────────────────────────────────────

	it("refuses floats, special buffers, denylisted filetypes and small windows", function()
		open_file({ "local a = 1" })
		local host = vim.api.nvim_get_current_win()
		assert.is_true(minimap._eligible(host))

		local float = vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), false, {
			relative = "editor",
			width = 40,
			height = 20,
			row = 1,
			col = 1,
		})
		assert.is_false(minimap._eligible(float), "floats are never hosts")
		vim.api.nvim_win_close(float, true)

		vim.bo[vim.api.nvim_get_current_buf()].buftype = "nofile"
		assert.is_false(minimap._eligible(host), "only real file buffers get a map")
		vim.bo[vim.api.nvim_get_current_buf()].buftype = ""

		vim.bo[vim.api.nvim_get_current_buf()].filetype = "neo-tree"
		assert.is_false(minimap._eligible(host), "denylisted filetype")
		vim.bo[vim.api.nvim_get_current_buf()].filetype = "lua"

		vim.cmd("vsplit")
		vim.api.nvim_win_set_width(0, minimap.MIN_WIDTH - 10)
		assert.is_false(minimap._eligible(0), "too narrow to give up columns to a map")
		vim.cmd("close")
	end)

	it("costs one boolean while it is off", function()
		open_file({ "local a = 1" })
		minimap.refresh()
		assert.is_nil(minimap._win(), "no pane, no timer, nothing drawn while off")
	end)

	-- ─── The pane ────────────────────────────────────────────────────────────

	it("opens one non-focusable float anchored to the host window", function()
		open_file({ "local a = 1", "local b = 2" })
		local host = vim.api.nvim_get_current_win()
		minimap.enable()

		local pane = minimap._win()
		assert.is_true(pane ~= nil and vim.api.nvim_win_is_valid(pane))
		local cfg = vim.api.nvim_win_get_config(pane)
		assert.are.equal("win", cfg.relative)
		assert.are.equal(minimap.WIDTH, cfg.width)
		assert.are.equal(minimap.ZINDEX, cfg.zindex, "must stay under core/backdrop.lua's dimming layer")
		assert.is_false(cfg.focusable, "it must never join <C-w> cycling or the window picker")
		assert.are.equal(
			vim.api.nvim_win_get_width(host) - minimap.WIDTH - minimap.GUTTER,
			cfg.col,
			"a gutter is left at the edge for satellite's bar"
		)
		assert.are.equal("nvsinner-minimap", vim.bo[vim.api.nvim_win_get_buf(pane)].filetype)

		-- The same predicate diffview/neo-tree use to find an editable window
		-- must never offer the pane.
		assert.is_false(require("core.window-picker")._editable(pane))

		minimap.disable()
		assert.is_nil(minimap._win(), "disable closes the pane")
	end)

	it("hides the pane when focus lands somewhere ineligible", function()
		open_file({ "local a = 1" })
		minimap.enable()
		assert.is_not_nil(minimap._win())

		local scratch = vim.api.nvim_create_buf(false, true)
		vim.cmd("split")
		vim.api.nvim_win_set_buf(0, scratch)
		minimap.refresh()
		assert.is_nil(minimap._win(), "a scratch/terminal pane gets no map")
		vim.cmd("close")
	end)

	it("survives a transient float instead of tearing itself down", function()
		open_file({ "local a = 1", "local b = 2" })
		local host = vim.api.nvim_get_current_win()
		minimap.enable()
		local pane = minimap._win()

		-- A cmdline / telescope / hover float is not a code window, but the map
		-- belongs to the editor group: measured in a PTY, hiding here meant
		-- every ":" command killed the pane for good.
		local float = vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), false, {
			relative = "editor",
			width = 30,
			height = 5,
			row = 1,
			col = 1,
		})
		minimap.refresh(float)
		assert.are.equal(pane, minimap._win(), "the pane stays on its host")
		assert.are.equal(host, vim.api.nvim_win_get_config(minimap._win()).win)
		vim.api.nvim_win_close(float, true)
	end)

	it("bands the viewport and the cursor's row", function()
		local lines = {}
		for i = 1, 600 do
			lines[i] = ("x"):rep(i % 40)
		end
		open_file(lines)
		local host = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_cursor(host, { 300, 0 })
		vim.cmd("normal! zz")
		minimap.enable()

		local pbuf = vim.api.nvim_win_get_buf(minimap._win())
		local groups = {}
		for _, m in ipairs(vim.api.nvim_buf_get_extmarks(pbuf, minimap._ns, 0, -1, { details = true })) do
			groups[m[4].line_hl_group] = (groups[m[4].line_hl_group] or 0) + 1
		end
		assert.are.equal(1, groups.NvMinimapCursor, "exactly one row carries the cursor")
		assert.is_true((groups.NvMinimapView or 0) > 0, "the viewport band must be drawn")
		assert.are.equal(
			vim.fn.getwininfo(host)[1].height,
			vim.api.nvim_buf_line_count(pbuf),
			"the pane is exactly as tall as its host's TEXT area"
		)
	end)

	it("colors the map from carbon roles", function()
		local theme = vim.g.nvsinner_theme
		vim.g.nvsinner_theme = "carbon" -- specs must not depend on the user's real settings
		local c = require("core.carbon").colors()
		vim.api.nvim_exec_autocmds("ColorScheme", { pattern = "*" })

		local function fg(name)
			return vim.api.nvim_get_hl(0, { name = name }).fg
		end
		assert.are.equal(tonumber(c.base03:sub(2), 16), fg("NvMinimap"))
		assert.are.equal(tonumber(c.base04:sub(2), 16), fg("NvMinimapView"))
		assert.are.equal(tonumber(c.base09:sub(2), 16), fg("NvMinimapCursor"))
		vim.g.nvsinner_theme = theme
	end)

	-- ─── Height: never over the statusline ───────────────────────────────────

	it("sizes itself from the text area, not the winbar-inclusive height", function()
		open_file({ "local a = 1", "local b = 2" })
		local host = vim.api.nvim_get_current_win()
		vim.wo[host].winbar = "%#Normal#badge" -- core/filebadge puts one on every code window
		minimap.enable()

		local text_rows = vim.fn.getwininfo(host)[1].height
		assert.are.equal(
			text_rows,
			vim.api.nvim_win_get_config(minimap._win()).height,
			"nvim_win_get_height() counts the winbar row; a pane sized from it covers the statusline"
		)
		assert.is_true(text_rows < vim.api.nvim_win_get_height(host), "the winbar row is the difference")
		vim.wo[host].winbar = ""
	end)

	-- ─── Click to jump ───────────────────────────────────────────────────────

	it("maps a click on the pane back to a source line", function()
		local lines = {}
		for i = 1, 400 do
			lines[i] = "local x" .. i
		end
		open_file(lines)
		minimap.enable()
		local pane = minimap._win()
		local pos = vim.fn.win_screenpos(pane)

		-- First row of the pane → the first source line of the rendered slice.
		local top = minimap._clicked_line({ screenrow = pos[1], screencol = pos[2] })
		assert.is_number(top)
		local third = minimap._clicked_line({ screenrow = pos[1] + 2, screencol = pos[2] + 3 })
		assert.are.equal(top + 2 * minimap.ROWS_PER_CELL, third, "each row covers ROWS_PER_CELL lines")

		-- Off the pane in both axes → nil, so the click falls through to Vim.
		assert.is_nil(minimap._clicked_line({ screenrow = pos[1], screencol = pos[2] - 1 }))
		assert.is_nil(minimap._clicked_line({ screenrow = pos[1] + 1000, screencol = pos[2] }))
	end)

	it("jumps the host window to the clicked line and re-centres it", function()
		local lines = {}
		for i = 1, 400 do
			lines[i] = "local x" .. i
		end
		open_file(lines)
		local host = vim.api.nvim_get_current_win()
		minimap.enable()

		minimap.jump(250)
		assert.are.equal(250, vim.api.nvim_win_get_cursor(host)[1])
		assert.is_true(vim.fn.line("w0", host) < 250, "zz centres the target instead of pinning it to the top")
		minimap.jump(100000)
		assert.are.equal(400, vim.api.nvim_win_get_cursor(host)[1], "clamped to the last line")
	end)

	it("installs the global click maps only while it is on", function()
		open_file({ "local a = 1" })
		local function mapped(key)
			local m = vim.fn.maparg(key, "n", false, true)
			return type(m) == "table" and next(m) ~= nil
		end
		for _, m in ipairs(minimap.MOUSE_KEYS) do
			assert.is_false(mapped(m.key), "off costs nothing, not even a mouse map: " .. m.key)
		end
		minimap.enable()
		for _, m in ipairs(minimap.MOUSE_KEYS) do
			assert.is_true(mapped(m.key), m.key .. " must be claimed while the map is up")
			assert.are.equal(1, vim.fn.maparg(m.key, "n", false, true).expr, "expr, so it can fall through")
		end
		minimap.disable()
		for _, m in ipairs(minimap.MOUSE_KEYS) do
			assert.is_false(mapped(m.key), "disable hands " .. m.key .. " back to Vim")
		end
	end)

	-- The PRESS must be claimed, not only the release: unmapped, Vim's builtin
	-- moves the cursor to the text under the pane before the release lands.
	it("claims the press as well as the release", function()
		local keys = {}
		for _, m in ipairs(minimap.MOUSE_KEYS) do
			keys[m.key] = m.jump
		end
		assert.is_true(keys["<LeftMouse>"], "the press jumps")
		assert.is_true(keys["<LeftDrag>"], "a sweep scrubs")
		assert.is_false(keys["<LeftRelease>"], "the release only swallows — the press already jumped")
	end)

	-- ─── Settings write-through ──────────────────────────────────────────────

	it("is driven by the persisted setting, so the menu and the command agree", function()
		settings.load({ file = vim.fn.tempname() })
		open_file({ "local a = 1" })
		assert.is_false(settings.get("minimap"), "off by default — the pane covers text")

		settings.set("minimap", true)
		assert.is_true(minimap.on)
		assert.is_not_nil(minimap._win(), "the applier opens the pane")

		minimap.toggle()
		assert.is_false(minimap.on)
		assert.is_false(settings.get("minimap"), "the command writes through settings")
		assert.is_nil(minimap._win())
	end)
end)
