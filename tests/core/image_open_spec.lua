-- Tests for the image viewer (lua/core/image-open.lua).
--
-- A valid 1x1 PNG is written to a temp file and :edit'd; the BufReadCmd should
-- replace the binary with the metadata placeholder and guard the buffer against
-- writes. Running headless, the auto-preview must NOT fire (no qlmanage spawn).
-- The inline preview (half-block extmarks via macOS `sips`) is exercised for
-- real when `sips` is executable and skipped otherwise; the fallbacks (heic, the
-- "quicklook" setting, a file `sips` can't decode) and the cache key are pure.

describe("core.image-open", function()
	require("core.image-open") -- self-registers its augroup on require

	-- Minimal valid 1x1 PNG (base64), decoded to a temp .png.
	local function make_png()
		local b64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
		local path = vim.fn.tempname() .. ".png"
		local bytes = vim.base64.decode(b64)
		local fd = assert(io.open(path, "wb"))
		fd:write(bytes)
		fd:close()
		return path
	end

	it("registers a BufReadCmd for image extensions", function()
		local aus = vim.api.nvim_get_autocmds({ group = "NvImageOpen", event = "BufReadCmd" })
		assert.is_true(#aus > 0)
	end)

	it("replaces an opened image with a non-writable placeholder", function()
		local path = make_png()
		vim.cmd("edit " .. vim.fn.fnameescape(path))

		assert.equals("nvsinner_image", vim.bo.filetype)
		-- nofile so :w can't overwrite the image with the placeholder text.
		assert.equals("nofile", vim.bo.buftype)
		assert.is_false(vim.bo.modifiable)
		-- Compare basenames: macOS resolves /var -> /private/var, so the buffer's
		-- real name won't be byte-equal to the unresolved tempname().
		assert.equals(vim.fn.fnamemodify(path, ":t"), vim.fn.fnamemodify(vim.b.nv_image_path, ":t"))

		local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
		assert.matches(vim.fn.fnamemodify(path, ":t"), text) -- filename shown
		assert.matches("Quick Look", text) -- key hints shown

		-- <cr> and gO are bound buffer-locally in the placeholder.
		assert.equals(1, vim.fn.maparg("<cr>", "n", false, true).buffer)
		assert.equals(1, vim.fn.maparg("gO", "n", false, true).buffer)

		vim.cmd("bwipeout!")
		os.remove(path)
	end)

	it("does not auto-preview headlessly (no b: previewed flag set)", function()
		-- Headless has no UIs, so the FileType handler must bail before spawning
		-- Quick Look; it only sets nv_image_previewed on a real interactive pop.
		local path = make_png()
		vim.cmd("edit " .. vim.fn.fnameescape(path))
		vim.wait(50)
		assert.is_nil(vim.b.nv_image_previewed)
		vim.cmd("bwipeout!")
		os.remove(path)
	end)

	describe("inline preview", function()
		local image_open = require("core.image-open")
		local settings = require("core.settings")
		local have_sips = vim.fn.executable("sips") == 1
		local created = {}

		before_each(function()
			settings.load({ file = vim.fn.tempname() }) -- never touch the user's real settings
			vim.o.columns, vim.o.lines = 80, 24
		end)

		after_each(function()
			vim.cmd("silent! %bwipeout!")
			for _, f in ipairs(created) do
				os.remove(f)
			end
			created = {}
		end)

		local function tmp(ext, bytes)
			local path = vim.fn.tempname() .. ext
			local fd = assert(io.open(path, "wb"))
			fd:write(bytes)
			fd:close()
			created[#created + 1] = path
			return path
		end

		local function lines()
			return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
		end

		local function marks(buf)
			return vim.api.nvim_buf_get_extmarks(buf, image_open.ns, 0, -1, { details = true })
		end

		it("opens svg as its source code (text, never intercepted)", function()
			local src = "<svg xmlns='http://www.w3.org/2000/svg'/>"
			local path = tmp(".svg", src)
			vim.cmd("edit " .. vim.fn.fnameescape(path))
			local buf = vim.api.nvim_get_current_buf()
			assert.are.same({ src }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
			assert.are.equal("", vim.bo[buf].buftype, "a real, writable file buffer")
			assert.is_nil(vim.b[buf].nv_image_inline)
			assert.is_nil(image_open._state(buf))
			assert.are.equal(0, #marks(buf))
		end)

		it("never attempts heic/heif inline (placeholder fallback)", function()
			assert.is_false(image_open.inline_possible(tmp(".heic", "x")))
			assert.is_false(image_open.inline_possible(tmp(".heif", "x")))
		end)

		it("falls back to the placeholder when image_preview is quicklook", function()
			settings.set("image_preview", "quicklook")
			assert.are.equal("quicklook", image_open.mode())
			local path = tmp(".png", "x")
			assert.is_false(image_open.inline_possible(path))
			vim.cmd("edit " .. vim.fn.fnameescape(path))
			assert.matches("Shown in macOS Quick Look", lines())
			assert.is_false(vim.b.nv_image_inline)
		end)

		it("defaults to inline and rejects unknown values", function()
			assert.are.equal("inline", image_open.mode())
			settings.set("image_preview", "bogus")
			assert.are.equal("inline", image_open.mode())
		end)

		it("keys the cache by path, mtime and size", function()
			local st = { mtime = { sec = 10, nsec = 5 }, size = 100 }
			local a = image_open.cache_path("/a.png", st)
			assert.are.equal(a, image_open.cache_path("/a.png", vim.deepcopy(st)))
			assert.matches("/nvsinner/img/%x+%.bmp$", a)
			assert.are_not.equal(a, image_open.cache_path("/b.png", st))
			assert.are_not.equal(a, image_open.cache_path("/a.png", { mtime = { sec = 11, nsec = 5 }, size = 100 }))
			assert.are_not.equal(a, image_open.cache_path("/a.png", { mtime = { sec = 10, nsec = 5 }, size = 101 }))
		end)

		it("paints the image as half-block extmarks under the header (real sips)", function()
			if not have_sips then
				return pending("sips not available")
			end
			local path = vim.fn.getcwd() .. "/assets/dashboard.png"
			vim.cmd("edit " .. vim.fn.fnameescape(path))
			local buf = vim.api.nvim_get_current_buf()
			assert.is_true(vim.b.nv_image_inline)
			assert.is_true(vim.wait(10000, function()
				local st = image_open._state(buf)
				return st and st.img ~= nil
			end, 20))
			local m = marks(buf)
			assert.is_true(#m > 0)
			local header = image_open._state(buf).header
			local win = vim.api.nvim_get_current_win()
			local info = vim.fn.getwininfo(win)[1]
			for _, mark in ipairs(m) do
				assert.is_true(mark[2] >= header) -- never over the metadata header
				assert.is_true(mark[2] < info.height) -- never past the window
				assert.are.equal("▄", mark[4].virt_text[1][1]:sub(1, 3))
			end
			assert.matches("dashboard.png", lines()) -- header kept
			-- Cached: the BMP now exists next to the key.
			local st = vim.uv.fs_stat(path)
			assert.is_not_nil(vim.uv.fs_stat(image_open.cache_path(path, st)))
			-- Wiping the buffer drops the state.
			vim.cmd("bwipeout!")
			assert.is_nil(image_open._state(buf))
		end)

		it("repaints on resize (fit follows the window)", function()
			if not have_sips then
				return pending("sips not available")
			end
			vim.cmd("edit " .. vim.fn.fnameescape(vim.fn.getcwd() .. "/assets/dashboard.png"))
			local buf = vim.api.nvim_get_current_buf()
			assert.is_true(vim.wait(10000, function()
				local st = image_open._state(buf)
				return st and st.img ~= nil
			end, 20))
			local before = image_open._state(buf).key
			vim.o.columns, vim.o.lines = 40, 12
			image_open.paint(buf)
			assert.are_not.equal(before, image_open._state(buf).key)
			assert.is_true(#marks(buf) > 0)
		end)

		it("falls back to the placeholder when sips cannot decode the file", function()
			if not have_sips then
				return pending("sips not available")
			end
			local path = tmp(".png", "this is not a png")
			vim.cmd("edit " .. vim.fn.fnameescape(path))
			local buf = vim.api.nvim_get_current_buf()
			assert.is_true(vim.wait(10000, function()
				return vim.b[buf].nv_image_inline == false
			end, 20))
			assert.matches("Shown in macOS Quick Look", lines())
			assert.is_nil(image_open._state(buf))
		end)
	end)
end)
