local T = MiniTest.new_set({ hooks = { post_case = function() vim.g.dbt_lens = nil end } })
local eq = MiniTest.expect.equality
local config = require 'dbt_lens.config'

T['defaults when unset'] = function()
  local cfg, unknown = config.get()
  eq(cfg.picker, 'auto')
  eq(cfg.keymaps, false)
  eq(unknown, {})
end

T['table and function forms merge over defaults'] = function()
  vim.g.dbt_lens = { picker = 'ui' }
  eq(config.get().picker, 'ui')
  vim.g.dbt_lens = function() return { picker = 'telescope' } end
  eq(config.get().picker, 'telescope')
end

T['unknown keys are reported, not thrown'] = function()
  vim.g.dbt_lens = { pickr = 'ui' }
  local _, unknown = config.get()
  eq(unknown, { 'pickr' })
end

T['invalid values throw'] = function()
  vim.g.dbt_lens = { picker = 'fzf' }
  MiniTest.expect.error(function() config.get() end)
end

return T
