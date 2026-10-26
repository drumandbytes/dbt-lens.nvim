local T = MiniTest.new_set()
local eq = MiniTest.expect.equality

local function project_copy()
  local dir = vim.uv.fs_realpath(vim.fn.tempname() .. '_x') or vim.fn.tempname()
  vim.fn.mkdir(dir .. '/project/target', 'p')
  vim.fn.system({ 'cp', '-R', 'tests/fixtures/project/.', dir .. '/project' })
  vim.fn.system({ 'cp', 'tests/fixtures/manifest.json', dir .. '/project/target/manifest.json' })
  require('dbt_lens.manifest').clear_cache()
  return vim.uv.fs_realpath(dir .. '/project')
end

local function lines() return vim.api.nvim_buf_get_lines(0, 0, -1, false) end
local function press(lhs) vim.fn.maparg(lhs, 'n', false, true).callback() end
local function goto_line(text)
  for i, l in ipairs(lines()) do
    if l:find(text, 1, true) then return vim.api.nvim_win_set_cursor(0, { i, 0 }) end
  end
  error('no line with ' .. text)
end

T['view'] = MiniTest.new_set({
  hooks = {
    pre_case = function() vim.cmd 'silent! only | enew' end,
    post_case = function()
      vim.g.dbt_lens = nil
      pcall(vim.cmd, 'silent! only')
    end,
  },
})

T['view']['opens a split for the current model, cursor on the root'] = function()
  local root = project_copy()
  vim.cmd('edit ' .. root .. '/models/fct_orders.sql')
  vim.cmd 'DbtLens lineage'
  eq(vim.bo.filetype, 'dbt-lens-lineage')
  eq(lines()[6], '● fct_orders')
  eq(vim.api.nvim_get_current_line(), '● fct_orders')
  eq(vim.wo.winbar:find('lineage: fct_orders', 1, true) ~= nil, true)
end

T['view']['r re-roots, + and - change the depth'] = function()
  local root = project_copy()
  vim.cmd('edit ' .. root .. '/models/fct_orders.sql')
  vim.cmd 'DbtLens lineage'
  goto_line 'report_daily'
  press 'r'
  eq(vim.api.nvim_get_current_line(), '● report_daily')

  press '-'
  eq(vim.wo.winbar:find('▲1 ▼1', 1, true) ~= nil, true)
  press '+'
  press '+'
  eq(vim.wo.winbar:find('▲3 ▼3', 1, true) ~= nil, true)
end

T['view']['<CR> opens the file in the other window'] = function()
  local root = project_copy()
  vim.cmd('edit ' .. root .. '/models/fct_orders.sql')
  vim.cmd 'DbtLens lineage'
  goto_line 'stg_orders'
  press '<CR>'
  eq(vim.api.nvim_buf_get_name(0), root .. '/models/stg_orders.sql')
end

T['view']['<CR> on a source opens its yaml'] = function()
  local root = project_copy()
  vim.cmd('edit ' .. root .. '/models/fct_orders.sql')
  vim.cmd 'DbtLens lineage'
  for i, l in ipairs(lines()) do
    if l:find('raw.orders', 1, true) then vim.api.nvim_win_set_cursor(0, { i, 0 }) end
  end
  press '<CR>'
  eq(vim.api.nvim_buf_get_name(0), root .. '/models/sources.yml')
end

T['view']['y yanks the +model+ selector'] = function()
  local root = project_copy()
  vim.cmd('edit ' .. root .. '/models/fct_orders.sql')
  vim.cmd 'DbtLens lineage'
  press 'y'
  eq(vim.fn.getreg '"', '+demo.fct_orders+')
end

T['view']['lineage with a model name argument'] = function()
  local root = project_copy()
  vim.cmd('edit ' .. root .. '/models/dim_customers.sql')
  vim.cmd 'DbtLens lineage report_daily'
  eq(vim.api.nvim_get_current_line(), '● report_daily')
end

return T
