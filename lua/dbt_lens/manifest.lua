local M = {}

---@class dbt_lens.Node
---@field uid string
---@field kind string model|seed|snapshot
---@field name string
---@field package string
---@field version? integer|string
---@field latest_version? integer|string
---@field fqn string[] dbt's fully qualified name, the safe selector (`demo.staging.stg_orders`)
---@field path string original_file_path (relative to its package root)
---@field patch_path? string
---@field materialized? string
---@field relation_name? string
---@field description? string
---@field refs { name: string, package?: string, version?: integer|string }[]
---@field sources string[][] { source_name, table }
---@field columns { name: string, description?: string, data_type?: string }[]

---@class dbt_lens.Source
---@field uid string
---@field source_name string
---@field name string table name
---@field package string
---@field path string yaml file, relative to its package root

---@class dbt_lens.Macro
---@field uid string
---@field name string
---@field package string
---@field path string

---@class dbt_lens.Index
---@field nodes table<string, dbt_lens.Node>
---@field sources table<string, dbt_lens.Source>
---@field tests table<string, { uid: string, name: string, package: string, path: string }> run_results lookup only
---@field macro_by_uid table<string, dbt_lens.Macro>
---@field by_name table<string, string[]> model name -> uids (root project first)
---@field by_file table<string, string> "<package>:<path>" -> uid
---@field source_by_key table<string, string[]> "<source>.<table>" -> uids
---@field macros table<string, dbt_lens.Macro[]> macro name -> macros (root project first)
---@field parents table<string, string[]>
---@field children table<string, string[]>
---@field counts table<string, integer>
---@field meta { dbt_version?: string, schema?: string, generated_at?: string, root_package?: string }

local REFABLE = { model = true, seed = true, snapshot = true }

---@param list string[]
---@param nodes table<string, { package: string, name?: string, version?: any }>
---@param root_package? string
local function sort_root_first(list, nodes, root_package)
  table.sort(list, function(a, b)
    local na, nb = nodes[a], nodes[b]
    local ra, rb = na.package == root_package, nb.package == root_package
    if ra ~= rb then return ra end
    if na.package ~= nb.package then return na.package < nb.package end
    return tostring(na.version or '') < tostring(nb.version or '')
  end)
end

