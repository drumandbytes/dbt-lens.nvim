local T = MiniTest.new_set()
local eq = MiniTest.expect.equality
local project = require 'dbt_lens.project'

T['parse_project_yml'] = MiniTest.new_set()

T['parse_project_yml']['reads name, target-path and inline model-paths'] = function()
  local p = project.parse_project_yml [[
name: 'demo'
target-path: "build"  # comment
model-paths: ["models", 'more_models']
]]
  eq(p.name, 'demo')
  eq(p.target_path, 'build')
  eq(p.model_paths, { 'models', 'more_models' })
end

T['parse_project_yml']['ignores nested keys and missing values'] = function()
  local p = project.parse_project_yml 'models:\n  demo:\n    name: nested\nname: top\n'
  eq(p.name, 'top')
  eq(p.model_paths, nil)
end

T['resolve_cmd'] = MiniTest.new_set()

T['resolve_cmd']['override wins'] = function()
  eq(project.resolve_cmd('/nowhere', 'my-dbt'), { 'my-dbt' })
  eq(project.resolve_cmd('/nowhere', { 'uv', 'run', 'dbt' }), { 'uv', 'run', 'dbt' })
end

T['get'] = MiniTest.new_set()

T['get']['finds the project from a file inside it'] = function()
  local root = vim.fn.fnamemodify('tests/fixtures/project', ':p'):gsub('/$', '')
  vim.cmd('edit ' .. root .. '/models/.gitkeep')
  local p = project.get()
  eq(p.root, vim.uv.fs_realpath(root))
  eq(p.name, 'demo')
  eq(p.target_path, p.root .. '/target')
  eq(p.model_paths, { 'models', 'more_models' })
end

T['get']['scheme buffers fall back to the cwd'] = function()
  vim.cmd 'cd tests/fixtures/project'
  vim.cmd 'edit oil:///somewhere/else'
  eq(project.get().name, 'demo')
  vim.cmd 'cd -'
end

return T
