local M = {}

---@type table<string, fun(args: string[])>
local subcommands = {}

local function age(secs)
  local d = os.time() - secs
  if d < 90 then return d .. ' s' end
  if d < 5400 then return ('%.0f min'):format(d / 60) end
  return ('%.1f h'):format(d / 3600)
end

local function notify(lines, level) vim.notify(table.concat(lines, '\n'), level) end

function subcommands.status()
  local project = require('dbt_lens.project').get()
  if not project then return vim.notify('dbt-lens: no dbt_project.yml found', vim.log.levels.WARN) end
  local lines = {
    'dbt-lens',
    'project:  ' .. (project.name or '?'),
    'root:     ' .. project.root,
    'dbt:      ' .. (project.cmd and table.concat(project.cmd, ' ') or 'not found'),
  }
  local idx, err, info = require('dbt_lens.manifest').load(project)
  if idx then
    local c = idx.counts
    lines[#lines + 1] = ('manifest: %d models, %d sources, %d macros, %d seeds, %d snapshots (%s old)'):format(
      c.model,
      c.source,
      c.macro,
      c.seed,
      c.snapshot,
      age(info.mtime)
    )
    if err then lines[#lines + 1] = 'warning:  ' .. err end
  else
    lines[#lines + 1] = 'manifest: ' .. err .. ' (run :DbtLens refresh)'
  end
  notify(lines)
end

function subcommands.refresh()
  local project = require('dbt_lens.project').get()
  if not project then return vim.notify('dbt-lens: no dbt_project.yml found', vim.log.levels.WARN) end
  vim.notify 'dbt-lens: dbt parse ...'
  require('dbt_lens.runner').exec(project, { 'parse' }, function(res)
    if res.code ~= 0 then
      local tail = vim.split(vim.trim((res.stdout or '') .. (res.stderr or '')), '\n')
      return notify(
        vim.list_extend({ 'dbt-lens: dbt parse failed' }, vim.list_slice(tail, math.max(1, #tail - 15))),
        vim.log.levels.ERROR
      )
    end
    require('dbt_lens.manifest').clear_cache()
    subcommands.status()
  end)
end

---@return dbt_lens.Project?, dbt_lens.Index?
local function load_project()
  local project = require('dbt_lens.project').get()
  if not project then
    vim.notify('dbt-lens: no dbt_project.yml found', vim.log.levels.WARN)
    return
  end
  local idx, err = require('dbt_lens.manifest').load(project)
  if not idx then
    vim.notify('dbt-lens: ' .. err .. ' (run :DbtLens refresh)', vim.log.levels.WARN)
    return project
  end
  return project, idx
end

---@param project dbt_lens.Project
---@param idx dbt_lens.Index
---@return dbt_lens.Node?
local function current_node(project, idx)
  local rel = require('dbt_lens.project').rel_path(project)
  return rel and require('dbt_lens.manifest').node_for_path(idx, project.name, rel, project.packages_path)
end

---@param idx dbt_lens.Index
---@return dbt_lens.Node[]
local function sorted_models(idx)
  local list = vim.tbl_values(idx.nodes)
  table.sort(list, function(a, b)
    if a.package ~= b.package then return a.package < b.package end
    return table.concat(a.fqn, '.') < table.concat(b.fqn, '.')
  end)
  return list
end

---@param idx dbt_lens.Index
---@param prompt string
---@param on_choice fun(node: dbt_lens.Node)
local function pick_model(idx, prompt, on_choice)
  require('dbt_lens.pick').pick(sorted_models(idx), {
    prompt = prompt,
    format = function(n) return table.concat(n.fqn, '.') .. (n.materialized and ('  (' .. n.materialized .. ')') or '') end,
  }, function(node)
    if node then on_choice(node) end
  end)
end

---@param sub string
---@return fun(args: string[])
local function dbt_job(sub)
  return function(args)
    local project, idx = load_project()
    if not project then return end
    local selector = table.concat(args, ' ')
    local runner = require 'dbt_lens.runner'
    if selector == '' and not idx then return runner.run(project, sub, nil) end -- no manifest: whole project
    local node = idx and current_node(project, idx)
    if selector == '' then
      if node then return runner.run(project, sub, table.concat(node.fqn, '.')) end
      -- not in a model file: choose one
      return pick_model(idx, 'dbt ' .. sub, function(n) runner.run(project, sub, table.concat(n.fqn, '.')) end)
    end
    local expanded = runner.expand_selector(selector, node)
    if not expanded then
      return vim.notify('dbt-lens: `%` needs a model file in the current buffer', vim.log.levels.WARN)
    end
    runner.run(project, sub, expanded)
  end
end

subcommands.run = dbt_job 'run'
subcommands.test = dbt_job 'test'
subcommands.build = dbt_job 'build'

function subcommands.cancel()
  local project = require('dbt_lens.project').get()
  if project then require('dbt_lens.runner').cancel(project) end
end

function subcommands.models()
  local project, idx = load_project()
  if not (project and idx) then return end
  pick_model(
    idx,
    'Open model',
    function(n) vim.cmd.edit(vim.fn.fnameescape(require('dbt_lens.project').abs_path(project, n.package, n.path))) end
  )
end

---@param opts? { how?: string, quiet?: boolean }
---@return boolean handled false when the cursor is not on something dbt-lens can resolve
function M.goto_definition(opts)
  opts = opts or {}
  local nav = require 'dbt_lens.nav'
  local project = require('dbt_lens.project').get()
  if not project then return false end
  local idx = require('dbt_lens.manifest').load(project)
  if not idx then
    if not opts.quiet then vim.notify('dbt-lens: no manifest (run :DbtLens refresh)', vim.log.levels.WARN) end
    return false
  end
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local construct = nav.at_cursor(vim.api.nvim_buf_get_lines(0, 0, -1, false), row, col)
  if not construct then
    if not opts.quiet then vim.notify('dbt-lens: no ref(), source() or macro under the cursor', vim.log.levels.INFO) end
    return false
  end
  local target, extra = nav.resolve(construct, idx, project)
  if target then
    nav.open(target, opts.how)
    return true
  elseif type(extra) == 'table' then
    pick_model(
      idx,
      "'" .. construct.name .. "' is ambiguous",
      function(n)
        nav.open(
          { file = require('dbt_lens.project').abs_path(project, n.package, n.path), line = 1, label = n.name },
          opts.how
        )
      end
    )
    return true
  elseif type(extra) == 'string' then
    vim.notify('dbt-lens: ' .. extra, vim.log.levels.WARN)
    return true
  end
  return false -- a macro we do not know: Jinja builtin or local variable
end

subcommands['goto'] = function(args)
  local how = args[1]
  if how and not vim.list_contains({ 'edit', 'split', 'vsplit', 'tab' }, how) then
    return vim.notify('dbt-lens: goto takes split, vsplit or tab', vim.log.levels.ERROR)
  end
  M.goto_definition({ how = how })
end

---@return dbt_lens.Project?, dbt_lens.Index?, dbt_lens.Node?
local function project_and_node()
  local project, idx = load_project()
  if not (project and idx) then return end
  local node = current_node(project, idx)
  if not node then return vim.notify('dbt-lens: the current buffer is not a model file', vim.log.levels.WARN) end
  return project, idx, node
end

function subcommands.references()
  local project, idx, node = project_and_node()
  if not node then return end
  local items = {}
  for _, uid in ipairs(idx.children[node.uid] or {}) do
    local child = idx.nodes[uid]
    if child then
      items[#items + 1] = {
        filename = require('dbt_lens.project').abs_path(project, child.package, child.path),
        lnum = 1,
        text = table.concat(child.fqn, '.'),
      }
    end
  end
  if #items == 0 then return vim.notify('dbt-lens: nothing depends on ' .. node.name, vim.log.levels.INFO) end
  vim.fn.setqflist({}, ' ', { title = 'Models using ' .. node.name, items = items })
  vim.cmd 'copen'
end

function subcommands.yaml()
  local project, _, node = project_and_node()
  if not node then return end
  local pkg, rel = (node.patch_path or ''):match '^([^:]+)://(.+)$'
  if not pkg then return vim.notify('dbt-lens: ' .. node.name .. ' has no YAML entry', vim.log.levels.INFO) end
  local nav = require 'dbt_lens.nav'
  local file = require('dbt_lens.project').abs_path(project, pkg, rel)
  nav.open({ file = file, line = nav.find_entry_line(vim.fn.readfile(file), node.name) or 1, label = node.name })
end

local planned = { 'lineage', 'compiled', 'show' }

function M.command(opts)
  local sub = opts.fargs[1]
  if not sub then return subcommands.status({}) end
  local fn = subcommands[sub]
  if fn then return fn(vim.list_slice(opts.fargs, 2)) end
  if vim.list_contains(planned, sub) then
    return vim.notify('dbt-lens: `' .. sub .. '` is not implemented yet', vim.log.levels.WARN)
  end
  vim.notify('dbt-lens: unknown subcommand `' .. sub .. '`', vim.log.levels.ERROR)
end

function M.complete(arglead, cmdline)
  if
    #vim.split(cmdline, '%s+', { trimempty = true }) > 2
    or (cmdline:match '%s$' and #vim.split(cmdline, '%s+', { trimempty = true }) > 1)
  then
    return {}
  end
  local names = vim.tbl_keys(subcommands)
  vim.list_extend(names, planned)
  table.sort(names)
  return vim.tbl_filter(function(n) return vim.startswith(n, arglead) end, names)
end

return M
