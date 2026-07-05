-- Tests for the persistent settings layer (lua/core/settings.lua) and the
-- carbon accent packs it drives (lua/core/carbon.lua): defaults, the JSON
-- save/load roundtrip via the { file = … } test seam, the vim.g seeding
-- precedence, the quiet (notification-mute) wrapper, and accent resolution.

describe("core.settings", function()
	local settings = require("core.settings")
	local carbon = require("core.carbon")

	-- Re-point persistence at a throwaway file so specs never touch the real
	-- stdpath("data") settings (require() already loaded that one).
	local temp
	before_each(function()
		temp = vim.fn.tempname()
		settings.load({ file = temp })
	end)

	it("starts from the documented defaults", function()
		assert.are.equal("carbon", settings.get("theme"))
		assert.is_false(settings.get("transparent"))
		assert.are.equal("blue", settings.get("accent"))
		assert.are.equal("accent", settings.get("folder"))
		for _, slot in ipairs({ "notif", "variables", "strings", "functions" }) do
			assert.are.equal("default", settings.get(slot), slot)
		end
		assert.are.equal("left", settings.get("tree_side"))
		assert.are.equal("right", settings.get("ai_side"))
		assert.is_false(settings.get("quiet"))
	end)

	it("persists a set() and reads it back from disk", function()
		settings.set("tree_side", "right")
		-- Wipe in-memory state, then reload from the same file.
		settings.load({ file = temp })
		assert.are.equal("right", settings.get("tree_side"))
		-- Unknown keys are refused (nothing persisted, no error).
		settings.set("bogus", 1)
		assert.is_nil(settings.get("bogus"))
	end)

	it("survives a corrupt settings file (falls back to defaults)", function()
		local fd = assert(io.open(temp, "w"))
		fd:write("{ not json !!!")
		fd:close()
		settings.load({ file = temp })
		assert.are.equal("carbon", settings.get("theme"))
	end)

	it("migrates the legacy background key to the equivalent named theme", function()
		local fd = assert(io.open(temp, "w"))
		fd:write(vim.json.encode({ background = "light" }))
		fd:close()
		settings.load({ file = temp })
		assert.are.equal("moon", settings.get("theme"))

		fd = assert(io.open(temp, "w"))
		fd:write(vim.json.encode({ background = "dark" }))
		fd:close()
		settings.load({ file = temp })
		assert.are.equal("carbon", settings.get("theme"))

		-- A persisted theme wins over a stale background key.
		fd = assert(io.open(temp, "w"))
		fd:write(vim.json.encode({ background = "light", theme = "fjord" }))
		fd:close()
		settings.load({ file = temp })
		assert.are.equal("fjord", settings.get("theme"))
	end)

	it("seeds the carbon vim.g flags only when unset (vim.g/env win)", function()
		local orig = vim.g.nvsinner_theme
		local fd = assert(io.open(temp, "w"))
		fd:write(vim.json.encode({ theme = "mocha" }))
		fd:close()

		vim.g.nvsinner_theme = nil
		settings.setup({ file = temp })
		assert.are.equal("mocha", vim.g.nvsinner_theme, "persisted value should seed an unset flag")

		vim.g.nvsinner_theme = "carbon" -- user override in place…
		settings.setup({ file = temp })
		assert.are.equal("carbon", vim.g.nvsinner_theme, "…must NOT be clobbered by the persisted value")

		vim.g.nvsinner_theme = orig
	end)

	it("quiet mutes INFO notifications but lets WARN/ERROR through", function()
		local captured = {}
		local orig = vim.notify
		vim.notify = function(msg, level)
			captured[#captured + 1] = { msg = msg, level = level }
		end

		settings.set("quiet", true)
		vim.notify("info toast") -- default level INFO → muted
		vim.notify("boom", vim.log.levels.ERROR) -- must pass
		settings.set("quiet", false) -- unwraps back to the capture fn
		vim.notify("info again") -- passes again

		vim.notify = orig -- restore BEFORE asserting so a failure can't leak it

		assert.are.equal(2, #captured)
		assert.are.equal("boom", captured[1].msg)
		assert.are.equal("info again", captured[2].msg)
	end)

	describe("carbon accent packs", function()
		local saved_accent
		before_each(function()
			saved_accent = vim.g.nvsinner_accent
		end)
		after_each(function()
			vim.g.nvsinner_accent = saved_accent
		end)

		it("ships the four packs with dark+light overrides", function()
			for _, name in ipairs({ "blue", "magenta", "green", "purple" }) do
				local pack = carbon.accents[name]
				assert.is_table(pack, name)
				assert.is_table(pack.dark, name .. ".dark")
				assert.is_table(pack.light, name .. ".light")
			end
		end)

		it("resolves the accent flag, falling back to blue", function()
			vim.g.nvsinner_accent = nil
			if vim.env.NVSINNER_ACCENT == nil then
				assert.are.equal("blue", carbon.accent())
			end
			vim.g.nvsinner_accent = "green"
			assert.are.equal("green", carbon.accent())
			vim.g.nvsinner_accent = "bogus"
			assert.are.equal("blue", carbon.accent())
		end)

		it("ships the folder packs as role pairs and resolves the flag", function()
			for _, name in ipairs({ "accent", "teal", "aqua", "pink", "green", "purple", "gray" }) do
				local pack = carbon.folders[name]
				assert.is_table(pack, name)
				assert.is_string(carbon.dark[pack.name], name .. ".name must be a palette role")
				assert.is_string(carbon.dark[pack.icon], name .. ".icon must be a palette role")
			end
			local saved = vim.g.nvsinner_folder
			vim.g.nvsinner_folder = nil
			if vim.env.NVSINNER_FOLDER == nil then
				assert.are.equal("accent", carbon.folder())
			end
			vim.g.nvsinner_folder = "aqua"
			assert.are.equal("aqua", carbon.folder())
			vim.g.nvsinner_folder = "bogus"
			assert.are.equal("accent", carbon.folder())
			vim.g.nvsinner_folder = saved
		end)

		it("folder_colors() follows the accent pack on stock, a fixed accent otherwise", function()
			local bg = vim.o.background
			vim.o.background = "dark"
			local saved = vim.g.nvsinner_folder
			vim.g.nvsinner_folder = "accent"
			vim.g.nvsinner_accent = "green" -- stock folder names must follow base09…
			assert.are.equal(carbon.accents.green.dark.base09, carbon.folder_colors().name)
			assert.are.equal(carbon.dark.base12, carbon.folder_colors().icon)
			vim.g.nvsinner_folder = "aqua" -- …a fixed pack must not
			assert.are.equal(carbon.dark.base08, carbon.folder_colors().name)
			assert.are.equal(carbon.dark.base08, carbon.folder_colors().icon)
			vim.g.nvsinner_folder = saved
			vim.g.nvsinner_accent = "blue"
			vim.o.background = bg
		end)

		it("single-role slots resolve their flag and go nil on default", function()
			for slot, def in pairs(carbon.slots) do
				assert.is_string(def.g, slot)
				assert.is_string(def.env, slot)
			end
			for choice, role in pairs(carbon.slot_choices) do
				assert.is_string(carbon.dark[role], choice .. " must map to a palette role")
			end
			local bg = vim.o.background
			vim.o.background = "dark"
			local saved = vim.g.nvsinner_strings
			vim.g.nvsinner_strings = nil
			if vim.env.NVSINNER_STRINGS == nil then
				assert.are.equal("default", carbon.slot("strings"))
				assert.is_nil(carbon.slot_color("strings"), "default must keep the stock roles")
			end
			vim.g.nvsinner_strings = "teal"
			assert.are.equal(carbon.dark.base07, carbon.slot_color("strings"))
			vim.g.nvsinner_strings = "accent" -- follows the accent pack…
			vim.g.nvsinner_accent = "green"
			assert.are.equal(carbon.accents.green.dark.base09, carbon.slot_color("strings"))
			vim.g.nvsinner_strings = "bogus" -- …and unknown values fall back
			assert.are.equal("default", carbon.slot("strings"))
			vim.g.nvsinner_strings = saved
			vim.g.nvsinner_accent = "blue"
			vim.o.background = bg
		end)

		it("colors() applies the pack over base09 only, never the surfaces", function()
			local bg = vim.o.background
			vim.o.background = "dark"
			vim.g.nvsinner_accent = "green"
			local c = carbon.colors()
			assert.are.equal(carbon.accents.green.dark.base09, c.base09)
			assert.are.equal(carbon.dark.base00, c.base00, "gray surfaces must not change")
			assert.are.equal(carbon.dark.blend, c.blend)
			vim.g.nvsinner_accent = "blue"
			assert.are.equal(carbon.dark.base09, carbon.colors().base09)
			vim.o.background = bg
		end)
	end)
end)
