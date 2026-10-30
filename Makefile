# Test suite (plenary busted). plenary.nvim is already present as a telescope
# dependency. Run all specs:   make test
# Run one file:                make test-file FILE=tests/core/options_spec.lua
# Opt in to the pre-push gate (stylua --check, selene, make test) for this clone:
#                              make hooks
.PHONY: test test-file hooks

hooks:
	git config core.hooksPath .githooks
	chmod +x .githooks/pre-push

test:
	nvim --headless --noplugin -u tests/minimal_init.lua \
		-c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua', sequential = true }"

test-file:
	nvim --headless --noplugin -u tests/minimal_init.lua \
		-c "PlenaryBustedDirectory $(FILE) { minimal_init = 'tests/minimal_init.lua', sequential = true }"
