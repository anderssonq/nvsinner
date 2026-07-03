-- Image viewer — "show it" for image files (native, required from init.lua).
--
-- iTerm2 (this config's terminal) uses its own inline-image escape codes, NOT
-- the Kitty graphics protocol that in-buffer image plugins (image.nvim /
-- snacks.image) need, so true inline-in-the-editor rendering isn't practical
-- here. Instead, opening an image is intercepted: the buffer shows a small,
-- non-editable placeholder (icon, filename, dimensions, size) and the image is
-- popped into macOS Quick Look — a fast floating preview that closes with
-- <space>/<esc>. This keeps binary bytes out of the editor and never risks
-- writing the placeholder back over the image.
--
-- Keys inside an image buffer:  <cr> reopen Quick Look · gO open in Preview.app

local M = {}

-- Extensions we treat as images. Kept lowercase; matched case-insensitively.
M.exts = {
	"png",
	"jpg",
	"jpeg",
	"gif",
	"webp",
	"bmp",
	"svg",
	"ico",
	"tiff",
	"tif",
	"heic",
	"heif",
	"avif",
	"jfif",
}

local function human_size(bytes)
	local units = { "B", "KB", "MB", "GB", "TB" }
	local i, n = 1, bytes
	while n >= 1024 and i < #units do
		n = n / 1024
		i = i + 1
	end
	if i == 1 then
		return string.format("%d %s", n, units[i])
	end
	return string.format("%.1f %s", n, units[i])
end

-- Pixel dimensions via macOS `sips` (built-in). Returns w, h or nil.
local function image_dims(path)
	if vim.fn.executable("sips") == 0 then
		return nil
	end
	local out = vim.fn.systemlist({ "sips", "-g", "pixelWidth", "-g", "pixelHeight", path })
	if vim.v.shell_error ~= 0 then
		return nil
	end
	local w, h
	for _, line in ipairs(out) do
		local key, val = line:match("(%w+):%s*(%d+)")
		if key == "pixelWidth" then
			w = tonumber(val)
		elseif key == "pixelHeight" then
			h = tonumber(val)
		end
	end
	if w and h then
		return w, h
	end
end

-- Launch macOS Quick Look on the file (async, non-blocking). qlmanage keeps the
-- process alive until the panel is dismissed; we don't wait on it.
function M.quicklook(path)
	if not path or path == "" then
		return
	end
	if vim.fn.executable("qlmanage") == 0 then
		vim.notify("🖼  Quick Look (qlmanage) not found — macOS only", vim.log.levels.WARN)
		return
	end
	vim.system({ "qlmanage", "-p", path }, { text = false }, function() end)
end

-- Open the file in macOS Preview.app (async, persists as a real window).
function M.preview_app(path)
	if not path or path == "" then
		return
	end
	if vim.fn.executable("open") == 0 then
		vim.notify("🖼  `open` not found — macOS only", vim.log.levels.WARN)
		return
	end
	vim.system({ "open", "-a", "Preview", path }, {}, function() end)
end

-- Paint the placeholder (metadata + key hints) into the image buffer.
local function render(buf)
	local path = vim.b[buf].nv_image_path
	if not path then
		return
	end
	local name = vim.fn.fnamemodify(path, ":t")
	local st = vim.uv.fs_stat(path)
	local size = st and human_size(st.size) or "?"
	local w, h = image_dims(path)
	local dim = (w and h) and string.format("%d × %d", w, h) or "size unknown"
	local ext = (path:match("%.([%w]+)$") or "img"):upper()

	local lines = {
		"",
		"",
		"    🖼  " .. name,
		"",
		"    " .. dim .. " · " .. size .. " · " .. ext,
		"",
		"    Shown in macOS Quick Look.",
		"",
		"    <cr>  reopen in Quick Look",
		"    gO    open in Preview.app",
		"",
	}
	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
	vim.bo[buf].modified = false
end

function M.setup()
	local aug = vim.api.nvim_create_augroup("NvImageOpen", { clear = true })

	-- One pattern per extension, both cases (BufReadCmd patterns aren't regex).
	local patterns = {}
	for _, e in ipairs(M.exts) do
		patterns[#patterns + 1] = "*." .. e
		patterns[#patterns + 1] = "*." .. e:upper()
	end

	-- Take over the read: never load the binary into the buffer.
	vim.api.nvim_create_autocmd("BufReadCmd", {
		group = aug,
		pattern = patterns,
		callback = function(ev)
			local buf = ev.buf
			local path = vim.api.nvim_buf_get_name(buf)
			-- `nofile` so `:w` can't overwrite the image with placeholder text.
			vim.bo[buf].buftype = "nofile"
			vim.bo[buf].swapfile = false
			vim.b[buf].nv_image_path = path
			render(buf)
			-- Setting filetype last fires the FileType autocmd below (keys + QL).
			vim.bo[buf].filetype = "nvsinner_image"
		end,
	})

	vim.api.nvim_create_autocmd("FileType", {
		group = aug,
		pattern = "nvsinner_image",
		callback = function(ev)
			local buf = ev.buf
			vim.keymap.set("n", "<cr>", function()
				M.quicklook(vim.b[buf].nv_image_path)
			end, { buffer = buf, silent = true, desc = "Preview image (Quick Look)" })
			vim.keymap.set("n", "gO", function()
				M.preview_app(vim.b[buf].nv_image_path)
			end, { buffer = buf, silent = true, desc = "Open image in Preview.app" })

			-- Auto-pop Quick Look on a genuine interactive open only: skip headless
			-- and skip floating previews (telescope's preview window is floating).
			if #vim.api.nvim_list_uis() == 0 or vim.b[buf].nv_image_previewed then
				return
			end
			local path = vim.b[buf].nv_image_path
			if not (path and vim.uv.fs_stat(path)) then
				return
			end
			vim.schedule(function()
				local win = vim.fn.bufwinid(buf)
				if win ~= -1 and vim.api.nvim_win_get_config(win).relative == "" then
					vim.b[buf].nv_image_previewed = true
					M.quicklook(path)
				end
			end)
		end,
	})
end

M.setup()

return M
