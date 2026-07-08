-- Tests for the :NvSinnerIA hub modal (lua/core/ia.lua): the user command, the
-- float and its rendered rows (settings + actions), the toggle writing through
-- to core/settings, the model picker's recommended-first ordering + _choose_model
-- persisting ai_model, and the model catalogue seam (ai-complete.fetch_models).
-- Mouse clicks / vim.ui.select popups aren't exercised headless; the handlers
-- route into the same activate() / _choose_model() these specs cover.

describe("core.ia", function()
	local settings = require("core.settings")
	local ai = require("core.ai-complete")
	local ia = require("core.ia")

	before_each(function()
		settings.load({ file = vim.fn.tempname() }) -- throwaway persistence
		ia.close()
	end)

	it("defines the :NvSinnerIA user command", function()
		assert.is_not_nil(vim.api.nvim_get_commands({})["NvSinnerIA"])
	end)

	it("opens a floating modal with the settings + action rows under section headers", function()
		ia.open()
		local win = vim.api.nvim_get_current_win()
		assert.are.equal("editor", vim.api.nvim_win_get_config(win).relative, "must be a float")
		local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
		for _, row in ipairs({
			"SETTINGS",
			"AI completion",
			"Model",
			"ACTIONS",
			"Ask AI (selection)",
			"Complete at cursor",
			"Prompt library",
		}) do
			assert.matches(row, text, nil, true)
		end
		assert.matches("glm%-5.2", text) -- the current model shows in the Model row
		assert.matches("q close", text, nil, true)
		ia.close()
		assert.are_not.equal(win, vim.api.nvim_get_current_win())
	end)

	it("opens on the solid NvMenuNormal surface with a backdrop behind it", function()
		local before = #vim.api.nvim_list_wins()
		ia.open()
		local modal = vim.api.nvim_get_current_win()
		assert.matches("NvMenuNormal", vim.wo[modal].winhighlight, nil, true)
		assert.are.equal(before + 2, #vim.api.nvim_list_wins(), "modal + backdrop expected")
		ia.close()
		vim.wait(200, function()
			return #vim.api.nvim_list_wins() == before
		end)
		assert.are.equal(before, #vim.api.nvim_list_wins(), "backdrop must close with the modal")
	end)

	it("activate() on the AI-completion toggle flips + persists ai_complete in place", function()
		ia.open()
		local win = vim.api.nvim_get_current_win()
		ia.move(-99) -- row 1: AI completion
		local before = settings.get("ai_complete")
		ia.activate()
		assert.are_not.equal(before, settings.get("ai_complete"), "the toggle must flip the setting")
		assert.are.equal(win, vim.api.nvim_get_current_win(), "a toggle re-renders in place, not closes")
		ia.activate() -- back
		assert.are.equal(before, settings.get("ai_complete"))
		ia.close()
	end)

	it("activate() on an action row runs the command and closes", function()
		local fired = false
		vim.api.nvim_create_user_command("NvSinnerAskAI", function()
			fired = true
		end, { desc = "stub" })
		ia.open()
		local win = vim.api.nvim_get_current_win()
		ia.move(-99)
		ia.move(2) -- row 3: Ask AI (selection) → action
		ia.activate()
		assert.is_true(fired, "the action must run its command")
		assert.are_not.equal(win, vim.api.nvim_get_current_win(), "an action closes the modal")
		pcall(vim.api.nvim_del_user_command, "NvSinnerAskAI")
	end)

	it("_model_items lists recommended models first, marked with a check", function()
		local items = ia._model_items({ "deepseek-v4-flash", "glm-5", "minimax-m2.7", "glm-5.2" })
		-- Recommended (in ai.RECOMMENDED order) come first, ✓-marked.
		assert.are.equal("glm-5.2", items[1].id)
		assert.matches("✓", items[1].display)
		assert.are.equal("glm-5", items[2].id)
		assert.are.equal("minimax-m2.7", items[3].id)
		-- Non-recommended keep their catalogue place, no check.
		assert.are.equal("deepseek-v4-flash", items[4].id)
		assert.is_falsy(items[4].display:find("✓", 1, true))
	end)

	it("_model_items falls back to the curated list when no catalogue is given", function()
		local items = ia._model_items(nil)
		assert.is_true(#items > 0)
		assert.are.equal("glm-5.2", items[1].id) -- default, recommended, first
	end)

	it("_choose_model persists the picked model (what M.model() then returns)", function()
		local prev = vim.env.OPENCODE_MODEL
		vim.env.OPENCODE_MODEL = nil -- so the persisted choice is the effective one
		ia._choose_model("minimax-m2.7")
		assert.are.equal("minimax-m2.7", settings.get("ai_model"))
		assert.are.equal("minimax-m2.7", ai.model())
		ia._choose_model("glm-5.2")
		assert.are.equal("glm-5.2", ai.model())
		vim.env.OPENCODE_MODEL = prev
	end)

	it("fetch_models returns nil without an API key (picker uses the fallback)", function()
		ai._reset() -- clears the model cache
		local prev = vim.env.OPENCODE_API_KEY
		vim.env.OPENCODE_API_KEY = nil
		local called, got = false, "unset"
		ai.fetch_models(function(ids)
			called, got = true, ids
		end)
		assert.is_true(called, "the callback must always fire")
		assert.is_nil(got)
		vim.env.OPENCODE_API_KEY = prev
	end)

	it("fetch_models serves a cached catalogue synchronously (no request)", function()
		ai._models_cache = { "glm-5.2", "glm-5" }
		local got
		ai.fetch_models(function(ids)
			got = ids
		end)
		assert.are.same({ "glm-5.2", "glm-5" }, got)
		ai._reset()
	end)
end)
