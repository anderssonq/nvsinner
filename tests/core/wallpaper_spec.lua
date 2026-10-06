-- Tests for the dashboard wallpaper (lua/core/wallpaper.lua): the PPM decoder,
-- the cover-fit sampler, the quantized colour mix, the paint onto a buffer
-- (image glyphs on blank cells, bg-only marks under text, a lone inner space
-- kept as text, pure black as the transparency key), the shipped image, the
-- on/off setting + :NvSinnerWallpaper toggle, and the alpha.draw hook.

-- Palette-dependent: pin the theme so the user's real settings can't leak in.
vim.g.nvsinner_theme = "carbon"

local settings = require("core.settings")
local wallpaper = require("core.wallpaper")

describe("core.wallpaper", function()
	local win, buf

	before_each(function()
		settings.load({ file = vim.fn.tempname() })
		wallpaper._reset()
		vim.o.columns, vim.o.lines = 40, 12
		buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_set_current_buf(buf)
		win = vim.api.nvim_get_current_win()
	end)

	after_each(function()
		pcall(vim.api.nvim_buf_delete, buf, { force = true })
	end)

	local function marks()
		return vim.api.nvim_buf_get_extmarks(buf, wallpaper.ns, 0, -1, { details = true })
	end

	-- A grid of identical ▄ cells sized to the window.
	local function grid(fg, bg)
		local g = {}
		for r = 1, vim.api.nvim_win_get_height(win) do
			g[r] = {}
			for c = 1, vim.api.nvim_win_get_width(win) do
				g[r][c] = { ch = "▄", fg = fg, bg = bg }
			end
		end
		return g
	end

	-- 2×2 PPM: red, green / blue, white (with a header comment).
	local PPM = "P6\n# test\n2 2\n255\n" .. string.char(255, 0, 0, 0, 255, 0) .. string.char(0, 0, 255, 255, 255, 255)

	describe("image", function()
		it("parses a P6 PPM and rejects anything else", function()
			local img = wallpaper.parse_ppm(PPM)
			assert.are.equal(2, img.w)
			assert.are.equal(2, img.h)
			assert.are.equal(12, #img.data)
			assert.is_nil(wallpaper.parse_ppm("P3\n2 2\n255\n0 0 0"))
			assert.is_nil(wallpaper.parse_ppm("P6\n2 2\n255\n" .. "xx")) -- truncated
		end)

		it("samples to any grid size as ▄ half-blocks (bg = top, fg = bottom)", function()
			local g = wallpaper.sample(wallpaper.parse_ppm(PPM), 2, 1)
			assert.are.equal(1, #g)
			assert.are.equal(2, #g[1])
			assert.are.equal("▄", g[1][1].ch)
			-- top-left pixel is red, bottom-left blue
			assert.is_true(g[1][1].bg[1] > 200 and g[1][1].bg[3] < 50)
			assert.is_true(g[1][1].fg[3] > 200 and g[1][1].fg[1] < 50)
			local big = wallpaper.sample(wallpaper.parse_ppm(PPM), 37, 11)
			assert.are.equal(11, #big)
			assert.are.equal(37, #big[11])
		end)

		it("ships the image as a valid, small PPM — no external tool needed", function()
			local p = wallpaper.path()
			assert.is_not_nil(p)
			local fd = assert(io.open(p, "rb"))
			local raw = fd:read("*a")
			fd:close()
			assert.is_true(#raw < 192 * 1024, "the wallpaper is over 192 KB")
			assert.is_not_nil(wallpaper.parse_ppm(raw))
		end)
	end)

	describe("mix", function()
		it("returns base for nil and pulls toward base by strength, quantized", function()
			local base = { 0, 0, 0 }
			assert.are.same({ 0, 0, 0 }, wallpaper.mix(nil, base, 0.5))
			local m = wallpaper.mix({ 200, 100, 50 }, base, 0.5)
			for j = 1, 3 do
				assert.are.equal(0, m[j] % wallpaper.STEP)
			end
			assert.is_true(math.abs(m[1] - 100) <= wallpaper.STEP)
			assert.are.same({ 0, 0, 0 }, wallpaper.mix({ 255, 255, 255 }, base, 0))
		end)
	end)

	describe("paint_grid", function()
		it("puts image glyphs on blank cells and bg-only marks under text", function()
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "   ab cd", "" })
			local h = vim.api.nvim_win_get_height(win)
			wallpaper.paint_grid(win, buf, grid({ 200, 100, 50 }, { 10, 20, 30 }), 0.5)
			-- buffer padded to the window height
			assert.are.equal(h, vim.api.nvim_buf_line_count(buf))
			local virt, hl = 0, {}
			for _, m in ipairs(marks()) do
				local d = m[4]
				if d.virt_text then
					virt = virt + 1
					assert.are.equal("▄", d.virt_text[1][1])
				elseif m[2] == 0 then
					hl[#hl + 1] = m[3]
					assert.is_truthy(d.hl_group:match("^NvWallpaper_x_"))
				end
			end
			assert.is_true(virt >= h) -- at least one image run per row
			-- row 0: a, b, the lone inner space, c, d → 5 bg marks starting at bytes 3..7
			table.sort(hl)
			assert.are.same({ 3, 4, 5, 6, 7 }, hl)
		end)

		it("treats pure black as transparent: no mark at all when both halves are keyed", function()
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
			local g = grid({ 0, 0, 0 }, { 3, 3, 3 })
			-- one visible cell on row 1, col 1: a lit top half over a keyed bottom
			g[1][1] = { ch = "▄", fg = { 0, 0, 0 }, bg = { 200, 200, 200 } }
			wallpaper.paint_grid(win, buf, g, 0.5)
			local all = marks()
			assert.are.equal(1, #all)
			assert.are.equal(0, all[1][4].virt_text_win_col)
			assert.are.equal(1, #all[1][4].virt_text)
		end)

		it("keeps the hover-pill priority above the wallpaper", function()
			assert.is_true(wallpaper.PRIORITY < 1000)
		end)
	end)

	describe("paint + on/off", function()
		it("is on by default and paints the shipped image", function()
			assert.is_true(settings.defaults.wallpaper_on)
			assert.is_true(wallpaper.enabled())
			wallpaper.paint(win, buf)
			assert.is_true(#marks() > 0)
		end)

		it("clears when switched off", function()
			wallpaper.paint(win, buf)
			assert.is_true(#marks() > 0)
			settings.set("wallpaper_on", false)
			wallpaper.paint(win, buf)
			assert.are.equal(0, #marks())
		end)

		it(":NvSinnerWallpaper toggles with no argument and takes on/off", function()
			assert.is_not_nil(vim.api.nvim_get_commands({})["NvSinnerWallpaper"])
			vim.cmd("NvSinnerWallpaper")
			assert.is_false(settings.get("wallpaper_on"))
			vim.cmd("NvSinnerWallpaper")
			assert.is_true(settings.get("wallpaper_on"))
			vim.cmd("NvSinnerWallpaper off")
			assert.is_false(settings.get("wallpaper_on"))
			vim.cmd("NvSinnerWallpaper on")
			assert.is_true(settings.get("wallpaper_on"))
		end)

		it("rejects anything but on/off (no image switching)", function()
			vim.cmd("NvSinnerWallpaper ~/some.png")
			assert.is_true(settings.get("wallpaper_on"))
		end)
	end)

	describe("attach_alpha", function()
		it("repaints after every draw, once wrapped", function()
			local calls = 0
			local fake = {
				draw = function()
					calls = calls + 1
				end,
			}
			local painted = 0
			local orig = wallpaper.paint
			wallpaper.paint = function()
				painted = painted + 1
			end
			wallpaper.attach_alpha(fake)
			wallpaper.attach_alpha(fake) -- idempotent
			fake.draw({}, { windows = { win }, buffer = buf })
			wallpaper.paint = orig
			assert.are.equal(1, calls)
			assert.are.equal(1, painted)
		end)
	end)
end)
