local M = {}

---@type table<string, string>
M.defaults = {
  run = '<leader>dr',
  test = '<leader>dt',
  build = '<leader>db',
  models = '<leader>dm',
  ['goto'] = 'gd',
}

--- Buffer-local maps for SQL/Jinja files inside a dbt project; only when `keymaps` is enabled.
---@param buf integer
function M.attach(buf)
  local cfg = require('dbt_lens.config').get()
  if not cfg.keymaps then return end
  if not vim.fs.root(vim.api.nvim_buf_get_name(buf), 'dbt_project.yml') then return end
  local keys = cfg.keymaps == true and M.defaults or vim.tbl_extend('force', M.defaults, cfg.keymaps)
  for action, lhs in pairs(keys) do
    if lhs then
      local rhs = '<Cmd>DbtLens ' .. action .. '<CR>'
      local desc = 'dbt-lens: ' .. action
      if action == 'goto' then
        -- not on a dbt reference (or no manifest): hand `gd` back to the LSP
        rhs = function()
          if not require('dbt_lens').goto_definition({ quiet = true }) then vim.lsp.buf.definition() end
        end
        desc = 'dbt-lens: go to ref/source/macro, else LSP definition'
      end
      vim.keymap.set('n', lhs, rhs, { buffer = buf, desc = desc })
    end
  end
end

return M
