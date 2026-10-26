local T = MiniTest.new_set({ hooks = {
  post_case = function()
    vim.g.dbt_lens = nil
    _G.Snacks = nil
  end,
} })
local eq = MiniTest.expect.equality
local pick = require 'dbt_lens.pick'

local items = { { name = 'a' }, { name = 'b' } }
local opts =
  { prompt = 'Pick', format = function(i) return i.name end, file = function(i) return '/x/' .. i.name .. '.sql' end }

T['backend choice'] = MiniTest.new_set()

T['backend choice']['auto falls back to vim.ui.select'] = function()
  local chosen
  local orig = vim.ui.select
  vim.ui.select = function(its, o, cb)
    eq(o.prompt, 'Pick')
    eq(o.format_item(its[2]), 'b')
    cb(its[2])
  end
  pick.pick(items, opts, function(i) chosen = i end)
  vim.ui.select = orig
  eq(chosen, items[2])
end

T['backend choice']['snacks gets items with file previews and maps the choice back'] = function()
  local captured
  _G.Snacks = { picker = { pick = function(o) captured = o end } }
  vim.g.dbt_lens = { picker = 'snacks' }
  local chosen
  pick.pick(items, opts, function(i) chosen = i end)
  eq(captured.title, 'Pick')
  eq(captured.preview, 'file')
  eq({ captured.items[1].text, captured.items[1].file }, { 'a', '/x/a.sql' })
  eq(captured.format(captured.items[2]), { { 'b' } })
  local closed
  captured.confirm({ close = function() closed = true end }, captured.items[2])
  vim.wait(200, function() return chosen ~= nil end)
  eq(closed, true)
  eq(chosen, items[2])
end

T['backend choice']['forced backend that is missing falls back to ui'] = function()
  vim.g.dbt_lens = { picker = 'telescope' }
  if pcall(require, 'telescope.pickers') then return MiniTest.skip 'telescope is installed' end
  eq(pick.backend 'telescope' ~= nil, true)
end

T['health'] = MiniTest.new_set()

T['health']['reports the fixture project and its profile'] = function()
  local calls = {}
  local orig = vim.health
  vim.health = setmetatable({}, {
    __index = function(_, level)
      return function(msg) calls[#calls + 1] = level .. ': ' .. tostring(msg) end
    end,
  })
  vim.cmd('edit ' .. vim.fn.fnamemodify('tests/fixtures/project/models/shared.sql', ':p'))
  require('dbt_lens.health').check()
  vim.health = orig
  local text = table.concat(calls, '\n')
  eq(text:find('ok: Project demo', 1, true) ~= nil, true)
  eq(text:find('ok: profile demo in ', 1, true) ~= nil, true)
  eq(text:find('start: dbt-lens: optional', 1, true) ~= nil, true)
end

return T
