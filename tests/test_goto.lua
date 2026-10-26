local T = MiniTest.new_set()
local eq = MiniTest.expect.equality

--- A copy of the fixture project with the fixture manifest in its target dir.
local function project_copy()
  local dir = vim.uv.fs_realpath(vim.fn.tempname() .. '_x') or vim.fn.tempname()
  vim.fn.mkdir(dir .. '/project/target', 'p')
  vim.fn.system({ 'cp', '-R', 'tests/fixtures/project/.', dir .. '/project' })
  vim.fn.system({ 'cp', 'tests/fixtures/manifest.json', dir .. '/project/target/manifest.json' })
  local root = vim.uv.fs_realpath(dir .. '/project')
  require('dbt_lens.manifest').clear_cache()
  return root
end

local function cursor_on(needle)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  for i, l in ipairs(lines) do
    local c = l:find(needle, 1, true)
    if c then return vim.api.nvim_win_set_cursor(0, { i, c }) end
  end
  error('needle not found: ' .. needle)
end

T['goto'] = MiniTest.new_set({ hooks = { post_case = function() vim.g.dbt_lens = nil end } })

T['goto']['ref opens the model file'] = function()
  local root = project_copy()
  vim.cmd('edit ' .. root .. '/models/report_daily.sql')
  cursor_on "ref('fct_orders'"
  eq(require('dbt_lens').goto_definition(), true)
  eq(vim.api.nvim_buf_get_name(0), root .. '/models/fct_orders.sql')
end

T['goto']['source opens the yaml at the table line'] = function()
  local root = project_copy()
  vim.cmd('edit ' .. root .. '/models/stg_customers.sql')
  cursor_on "source('raw'"
  eq(require('dbt_lens').goto_definition(), true)
  eq(vim.api.nvim_buf_get_name(0), root .. '/models/sources.yml')
  eq(vim.api.nvim_win_get_cursor(0)[1], 7)
end

T['goto']['macro opens its definition'] = function()
  local root = project_copy()
  vim.cmd('edit ' .. root .. '/models/fct_orders.sql')
  cursor_on 'money('
  eq(require('dbt_lens').goto_definition(), true)
  eq(vim.api.nvim_buf_get_name(0), root .. '/macros/money.sql')
end

T['goto']['package ref and versioned ref'] = function()
  local root = project_copy()
  vim.cmd('edit ' .. root .. '/models/uses_versioned.sql')
  cursor_on "ref('versioned'"
  eq(require('dbt_lens').goto_definition(), true)
  eq(vim.api.nvim_buf_get_name(0), root .. '/models/versioned_v1.sql')
end

T['goto']['returns false off any construct, so gd can fall back'] = function()
  local root = project_copy()
  vim.cmd('edit ' .. root .. '/models/dim_customers.sql')
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  eq(require('dbt_lens').goto_definition({ quiet = true }), false)
end

T['references'] = function()
  local root = project_copy()
  vim.cmd('edit ' .. root .. '/models/stg_customers.sql')
  vim.cmd 'DbtLens references'
  local names = vim.tbl_map(function(i) return i.text end, vim.fn.getqflist())
  table.sort(names)
  eq(names, { 'demo.dim_customers', 'demo.fct_orders' })
end

T['yaml jumps to the model entry'] = function()
  local root = project_copy()
  vim.cmd('edit ' .. root .. '/models/fct_orders.sql')
  vim.cmd 'DbtLens yaml'
  eq(vim.api.nvim_buf_get_name(0), root .. '/models/schema.yml')
  eq(
    vim.api.nvim_buf_get_lines(0, vim.api.nvim_win_get_cursor(0)[1] - 1, vim.api.nvim_win_get_cursor(0)[1], false)[1],
    '  - name: fct_orders'
  )
end

T['keymaps'] = MiniTest.new_set({ hooks = { post_case = function() vim.g.dbt_lens = nil end } })

T['keymaps']['opt-in, buffer-local, only inside a dbt project'] = function()
  local root = project_copy()
  vim.cmd('edit ' .. root .. '/models/dim_customers.sql')
  eq(vim.fn.maparg('gd', 'n') == '', true) -- off by default

  vim.g.dbt_lens = { keymaps = true }
  vim.cmd 'edit! | set filetype=sql'
  eq(vim.fn.maparg('gd', 'n', false, true).buffer, 1)
  eq(vim.fn.maparg('<leader>dr', 'n', false, true).buffer, 1)

  vim.g.dbt_lens = { keymaps = { run = '<leader>xx', build = false } }
  vim.cmd('enew | edit ' .. root .. '/models/fct_orders.sql | set filetype=sql')
  eq(vim.fn.maparg('<leader>xx', 'n', false, true).buffer, 1)
  eq(vim.fn.maparg('<leader>db', 'n') == '', true)
end

return T
