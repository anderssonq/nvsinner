-- Behavioural guard for the AI column across tabs (agent mode, <leader>ga).
--
-- The column logic lives in closures inside the toggleterm spec's config(), and
-- tests/minimal_init.lua loads no plugins. So this runs that config() for real
-- against a FAKE toggleterm: `Terminal` opens/closes plain windows on a scratch
-- buffer, the way toggleterm does for a split. Everything under test — the
-- picker, show_here, adopt-on-toggle, hide, restore_layout — is the real code,
-- reached through the same seams agent mode uses (core.ai-sessions).
--
-- The contract it pins:
--   * agent mode never CREATES a session: show_here(n, { existing = true })
--     with no session opens no column and no CLI picker;
--   * one session is shown in a window per tab — the same buffer, never a
--     second column, and the other tab's window is left alone;
--   * toggling / hiding acts on the current tab's window only, and stays in it;
--   * a second press while the picker is up never stacks another picker.

local function repo_root()
	local f = vim.api.nvim_get_runtime_file("lua/core/ai-activity.lua", false)[1]
	assert(f, "this config must be on the runtimepath (see tests/minimal_init.lua)")
	return vim.fn.fnamemodify(f, ":h:h:h")
end

-- A minimal stand-in for toggleterm's Terminal: a vertical split on a scratch
-- buffer, with toggleterm's single-`window` bookkeeping and its on_open hook.
local Terminal = {}
Terminal.__index = Terminal
function Terminal:new(o)
	return setmetatable(o or {}, Terminal)
end
function Terminal:is_open()
	return self.window ~= nil and vim.api.nvim_win_is_valid(self.window)
end
function Terminal:open()
	vim.cmd("botright vsplit")
	self.window = vim.api.nvim_get_current_win()
	if not (self.bufnr and vim.api.nvim_buf_is_valid(self.bufnr)) then
		self.bufnr = vim.api.nvim_create_buf(false, true)
	end
	vim.api.nvim_win_set_buf(self.window, self.bufnr)
	if self.on_open then
		self:on_open()
	end
end
function Terminal:close()
	if self:is_open() then
		vim.api.nvim_win_close(self.window, true)
	end
end
function Terminal:toggle()
	if self:is_open() then
		self:close()
	else
		self:open()
	end
	return self
end
function Terminal:shutdown()
	self:close()
	if self.bufnr and vim.api.nvim_buf_is_valid(self.bufnr) then
		vim.api.nvim_buf_delete(self.bufnr, { force = true })
	end
end

