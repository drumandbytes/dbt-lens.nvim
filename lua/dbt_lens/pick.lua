local M = {}

---@class dbt_lens.PickOpts
---@field prompt string
---@field format fun(item: any): string
---@field file? fun(item: any): string absolute path, enables file previews in the picker backends

---@param items any[]
---@param opts dbt_lens.PickOpts
---@param on_choice fun(item: any?)
local function ui(items, opts, on_choice)
  vim.ui.select(items, { prompt = opts.prompt, format_item = opts.format }, on_choice)
end

local function snacks(items, opts, on_choice)
  local entries = {}
  for _, item in ipairs(items) do
    entries[#entries + 1] = { text = opts.format(item), file = opts.file and opts.file(item), item = item }
  end
  Snacks.picker.pick({
    title = opts.prompt,
    items = entries,
    format = function(e) return { { e.text } } end,
    preview = opts.file and 'file' or nil,
    confirm = function(picker, e)
      picker:close()
      if e then vim.schedule(function() on_choice(e.item) end) end
    end,
  })
end

local function telescope(items, opts, on_choice)
  local pickers = require 'telescope.pickers'
  local finders = require 'telescope.finders'
  local conf = require('telescope.config').values
  local actions = require 'telescope.actions'
  local action_state = require 'telescope.actions.state'
  pickers
    .new({}, {
      prompt_title = opts.prompt,
      finder = finders.new_table({
        results = items,
        entry_maker = function(item)
          local text = opts.format(item)
          return { value = item, display = text, ordinal = text, filename = opts.file and opts.file(item) or nil }
        end,
      }),
      sorter = conf.generic_sorter({}),
      previewer = opts.file and conf.file_previewer({}) or nil,
      attach_mappings = function(bufnr)
        actions.select_default:replace(function()
          local entry = action_state.get_selected_entry()
          actions.close(bufnr)
          if entry then on_choice(entry.value) end
        end)
        return true
      end,
    })
    :find()
end

--- Backend for the configured `picker`: 'auto' takes snacks, then telescope, then vim.ui.select.
---@param name string
---@return fun(items: any[], opts: dbt_lens.PickOpts, on_choice: fun(item: any?))
function M.backend(name)
  local has_snacks = _G.Snacks ~= nil and Snacks.picker ~= nil
  local has_telescope = pcall(require, 'telescope.pickers')
  if name == 'snacks' or (name == 'auto' and has_snacks) then
    if has_snacks then return snacks end
    vim.notify_once(
      'dbt-lens: picker = "snacks" but snacks.nvim is not loaded, using vim.ui.select',
      vim.log.levels.WARN
    )
  elseif name == 'telescope' or (name == 'auto' and has_telescope) then
    if has_telescope then return telescope end
    vim.notify_once(
      'dbt-lens: picker = "telescope" but telescope.nvim is not installed, using vim.ui.select',
      vim.log.levels.WARN
    )
  end
  return ui
end

---@param items any[]
---@param opts dbt_lens.PickOpts
---@param on_choice fun(item: any?)
function M.pick(items, opts, on_choice) M.backend(require('dbt_lens.config').get().picker)(items, opts, on_choice) end

return M
