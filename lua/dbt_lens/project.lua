local M = {}

---@class dbt_lens.Project
---@field root string absolute project root
---@field name string? from dbt_project.yml
---@field profile string? the `profile:` key of dbt_project.yml
---@field target_path string absolute path of the dbt target dir
---@field packages_path string packages install dir, relative to root
---@field model_paths string[] relative to root
---@field cmd string[]? dbt invocation, nil when none found

--- Flat scan of dbt_project.yml: top-level scalars and inline lists only, which is all we need.
---@param text string
---@return { name: string?, profile: string?, target_path: string?, model_paths: string[]?, packages_path: string? }
function M.parse_project_yml(text)
  local out = {}
  for line in text:gmatch '[^\r\n]+' do
    local key, value = line:match '^([%w_%-]+):%s*(.-)%s*$'
    if key and value ~= '' then
      value = value:gsub('%s+#.*$', '')
      if key == 'name' then
        out.name = value:match '^[\'"]?([^\'"]+)[\'"]?$'
      elseif key == 'profile' then
        out.profile = value:match '^[\'"]?([^\'"]+)[\'"]?$'
      elseif key == 'target-path' then
        out.target_path = value:match '^[\'"]?([^\'"]+)[\'"]?$'
      elseif key == 'packages-install-path' then
        out.packages_path = value:match '^[\'"]?([^\'"]+)[\'"]?$'
      elseif key == 'model-paths' then
        local inner = value:match '^%[(.*)%]$'
        if inner then
          out.model_paths = {}
          for item in inner:gmatch '[^,]+' do
            local p = item:match '^%s*[\'"]?([^\'"]-)[\'"]?%s*$'
            if p and p ~= '' then out.model_paths[#out.model_paths + 1] = p end
          end
        end
      end
    end
  end
  return out
end

--- Project root for a buffer. Buffers with a URI scheme (oil://, fugitive://) start from the cwd:
--- a scheme must never end up in a path handed to dbt.
---@param buf? integer
---@return string? root
function M.find_root(buf)
  buf = buf or 0
  local name = vim.api.nvim_buf_get_name(buf)
  local start = (name == '' or name:match '^%a[%w+.-]*://') and vim.uv.cwd() or name
  return vim.fs.root(start, 'dbt_project.yml')
end

---@param root string
---@param override? string|string[]
---@return string[]?
function M.resolve_cmd(root, override)
  if type(override) == 'string' then return { override } end
  if type(override) == 'table' and #override > 0 then return override end
  local venv = root .. '/.venv/bin/dbt'
  if vim.fn.executable(venv) == 1 then return { venv } end
  if vim.uv.fs_stat(root .. '/uv.lock') and vim.fn.executable 'uv' == 1 then return { 'uv', 'run', 'dbt' } end
  if vim.fn.executable 'dbt' == 1 then return { 'dbt' } end
  return nil
end

---@param buf? integer
---@return dbt_lens.Project?
function M.get(buf)
  local root = M.find_root(buf)
  if not root then return nil end
  local f = io.open(root .. '/dbt_project.yml', 'r')
  local parsed = f and M.parse_project_yml(f:read '*a') or {}
  if f then f:close() end
  local target = vim.env.DBT_TARGET_PATH or parsed.target_path or 'target'
  if not vim.startswith(target, '/') then target = root .. '/' .. target end
  return {
    root = root,
    name = parsed.name,
    profile = parsed.profile,
    target_path = target,
    packages_path = parsed.packages_path or 'dbt_packages',
    model_paths = parsed.model_paths or { 'models' },
    cmd = M.resolve_cmd(root, require('dbt_lens.config').get().cmd),
  }
end

--- Absolute path of a node's (or source's, or macro's) file.
---@param project dbt_lens.Project
---@param package string
---@param path string original_file_path
---@return string
function M.abs_path(project, package, path)
  if package == project.name then return project.root .. '/' .. path end
  return ('%s/%s/%s/%s'):format(project.root, project.packages_path, package, path)
end

--- Path of a buffer relative to the project root, nil when outside it.
---@param project dbt_lens.Project
---@param buf? integer
---@return string?
function M.rel_path(project, buf)
  local name = vim.api.nvim_buf_get_name(buf or 0)
  local real = vim.uv.fs_realpath(name)
  if not real then return nil end
  local root = vim.uv.fs_realpath(project.root) or project.root
  if not vim.startswith(real, root .. '/') then return nil end
  return real:sub(#root + 2)
end

return M
