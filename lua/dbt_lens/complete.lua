--- Pure completion logic (no vim.* beyond what the callers pass in): what is being typed, and the items for it.
local M = {}

---@class dbt_lens.CompleteContext
---@field kind 'ref'|'ref_package'|'source'|'source_table'|'macro'
---@field package? string ref_package: the package; macro: the `pkg.` prefix
---@field source_name? string
---@field prefix string what is typed so far

local Q = [=[['"]]=]

--- True when the cursor sits inside an unclosed `{{ ... }}` or `{% ... %}`.
---@param before string
local function in_jinja(before)
  local open = 0
  for pos in before:gmatch '()[{][{%%]' do
    open = pos
  end
  if open == 0 then return false end
  local close = 0
  for pos in before:gmatch '()[}%%][}]' do
    close = pos
  end
  return close < open
end

--- What the text before the cursor asks for, or nil.
---@param before string line text up to the cursor
---@return dbt_lens.CompleteContext?
function M.context(before)
  local pkg, prefix = before:match('ref%(%s*' .. Q .. '([^\'"]+)' .. Q .. '%s*,%s*' .. Q .. '([^\'"]*)$')
  if pkg then return { kind = 'ref_package', package = pkg, prefix = prefix } end
  prefix = before:match('ref%(%s*' .. Q .. '([^\'"]*)$')
  if prefix then return { kind = 'ref', prefix = prefix } end

  local src, tbl = before:match('source%(%s*' .. Q .. '([^\'"]+)' .. Q .. '%s*,%s*' .. Q .. '([^\'"]*)$')
  if src then return { kind = 'source_table', source_name = src, prefix = tbl } end
  prefix = before:match('source%(%s*' .. Q .. '([^\'"]*)$')
  if prefix then return { kind = 'source', prefix = prefix } end

  if in_jinja(before) then
    -- not inside a string literal
    local _, quotes = before:gsub('[\'"]', '')
    local p, name = before:match '([%a_][%w_]*)%.([%w_]*)$'
    if p and quotes % 2 == 0 then return { kind = 'macro', package = p, prefix = name } end
    name = before:match '[^%w_%.]([%a_][%w_]*)$'
    if name and quotes % 2 == 0 then return { kind = 'macro', prefix = name } end
  end
end

-- LSP CompletionItemKind numbers (spelled out so this module stays pure)
local KIND = { function_ = 3, module = 9, folder = 19, struct = 22 }

---@param n dbt_lens.Node
---@return string
local function model_doc(n)
  local out = { ('**%s**%s'):format(n.name, n.version ~= nil and (' v' .. tostring(n.version)) or '') }
  if n.description then out[#out + 1] = n.description end
  out[#out + 1] = ('`%s` · %s · %s'):format(n.path, n.package, n.materialized or n.kind)
  if #n.columns > 0 then
    out[#out + 1] = 'Columns: '
      .. table.concat(vim.tbl_map(function(c) return c.name end, vim.list_slice(n.columns, 1, 12)), ', ')
      .. (#n.columns > 12 and ', ...' or '')
  end
  return table.concat(out, '\n\n')
end

---@param idx dbt_lens.Index
---@param pkg? string only models of this package
---@return table[]
local function model_items(idx, pkg)
  local items, seen = {}, {}
  for _, uids in pairs(idx.by_name) do
    for _, uid in ipairs(uids) do
      local n = idx.nodes[uid]
      local key = n.package .. '/' .. n.name -- versions of one model are one entry
      if
        not seen[key]
        and (not pkg or n.package == pkg)
        and (n.latest_version == nil or n.version == n.latest_version)
      then
        seen[key] = true
        items[#items + 1] = {
          label = n.name,
          insertText = n.name,
          kind = KIND.module,
          sortText = (n.package == idx.meta.root_package and '0' or '1') .. n.name,
          labelDetails = {
            description = n.package == idx.meta.root_package and (n.materialized or n.kind) or n.package,
          },
          documentation = { kind = 'markdown', value = model_doc(n) },
        }
      end
    end
  end
  return items
end

--- Plain LSP-shaped items for a context; callers must copy them before handing them to blink (it mutates).
---@param ctx dbt_lens.CompleteContext
---@param idx dbt_lens.Index
---@return table[]
function M.items(ctx, idx)
  if ctx.kind == 'ref' or ctx.kind == 'ref_package' then
    local items = model_items(idx, ctx.package)
    if ctx.kind == 'ref' then -- the first argument may also be a package name
      local pkgs = {}
      for _, n in pairs(idx.nodes) do
        pkgs[n.package] = true
      end
      pkgs[idx.meta.root_package or ''] = nil
      for p in pairs(pkgs) do
        items[#items + 1] = {
          label = p,
          insertText = p,
          kind = KIND.folder,
          sortText = '2' .. p,
          labelDetails = { description = 'package' },
        }
      end
    end
    return items
  elseif ctx.kind == 'source' then
    local names = {}
    for _, s in pairs(idx.sources) do
      names[s.source_name] = (names[s.source_name] or 0) + 1
    end
    local items = {}
    for name, count in pairs(names) do
      items[#items + 1] =
        { label = name, insertText = name, kind = KIND.struct, labelDetails = { description = count .. ' tables' } }
    end
    return items
  elseif ctx.kind == 'source_table' then
    local items = {}
    for _, s in pairs(idx.sources) do
      if s.source_name == ctx.source_name then
        items[#items + 1] =
          { label = s.name, insertText = s.name, kind = KIND.struct, documentation = ('`%s`'):format(s.path) }
      end
    end
    return items
  end

  local items = {}
  for name, list in pairs(idx.macros) do
    -- adapter implementations (`default__x`, `duckdb__x`), materializations and tests are not called by name
    if not name:find '__' and not vim.startswith(name, 'materialization_') and not vim.startswith(name, 'test_') then
      for _, m in ipairs(list) do
        if not ctx.package or m.package == ctx.package then
          items[#items + 1] = {
            label = name,
            insertText = name,
            kind = KIND.function_,
            sortText = (m.package == idx.meta.root_package and '0' or '1') .. name,
            labelDetails = { description = m.package },
            documentation = ('`%s`'):format(m.path),
          }
        end
      end
    end
  end
  return items
end

return M
