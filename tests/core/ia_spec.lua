-- Tests for the :NvSinnerIA hub modal (lua/core/ia.lua): the user command, the
-- float and its rendered rows (settings + actions), the missing-key footer
-- hint (OpenCode Zen is the only supported provider), the toggle writing
-- through to core/settings, the model picker offering ONLY the verified-safe
-- OpenCode Zen models (fastest first, probe notes attached, broken catalogue
-- ids filtered out) + _choose_model persisting ai_model, and the model
-- catalogue seam (ai-complete.fetch_models). Mouse clicks / vim.ui.select
-- popups aren't exercised headless; the handlers route into the same
-- activate() / _choose_model() these specs cover.

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
		assert.matches("minimax%-m2.5", text) -- the current model shows in the Model row
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

	it("_model_items offers only verified-safe models, fastest first with its note", function()
		local items = ia._model_items({ "deepseek-v4-flash", "glm-5", "minimax-m2.7", "glm-5.2", "minimax-m2.5" })
		local ids = vim.tbl_map(function(it)
			return it.id
		end, items)
		-- SAFE_MODELS ∩ catalogue, in SAFE_MODELS' speed order — broken catalogue
		-- ids (deepseek-v4-flash: reasoning-only empty content; glm-5: same) are
		-- never offered.
		assert.are.same({ "minimax-m2.5", "minimax-m2.7", "glm-5.2" }, ids)
		-- The fastest model carries the recommendation note in the picker.
		assert.matches("fastest", items[1].display)
		assert.matches("recommended", items[1].display)
	end)

	it("_model_items falls back to the whole safe set without a usable catalogue", function()
		local ai_mod = require("core.ai-complete")
		local items = ia._model_items(nil) -- offline / no key
		assert.are.equal(#ai_mod.SAFE_MODELS, #items)
		assert.are.equal("minimax-m2.5", items[1].id) -- default, fastest, first
		-- A catalogue that intersects to nothing (drift) also degrades to the safe set.
		local drifted = ia._model_items({ "brand-new-unverified-model" })
		assert.are.equal(#ai_mod.SAFE_MODELS, #drifted)
	end)

	it("shows the ~/.zshrc key hint only while $OPENCODE_API_KEY is missing", function()
		local prev = vim.env.OPENCODE_API_KEY
		vim.env.OPENCODE_API_KEY = nil
		ia.open()
		local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
		assert.matches("OPENCODE_API_KEY", text, nil, true)
		assert.matches("zshrc", text, nil, true)
		ia.close()
		vim.env.OPENCODE_API_KEY = "k"
		ia.open()
		text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
		assert.is_falsy(text:find("zshrc", 1, true), "no hint once the key is set")
		ia.close()
		vim.env.OPENCODE_API_KEY = prev
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
