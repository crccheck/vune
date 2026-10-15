-- Turn "mpv playlist -> buffer lines" into the smallest practical mpv command
-- list. Entries are matched by path and mpv entry id, so the playing entry
-- keeps playing unless its line is deleted.
local M = {}

---@class vune.Entry
---@field id integer
---@field filename string
---@field current boolean?

--- Match buffer lines to existing mpv entries.
---@param old vune.Entry[]
---@param lines string[]
---@return table<integer, integer> ids  line index -> old entry index (1-based)
local function match(old, lines)
  local ids, used = {}, {}
  local queue = {}
  for k, e in ipairs(old) do
    queue[e.filename] = queue[e.filename] or {}
    table.insert(queue[e.filename], k)
  end

  -- The playing entry takes the nearest line with its path, so it is never
  -- swapped for a duplicate and restarted.
  for k, e in ipairs(old) do
    if e.current then
      local best
      for i, l in ipairs(lines) do
        if l == e.filename and (not best or math.abs(i - k) < math.abs(best - k)) then
          best = i
        end
      end
      if best then
        ids[best], used[k] = k, true
      end
    end
  end

  local nextq = {}
  for i, l in ipairs(lines) do
    if not ids[i] and queue[l] then
      local n = nextq[l] or 1
      while queue[l][n] and used[queue[l][n]] do
        n = n + 1
      end
      local k = queue[l][n]
      if k then
        ids[i], used[k] = k, true
        n = n + 1
      end
      nextq[l] = n
    end
  end
  return ids, used
end

---@param old vune.Entry[]
---@param lines string[]
---@return any[][] ops mpv commands, to send in order
function M.plan(old, lines)
  local ids, used = match(old, lines)
  local ops = {}

  -- 1. Remove unmatched entries, highest index first so indices stay valid.
  for k = #old, 1, -1 do
    if not used[k] then
      table.insert(ops, { "playlist-remove", k - 1 })
    end
  end

  -- 2. Reorder the survivors into buffer order.
  local sim = {}
  for k = 1, #old do
    if used[k] then
      table.insert(sim, k)
    end
  end
  local target = {}
  for i = 1, #lines do
    if ids[i] then
      table.insert(target, ids[i])
    end
  end
  for t = 1, #target do
    if sim[t] ~= target[t] then
      local c
      for j = t + 1, #sim do
        if sim[j] == target[t] then
          c = j
          break
        end
      end
      table.insert(ops, { "playlist-move", c - 1, t - 1 })
      table.remove(sim, c)
      table.insert(sim, t, target[t])
    end
  end

  -- 3. Insert new lines, ascending, at their final index.
  for i, l in ipairs(lines) do
    if not ids[i] then
      table.insert(ops, { "loadfile", l, "insert-at", i - 1 })
    end
  end
  return ops
end

return M
