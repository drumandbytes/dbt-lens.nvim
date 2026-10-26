local M = {}

--- Run dbt in the project root without blocking; on_exit runs on the main loop.
---@param project dbt_lens.Project
---@param args string[] dbt subcommand and flags
---@param on_exit fun(res: vim.SystemCompleted)
---@return vim.SystemObj?
function M.exec(project, args, on_exit)
  if not project.cmd then
    vim.notify('dbt-lens: dbt not found (see :checkhealth dbt_lens)', vim.log.levels.ERROR)
    return nil
  end
  local argv = vim.list_extend(vim.deepcopy(project.cmd), args)
  argv[#argv + 1] = '--no-use-colors'
  return vim.system(argv, { cwd = project.root, text = true }, vim.schedule_wrap(on_exit))
end

return M
