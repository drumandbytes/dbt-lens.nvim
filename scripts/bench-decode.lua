-- nvim --headless -l scripts/bench-decode.lua [copies]
-- Decode + index time for a synthetic manifest: the fixture's nodes cloned `copies` times, each with a ~4 KB code body.
local copies = tonumber(arg[1]) or 2000
local f = assert(io.open 'tests/fixtures/manifest.json')
local base = vim.json.decode(f:read '*a')
f:close()
local body = ('select * from t where x = 1\n'):rep(150)
local m = {
  metadata = base.metadata,
  nodes = {},
  sources = base.sources,
  macros = base.macros,
  parent_map = {},
  child_map = {},
  disabled = {},
}
for i = 1, copies do
  for uid, n in pairs(base.nodes) do
    local c = vim.deepcopy(n)
    c.raw_code, c.compiled_code = body, body
    local u = uid .. '_' .. i
    c.unique_id, c.name = u, c.name .. '_' .. i
    m.nodes[u] = c
    m.parent_map[u] = {}
    m.child_map[u] = {}
  end
end
local text = vim.json.encode(m)
local t0 = vim.uv.hrtime()
local decoded = vim.json.decode(text, { luanil = { object = true, array = true } })
local t1 = vim.uv.hrtime()
vim.opt.rtp:prepend(vim.fn.getcwd())
require('dbt_lens.manifest').build_index(decoded, 'demo')
local t2 = vim.uv.hrtime()
print(
  ('%.0f MB, %d nodes: decode %.0f ms, index %.0f ms'):format(
    #text / 1048576,
    copies * 14,
    (t1 - t0) / 1e6,
    (t2 - t1) / 1e6
  )
)
