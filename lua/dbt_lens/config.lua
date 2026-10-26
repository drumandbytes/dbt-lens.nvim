local M = {}

---@class (partial) dbt_lens.Config
---@field cmd? string|string[] dbt executable override
---@field picker? 'auto'|'ui'|'snacks'|'telescope'
---@field keymaps? boolean|table<string, string|false>
---@field manifest? { warn_mb?: integer }
---@field log? { height?: integer }

---@type dbt_lens.Config
M.defaults = {
  cmd = nil,
  picker = 'auto',
  keymaps = false,
  manifest = { warn_mb = 100 },
  log = { height = 15 },
}

--- vim.g.dbt_lens may be a table or a function returning one.
---@return table user table as given, unvalidated
local function user_config()
  local g = vim.g.dbt_lens
  if type(g) == 'function' then g = g() end
  return type(g) == 'table' and g or {}
end

--- Merged config. Unknown keys are returned in `unknown` (reported by :checkhealth), not thrown.
---@return dbt_lens.Config config
---@return string[] unknown
function M.get()
  local user = user_config()
  local unknown = {}
  for key in pairs(user) do
    if M.defaults[key] == nil and key ~= 'cmd' then unknown[#unknown + 1] = tostring(key) end
  end
  table.sort(unknown)
  local cfg = vim.tbl_deep_extend('force', M.defaults, user)
  vim.validate('cmd', cfg.cmd, { 'string', 'table' }, true)
  vim.validate(
    'picker',
    cfg.picker,
    function(v) return vim.list_contains({ 'auto', 'ui', 'snacks', 'telescope' }, v) end,
    "one of 'auto', 'ui', 'snacks', 'telescope'"
  )
  vim.validate('keymaps', cfg.keymaps, { 'boolean', 'table' })
  vim.validate('manifest.warn_mb', cfg.manifest.warn_mb, 'number')
  vim.validate('log.height', cfg.log.height, 'number')
  return cfg, unknown
end

return M
