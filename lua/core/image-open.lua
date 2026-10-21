-- Image viewer — "show it" for image files (native, required from init.lua).
--
-- Opening an image is intercepted: the binary never reaches the buffer. By
-- default (setting `image_preview = "inline"`) the picture is painted INSIDE the
-- buffer as `▄` half-block extmarks, reusing lua/core/wallpaper.lua's pipeline
-- (see .claude/skills/nvsinner-image-rendering): macOS `sips` converts any
-- supported image to a small BMP in the cache (async), wallpaper.parse_bmp
-- decodes it, and it is contain-fitted (never cropped), centred, under a short
-- metadata header, at full strength and without the black-is-transparent key.
--
-- SVG is NOT intercepted: it is text (XML), so it opens as its source code.
--
-- Anything the inline path can't do — heic/heif, no `sips`, a `sips` failure,
-- an undecodable result, or `image_preview = "quicklook"` — falls back to the
-- text placeholder (icon, filename, dimensions, size) and macOS Quick Look
-- (closes with <space>/<esc>). The buffer is `nofile`, so `:w` can never write
-- the placeholder back over the image.
--
-- Keys inside an image buffer:  <cr> Quick Look · gO open in Preview.app

local M = {}

-- Extensions we treat as images. Kept lowercase; matched case-insensitively.
M.exts = {
	"png",
	"jpg",
	"jpeg",
	"gif",
	"webp",
	"bmp",
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

-- ─── Inline preview ──────────────────────────────────────────────────────────

M.ns = vim.api.nvim_create_namespace("nvsinner_image_preview")
M.PRIORITY = 10
M.MAXPX = 640 -- sips pre-scales to this longest side, so Lua never resamples a 4K photo
M.STEP = 12 -- colour quantization: bounds the NvWallpaper_* highlight groups a photo creates
M.MAX_GROUPS = 3000 -- a paint using more distinct groups is repainted with a coarser step
M.DEBOUNCE_MS = 60
M.NO_INLINE = { heic = true, heif = true } -- formats sips can't be trusted with here

-- buf → { img = parsed BMP, key = last sample key, px = last resample }
local states = {}

local function ext_of(path)
	return (path:match("%.([%w]+)$") or ""):lower()
end

local function cache_dir()
	return vim.fn.stdpath("cache") .. "/nvsinner/img"
end

-- Cache file for `path`: keyed by path + mtime + size, so an edited image never
-- serves a stale decode. `st` is a vim.uv.fs_stat result.
function M.cache_path(path, st)
	local key = table.concat({ path, st.mtime.sec, st.mtime.nsec, st.size }, "\0")
	return string.format("%s/%s.bmp", cache_dir(), vim.fn.sha256(key):sub(1, 32))
end

function M.mode()
	local ok, settings = pcall(require, "core.settings")
	local v = ok and settings.get("image_preview") or "inline"
	return v == "quicklook" and "quicklook" or "inline"
end

-- Can the inline path even be attempted for `path`?
function M.inline_possible(path)
	return M.mode() == "inline" and not M.NO_INLINE[ext_of(path)] and vim.fn.executable("sips") == 1
end

-- Decode `path` into a parsed image. Async: `sips` converts to a cached BMP,
-- then `cb(img | nil)` runs on the main loop. A cache hit skips the process.
function M.decode(path, cb, dims)
	local st = vim.uv.fs_stat(path)
	if not st then
		return cb(nil)
	end
	local out = M.cache_path(path, st)
	local function load()
		local fd = io.open(out, "rb")
		if not fd then
			return nil
		end
		local raw = fd:read("*a")
		fd:close()
		return require("core.wallpaper").parse_bmp(raw)
	end
	if vim.uv.fs_stat(out) then
		local img = load()
		if img then
			return cb(img)
		end
	end
	vim.fn.mkdir(cache_dir(), "p")
	local part = out .. ".part"
	local cmd = { "sips", "-s", "format", "bmp" }
	if not (dims and dims <= M.MAXPX) then
		vim.list_extend(cmd, { "-Z", tostring(M.MAXPX) })
	end
	vim.list_extend(cmd, { path, "--out", part })
	local ok = pcall(vim.system, cmd, { text = true }, function(res)
		vim.schedule(function()
			if res.code == 0 and vim.uv.fs_stat(part) then
				os.rename(part, out)
				return cb(load())
			end
			os.remove(part)
			cb(nil)
		end)
	end)
	if not ok then
		cb(nil)
	end
end

local function image_win(buf)
	for _, win in ipairs(vim.fn.win_findbuf(buf)) do
		if vim.api.nvim_win_get_config(win).relative == "" then
			return win
		end
	end
end

-- Paint the decoded image into `buf`, fitted to the window that shows it. Safe
-- to call any time: no state / no window / a window too small is a no-op.
function M.paint(buf)
	local st = states[buf]
	if not (st and st.img and vim.api.nvim_buf_is_valid(buf)) then
		return
	end
	local win = image_win(buf)
	if not win then
		vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
		return
	end
	local info = vim.fn.getwininfo(win)[1]
	-- Text area of the window: getwininfo, not nvim_win_get_height/width (those
	-- count the winbar row and the number/sign columns).
	local width, height = info.width - info.textoff, info.height
	local row0 = st.header or 0
	local rows = height - row0
	if width < 4 or rows < 2 then
		vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
		return
	end
	local wp = require("core.wallpaper")
	local dc, dr, col0, off = wp.contain(st.img, width, rows)
	local key = dc .. "x" .. dr
	if st.key ~= key then
		st.px, st.key = wp.pixels(st.img, dc, dr), key
	end
	local grid = wp.frame(st.px, dc, dr, 0)
	local step = M.STEP
	repeat
		local used = wp.paint_grid(win, buf, grid, 1.0, {
			ns = M.ns,
			priority = M.PRIORITY,
			key = false,
			step = step,
			col0 = col0,
			row0 = row0 + off,
			width = width,
			height = height,
		})
		step = step * 2
	until used <= M.MAX_GROUPS or step > 48
end

-- ─── Placeholder + header ────────────────────────────────────────────────────

local function set_lines(buf, lines)
	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
	vim.bo[buf].modified = false
end

-- Metadata lines shared by the header and the placeholder.
local function meta(path)
	local name = vim.fn.fnamemodify(path, ":t")
	local st = vim.uv.fs_stat(path)
	local size = st and human_size(st.size) or "?"
	local w, h = image_dims(path)
	local dim = (w and h) and string.format("%d × %d", w, h) or "size unknown"
	local ext = ext_of(path)
	ext = ext == "" and "IMG" or ext:upper()
	return name, string.format("%s · %s · %s", dim, size, ext), (w and h) and math.max(w, h) or nil
end

-- The text placeholder (fallback, and the quicklook mode).
local function placeholder(buf, path)
	local name, info = meta(path)
	set_lines(buf, {
		"",
		"",
		"    🖼  " .. name,
		"",
		"    " .. info,
		"",
		"    Shown in macOS Quick Look.",
		"",
		"    <cr>  reopen in Quick Look",
		"    gO    open in Preview.app",
		"",
	})
	states[buf] = nil
	vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
end

-- Pop Quick Look on a genuine interactive open only: skip headless and skip
-- floating previews (telescope's preview window is floating). Once per buffer.
local function auto_quicklook(buf)
	if #vim.api.nvim_list_uis() == 0 or vim.b[buf].nv_image_previewed then
		return
	end
	local path = vim.b[buf].nv_image_path
	if not (path and vim.uv.fs_stat(path)) then
		return
	end
	vim.schedule(function()
		if not vim.api.nvim_buf_is_valid(buf) then
			return
		end
		local win = vim.fn.bufwinid(buf)
		if win ~= -1 and vim.api.nvim_win_get_config(win).relative == "" then
			vim.b[buf].nv_image_previewed = true
			M.quicklook(path)
		end
	end)
end

-- Fill the buffer: header + inline paint when possible, else the placeholder.
local function render(buf)
	local path = vim.b[buf].nv_image_path
	if not path then
		return
	end
	if not M.inline_possible(path) then
		vim.b[buf].nv_image_inline = false
		return placeholder(buf, path)
	end
	local name, info, longest = meta(path)
	local lines = { "  🖼  " .. name, "  " .. info .. "   ·   <cr> Quick Look   gO Preview.app", "" }
	set_lines(buf, lines)
	states[buf] = { header = #lines }
	vim.b[buf].nv_image_inline = true
	M.decode(path, function(img)
		if not (vim.api.nvim_buf_is_valid(buf) and states[buf]) then
			return
		end
		if not img then
			-- sips failed or the BMP was unreadable: fall back to the placeholder.
			vim.b[buf].nv_image_inline = false
			placeholder(buf, path)
			return auto_quicklook(buf)
		end
		states[buf].img = img
		M.paint(buf)
	end, longest)
end

-- Test seam.
function M._state(buf)
	return states[buf]
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

			-- Quick Look pops on open only when the inline paint isn't (or can't
			-- be) in charge; a failed decode pops it later from render().
			if not vim.b[buf].nv_image_inline then
				auto_quicklook(buf)
			end
		end,
	})

	-- Repaint for windows showing an image buffer (debounced: a drag-resize
	-- fires continuously). The timer handle is anchored on M._timer.
	local function repaint_all()
		for buf in pairs(states) do
			pcall(M.paint, buf)
		end
	end
	local function debounced()
		if next(states) == nil then
			return
		end
		M._timer = M._timer or vim.uv.new_timer()
		M._timer:stop()
		M._timer:start(M.DEBOUNCE_MS, 0, vim.schedule_wrap(repaint_all))
	end
	vim.api.nvim_create_autocmd({ "WinResized", "VimResized", "WinScrolled" }, { group = aug, callback = debounced })
	vim.api.nvim_create_autocmd("BufWinEnter", {
		group = aug,
		callback = function(ev)
			if states[ev.buf] then
				vim.schedule(function()
					pcall(M.paint, ev.buf)
				end)
			end
		end,
	})
	-- `:hi clear` wipes the groups; wallpaper resets its cache on ColorScheme
	-- synchronously, so this scheduled repaint always runs after it.
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = aug,
		callback = function()
			if next(states) == nil then
				return
			end
			vim.schedule(repaint_all)
		end,
	})
	vim.api.nvim_create_autocmd("BufWipeout", {
		group = aug,
		callback = function(ev)
			states[ev.buf] = nil
		end,
	})
end

M.setup()

return M
