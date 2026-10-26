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

local planned = { 'run', 'test', 'build', 'goto', 'lineage', 'compiled', 'show', 'models' }

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