--- Pure: decoded manifest.json -> lookup tables. Code bodies (raw_code, macro_sql, ...) are not kept.
---@param m table decoded manifest (null -> nil)
---@param root_package? string project name; its models win name clashes
---@return dbt_lens.Index
function M.build_index(m, root_package)
  ---@type dbt_lens.Index
  local idx = {
    nodes = {},
    sources = {},
    tests = {},
    macro_by_uid = {},
    by_name = {},
    by_file = {},
    source_by_key = {},
    macros = {},
    parents = {},
    children = {},
    counts = { model = 0, seed = 0, snapshot = 0, source = 0, macro = 0 },
    meta = {
      dbt_version = m.metadata and m.metadata.dbt_version,
      schema = m.metadata and m.metadata.dbt_schema_version,
      generated_at = m.metadata and m.metadata.generated_at,
      root_package = root_package,
    },
  }

  for uid, n in pairs(m.nodes or {}) do
    if REFABLE[n.resource_type] then
      local columns = {}
      for _, c in pairs(n.columns or {}) do
        columns[#columns + 1] = { name = c.name, description = c.description, data_type = c.data_type }
      end
      table.sort(columns, function(a, b) return a.name < b.name end)
      idx.nodes[uid] = {
        uid = uid,
        kind = n.resource_type,
        name = n.name,
        package = n.package_name,
        fqn = n.fqn or { n.package_name, n.name },
        version = n.version,
        latest_version = n.latest_version,
        path = n.original_file_path,
        patch_path = n.patch_path,
        materialized = n.config and n.config.materialized,
        relation_name = n.relation_name,
        description = n.description ~= '' and n.description or nil,
        refs = n.refs or {},
        sources = n.sources or {},
        columns = columns,
      }
      idx.counts[n.resource_type] = idx.counts[n.resource_type] + 1
      idx.by_name[n.name] = idx.by_name[n.name] or {}
      table.insert(idx.by_name[n.name], uid)
      idx.by_file[n.package_name .. ':' .. n.original_file_path] = uid
    end
    if n.resource_type == 'test' then
      idx.tests[uid] = { uid = uid, name = n.name, package = n.package_name, path = n.original_file_path }
    end
  end
  for _, uids in pairs(idx.by_name) do
    sort_root_first(uids, idx.nodes, root_package)
  end

  for uid, s in pairs(m.sources or {}) do
    idx.sources[uid] =
      { uid = uid, source_name = s.source_name, name = s.name, package = s.package_name, path = s.original_file_path }
    local key = s.source_name .. '.' .. s.name
    idx.source_by_key[key] = idx.source_by_key[key] or {}
    table.insert(idx.source_by_key[key], uid)
    idx.counts.source = idx.counts.source + 1
  end
  for _, uids in pairs(idx.source_by_key) do
    sort_root_first(uids, idx.sources, root_package)
  end

  for uid, mac in pairs(m.macros or {}) do
    local entry = { uid = uid, name = mac.name, package = mac.package_name, path = mac.original_file_path }
    idx.macro_by_uid[uid] = entry
    idx.macros[mac.name] = idx.macros[mac.name] or {}
    table.insert(idx.macros[mac.name], entry)
    idx.counts.macro = idx.counts.macro + 1
  end
  for _, list in pairs(idx.macros) do
    table.sort(list, function(a, b)
      local ra, rb = a.package == root_package, b.package == root_package
      if ra ~= rb then return ra end
      return a.package < b.package
    end)
  end

  -- graph: only models/seeds/snapshots and sources; tests and other node kinds are dropped at both ends
  local function known(uid) return idx.nodes[uid] ~= nil or idx.sources[uid] ~= nil end
  local function filtered(map, out)
    for uid, list in pairs(map or {}) do
      if known(uid) then
        local kept = {}
        for _, other in ipairs(list) do
          if known(other) then kept[#kept + 1] = other end
        end
        table.sort(kept)
        out[uid] = kept
      end
    end
  end
  filtered(m.parent_map, idx.parents)
  filtered(m.child_map, idx.children)
  return idx
end

--- Pure: the model/seed/snapshot behind a file inside the project. `rel` is relative to the project root;
--- files under the packages dir (`dbt_packages/<pkg>/...`) are matched inside their package.
---@param idx dbt_lens.Index
---@param project_name string
---@param rel string
---@param packages_path? string default dbt_packages
---@return dbt_lens.Node?
function M.node_for_path(idx, project_name, rel, packages_path)
  packages_path = (packages_path or 'dbt_packages') .. '/'
  local pkg, path = project_name, rel
  if vim.startswith(rel, packages_path) then
    pkg, path = rel:sub(#packages_path + 1):match '^([^/]+)/(.+)$'
    if not pkg then return nil end
  end
  local uid = idx.by_file[pkg .. ':' .. path]
  return uid and idx.nodes[uid] or nil
end

--- Pure: which model does `ref(name[, package][, v=version])` mean?
--- Package given: only that package. Otherwise the root project's model, else the only candidate.
--- A versioned model without an explicit version resolves to its latest version.
---@param idx dbt_lens.Index
---@param name string
---@param opts? { package?: string, version?: integer|string }
---@return dbt_lens.Node? node nil when none or ambiguous
---@return dbt_lens.Node[] candidates every model that matched (for asking the user when ambiguous)
function M.resolve_ref(idx, name, opts)
  opts = opts or {}
  local candidates = {}
  for _, uid in ipairs(idx.by_name[name] or {}) do
    local n = idx.nodes[uid]
    local pkg_ok = not opts.package or n.package == opts.package
    local ver_ok
    if opts.version ~= nil then
      ver_ok = tostring(n.version) == tostring(opts.version)
    else
      ver_ok = n.version == nil or n.latest_version == nil or tostring(n.version) == tostring(n.latest_version)
    end
    if pkg_ok and ver_ok then candidates[#candidates + 1] = n end
  end
  if #candidates == 1 then return candidates[1], candidates end
  if not opts.package then
    for _, n in ipairs(candidates) do
      if n.package == idx.meta.root_package then return n, candidates end
    end
  end
  return nil, candidates
end

---@type table<string, { stamp: string, index: dbt_lens.Index }>
local cache = {}

--- Index for a project's manifest, cached on mtime and size. When the file is unreadable (dbt is mid-write)
--- the previous index is kept and a warning returned alongside it.
---@param project dbt_lens.Project
---@return dbt_lens.Index? index
---@return string? err fatal when index is nil, otherwise a warning about a kept stale index
---@return { path: string, mtime: integer, size: integer }? info
function M.load(project)
  local path = project.target_path .. '/manifest.json'
  local stat = vim.uv.fs_stat(path)
  if not stat then return nil, 'no manifest at ' .. path end
  local info = { path = path, mtime = stat.mtime.sec, size = stat.size }
  local stamp = ('%d.%d:%d'):format(stat.mtime.sec, stat.mtime.nsec, stat.size)
  local cached = cache[path]
  if cached and cached.stamp == stamp then return cached.index, nil, info end

  local f = io.open(path, 'r')
  local text = f and f:read '*a'
  if f then f:close() end
  local ok, decoded = pcall(vim.json.decode, text or '', { luanil = { object = true, array = true } })
  if not ok or type(decoded) ~= 'table' then
    if cached then return cached.index, 'manifest unreadable, keeping the previous one', info end
    return nil, 'cannot read ' .. path .. ': ' .. tostring(decoded)
  end

  local index = M.build_index(decoded, project.name)
  cache[path] = { stamp = stamp, index = index }
  local warn_mb = require('dbt_lens.config').get().manifest.warn_mb
  if stat.size > warn_mb * 1024 * 1024 then
    return index, ('manifest is %.0f MB (warn threshold %d MB)'):format(stat.size / 1024 / 1024, warn_mb), info
  end
  return index, nil, info
end

function M.clear_cache() cache = {} end

return M
