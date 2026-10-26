--- Pure graph helpers (no vim.*): everything here is unit-tested without Neovim.
local M = {}

---@class dbt_lens.TreeEntry
---@field uid string
---@field depth integer 1 = direct neighbour of the root
---@field again boolean already shown earlier in this tree (diamond): not expanded again
---@field more boolean has further neighbours beyond the depth limit

--- Walk from `root` along `links` (parents or children), depth-limited. `order` 'pre' lists a node before
--- its neighbours, 'post' after them (upstream reads furthest-first). A node reachable by several paths is
--- listed in full once and marked `again` afterwards.
---@param links table<string, string[]> parents or children map
---@param root string
---@param max_depth integer
---@param order? 'pre'|'post' default 'pre'
---@return dbt_lens.TreeEntry[]
function M.tree(links, root, max_depth, order)
  local out, seen = {}, { [root] = true }
  local function walk(uid, depth)
    local next_uids = links[uid] or {}
    if depth > max_depth then return end
    for _, n in ipairs(next_uids) do
      local again = seen[n] == true
      seen[n] = true
      local more = not again and depth == max_depth and #(links[n] or {}) > 0
      local entry = { uid = n, depth = depth, again = again, more = more }
      if order ~= 'post' then out[#out + 1] = entry end
      if not again then walk(n, depth + 1) end
      if order == 'post' then out[#out + 1] = entry end
    end
  end
  walk(root, 1)
  return out
end

--- dbt selector for a node plus everything up and downstream of it.
---@param fqn string[]
---@return string
function M.family_selector(fqn) return '+' .. table.concat(fqn, '.') .. '+' end

return M
