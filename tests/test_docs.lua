local T = MiniTest.new_set()
local eq = MiniTest.expect.equality

T['vimdoc builds tags without errors'] = function()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, 'p')
  vim.fn.system({ 'cp', 'doc/dbt-lens.txt', dir .. '/dbt-lens.txt' })
  vim.cmd('helptags ' .. dir)
  local tags = table.concat(vim.fn.readfile(dir .. '/tags'), '\n')
  for _, tag in ipairs({ 'dbt-lens', ':DbtLens', 'dbt-lens-config', 'dbt-lens-blink', 'dbt-lens-health' }) do
    eq(tags:find('\n' .. vim.pesc(tag) .. '\t') ~= nil or tags:find('^' .. vim.pesc(tag) .. '\t') ~= nil, true)
  end
end

return T
