local M = {}

--- One picker entry point; backends other than vim.ui.select arrive later.
---@generic T
---@param items T[]
---@param opts { prompt: string, format: fun(item: T): string }
---@param on_choice fun(item: T?)
function M.pick(items, opts, on_choice)
  vim.ui.select(items, { prompt = opts.prompt, format_item = opts.format }, on_choice)
end

return M
