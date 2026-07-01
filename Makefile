# Test suite (plenary busted). plenary.nvim is already present as a telescope
# dependency. Run all specs:   make test
# Run one file:                make test-file FILE=tests/core/options_spec.lua
.PHONY: test test-file

test:
	nvim --headless --noplugin -u tests/minimal_init.lua \
		-c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua', sequential = true }"

test-file:
	nvim --headless --noplugin -u tests/minimal_init.lua \
		-c "PlenaryBustedFile $(FILE)"
