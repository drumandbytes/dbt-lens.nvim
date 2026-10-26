local graph = require 'dbt_lens.graph'

local M = {}

---@class dbt_lens.LineageOpts
---@field up integer
---@field down integer

---@class dbt_lens.LineageRow
---@field text string
---@field uid? string node on this row (nil for section headers)
---@field kind 'header'|'root'|'node'
---@field mat? string materialization, shown as virtual text

---@param idx dbt_lens.Index
---@param uid string
---@return { label: string, kind: string, mat?: string }
local function describe(idx, uid)
  local n = idx.nodes[uid]
  if n then
    local label = n.name .. (n.version ~= nil and (' v' .. tostring(n.version)) or '')
    if n.package ~= idx.meta.root_package then label = n.package .. '.' .. label end
    return { label = label, kind = n.kind, mat = n.materialized }
  end
  local s = idx.sources[uid]
  if s then return { label = s.source_name .. '.' .. s.name, kind = 'source' } end
  return { label = uid, kind = '?' }
end

--- Pure: the rows of the tree view, upstream above the root, downstream below.
---@param idx dbt_lens.Index
---@param root string unique_id
---@param opts dbt_lens.LineageOpts
---@return dbt_lens.LineageRow[]
function M.build(idx, root, opts)
  local rows = {}
  local function section(title, links, depth, up)
    local list = graph.tree(links, root, depth, up and 'post' or 'pre')
    rows[#rows + 1] = { text = title .. (#list == 0 and ' (none)' or ''), kind = 'header' }
    for _, e in ipairs(list) do
      local d = describe(idx, e.uid)
      local text = ('%s%-8s %s'):format(('  '):rep(e.depth), d.kind, d.label)
      if e.again then text = text .. '  ↺' end
      if e.more then text = text .. '  …' end
      rows[#rows + 1] = { text = text, uid = e.uid, kind = 'node', mat = d.mat }
    end
  end

  section('▲ upstream', idx.parents, opts.up, true)
  local d = describe(idx, root)
  rows[#rows + 1] = { text = ('● %s'):format(d.label), uid = root, kind = 'root', mat = d.mat }
  section('▼ downstream', idx.children, opts.down, false)
  return rows
end

-- [[ The window ]]

local ns = vim.api.nvim_create_namespace 'dbt-lens-lineage'

---@class dbt_lens.LineageState
---@field project dbt_lens.Project
---@field root string unique_id
---@field up integer
---@field down integer
---@field buf integer
---@field win integer
---@field rows dbt_lens.LineageRow[]

---@type dbt_lens.LineageState?
local state

local MAX_DEPTH = 9

local function define_highlights()
  for name, link in pairs({
    DbtLensLineageRoot = 'Title',
    DbtLensLineageHeader = 'Comment',
    DbtLensLineageKind = 'Type',
    DbtLensLineageMat = 'Comment',
  }) do
    vim.api.nvim_set_hl(0, name, { link = link, default = true })
  end
end

local function age_text(project)
  local stat = vim.uv.fs_stat(project.target_path .. '/manifest.json')
  if not stat then return 'no manifest' end
  local d = os.time() - stat.mtime.sec
  return d < 90 and (d .. ' s old')
    or d < 5400 and (('%.0f min old'):format(d / 60))
    or (('%.1f h old'):format(d / 3600))
end

---@param idx dbt_lens.Index
local function draw(idx)
  local st = state
  if not (st and vim.api.nvim_buf_is_valid(st.buf)) then return end
  st.rows = M.build(idx, st.root, { up = st.up, down = st.down })
  local lines = vim.tbl_map(function(r) return r.text end, st.rows)
  vim.bo[st.buf].modifiable = true
  vim.api.nvim_buf_set_lines(st.buf, 0, -1, false, lines)
  vim.bo[st.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(st.buf, ns, 0, -1)
  for i, r in ipairs(st.rows) do
    local group = r.kind == 'header' and 'DbtLensLineageHeader' or r.kind == 'root' and 'DbtLensLineageRoot' or nil
    if group then vim.api.nvim_buf_set_extmark(st.buf, ns, i - 1, 0, { line_hl_group = group }) end
    if r.kind == 'node' then
      local kind_start = #r.text:match '^%s*'
      local kind_end = kind_start + #r.text:sub(kind_start + 1):match '^%S+'
      vim.api.nvim_buf_set_extmark(
        st.buf,
        ns,
        i - 1,
        kind_start,
        { end_col = kind_end, hl_group = 'DbtLensLineageKind' }
      )
    end
    if r.mat then
      vim.api.nvim_buf_set_extmark(
        st.buf,
        ns,
        i - 1,
        0,
        { virt_text = { { '(' .. r.mat .. ')', 'DbtLensLineageMat' } }, virt_text_pos = 'eol' }
      )
    end
  end
  local root = idx.nodes[st.root] or { name = st.root }
  vim.wo[st.win].winbar = (' lineage: %s  ▲%d ▼%d  manifest %s'):format(
    root.name,
    st.up,
    st.down,
    age_text(st.project)
  )
end

local function cursor_to_root()
  for i, r in ipairs(state.rows) do
    if r.kind == 'root' then return vim.api.nvim_win_set_cursor(state.win, { i, 0 }) end
  end
end

---@param idx dbt_lens.Index
local function reroot(idx, uid)
  if not (state and uid) then return end
  state.root = uid
  draw(idx)
  cursor_to_root()
end

--- A window to show files in: the first ordinary one that is not the lineage window.
---@return integer
local function file_window()
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if w ~= state.win and vim.bo[vim.api.nvim_win_get_buf(w)].buftype == '' then return w end
  end
  vim.cmd 'aboveleft vsplit'
  local w = vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_win(state.win)
  return w
end

---@return string? uid of the node on the cursor row
local function row_at_cursor()
  local r = state.rows[vim.api.nvim_win_get_cursor(state.win)[1]]
  return r and r.uid
end

local function reload(project, on_loaded)
  local idx, err = require('dbt_lens.manifest').load(project)
  if not idx then return vim.notify('dbt-lens: ' .. err, vim.log.levels.WARN) end
  on_loaded(idx)
end

local function attach_keys(project)
  local buf = state.buf
  local function map(lhs, fn, desc)
    vim.keymap.set('n', lhs, fn, { buffer = buf, nowait = true, desc = 'dbt-lens lineage: ' .. desc })
  end
  local function with_idx(fn)
    return function() reload(project, fn) end
  end

  map(
    '<CR>',
    with_idx(function(idx)
      local uid = row_at_cursor()
      if not uid then return end
      local pr = require 'dbt_lens.project'
      local n, s = idx.nodes[uid], idx.sources[uid]
      local item = n or s
      local w = file_window()
      vim.api.nvim_set_current_win(w)
      vim.cmd.edit(vim.fn.fnameescape(pr.abs_path(project, item.package, item.path)))
    end),
    'open the file'
  )
  map('r', with_idx(function(idx) reroot(idx, row_at_cursor()) end), 're-root on this node')
  map(
    '+',
    with_idx(function(idx)
      state.up, state.down = math.min(state.up + 1, MAX_DEPTH), math.min(state.down + 1, MAX_DEPTH)
      draw(idx)
    end),
    'deeper'
  )
  map(
    '-',
    with_idx(function(idx)
      state.up, state.down = math.max(state.up - 1, 1), math.max(state.down - 1, 1)
      draw(idx)
    end),
    'shallower'
  )
  map('R', function()
    vim.notify 'dbt-lens: dbt parse ...'
    require('dbt_lens.runner').exec(project, { 'parse' }, function(res)
      if res.code ~= 0 then
        return vim.notify('dbt-lens: dbt parse failed, keeping the old manifest', vim.log.levels.ERROR)
      end
      require('dbt_lens.manifest').clear_cache()
      reload(project, draw)
    end)
  end, 'dbt parse, then reload')
  map(
    'y',
    with_idx(function(idx)
      local uid = row_at_cursor()
      local n = uid and idx.nodes[uid]
      if not n then return end
      local sel = require('dbt_lens.graph').family_selector(n.fqn)
      vim.fn.setreg('"', sel)
      vim.fn.setreg('+', sel)
      vim.notify('dbt-lens: yanked ' .. sel)
    end),
    'yank the +model+ selector'
  )
  map('q', '<Cmd>close<CR>', 'close')
end

--- Show (or re-root) the lineage view for a node.
---@param project dbt_lens.Project
---@param idx dbt_lens.Index
---@param node dbt_lens.Node
function M.open(project, idx, node)
  define_highlights()
  local cfg = require('dbt_lens.config').get().lineage
  if state and vim.api.nvim_win_is_valid(state.win) and state.project.root == project.root then
    state.root = node.uid
    draw(idx)
    return state
  end
  local prev = vim.api.nvim_get_current_win()
  vim.cmd(('botright vertical %dnew'):format(cfg.width))
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = 'dbt-lens-lineage'
  vim.wo[win].wrap = false
  vim.wo[win].number = false
  vim.wo[win].signcolumn = 'no'
  vim.wo[win].winfixwidth = true
  state = { project = project, root = node.uid, up = cfg.up, down = cfg.down, buf = buf, win = win, rows = {} }
  attach_keys(project)
  draw(idx)
  cursor_to_root()
  if cfg.follow then
    local group = vim.api.nvim_create_augroup('dbt-lens-lineage-follow', { clear = true })
    vim.api.nvim_create_autocmd('BufEnter', {
      group = group,
      callback = function(a)
        if not (state and vim.api.nvim_win_is_valid(state.win)) then return true end
        if a.buf == state.buf or vim.bo[a.buf].buftype ~= '' then return end
        local pr = require 'dbt_lens.project'
        local p = pr.get(a.buf)
        local rel = p and pr.rel_path(p, a.buf)
        local i = p and require('dbt_lens.manifest').load(p)
        local n = i and rel and require('dbt_lens.manifest').node_for_path(i, p.name, rel, p.packages_path)
        if n and n.uid ~= state.root then
          state.root = n.uid
          draw(i)
        end
      end,
    })
  end
  if vim.api.nvim_win_is_valid(prev) and state.win ~= prev then vim.api.nvim_set_current_win(win) end
  return state
end

---@return dbt_lens.LineageState?
function M.state() return state end

return M
