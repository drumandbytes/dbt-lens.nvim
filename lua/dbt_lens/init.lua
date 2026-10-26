local M = {}

---@type table<string, fun(args: string[])>
local subcommands = {
  status = function()
    local project = require('dbt_lens.project').get()
    if not project then return vim.notify('dbt-lens: no dbt_project.yml found', vim.log.levels.WARN) end
    vim.notify(table.concat({
      'dbt-lens',
      'project: ' .. (project.name or '?'),
      'root:    ' .. project.root,
      'dbt:     ' .. (project.cmd and table.concat(project.cmd, ' ') or 'not found'),
      'target:  ' .. project.target_path,
    }, '\n'))
  end,
}

local planned = { 'run', 'test', 'build', 'goto', 'lineage', 'compiled', 'show', 'refresh', 'models' }

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
