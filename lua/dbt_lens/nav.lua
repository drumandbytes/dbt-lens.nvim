local M = {}

---@class dbt_lens.Construct
---@field kind 'ref'|'source'|'macro'
---@field name string model name, source table name, or macro name
---@field package? string
---@field version? string
---@field source_name? string
---@field s integer start offset (1-based) of the call
---@field e integer offset of the closing parenthesis

local CLOSERS = { ['{'] = '}}', ['%'] = '%}', ['#'] = '#}' }

--- Bodies of `{{ }}` and `{% %}` blocks; `{# #}` comments are skipped (dbt ignores refs in them).
---@param text string
---@return integer[][] regions { start, end }
local function regions(text)
  local out, i = {}, 1
  while true do
    local s, _, open = text:find('{([{%%#])', i)
    if not s then break end
    local cs, ce = text:find(CLOSERS[open], s + 2, true)
    if open ~= '#' then out[#out + 1] = { s + 2, (cs or (#text + 1)) - 1 } end
    i = (ce or #text) + 1
  end
  return out
end

--- Split the arguments of the call whose `(` is at `open`; quotes and nested brackets respected.
---@return string[]? args trimmed raw arguments
---@return integer? close offset of the matching `)`
local function call_args(text, open)
  local args, depth, quote, from = {}, 0, nil, open + 1
  local i = open
  while i <= #text do
    local c = text:sub(i, i)
    if quote then
      if c == '\\' then
        i = i + 1
      elseif c == quote then
        quote = nil
      end
    elseif c == "'" or c == '"' then
      quote = c
    elseif c == '(' or c == '[' or c == '{' then
      depth = depth + 1
    elseif c == ')' or c == ']' or c == '}' then
      depth = depth - 1
      if depth == 0 then
        local last = vim.trim(text:sub(from, i - 1))
        if last ~= '' or #args > 0 then args[#args + 1] = last end
        return args, i
      end
    elseif c == ',' and depth == 1 then
      args[#args + 1] = vim.trim(text:sub(from, i - 1))
      from = i + 1
    end
    i = i + 1
  end
  return nil, nil
end

---@param arg string
---@return string? value
local function literal(arg) return arg:match '^"(.*)"$' or arg:match "^'(.*)'$" end

---@param args string[]
---@return string[] positional string literals
---@return table<string, string> keyword arguments (values unquoted)
local function split_args(args)
  local pos, kw = {}, {}
  for _, a in ipairs(args) do
    local k, v = a:match '^([%a_][%w_]*)%s*=%s*(.+)$'
    if k then
      kw[k] = literal(v) or v
    elseif literal(a) then
      pos[#pos + 1] = literal(a)
    end
  end
  return pos, kw
end

--- Pure: every ref/source/macro call in the text, in source order.
---@param text string
---@return dbt_lens.Construct[]
function M.constructs(text)
  local out = {}
  for _, r in ipairs(regions(text)) do
    local init = r[1]
    while init <= r[2] do
      local s, _, ident = text:find('([%a_][%w_%.]*)%s*%(', init)
      if not s or s > r[2] then break end
      local open = text:find('(', s + #ident, true)
      local args, close = call_args(text, open)
      local pos, kw = split_args(args or {})
      if ident == 'ref' then
        if #pos >= 1 and close then
          out[#out + 1] = {
            kind = 'ref',
            name = pos[#pos],
            package = #pos >= 2 and pos[1] or nil,
            version = kw.v or kw.version,
            s = s,
            e = close,
          }
        end
      elseif ident == 'source' then
        if #pos >= 2 and close then
          out[#out + 1] = { kind = 'source', source_name = pos[1], name = pos[2], s = s, e = close }
        end
      elseif close then
        local pkg, name = ident:match '^(.*)%.([^.]+)$'
        out[#out + 1] = { kind = 'macro', name = name or ident, package = pkg, s = s, e = close }
      end
      init = s + #ident -- step into the arguments so nested calls are found too
    end
  end
  return out
end

--- Pure: the innermost construct under the cursor.
---@param lines string[] buffer lines
---@param row integer 1-based
---@param col integer 0-based byte column
---@return dbt_lens.Construct?
function M.at_cursor(lines, row, col)
  local text = table.concat(lines, '\n')
  local offset = col + 1
  for i = 1, row - 1 do
    offset = offset + #lines[i] + 1
  end
  local best
  for _, c in ipairs(M.constructs(text)) do
    if c.s <= offset and offset <= c.e and (not best or (c.e - c.s) < (best.e - best.s)) then best = c end
  end
  return best
end

--- Pure: 1-based line of `{% macro name(` in the file's lines.
---@param lines string[]
---@param name string
---@return integer?
function M.find_macro_line(lines, name)
  for i, l in ipairs(lines) do
    if l:find('^%s*{%%%-?%s*macro%s+' .. vim.pesc(name) .. '%s*%(') then return i end
  end
end

---@param line string
---@return integer indent
local function indent_of(line) return #line:match '^%s*' end

--- Pure: 1-based line of `- name: <table>` inside `- name: <source>`, falling back to the source line.
---@param lines string[]
---@param source_name string
---@param table_name string
---@return integer?
function M.find_source_line(lines, source_name, table_name)
  local function entry(name) return '^%s*%-%s+name:%s*[\'"]?' .. vim.pesc(name) .. '[\'"]?%s*$' end
  for i, l in ipairs(lines) do
    if l:find(entry(source_name)) then
      local base = indent_of(l:match '^(%s*%-)' .. ' ')
      for j = i + 1, #lines do
        local lj = lines[j]
        if lj:find '%S' and indent_of(lj) <= base then break end
        if lj:find(entry(table_name)) then return j end
      end
      return i
    end
  end
end

--- Pure: 1-based line of the first `- name: <name>` entry (model documentation in a schema yml).
---@param lines string[]
---@param name string
---@return integer?
function M.find_entry_line(lines, name)
  for i, l in ipairs(lines) do
    if l:find('^%s*%-%s+name:%s*[\'"]?' .. vim.pesc(name) .. '[\'"]?%s*$') then return i end
  end
end

---@class dbt_lens.Target
---@field file string
---@field line integer
---@field label string

---@param file string
---@return string[]
local function read_lines(file)
  local ok, lines = pcall(vim.fn.readfile, file)
  return ok and lines or {}
end

--- Where a construct points. Returns candidates when a ref is ambiguous, a message when nothing matches.
---@param construct dbt_lens.Construct
---@param idx dbt_lens.Index
---@param project dbt_lens.Project
---@return dbt_lens.Target? target
---@return dbt_lens.Node[]|string? candidates_or_message
function M.resolve(construct, idx, project)
  local manifest = require 'dbt_lens.manifest'
  local pr = require 'dbt_lens.project'
  if construct.kind == 'ref' then
    local node, candidates =
      manifest.resolve_ref(idx, construct.name, { package = construct.package, version = construct.version })
    if node then
      return { file = pr.abs_path(project, node.package, node.path), line = 1, label = table.concat(node.fqn, '.') }
    end
    if #candidates > 1 then return nil, candidates end
    return nil, ("no model '%s' in the manifest (run :DbtLens refresh?)"):format(construct.name)
  elseif construct.kind == 'source' then
    local key = construct.source_name .. '.' .. construct.name
    local uids = idx.source_by_key[key]
    if not uids then return nil, ("no source '%s' in the manifest"):format(key) end
    local src = idx.sources[uids[1]]
    local file = pr.abs_path(project, src.package, src.path)
    return {
      file = file,
      line = M.find_source_line(read_lines(file), construct.source_name, construct.name) or 1,
      label = key,
    }
  end
  local macros = vim.tbl_filter(
    function(m) return not construct.package or m.package == construct.package end,
    idx.macros[construct.name] or {}
  )
  if #macros == 0 then return nil, nil end -- not a macro we know (Jinja builtin, local variable, ...)
  local mac = macros[1]
  local file = pr.abs_path(project, mac.package, mac.path)
  if vim.fn.filereadable(file) == 0 then
    return nil, ("macro '%s' lives in package '%s', which is not on disk (%s)"):format(mac.name, mac.package, file)
  end
  return {
    file = file,
    line = M.find_macro_line(read_lines(file), mac.name) or 1,
    label = mac.package .. '.' .. mac.name,
  }
end

--- Open a target in the current window, or a split/tab.
---@param target dbt_lens.Target
---@param how? 'edit'|'split'|'vsplit'|'tab'
function M.open(target, how)
  how = how == 'tab' and 'tabedit' or how or 'edit'
  vim.cmd(how .. ' ' .. vim.fn.fnameescape(target.file))
  vim.api.nvim_win_set_cursor(0, { math.min(target.line, vim.api.nvim_buf_line_count(0)), 0 })
  vim.cmd 'normal! zz'
end

return M
