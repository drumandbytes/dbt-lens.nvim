test:
	nvim --headless --noplugin -u tests/minimal_init.lua -c "lua MiniTest.run({ collect = { find_files = function() return vim.fn.globpath('tests', 'test_*.lua', true, true) end } })"
