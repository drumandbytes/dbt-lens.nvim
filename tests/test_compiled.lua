local T = MiniTest.new_set()
local eq = MiniTest.expect.equality
local compiled = require 'dbt_lens.compiled'

T['path'] = function()
  local project = { target_path = '/p/target' }
  eq(
    compiled.path(project, { package = 'demo', path = 'models/staging/stg.sql' }),
    '/p/target/compiled/demo/models/staging/stg.sql'
  )
  eq(
    compiled.path(project, { package = 'pkg_a', path = 'models/shared.sql' }),
    '/p/target/compiled/pkg_a/models/shared.sql'
  )
end

T['is_stale'] = function()
  eq(compiled.is_stale(nil, 10, false), true) -- missing
  eq(compiled.is_stale(20, 10, false), false) -- compiled after the source changed
  eq(compiled.is_stale(10, 20, false), true) -- source edited since
  eq(compiled.is_stale(20, 10, true), true) -- forced
  eq(compiled.is_stale(20, nil, false), false)
end

T['show_args'] = function()
  eq(compiled.show_args({ selector = 'demo.x', limit = 20 }), { 'show', '-s', 'demo.x', '--limit', '20', '--quiet' })
  eq(compiled.show_args({ sql = 'select 1', limit = 5 }), { 'show', '--inline', 'select 1', '--limit', '5', '--quiet' })
end

return T
