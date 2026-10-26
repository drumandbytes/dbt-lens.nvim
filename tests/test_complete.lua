local T = MiniTest.new_set()
local eq = MiniTest.expect.equality
local complete = require 'dbt_lens.complete'
local manifest = require 'dbt_lens.manifest'

local function fixture()
  local f = assert(io.open 'tests/fixtures/manifest.json')
  local decoded = vim.json.decode(f:read '*a', { luanil = { object = true, array = true } })
  f:close()
  return manifest.build_index(decoded, 'demo')
end

local function labels(items)
  local out = vim.tbl_map(function(i) return i.label end, items)
  table.sort(out)
  return out
end

T['context'] = MiniTest.new_set()

T['context']['ref, source and their second arguments'] = function()
  eq(complete.context "select * from {{ ref('", { kind = 'ref', prefix = '' })
  eq(complete.context 'select * from {{ ref("stg_o', { kind = 'ref', prefix = 'stg_o' })
  eq(complete.context "{{ ref( 'pkg_a', 'pk", { kind = 'ref_package', package = 'pkg_a', prefix = 'pk' })
  eq(complete.context "{{ source('", { kind = 'source', prefix = '' })
  eq(complete.context "{{ source('raw', 'or", { kind = 'source_table', source_name = 'raw', prefix = 'or' })
end

T['context']['nothing once the call is closed or outside Jinja'] = function()
  eq(complete.context "{{ ref('orders') }} and more", nil)
  eq(complete.context 'select 1', nil)
  eq(complete.context "-- ref('x') then", nil)
end

T['context']['macros inside an open Jinja block, with a package prefix'] = function()
  eq(complete.context 'select {{ mon', { kind = 'macro', prefix = 'mon' })
  eq(complete.context '{% set x = pkg_a.cen', { kind = 'macro', package = 'pkg_a', prefix = 'cen' })
  eq(complete.context 'select mon', nil) -- plain SQL
  eq(complete.context "{{ config(materialized='tab", nil) -- inside a string
  eq(complete.context '{{ x }} select mon', nil) -- the block is closed
end

T['items'] = MiniTest.new_set()

T['items']['ref lists models once (versions collapsed) and package names'] = function()
  local items = complete.items({ kind = 'ref', prefix = '' }, fixture())
  eq(labels(items), {
    'dim_customers',
    'fct_orders',
    'pkg_a',
    'pkg_only',
    'report_daily',
    'shared',
    'shared',
    'stg_customers',
    'stg_orders',
    'uses_pkg',
    'uses_versioned',
    'versioned',
  })
end

T['items']['ref_package only that package'] = function()
  eq(
    labels(complete.items({ kind = 'ref_package', package = 'pkg_a', prefix = '' }, fixture())),
    { 'pkg_only', 'shared' }
  )
end

T['items']['root project sorts first, package shown as detail'] = function()
  local items = complete.items({ kind = 'ref_package', package = 'pkg_a', prefix = '' }, fixture())
  eq(items[1].labelDetails.description, 'pkg_a')
  local root_items = vim.tbl_filter(
    function(i) return i.label == 'fct_orders' end,
    complete.items({ kind = 'ref', prefix = '' }, fixture())
  )
  eq(root_items[1].sortText, '0fct_orders')
  eq(root_items[1].labelDetails.description, 'table')
  eq(root_items[1].documentation.value:find('models/fct_orders.sql', 1, true) ~= nil, true)
end

T['items']['sources and tables'] = function()
  eq(labels(complete.items({ kind = 'source', prefix = '' }, fixture())), { 'raw' })
  eq(
    labels(complete.items({ kind = 'source_table', source_name = 'raw', prefix = '' }, fixture())),
    { 'customers', 'orders' }
  )
  eq(complete.items({ kind = 'source_table', source_name = 'nope', prefix = '' }, fixture()), {})
end

T['items']['macros, filtered by package'] = function()
  eq(labels(complete.items({ kind = 'macro', prefix = '' }, fixture())), { 'cents_to_dollars', 'money' })
  eq(labels(complete.items({ kind = 'macro', package = 'pkg_a', prefix = '' }, fixture())), { 'cents_to_dollars' })
end

T['blink source'] = MiniTest.new_set({ hooks = { post_case = function() vim.cmd 'silent! only' end } })

T['blink source']['answers get_completions inside a dbt project'] = function()
  local dir = vim.uv.fs_realpath(vim.fn.tempname() .. '_x') or vim.fn.tempname()
  vim.fn.mkdir(dir .. '/project/target', 'p')
  vim.fn.system({ 'cp', '-R', 'tests/fixtures/project/.', dir .. '/project' })
  vim.fn.system({ 'cp', 'tests/fixtures/manifest.json', dir .. '/project/target/manifest.json' })
  require('dbt_lens.manifest').clear_cache()
  local root = vim.uv.fs_realpath(dir .. '/project')
  vim.cmd('edit ' .. root .. '/models/dim_customers.sql')
  vim.bo.filetype = 'sql'

  local source = require('dbt_lens.blink').new()
  eq(source:enabled(), true)
  local got
  source:get_completions(
    { line = "select * from {{ ref('stg", cursor = { 1, 26 }, bufnr = vim.api.nvim_get_current_buf() },
    function(r) got = r end
  )
  eq(got.is_incomplete_forward, false)
  eq(vim.tbl_contains(labels(got.items), 'stg_orders'), true)

  -- the cached items are copied: blink mutating a result does not poison the next one
  got.items[1].label = 'MUTATED'
  source:get_completions(
    { line = "{{ ref('", cursor = { 1, 8 }, bufnr = vim.api.nvim_get_current_buf() },
    function(r) got = r end
  )
  eq(vim.tbl_contains(labels(got.items), 'MUTATED'), false)

  source:get_completions(
    { line = 'select 1', cursor = { 1, 8 }, bufnr = vim.api.nvim_get_current_buf() },
    function(r) got = r end
  )
  eq(got.items, {})
end

return T
