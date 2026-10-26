if vim.g.loaded_dbt_lens then return end
vim.g.loaded_dbt_lens = true

vim.api.nvim_create_user_command('DbtLens', function(opts) require('dbt_lens').command(opts) end, {
  nargs = '*',
  complete = function(arglead, cmdline, pos) return require('dbt_lens').complete(arglead, cmdline, pos) end,
  desc = 'dbt-lens: run dbt, navigate, lineage',
})
