-- Tests for the image viewer (lua/core/image-open.lua).
--
-- A valid 1x1 PNG is written to a temp file and :edit'd; the BufReadCmd should
-- replace the binary with the metadata placeholder and guard the buffer against
-- writes. Running headless, the auto-preview must NOT fire (no qlmanage spawn).

describe("core.image-open", function()
	require("core.image-open") -- self-registers its augroup on require

	-- Minimal valid 1x1 PNG (base64), decoded to a temp .png.
	local function make_png()
		local b64 =
			"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
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
end)
