local T = MiniTest.new_set()
local eq = MiniTest.expect.equality
local manifest = require 'dbt_lens.manifest'

local function fixture()
  local f = assert(io.open 'tests/fixtures/manifest.json')
  local decoded = vim.json.decode(f:read '*a', { luanil = { object = true, array = true } })
  f:close()
  return manifest.build_index(decoded, 'demo')
end

T['build_index'] = MiniTest.new_set()

T['build_index']['counts and meta'] = function()
  local idx = fixture()
  eq(idx.counts, { model = 12, seed = 0, snapshot = 0, source = 2, macro = 2 })
  eq(idx.meta.dbt_version, '1.10.23')
  eq(idx.meta.root_package, 'demo')
end

T['build_index']['tests and disabled models are not in the index'] = function()
  local idx = fixture()
  for uid in pairs(idx.nodes) do
    eq(uid:match '^model%.' ~= nil, true)
  end
  eq(idx.nodes['model.demo.disabled_model'], nil)
  eq(idx.by_name['disabled_model'], nil)
end

T['build_index']['graph drops test nodes at both ends'] = function()
  local idx = fixture()
  eq(idx.children['model.demo.stg_orders'], { 'model.demo.fct_orders' })
  eq(idx.parents['model.demo.fct_orders'], { 'model.demo.stg_customers', 'model.demo.stg_orders' })
  eq(idx.parents['model.demo.stg_orders'], { 'source.demo.raw.orders' })
  eq(idx.children['source.demo.raw.orders'], { 'model.demo.stg_orders' })
end

T['build_index']['same file path in two packages stays distinct'] = function()
  local idx = fixture()
  eq(idx.by_file['demo:models/shared.sql'], 'model.demo.shared')
  eq(idx.by_file['pkg_a:models/shared.sql'], 'model.pkg_a.shared')
end

T['build_index']['duplicate names list the root project first'] = function()
  local idx = fixture()
  eq(idx.by_name['shared'], { 'model.demo.shared', 'model.pkg_a.shared' })
end

T['build_index']['sources, macros and columns'] = function()
  local idx = fixture()
  eq(idx.source_by_key['raw.orders'], { 'source.demo.raw.orders' })
  eq(idx.sources['source.demo.raw.orders'].path, 'models/sources.yml')
  eq(idx.macros['money'][1].package, 'demo')
  eq(idx.macros['cents_to_dollars'][1].path, 'macros/pkg_macros.sql')
  eq(idx.nodes['model.demo.stg_orders'].columns[1].name, 'id')
  eq(idx.nodes['model.demo.stg_orders'].description, 'Orders, one row each')
end

T['resolve_ref'] = MiniTest.new_set()

T['resolve_ref']['unique name'] = function()
  local node = manifest.resolve_ref(fixture(), 'fct_orders')
  eq(node.uid, 'model.demo.fct_orders')
end

T['resolve_ref']['root project wins a name clash, package form picks the package'] = function()
  local idx = fixture()
  eq(manifest.resolve_ref(idx, 'shared').uid, 'model.demo.shared')
  eq(manifest.resolve_ref(idx, 'shared', { package = 'pkg_a' }).uid, 'model.pkg_a.shared')
  eq(manifest.resolve_ref(idx, 'pkg_only', { package = 'pkg_a' }).uid, 'model.pkg_a.pkg_only')
end

T['resolve_ref']['versions: explicit, and latest by default'] = function()
  local idx = fixture()
  eq(manifest.resolve_ref(idx, 'versioned', { version = 1 }).uid, 'model.demo.versioned.v1')
  eq(manifest.resolve_ref(idx, 'versioned').uid, 'model.demo.versioned.v2')
end

T['resolve_ref']['unknown name returns nothing'] = function()
  local node, candidates = manifest.resolve_ref(fixture(), 'nope')
  eq(node, nil)
  eq(candidates, {})
end

T['load'] = MiniTest.new_set()

T['load']['caches on mtime, keeps the last good index on a broken file'] = function()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, 'p')
  local project = { name = 'demo', target_path = dir }
  eq((manifest.load(project)), nil) -- no manifest yet

  vim.fn.writefile(vim.fn.readfile 'tests/fixtures/manifest.json', dir .. '/manifest.json')
  manifest.clear_cache()
  local idx1, err1, info = manifest.load(project)
  eq(err1, nil)
  eq(idx1.counts.model, 12)
  eq(info.path, dir .. '/manifest.json')
  eq((manifest.load(project)), idx1) -- same table: served from cache

  vim.fn.writefile({ '{ "nodes": ' }, dir .. '/manifest.json')
  local idx2, err2 = manifest.load(project)
  eq(idx2, idx1)
  eq(err2, 'manifest unreadable, keeping the previous one')
end

return T
