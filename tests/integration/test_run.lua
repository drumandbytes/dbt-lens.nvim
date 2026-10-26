-- Real dbt (dbt-core 1.10 + dbt-duckdb through uvx); slow, run with `make test-integration`.
local T = MiniTest.new_set()
local eq = MiniTest.expect.equality

local FIXTURES = vim.fn.getcwd() .. '/tests/fixtures'
local DBT = { 'uvx', '--quiet', '--from', 'dbt-core==1.10.*', '--with', 'dbt-duckdb==1.10.*', 'dbt' }

local function copy_project()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, 'p')
  vim.fn.system({ 'cp', '-R', FIXTURES .. '/project', dir .. '/project' })
  vim.fn.system({ 'cp', '-R', FIXTURES .. '/pkg_a', dir .. '/pkg_a' })
  return dir .. '/project'
end

local function wait_for(fn, ms) return vim.wait(ms or 120000, fn, 200) end

T['refresh, run and failing run against dbt-duckdb'] = function()
  local root = copy_project()
  vim.env.DBT_PROFILES_DIR = root
  vim.g.dbt_lens = { cmd = DBT }
  vim.cmd('edit ' .. root .. '/models/shared.sql')
  local project = require('dbt_lens.project').get()
  local runner = require 'dbt_lens.runner'

  -- dbt deps (local package), then parse -> manifest
  local done
  runner.exec(project, { 'deps' }, function() done = true end)
  eq(wait_for(function() return done end), true)
  done = nil
  runner.exec(project, { 'parse' }, function(res)
    eq(res.code, 0)
    done = true
  end)
  eq(wait_for(function() return done end), true)
  local idx = require('dbt_lens.manifest').load(project)
  eq(idx.counts.model, 12)

  -- success: `shared` has no upstream
  local summary
  done = nil
  runner.run(project, 'run', 'demo.shared', {
    on_done = function(s)
      summary = s
      done = true
    end,
  })
  eq(wait_for(function() return done end), true)
  eq({ summary.ok, summary.failed }, { 1, 0 })
  local log =
    vim.api.nvim_buf_get_lines(vim.fn.bufnr 'dbt-lens-log' > 0 and vim.fn.bufnr 'dbt-lens-log' or 0, 0, -1, false)
  eq(#log > 0, true)

  -- failure: stg_orders reads a source table that does not exist
  done = nil
  runner.run(project, 'run', 'demo.stg_orders', {
    on_done = function(s)
      summary = s
      done = true
    end,
  })
  eq(wait_for(function() return done end), true)
  eq({ summary.ok, summary.failed }, { 0, 1 })
  eq(summary.qf[1].filename, vim.uv.fs_realpath(root) .. '/models/stg_orders.sql')
  eq(#vim.fn.getqflist(), 1)
end

T['compiled SQL and show against dbt-duckdb'] = function()
  local root = copy_project()
  vim.env.DBT_PROFILES_DIR = root
  vim.g.dbt_lens = { cmd = DBT }
  vim.cmd('edit ' .. root .. '/models/shared.sql')
  local project = require('dbt_lens.project').get()
  local runner = require 'dbt_lens.runner'

  local done
  runner.exec(project, { 'deps' }, function() done = true end)
  eq(wait_for(function() return done end), true)
  done = nil
  runner.exec(project, { 'parse' }, function() done = true end)
  eq(wait_for(function() return done end), true)

  vim.cmd('edit ' .. root .. '/models/shared.sql')
  vim.cmd 'DbtLens compiled'
  eq(wait_for(function() return vim.fn.expand '%:t' == 'shared.sql' and vim.bo.readonly end), true)
  eq(vim.api.nvim_buf_get_name(0), vim.uv.fs_realpath(root) .. '/target/compiled/demo/models/shared.sql')
  eq(vim.api.nvim_buf_get_lines(0, 0, -1, false)[1], "select 1 as id, 'project' as origin")
  eq(vim.bo.modifiable, false)

  vim.cmd('edit ' .. root .. '/models/shared.sql')
  vim.cmd 'DbtLens show'
  eq(wait_for(function() return vim.api.nvim_win_get_config(0).relative == 'editor' end), true)
  local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
  eq(text:find('| id | origin', 1, true) ~= nil, true)
  eq(text:find('project', 1, true) ~= nil, true)
  vim.cmd 'close'

  -- visual selection: inline SQL
  vim.cmd('edit ' .. root .. '/models/uses_pkg.sql')
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'select 7 as seven' })
  vim.cmd '1,1DbtLens show'
  eq(wait_for(function() return vim.api.nvim_win_get_config(0).relative == 'editor' end), true)
  eq(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n'):find('seven', 1, true) ~= nil, true)
end

return T
