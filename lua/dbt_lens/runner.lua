local M = {}

---@class dbt_lens.Handlers
---@field stdout? fun(err: string?, data: string?)
---@field stderr? fun(err: string?, data: string?)

--- Run dbt in the project root without blocking; on_exit runs on the main loop, handlers in a fast-event context.
---@param project dbt_lens.Project
---@param args string[] dbt subcommand and flags
---@param on_exit fun(res: vim.SystemCompleted)
---@param handlers? dbt_lens.Handlers
---@return vim.SystemObj?
function M.exec(project, args, on_exit, handlers)
  if not project.cmd then
    vim.notify('dbt-lens: dbt not found (see :checkhealth dbt_lens)', vim.log.levels.ERROR)
    return nil
  end
  local argv = vim.list_extend(vim.deepcopy(project.cmd), args)
  argv[#argv + 1] = '--no-use-colors'
  handlers = handlers or {}
  return vim.system(argv, {
    cwd = project.root,
    text = true,
    stdout = handlers.stdout,
    stderr = handlers.stderr,
  }, vim.schedule_wrap(on_exit))
end

--- Pure: `%` stands for the current model's fqn selector.
---@param selector string
---@param node? dbt_lens.Node
---@return string? selector nil when `%` is used without a current model
function M.expand_selector(selector, node)
  if not selector:find('%', 1, true) then return selector end
  if not node then return nil end
  return (selector:gsub('%%', (table.concat(node.fqn, '.'):gsub('%%', '%%%%'))))
end

---@class dbt_lens.Summary
---@field ok integer
---@field failed integer
---@field warned integer
---@field skipped integer
---@field qf { filename: string, lnum: integer, text: string }[]

local FAILED = { error = true, fail = true, ['runtime error'] = true }
local OK = { success = true, pass = true }

--- Pure: run_results.json `results` -> counts and quickfix items for the failed ones.
---@param results { unique_id: string, status: string, message?: string }[]
---@param idx? dbt_lens.Index
---@param project dbt_lens.Project
---@return dbt_lens.Summary
function M.summarize(results, idx, project)
  local s = { ok = 0, failed = 0, warned = 0, skipped = 0, qf = {} }
  for _, r in ipairs(results) do
    if OK[r.status] then
      s.ok = s.ok + 1
    elseif r.status == 'warn' then
      s.warned = s.warned + 1
    elseif r.status == 'skipped' then
      s.skipped = s.skipped + 1
    elseif FAILED[r.status] then
      s.failed = s.failed + 1
      local item = idx and (idx.nodes[r.unique_id] or idx.tests[r.unique_id])
      local first = vim.split(vim.trim(r.message or r.status), '\n')[1]
      s.qf[#s.qf + 1] = {
        filename = item and require('dbt_lens.project').abs_path(project, item.package, item.path) or '',
        lnum = 1,
        text = (item and item.name or r.unique_id) .. ': ' .. first,
      }
    end
  end
  return s
end

---@param s dbt_lens.Summary
---@param elapsed? number
---@return string
function M.format_summary(s, elapsed)
  local parts = { s.ok .. ' ok' }
  if s.failed > 0 then parts[#parts + 1] = s.failed .. ' failed' end
  if s.warned > 0 then parts[#parts + 1] = s.warned .. ' warned' end
  if s.skipped > 0 then parts[#parts + 1] = s.skipped .. ' skipped' end
  return table.concat(parts, ', ') .. (elapsed and (' in %.1f s'):format(elapsed) or '')
end

---@type table<string, { proc: vim.SystemObj, cancelled?: boolean }>
local jobs = {}

---@param project dbt_lens.Project
function M.cancel(project)
  local job = jobs[project.root]
  if not job then return vim.notify('dbt-lens: no dbt job running', vim.log.levels.INFO) end
  job.cancelled = true
  job.proc:kill(15)
end

---@param project dbt_lens.Project
---@param subcommand string run|test|build|...
---@param selector? string
---@param opts? { on_done?: fun(summary: dbt_lens.Summary?, res: vim.SystemCompleted) }
function M.run(project, subcommand, selector, opts)
  opts = opts or {}
  if jobs[project.root] then
    return vim.ui.select({ 'Cancel it and start the new one', 'Keep it running' }, {
      prompt = 'A dbt job is already running for ' .. (project.name or project.root),
    }, function(choice)
      if choice and choice:find '^Cancel' then
        M.cancel(project)
        vim.defer_fn(function() M.run(project, subcommand, selector, opts) end, 300)
      end
    end)
  end

  local args = { subcommand }
  if selector and selector ~= '' then vim.list_extend(args, { '-s', selector }) end
  local title = 'dbt ' .. table.concat(args, ' ')
  local log = require('dbt_lens.log').open(project, title .. '  (running)')
  local started = vim.uv.hrtime()

  local pending = ''
  local function feed(_, data)
    if not data then return end
    pending = pending .. data
    local lines = vim.split(pending, '\n', { plain = true })
    pending = table.remove(lines)
    vim.schedule(function() require('dbt_lens.log').append(log, lines) end)
  end

  local job = {}
  job.proc = M.exec(project, args, function(res)
    jobs[project.root] = nil
    if pending ~= '' then require('dbt_lens.log').append(log, { pending }) end
    local elapsed = (vim.uv.hrtime() - started) / 1e9
    require('dbt_lens.manifest').clear_cache() -- dbt rewrites the manifest on every invocation

    local summary
    if not job.cancelled then
      local f = io.open(project.target_path .. '/run_results.json', 'r')
      if f then
        local ok, decoded = pcall(vim.json.decode, f:read '*a', { luanil = { object = true, array = true } })
        f:close()
        if ok and type(decoded) == 'table' then
          local idx = require('dbt_lens.manifest').load(project)
          summary = M.summarize(decoded.results or {}, idx, project)
        end
      end
    end

    local log_mod = require 'dbt_lens.log'
    if job.cancelled then
      log_mod.set_title(log, title .. '  (cancelled)')
      vim.notify('dbt-lens: ' .. title .. ' cancelled', vim.log.levels.WARN)
    elseif summary then
      local text = M.format_summary(summary, elapsed)
      local mark = (res.code == 0 and summary.failed == 0) and '✓ ' or '✗ '
      log_mod.set_title(log, mark .. title .. '  (' .. text .. ')')
      vim.notify(
        ('dbt-lens: %s: %s'):format(title, text),
        summary.failed > 0 and vim.log.levels.ERROR or vim.log.levels.INFO
      )
      if #summary.qf > 0 then
        vim.fn.setqflist({}, ' ', { title = title, items = summary.qf })
        vim.cmd 'copen'
      end
    else
      log_mod.set_title(
        log,
        (res.code == 0 and '✓ ' or '✗ ') .. title .. ('  (exit %d, no run_results.json)'):format(res.code)
      )
    end
    if opts.on_done then opts.on_done(summary, res) end
  end, { stdout = feed, stderr = feed })
  if job.proc then jobs[project.root] = job end
end

return M
