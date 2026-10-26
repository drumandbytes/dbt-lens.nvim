local T = MiniTest.new_set()
local eq = MiniTest.expect.equality
local nav = require 'dbt_lens.nav'
local manifest = require 'dbt_lens.manifest'

---@param s string e.g. 'select {{ ref("a")| }}': `|` marks the cursor
local function at(s)
  local before, after = s:match '^(.-)|(.*)$'
  local text = before .. after
  local lines = vim.split(text, '\n', { plain = true })
  local row = select(2, before:gsub('\n', '\n')) + 1
  local col = #before:match '[^\n]*$'
  return nav.at_cursor(lines, row, col)
end

T['constructs'] = MiniTest.new_set()

T['constructs']['ref forms'] = function()
  eq(at([[select * from {{ ref('o|rders') }}]]).name, 'orders')
  eq(at([[select * from {{ ref("o|rders") }}]]).name, 'orders')
  eq(at([[{{-ref( 'orders'| )-}}]]).name, 'orders')
  local c = at [[{{ ref('pkg_a', 'pkg_o|nly') }}]]
  eq({ c.name, c.package }, { 'pkg_only', 'pkg_a' })
  c = at [[{{ ref('versioned', v=1|) }}]]
  eq({ c.name, c.version }, { 'versioned', '1' })
  c = at [[{{ ref('versioned', version = 2|) }}]]
  eq(c.version, '2')
end

T['constructs']['source'] = function()
  local c = at [[from {{ source('raw', 'ord|ers') }}]]
  eq({ c.kind, c.source_name, c.name }, { 'source', 'raw', 'orders' })
end

T['constructs']['macro, with and without package'] = function()
  local c = at [[{{ mon|ey('o.amount') }}]]
  eq({ c.kind, c.name, c.package }, { 'macro', 'money', nil })
  c = at [[{{ pkg_a.cents_to_|dollars(column) }}]]
  eq({ c.name, c.package }, { 'cents_to_dollars', 'pkg_a' })
end

T['constructs']['innermost call wins'] = function()
  eq(at([[{{ money(ref('o|rders')) }}]]).kind, 'ref')
  eq(at([[{{ mon|ey(ref('orders')) }}]]).kind, 'macro')
end

T['constructs']['multi-line calls'] = function()
  local c = at "{{ ref(\n  'pkg_a',\n  'pkg_o|nly'\n) }}"
  eq({ c.name, c.package }, { 'pkg_only', 'pkg_a' })
end

T['constructs']['inside {% set %} and {% if %}'] = function()
  eq(at([[{% set x = ref('or|ders') %}]]).name, 'orders')
  eq(at([[{% if is_incremental() %} {{ ref('or|ders') }} {% endif %}]]).name, 'orders')
end

T['constructs']['jinja comments and plain SQL are ignored'] = function()
  eq(at [[{# ref('or|ders') #}]], nil)
  eq(at [[select ref('or|ders') from t]], nil)
  eq(at [[select 1| from t]], nil)
end

T['constructs']['cursor outside the call'] = function() eq(at [[sel|ect {{ ref('orders') }}]], nil) end

T['line finders'] = MiniTest.new_set()

T['line finders']['macro definition'] = function()
  local lines = { '-- x', '{% macro other() %}', '{%- macro money(column) -%}', '{% endmacro %}' }
  eq(nav.find_macro_line(lines, 'money'), 3)
  eq(nav.find_macro_line(lines, 'nope'), nil)
end

T['line finders']['source table inside its source'] = function()
  local lines = vim.split(
    [[
version: 2
sources:
  - name: other
    tables:
      - name: orders
  - name: raw
    tables:
      - name: customers
      - name: "orders"
models:
  - name: orders]],
    '\n'
  )
  eq(nav.find_source_line(lines, 'raw', 'orders'), 9)
  eq(nav.find_source_line(lines, 'other', 'orders'), 5)
  eq(nav.find_source_line(lines, 'raw', 'missing'), 6) -- falls back to the source
  eq(nav.find_source_line(lines, 'nope', 'orders'), nil)
end

T['line finders']['model entry'] = function()
  eq(nav.find_entry_line({ 'models:', '  - name: a', '  - name: fct_orders' }, 'fct_orders'), 3)
end

T['resolve'] = MiniTest.new_set()

local function fixture()
  local f = assert(io.open 'tests/fixtures/manifest.json')
  local decoded = vim.json.decode(f:read '*a', { luanil = { object = true, array = true } })
  f:close()
  return manifest.build_index(decoded, 'demo')
end
local project = {
  name = 'demo',
  root = vim.fn.fnamemodify('tests/fixtures/project', ':p'):gsub('/$', ''),
  packages_path = '../pkg_a_parent',
}

T['resolve']['model, source line, macro line'] = function()
  local idx = fixture()
  local t = nav.resolve({ kind = 'ref', name = 'fct_orders' }, idx, project)
  eq(t.file, project.root .. '/models/fct_orders.sql')
  eq(t.label, 'demo.fct_orders')

  t = nav.resolve({ kind = 'source', source_name = 'raw', name = 'customers' }, idx, project)
  eq({ vim.fn.fnamemodify(t.file, ':t'), t.line }, { 'sources.yml', 7 })

  t = nav.resolve({ kind = 'macro', name = 'money' }, idx, project)
  eq({ vim.fn.fnamemodify(t.file, ':t'), t.line }, { 'money.sql', 1 })
end

T['resolve']['unknown names give a message, builtins give nothing'] = function()
  local idx = fixture()
  local t, msg = nav.resolve({ kind = 'ref', name = 'nope' }, idx, project)
  eq(t, nil)
  eq(msg:find "no model 'nope'" ~= nil, true)
  t, msg = nav.resolve({ kind = 'macro', name = 'is_incremental' }, idx, project)
  eq({ t, msg }, {})
end

T['resolve']['package macro not on disk is explained'] = function()
  local t, msg = nav.resolve({ kind = 'macro', name = 'cents_to_dollars', package = 'pkg_a' }, fixture(), project)
  eq(t, nil)
  eq(msg:find 'not on disk' ~= nil, true)
end

return T
