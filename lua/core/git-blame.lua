-- ─── Inline git blame (native) ──────────────────────────────────────────────
-- Replaces git-blame.nvim: an always-on virtual-text blame for the cursor
-- line — " <summary> • <date> • <author> • <sha>" rendered at end-of-line in
-- the comment tone. The cursor settles (debounced vim.uv timer, same anchor
-- discipline as ai-activity), then one async `git blame -L <line>,<line>
-- --porcelain` runs via vim.system; the result is dropped if the cursor moved
-- while it was in flight (generation counter — async results must never paint
-- a stale line).
--
-- The buffer's CURRENT content is blamed (`--contents -` with the buffer lines
-- on stdin), so an unsaved edit shifts blame like git-blame.nvim did instead
-- of blaming the wrong on-disk line. Untracked files are cached as dead per
-- buffer (cleared on save) so a scratch note doesn't spawn a git process on
-- every cursor move.
--
-- A SECOND virtual-text chunk names the branch (and PR) that merged the commit
-- in — resolved from the first merge commit that is a descendant of the blamed
-- sha, and memoised per repo+sha, since a sha is immutable. It is a separate
-- chunk on purpose: the annotation's first chunk is the contract the spec pins.

local M = {}

local ns = vim.api.nvim_create_namespace("nvsinner_git_blame")
M._ns = ns -- test seam: specs read the extmark in this namespace

M.DELAY = 350 -- ms after the cursor settles before blaming
M.DATE_FORMAT = "%m-%d-%Y %H:%M:%S" -- same format the plugin used

M.SHOW_REF = true -- resolve + render the merged-from branch / PR
M.REF_ICON = "  " -- separator + branch glyph: the branch it was merged FROM
M.REF_ICON_LOCAL = "  " -- pull-request glyph: still in flight on this branch
M.REF_CACHE_MAX = 512 -- entries kept before the memo table is dropped wholesale
-- "Landed" is decided by name, because there is no portable way to ask git
-- which branch is the mainline. Add to this set for a repo whose trunk is
-- called something else (`develop`, `staging`, …).
M.TRUNKS = { main = true, master = true, trunk = true }
-- An unmerged answer is the one volatile verdict here: it turns into a merge
-- the moment the branch lands, and the branch itself changes on checkout. So
-- it expires, while a resolved merge is cached for the session.
M.REF_TTL_MS = 15000

-- One extmark, rewritten in place: the annotation is painted as soon as the
-- blame lands and repainted once the (slower) ref lookup answers, so a fixed id
-- is what keeps the second paint from stacking a duplicate.
local MARK_ID = 1

local enabled = true
local gen = 0 -- bumped on every movement; in-flight results check it
local dead = {} -- dead[buf] = true when git said "untracked / not a repo"

-- Comment-tone virtual text: muted and italic, like the blame it replaces.
-- Role only (base03 = comments), re-applied on ColorScheme.
local function apply_hl()
	local c = require("core.carbon").colors()
	vim.api.nvim_set_hl(0, "NvGitBlame", { fg = c.base03, italic = true })
	-- The ref rides the identity accent (base09), so it follows the user's
	-- accent pack and reads as a reference rather than more comment prose.
	vim.api.nvim_set_hl(0, "NvGitBlameRef", { fg = c.base09, italic = true })
end
apply_hl()
vim.api.nvim_create_autocmd("ColorScheme", { pattern = "*", callback = apply_hl })

local function eligible(buf)
	return vim.api.nvim_buf_is_valid(buf)
		and vim.bo[buf].buftype == ""
		and vim.api.nvim_buf_get_name(buf) ~= ""
		and not dead[buf]
end

function M.clear(buf)
	if vim.api.nvim_buf_is_valid(buf) then
		vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	end
end

-- Parse `git blame --porcelain` for a single line into a display string.
-- Returns nil for uncommitted lines (all-zero sha) — no annotation is better
-- than a fake one.
function M._format(stdout)
	local sha = stdout:match("^(%x+) ")
	if not sha or sha:match("^0+$") then
		return nil
	end
	local author = stdout:match("\nauthor ([^\n]+)")
	local time = tonumber(stdout:match("\nauthor%-time (%d+)"))
	local summary = stdout:match("\nsummary ([^\n]+)")
	if not (author and time and summary) then
		return nil
	end
	local date = os.date(M.DATE_FORMAT, time)
	return string.format(" %s • %s • %s • <%s>", summary, date, author, sha:sub(1, 7))