-- Windows of `tab` showing `buf`.
local function wins_on(tab, buf)
	local out = {}
	for _, w in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
		if vim.api.nvim_win_get_buf(w) == buf then
			out[#out + 1] = w
		end
	end
	return out
end

local function count_ft(tab, ft)
	local n = 0
	for _, w in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
		if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == ft then
			n = n + 1
		end
	end
	return n
end

describe("AI column across tabs (agent mode)", function()
	local sessions = require("core.ai-sessions")
	local saved = {}

	before_each(function()
		for _, m in ipairs({ "toggleterm", "toggleterm.terminal", "toggleterm.ui" }) do
			saved[m] = package.loaded[m]
		end
		package.loaded["toggleterm"] = { setup = function() end }
		package.loaded["toggleterm.terminal"] = { Terminal = Terminal }
		package.loaded["toggleterm.ui"] = { hl_term = function() end }
		sessions._reset()
		dofile(repo_root() .. "/lua/plugins/terminal/toggleterm.lua").config()
	end)

	after_each(function()
		vim.cmd("silent! stopinsert")
		vim.cmd("silent! tabonly!")
		vim.cmd("silent! only!")
		for m, v in pairs(saved) do
			package.loaded[m] = v
		end
		sessions._reset()
	end)

	-- Session 1 through the real first-open flow: <leader>j → the CLI picker →
	-- "4" (plain terminal) → <CR>.
	local function create_session()
		vim.fn.maparg("<leader>j", "n", false, true).callback()
		assert.are.equal("nvsinner-picker", vim.bo.filetype, "the first open shows the CLI picker")
		vim.fn.maparg("4", "n", false, true).callback()
		vim.fn.maparg("<CR>", "n", false, true).callback()
		local e = sessions.sessions()[1]
		assert.is_not_nil(e, "choosing an entry creates session 1")
		return e.term
	end

	it("never creates a session: no column and no picker without one", function()
		local before = #vim.api.nvim_tabpage_list_wins(0)
		assert.is_false(sessions.show_here(1, { existing = true }))
		assert.are.equal(before, #vim.api.nvim_tabpage_list_wins(0), "no window opened")
		assert.are.equal(0, count_ft(0, "nvsinner-picker"), "no CLI picker")
		assert.are.equal(0, #sessions.sessions(), "no session registered")
	end)

	it("shows the SAME session in a second tab, leaving the first tab's column", function()
		local term = create_session()
		local tab1 = vim.api.nvim_get_current_tabpage()
		local col1 = wins_on(tab1, term.bufnr)[1]

		vim.cmd("tabnew")
		local tab2 = vim.api.nvim_get_current_tabpage()
		assert.is_true(sessions.show_here(1, { existing = true }))

		assert.are.equal(1, #wins_on(tab2, term.bufnr), "one column in the new tab")
		assert.are.same({ col1 }, wins_on(tab1, term.bufnr), "the first tab keeps its own column")
		assert.are.equal(1, #sessions.sessions(), "still one session — never a second one")
		assert.are.equal(tab2, vim.api.nvim_win_get_tabpage(term.window), "the visible tab's window is the managed one")
	end)

	it("pressed again in a tab that already shows it, only focuses it", function()
		local term = create_session()
		vim.cmd("wincmd p")
		assert.is_true(sessions.show_here(1, { existing = true }))
		assert.are.equal(1, #wins_on(0, term.bufnr))
		assert.are.equal(term.bufnr, vim.api.nvim_get_current_buf())
	end)

	it("<leader>j hides the column in the current tab only, and stays there", function()
		local term = create_session()
		local tab1 = vim.api.nvim_get_current_tabpage()
		vim.cmd("tabnew")
		local tab2 = vim.api.nvim_get_current_tabpage()
		sessions.show_here(1, { existing = true })

		vim.api.nvim_set_current_tabpage(tab1)
		vim.cmd("stopinsert")
		vim.fn.maparg("<leader>j", "n", false, true).callback()
		assert.are.equal(tab1, vim.api.nvim_get_current_tabpage(), "no jump to the other tab")
		assert.are.equal(0, #wins_on(tab1, term.bufnr), "hidden here")
		assert.are.equal(1, #wins_on(tab2, term.bufnr), "still shown in the other tab")

		vim.fn.maparg("<leader>j", "n", false, true).callback()
		assert.are.equal(1, #wins_on(tab1, term.bufnr), "shown here again, on the same buffer")
		assert.are.equal(1, #wins_on(tab2, term.bufnr))
	end)

	it("<leader>jh never hides another tab's column", function()
		local term = create_session()
		local tab1 = vim.api.nvim_get_current_tabpage()
		vim.cmd("tabnew")
		local orig = vim.notify
		vim.notify = function() end
		local hidden = sessions.hide_all()
		vim.notify = orig
		assert.are.equal(0, hidden, "nothing to hide in this tab")
		assert.are.equal(1, #wins_on(tab1, term.bufnr), "the first tab keeps its column")
	end)

	it("never stacks a second CLI picker", function()
		vim.fn.maparg("<leader>j", "n", false, true).callback()
		vim.cmd("wincmd p")
		vim.fn.maparg("<leader>j", "n", false, true).callback()
		assert.are.equal(1, count_ft(0, "nvsinner-picker"))
		assert.are.equal("nvsinner-picker", vim.bo.filetype, "the second press focuses the open picker")
	end)
end)
