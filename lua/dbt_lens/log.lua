local M = {}

---@type table<string, integer> project root -> log buffer
local bufs = {}

---@class dbt_lens.Log
---@field buf integer
---@field win integer

--- Bottom split with the job output, reused per project. Focus stays where it was.
---@param project dbt_lens.Project
---@param title string
---@return dbt_lens.Log
function M.open(project, title)
  local buf = bufs[project.root]
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    buf = vim.api.nvim_create_buf(false, true)
    bufs[project.root] = buf
    vim.bo[buf].buftype = 'nofile'
    vim.bo[buf].bufhidden = 'hide'
    vim.bo[buf].swapfile = false
    vim.bo[buf].filetype = 'dbt-lens-log'
    vim.keymap.set('n', 'q', '<Cmd>close<CR>', { buffer = buf, desc = 'Close the dbt log' })
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
  vim.bo[buf].modifiable = false

  local win = vim.fn.bufwinid(buf)
  if win == -1 then
    local prev = vim.api.nvim_get_current_win()
    vim.cmd('botright ' .. require('dbt_lens.config').get().log.height .. 'split')
    win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, buf)
    vim.wo[win].wrap = false
    vim.wo[win].number = false
    vim.wo[win].signcolumn = 'no'
    vim.api.nvim_set_current_win(prev)
  end
  vim.wo[win].winbar = ' ' .. title
  return { buf = buf, win = win }
end

---@param log dbt_lens.Log
---@param lines string[]
function M.append(log, lines)
  if not vim.api.nvim_buf_is_valid(log.buf) or #lines == 0 then return end
  local last = vim.api.nvim_buf_line_count(log.buf)
  local follow = vim.api.nvim_win_is_valid(log.win) and vim.api.nvim_win_get_cursor(log.win)[1] >= last
  vim.bo[log.buf].modifiable = true
  -- a fresh buffer holds one empty line: replace it rather than leave a blank first row
  local first_is_blank = last == 1 and vim.api.nvim_buf_get_lines(log.buf, 0, 1, false)[1] == ''
  vim.api.nvim_buf_set_lines(log.buf, first_is_blank and 0 or -1, -1, false, lines)
  vim.bo[log.buf].modifiable = false
  if follow and vim.api.nvim_win_is_valid(log.win) then
    vim.api.nvim_win_set_cursor(log.win, { vim.api.nvim_buf_line_count(log.buf), 0 })
  end
end

---@param log dbt_lens.Log
---@param title string
function M.set_title(log, title)
  if vim.api.nvim_win_is_valid(log.win) then vim.wo[log.win].winbar = ' ' .. title end
end

return M
