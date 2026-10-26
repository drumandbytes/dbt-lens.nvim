local M = {}

function M.check()
  local h = vim.health
  h.start 'dbt-lens'

  if vim.fn.has 'nvim-0.11' == 1 then
    h.ok('Neovim ' .. tostring(vim.version()))
  else
    h.error('Neovim 0.11+ required, found ' .. tostring(vim.version()))
  end

  local _, unknown = require('dbt_lens.config').get()
  if #unknown > 0 then h.warn('Unknown vim.g.dbt_lens keys: ' .. table.concat(unknown, ', ')) end

  local project = require('dbt_lens.project').get()
  if not project then
    h.warn 'No dbt_project.yml found above the current buffer or cwd'
    return
  end
  h.ok(('Project %s at %s'):format(project.name or '?', project.root))

  if not project.cmd then
    h.error 'dbt not found (.venv/bin/dbt, uv run dbt, $PATH, or vim.g.dbt_lens.cmd)'
    return
  end
  h.ok('dbt command: ' .. table.concat(project.cmd, ' '))

  local argv = vim.list_extend(vim.deepcopy(project.cmd), { '--version', '--no-use-colors' })
  local res = vim.system(argv, { cwd = project.root, text = true }):wait(15000)
  local out = (res.stdout or '') .. (res.stderr or '')
  local major, minor = out:match 'installed:%s*(%d+)%.(%d+)'
  if not major then
    h.warn 'Could not read dbt version from `dbt --version`'
  elseif tonumber(major) > 1 or tonumber(minor) >= 9 then
    h.ok(('dbt-core %s.%s'):format(major, minor))
  else
    h.warn(('dbt-core %s.%s found, 1.9+ is supported'):format(major, minor))
  end

  local manifest = project.target_path .. '/manifest.json'
  local stat = vim.uv.fs_stat(manifest)
  if stat then
    h.ok(('manifest.json (%.0f min old)'):format((os.time() - stat.mtime.sec) / 60))
  else
    h.info('No manifest.json yet at ' .. manifest .. ' (run `dbt parse`)')
  end
end

return M
