--- blink.cmp source. Register it in blink's `sources.providers`:
---   dbt_lens = { name = 'dbt', module = 'dbt_lens.blink' }
---@type blink.cmp.Source
local M = {}

local FILETYPES = { sql = true, jinja = true, ['sql.jinja'] = true }

---@type table<dbt_lens.Index, table<string, table[]>> items per index and context, built once
local cache = setmetatable({}, { __mode = 'k' })

function M.new() return setmetatable({}, { __index = M }) end

function M:enabled() return FILETYPES[vim.bo.filetype] == true and vim.fs.root(0, 'dbt_project.yml') ~= nil end

function M:get_trigger_characters() return { "'", '"' } end

function M:get_completions(ctx, callback)
  local function reply(items) callback({ items = items, is_incomplete_forward = false, is_incomplete_backward = false }) end
  local complete = require 'dbt_lens.complete'
  local c = complete.context(ctx.line:sub(1, ctx.cursor[2]))
  local project = c and require('dbt_lens.project').get(ctx.bufnr)
  local idx = project and require('dbt_lens.manifest').load(project)
  if not idx then
    reply({})
    return function() end
  end
  local key = table.concat({ c.kind, c.package or '', c.source_name or '' }, '|')
  cache[idx] = cache[idx] or {}
  cache[idx][key] = cache[idx][key] or complete.items(c, idx)
  reply(vim.deepcopy(cache[idx][key])) -- blink mutates the items it is given
  return function() end
end

return M
