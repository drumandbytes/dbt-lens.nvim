local T = MiniTest.new_set()
local eq = MiniTest.expect.equality
local graph = require 'dbt_lens.graph'
local lineage = require 'dbt_lens.lineage'
local manifest = require 'dbt_lens.manifest'

local function fixture()
  local f = assert(io.open 'tests/fixtures/manifest.json')
  local decoded = vim.json.decode(f:read '*a', { luanil = { object = true, array = true } })
  f:close()
  return manifest.build_index(decoded, 'demo')
end

local function texts(rows)
  return vim.tbl_map(function(r) return r.text end, rows)
end

T['graph.tree'] = MiniTest.new_set()

T['graph.tree']['depth limit and more-marker'] = function()
  local links = { a = { 'b' }, b = { 'c' }, c = { 'd' } }
  eq(graph.tree(links, 'a', 2), {
    { uid = 'b', depth = 1, again = false, more = false },
    { uid = 'c', depth = 2, again = false, more = true },
  })
  eq(vim.tbl_map(function(e) return e.uid end, graph.tree(links, 'a', 3, 'post')), { 'd', 'c', 'b' })
  eq(#graph.tree(links, 'a', 9), 3)
end

T['graph.tree']['diamonds are listed once, then marked again'] = function()
  local links = { root = { 'x', 'y' }, x = { 'z' }, y = { 'z' }, z = { 'w' } }
  eq(graph.tree(links, 'root', 3), {
    { uid = 'x', depth = 1, again = false, more = false },
    { uid = 'z', depth = 2, again = false, more = false },
    { uid = 'w', depth = 3, again = false, more = false },
    { uid = 'y', depth = 1, again = false, more = false },
    { uid = 'z', depth = 2, again = true, more = false },
  })
end

T['graph.tree']['cycles cannot loop'] = function()
  local links = { a = { 'b' }, b = { 'a' } }
  local entries = graph.tree(links, 'a', 9)
  eq(#entries, 2)
  eq({ entries[2].uid, entries[2].again }, { 'a', true }) -- the way back to the root is marked, not followed
end

T['graph.family_selector'] = function() eq(graph.family_selector({ 'demo', 'staging', 'x' }), '+demo.staging.x+') end

T['lineage.build'] = MiniTest.new_set()

T['lineage.build']['fct_orders with both directions'] = function()
  local rows = lineage.build(fixture(), 'model.demo.fct_orders', { up = 2, down = 2 })
  eq(texts(rows), {
    '▲ upstream',
    '    source   raw.customers',
    '  model    stg_customers',
    '    source   raw.orders',
    '  model    stg_orders',
    '● fct_orders',
    '▼ downstream',
    '  model    report_daily',
  })
  eq(rows[6].kind, 'root')
  eq(rows[6].mat, 'table')
  eq(rows[5].mat, 'view')
end

T['lineage.build']['diamond and depth cut-off markers'] = function()
  local rows = lineage.build(fixture(), 'model.demo.report_daily', { up = 2, down = 1 })
  eq(texts(rows), {
    '▲ upstream',
    '    model    stg_customers  …',
    '  model    dim_customers',
    '    model    stg_customers  ↺',
    '    model    stg_orders  …',
    '  model    fct_orders',
    '● report_daily',
    '▼ downstream (none)',
  })
end

T['lineage.build']['versioned models and package prefix'] = function()
  local rows = lineage.build(fixture(), 'model.demo.uses_pkg', { up = 1, down = 1 })
  eq(rows[2].text, '  model    pkg_a.pkg_only  …')
  rows = lineage.build(fixture(), 'model.demo.uses_versioned', { up = 1, down = 1 })
  eq(rows[2].text, '  model    versioned v1')
end

return T
