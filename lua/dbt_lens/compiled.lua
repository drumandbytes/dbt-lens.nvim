local M = {}

--- Pure: where dbt writes the compiled SQL of a node.
---@param project dbt_lens.Project
---@param node dbt_lens.Node
---@return string
function M.path(project, node) return ('%s/compiled/%s/%s'):format(project.target_path, node.package, node.path) end

--- Pure: recompile when the compiled file is missing or older than its source (or forced).
---@param compiled_mtime? integer
---@param source_mtime? integer
---@param force? boolean
---@return boolean
function M.is_stale(compiled_mtime, source_mtime, force)
  if force or not compiled_mtime then return true end
  return source_mtime ~= nil and source_mtime > compiled_mtime
end

--- Pure: arguments for `dbt show`, either a selector or inline SQL.
---@param opts { selector?: string, sql?: string, limit: integer }
---@return string[]
function M.show_args(opts)
  local args = { 'show' }
  if opts.sql then
    vim.list_extend(args, { '--inline', opts.sql })
  else
    vim.list_extend(args, { '-s', opts.selector })
  end
  vim.list_extend(args, { '--limit', tostring(opts.limit), '--quiet' })
  return args
end

---@param res vim.SystemCompleted
---@return string[]
local function output_lines(res)
  local text = vim.trim((res.stdout or '') .. (res.code ~= 0 and (res.stderr or '') or ''))
  return vim.split(text == '' and '(no output)' or text, '\n', { plain = true })
end

--- Open the compiled SQL of a model in a read-only split, compiling first when needed.
---@param project dbt_lens.Project
---@param node dbt_lens.Node
---@param force? boolean
function M.open(project, node, force)
  local path = M.path(project, node)
  local pr = require 'dbt_lens.project'
  local compiled = vim.uv.fs_stat(path)
  local source = vim.uv.fs_stat(pr.abs_path(project, node.package, node.path))
  local function open_file()
    vim.cmd('vsplit ' .. vim.fn.fnameescape(path))
    vim.bo.filetype = 'sql'
    vim.bo.modifiable = false
    vim.bo.readonly = true
  end
  if not M.is_stale(compiled and compiled.mtime.sec, source and source.mtime.sec, force) then return open_file() end

  vim.notify('dbt-lens: compiling ' .. node.name .. ' ...')
  require('dbt_lens.runner').exec(project, { 'compile', '-s', table.concat(node.fqn, '.') }, function(res)
    if res.code ~= 0 then
      return vim.notify('dbt-lens: dbt compile failed\n' .. table.concat(output_lines(res), '\n'), vim.log.levels.ERROR)
    end
    if not vim.uv.fs_stat(path) then
      return vim.notify('dbt-lens: compiled file not found at ' .. path, vim.log.levels.ERROR)
    end
    -- an already open copy is stale now
    local existing = vim.fn.bufnr(path)
    if existing > 0 then vim.cmd('silent! bwipeout ' .. existing) end
    open_file()
  end)
end

--- `dbt show` in a float: a model's rows (selector) or an inline query (selected SQL).
---@param project dbt_lens.Project
---@param opts { selector?: string, sql?: string, title: string }
function M.show(project, opts)
  local limit = require('dbt_lens.config').get().show.limit
  vim.notify 'dbt-lens: dbt show ...'
  require('dbt_lens.runner').exec(
    project,
    M.show_args({ selector = opts.selector, sql = opts.sql, limit = limit }),
    function(res) require('dbt_lens.float').show(output_lines(res), (res.code == 0 and '' or 'failed: ') .. opts.title) end
  )
end

return M
