vim.opt.rtp:prepend(vim.fn.getcwd())
local mini = vim.env.MINI_PATH or (vim.fn.getcwd() .. '/.deps/mini.nvim')
if not vim.uv.fs_stat(mini) then
  vim.fn.system({ 'git', 'clone', '--depth=1', 'https://github.com/echasnovski/mini.nvim', mini })
end
vim.opt.rtp:prepend(mini)
require('mini.test').setup()
vim.cmd 'runtime plugin/dbt-lens.lua' -- --noplugin skips it