end

-- Parse a merge commit's subject into the branch that was merged in (and the
-- PR number when the forge recorded one). The shapes below are the ones that
-- actually occur — collected from the merge history of every repo on this
-- machine, not from the git manual:
--   Merge pull request #22 from anderssonq/release/v3.1.0
--   Merge branch 'feature-x' [of <url>] [into main]
--   Merge remote-tracking branch 'origin/hotfix/x'
-- The owner is cut at the FIRST slash, because branch names carry slashes too
-- ("fix/highlight-jsx" must survive intact).
function M._parse_ref(subject)
	if type(subject) ~= "string" then
		return nil, nil
	end
	local pr, owner_branch = subject:match("^Merge pull request #(%d+) from (%S+)")
	if pr then
		return owner_branch:match("^[^/]+/(.+)$") or owner_branch, pr
	end
	local branch = subject:match("^Merge remote%-tracking branch '([^']+)'") or subject:match("^Merge branch '([^']+)'")
	if branch then
		-- 'origin/foo' and a fork's 'owner:foo' both name the plain branch.
		return branch:match("^origin/(.+)$") or branch:match("^[%w%-%._]+:(.+)$") or branch, nil
	end
	return nil, nil
end

-- Render a resolved ref as the second virt_text chunk. Pure — the seam the
-- spec asserts the display shape through.
function M._ref_text(ref)
	if not ref then
		return nil
	end
	local parts = {}
	if ref.branch then
		parts[#parts + 1] = ref.branch
	end
	if ref.pr then
		parts[#parts + 1] = "#" .. ref.pr
	end
	if #parts == 0 then
		return nil
	end
	-- `merged == false` is the in-flight case; nil means "not asked", which the
	-- merged glyph covers.
	local icon = ref.merged == false and M.REF_ICON_LOCAL or M.REF_ICON
	return icon .. table.concat(parts, " ")
end

-- Parse `git branch --all --contains <sha> --format=%(HEAD)%09%(refname)`.
-- Pure, and the seam the in-flight verdict is specced through. Full refnames
-- (not `refname:short`) so a remote can be stripped exactly — `origin/main`
-- must read as `main`, while a local branch really called `feature/main` must
-- not.
function M._parse_branches(stdout)
	local out = { names = {}, locals = {}, current = nil }
	for line in (stdout or ""):gmatch("[^\n]+") do
		local head, ref = line:match("^(.-)\t(.+)$")
		if ref then
			local name = ref:match("^refs/heads/(.+)$")
			local is_local = name ~= nil
			name = name or ref:match("^refs/remotes/[^/]+/(.+)$")
			if name and name ~= "HEAD" then
				out.names[#out.names + 1] = name
				if is_local then
					out.locals[#out.locals + 1] = name
					if head:find("*", 1, true) then
						out.current = name
					end
				end
			end
		end
	end
	return out
end

-- Has this commit reached the mainline at all?
function M._on_trunk(names)
	for _, name in ipairs(names or {}) do
		if M.TRUNKS[name] then
			return true
		end
	end
	return false
end

-- Memo of dir+sha -> ref table (or `false` for "looked up, nothing to show").
-- A sha is immutable, so this resolves once per distinct commit rather than per
-- cursor settle; caching the negatives matters just as much, or a shallow clone
-- and a repo without merges would re-spawn two processes on every line.
local ref_cache = {}
local ref_count = 0

local function cache_put(key, value, ttl)
	if ref_count >= M.REF_CACHE_MAX then
		ref_cache, ref_count = {}, 0
	end
	ref_cache[key] = { v = value, exp = ttl and (vim.uv.now() + ttl) or nil }
	ref_count = ref_count + 1
end

-- Resolve "which branch brought <sha> into the history I am on".
--
-- `--ancestry-path --reverse` yields the merges descending from <sha>; the
-- first is the one that introduced it. That alone is not enough: a commit made
-- straight on the mainline is ALSO an ancestor of every later merge, and naming
-- someone else's branch for it would be a plain lie. So the candidate is kept
-- only when <sha> is NOT reachable from the merge's first parent — i.e. it
-- genuinely arrived through the merged side.
--
-- With no merge at all there are two very different reasons, and conflating
-- them was the first version's bug: the commit may have LANDED without leaving
-- a merge (squash- or rebase-merge, or a direct push), or it may simply not
-- have been merged yet — the everyday case of reading a line you just wrote on
-- a feature branch, which reported nothing at all. One `git branch --contains`
-- separates them: if a trunk branch holds the commit it landed, and the
-- subject the blame already parsed is the fallback (forges append "(#123)", so
-- the PR costs no extra process); otherwise it is still in flight, and the
-- branch holding it is the answer.
function M._ref_for(dir, sha, summary, cb)
	local key = dir .. "\0" .. sha
	local hit = ref_cache[key]
	if hit and (not hit.exp or hit.exp > vim.uv.now()) then
		cb(hit.v or nil)
		return
	end

	local function finish(value, ttl)
		cache_put(key, value or false, ttl)
		vim.schedule(function()
			cb(value)
		end)
	end

	local function from_summary()
		local pr = summary and summary:match("%(#(%d+)%)%s*$")
		finish(pr and { pr = pr } or nil)
	end

	-- No merge introduced it: landed without one, or not merged yet?
	local function from_branches()
		vim.system(
			{ "git", "-C", dir, "branch", "--all", "--contains", sha, "--format=%(HEAD)%09%(refname)" },
			{ text = true },
			function(out)
				if out.code ~= 0 then
					return from_summary()
				end
				local b = M._parse_branches(out.stdout)
				if M._on_trunk(b.names) then
					return from_summary() -- already on the mainline
				end
				-- Prefer the branch we are standing on; a detached HEAD still
				-- has a local branch containing the commit worth naming.
				local branch = b.current or b.locals[1]
				if not branch then
					return from_summary()
				end
				finish({ branch = branch, merged = false }, M.REF_TTL_MS)
			end
		)
	end

	vim.system({
		"git",
		"-C",
		dir,
		"log",
		"--merges",
		"--ancestry-path",
		"--reverse",
		"--format=%H%x00%P%x00%s",
		sha .. "..HEAD",
	}, { text = true }, function(out)
		if out.code ~= 0 then
			return finish(nil) -- shallow clone, detached history, no HEAD…
		end
		local line = (out.stdout or ""):match("^([^\n]*)")
		local fields = vim.split(line or "", "\0", { plain = true })
		local parents, subject = fields[2], fields[3]
		local first_parent = parents and parents:match("^(%x+)")
		if not (first_parent and subject) then
			return from_branches() -- no merge descends from it
		end
		local branch, pr = M._parse_ref(subject)
		if not (branch or pr) then
			return from_summary()
		end
		-- Reachable from the mainline parent => it was already there.
		vim.system(
			{ "git", "-C", dir, "merge-base", "--is-ancestor", sha, first_parent },
			{ text = true },
			function(anc)
				if anc.code == 0 then
					return from_summary()
				end
				finish({ branch = branch, pr = pr })
			end
		)
	end)
end

local function annotate(buf, row, text, ref_text)
	if not text or not vim.api.nvim_buf_is_valid(buf) or row >= vim.api.nvim_buf_line_count(buf) then
		return
	end
	local chunks = { { text, "NvGitBlame" } }
	if ref_text then
		chunks[#chunks + 1] = { ref_text, "NvGitBlameRef" }
	end
	vim.api.nvim_buf_set_extmark(buf, ns, row, 0, {
		id = MARK_ID,
		virt_text = chunks,
		virt_text_pos = "eol",
		hl_mode = "combine",
	})
end

-- Blame the cursor line of `buf` right now (the debounce is the caller's
-- job — tests call this directly since CursorMoved doesn't fire headless).
function M.refresh(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	if not (enabled and eligible(buf)) then
		return
	end
	local win = vim.api.nvim_get_current_win()
	if vim.api.nvim_win_get_buf(win) ~= buf then
		return
	end
	local row = vim.api.nvim_win_get_cursor(win)[1]
	local path = vim.api.nvim_buf_get_name(buf)
	local dir = vim.fs.dirname(path)
	gen = gen + 1
	local this_gen = gen
	-- Blame the buffer content, not the file on disk: unsaved edits above the
	-- cursor would otherwise shift every annotation onto the wrong commit.
	local contents = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n") .. "\n"
	vim.system({
		"git",
		"-C",
		dir,
		"blame",
		"-L",
		row .. "," .. row,
		"--porcelain",
		"--contents",
		"-",
		"--",
		path,
	}, { stdin = contents, text = true }, function(out)
		vim.schedule(function()
			if this_gen ~= gen or not vim.api.nvim_buf_is_valid(buf) then
				return
			end
			if out.code ~= 0 then
				-- Untracked file or not a repo: stop asking until the next save.
				dead[buf] = true
				return
			end
			M.clear(buf)
			local porcelain = out.stdout or ""
			local text = M._format(porcelain)
			if not text then
				return
			end
			-- Paint what we already know immediately; the ref lookup is a second
			-- round-trip and must not hold the annotation back.
			annotate(buf, row - 1, text)
			if not M.SHOW_REF then
				return
			end
			local sha = porcelain:match("^(%x+) ")
			if not sha then
				return
			end
			M._ref_for(dir, sha, porcelain:match("\nsummary ([^\n]+)"), function(ref)
				if this_gen ~= gen or not vim.api.nvim_buf_is_valid(buf) then
					return -- the cursor moved on: never repaint a stale line
				end
				local ref_text = M._ref_text(ref)
				if ref_text then
					annotate(buf, row - 1, text, ref_text)
				end
			end)
		end)
	end)
end

-- Debounce: movement wipes the annotation immediately (a stale blame under a
-- new cursor line reads as wrong data) and re-arms the timer.
M._timer = nil -- anchored on the module table so luv can't GC a live timer
local function schedule(buf)
	gen = gen + 1 -- invalidate any in-flight result
	M.clear(buf)
	if not (enabled and eligible(buf)) then
		return
	end
	if M._timer then
		M._timer:stop()
	else
		M._timer = vim.uv.new_timer()
	end
	M._timer:start(
		M.DELAY,
		0,
		vim.schedule_wrap(function()
			M.refresh(buf)
		end)
	)
end

function M.toggle()
	enabled = not enabled
	if not enabled then
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			M.clear(buf)
		end
	else
		schedule(vim.api.nvim_get_current_buf())
	end
	vim.notify("Inline blame " .. (enabled and "on" or "off"), vim.log.levels.INFO, { timeout = 250 })
end

function M.enabled()
	return enabled
end

local grp = vim.api.nvim_create_augroup("nv_git_blame", { clear = true })

vim.api.nvim_create_autocmd({ "CursorMoved", "BufEnter", "InsertLeave" }, {
	group = grp,
	callback = function(args)
		schedule(args.buf)
	end,
})

-- While typing, only clear — re-blaming every keystroke is churn.
vim.api.nvim_create_autocmd({ "CursorMovedI", "InsertEnter" }, {
	group = grp,
	callback = function(args)
		gen = gen + 1
		M.clear(args.buf)
	end,
})

-- A save can turn an untracked file into a tracked one (git add + write from
-- the AI column, `:w` after `git add -N`, …): forget the dead verdict.
vim.api.nvim_create_autocmd("BufWritePost", {
	group = grp,
	callback = function(args)
		dead[args.buf] = nil
		schedule(args.buf)
	end,
})

vim.api.nvim_create_autocmd("BufWipeout", {
	group = grp,
	callback = function(args)
		dead[args.buf] = nil
	end,
})

vim.api.nvim_create_user_command("NvSinnerBlameToggle", M.toggle, {
	desc = "Toggle the inline git blame annotation",
})

-- Test seam: drop all state between specs.
function M._reset()
	gen = gen + 1
	dead = {}
	ref_cache, ref_count = {}, 0
	enabled = true
	if M._timer then
		M._timer:stop()
	end
end

return M
