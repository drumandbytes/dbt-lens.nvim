local T = MiniTest.new_set()
local eq = MiniTest.expect.equality
local runner = require 'dbt_lens.runner'
local manifest = require 'dbt_lens.manifest'

local function fixture()
  local f = assert(io.open 'tests/fixtures/manifest.json')
  local decoded = vim.json.decode(f:read '*a', { luanil = { object = true, array = true } })
  f:close()
  return manifest.build_index(decoded, 'demo')
end

local project = { name = 'demo', root = '/proj', packages_path = 'dbt_packages' }

T['expand_selector'] = MiniTest.new_set()

T['expand_selector']['substitutes % with the fqn selector'] = function()
  local node = fixture().nodes['model.demo.fct_orders']
  eq(runner.expand_selector('+%+', node), '+demo.fct_orders+')
  eq(runner.expand_selector('1+%', node), '1+demo.fct_orders')
  eq(runner.expand_selector('tag:nightly', nil), 'tag:nightly')
end

T['expand_selector']['% without a model is nil'] = function() eq(runner.expand_selector('+%', nil), nil) end

T['expand_selector']['versioned models select by version fqn'] = function()
  eq(runner.expand_selector('%', fixture().nodes['model.demo.versioned.v2']), 'demo.versioned.v2')
end

T['summarize'] = MiniTest.new_set()

T['summarize']['counts and quickfix for failures and failing tests'] = function()
  local idx = fixture()
  local s = runner.summarize({
    { unique_id = 'model.demo.shared', status = 'success' },
    {
      unique_id = 'model.demo.stg_orders',
      status = 'error',
      message = 'Runtime Error\n  Table raw.orders does not exist',
    },
    { unique_id = 'test.demo.unique_stg_orders_id.beb6e97f2f', status = 'fail', message = 'Got 2 results' },
    { unique_id = 'model.demo.report_daily', status = 'skipped' },
    { unique_id = 'test.demo.not_null_stg_orders_id.8cf5724805', status = 'warn' },
  }, idx, project)
  eq({ s.ok, s.failed, s.warned, s.skipped }, { 1, 2, 1, 1 })
  eq(s.qf[1], { filename = '/proj/models/stg_orders.sql', lnum = 1, text = 'stg_orders: Runtime Error' })
  eq(s.qf[2].filename, '/proj/models/schema.yml')
  eq(s.qf[2].text, 'unique_stg_orders_id: Got 2 results')
end

T['summarize']['package models point into the packages dir'] = function()
  local s =
    runner.summarize({ { unique_id = 'model.pkg_a.pkg_only', status = 'error', message = 'boom' } }, fixture(), project)
  eq(s.qf[1].filename, '/proj/dbt_packages/pkg_a/models/pkg_only.sql')
end

T['format_summary'] = function()
  eq(
    runner.format_summary({ ok = 3, failed = 1, warned = 0, skipped = 2, qf = {} }, 12.34),
    '3 ok, 1 failed, 2 skipped in 12.3 s'
  )
end

T['node_for_path'] = MiniTest.new_set()

T['node_for_path']['project and package files'] = function()
  local idx = fixture()
  eq(manifest.node_for_path(idx, 'demo', 'models/shared.sql').uid, 'model.demo.shared')
  eq(manifest.node_for_path(idx, 'demo', 'dbt_packages/pkg_a/models/shared.sql').uid, 'model.pkg_a.shared')
  eq(manifest.node_for_path(idx, 'demo', 'models/schema.yml'), nil)
  eq(
    manifest.node_for_path(idx, 'demo', 'custom_pkgs/pkg_a/models/pkg_only.sql', 'custom_pkgs').uid,
    'model.pkg_a.pkg_only'
  )
end

return T
