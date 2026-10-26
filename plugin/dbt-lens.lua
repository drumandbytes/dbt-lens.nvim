if vim.g.loaded_dbt_lens then return end
vim.g.loaded_dbt_lens = true

vim.api.nvim_create_user_command('DbtLens', function(opts) require('dbt_lens').command(opts) end, {
  nargs = '*',
  bang = true,
  range = true,
  complete = function(arglead, cmdline, pos) return require('dbt_lens').complete(arglead, cmdline, pos) end,
  desc = 'dbt-lens: run dbt, navigate, lineage',
})

for _, sub in ipairs({
  'run',
  'test',
  'build',
  'models',
  'refresh',
  'status',
  'cancel',
  'goto',
  'references',
  'yaml',
  'lineage',
  'compiled',
  'show',
}) do
  vim.keymap.set(
    'n',
    '<Plug>(dbt-lens-' .. sub .. ')',
    '<Cmd>DbtLens ' .. sub .. '<CR>',
    { desc = 'dbt-lens: ' .. sub }
  )
end
