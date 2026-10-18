-- Playlist buffer: one path per line, line = playlist-pos + 1.
local vune = require("vune")

local M = {}

---@param buf integer
local function paths(buf)
  return vim.tbl_filter(function(l)
    return l ~= ""
  end, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
end

--- Bring mpv's playlist in line with the buffer using minimal commands, so
--- the playing track keeps playing unless its line is deleted.
---@param buf integer
function M.sync(buf)
  local lines = paths(buf)
  vune.cmd({ "get_property", "playlist" }, function(err, old)
    vim.schedule(function()
      if err then
        vim.notify("vune: cannot read mpv playlist: " .. err, vim.log.levels.ERROR)
        return
      end
      for _, op in ipairs(require("vune.diff").plan(old, lines)) do
        vune.cmd(op)
      end
    end)
  end)
end

---@param buf integer
local function current_index(buf)
  return vim.api.nvim_win_get_cursor(0)[1] - 1
end

---@param buf integer
local function map(buf)
  local function m(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true })
  end
  m("<CR>", function()
    vune.cmd({ "playlist-play-index", current_index(buf) })
    vune.cmd({ "set_property", "pause", false })
  end)
  m("<Space>", function() vune.cmd({ "cycle", "pause" }) end)
end

--- Bind the buffer to mpv and sync once. An unchanged playlist yields no commands.
---@param buf integer
function M.bind(buf)
  map(buf)
  vim.api.nvim_create_autocmd("BufWritePost", {
    buffer = buf,
    group = vim.api.nvim_create_augroup("vune_sync_" .. buf, { clear = true }),
    callback = function() M.sync(buf) end,
  })
  require("vune.ui").bind(buf)
  M.sync(buf)
end

--- Directory mode: the buffer is not a file. It shows mpv's own (shuffled)
--- playlist, one path per line. `:w` syncs buffer edits to mpv.
---@param buf integer
---@param dir string
function M.bind_dir(buf, dir)
  vim.api.nvim_buf_set_name(buf, "vune://" .. dir)
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "vune"
  map(buf)
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    group = vim.api.nvim_create_augroup("vune_sync_" .. buf, { clear = true }),
    callback = function(ev)
      if ev.file ~= vim.api.nvim_buf_get_name(buf) then
        -- `:w list.m3u` saves the playlist as a file; mpv is unaffected.
        vim.fn.writefile(vim.api.nvim_buf_get_lines(buf, 0, -1, false), ev.file)
        return
      end
      M.sync(buf)
      vim.bo[buf].modified = false
    end,
  })
  require("vune.ui").bind(buf)

  -- mpv expands the directory after start; wait for the entries.
  local function load(attempt)
    vune.cmd({ "get_property", "playlist" }, function(err, data)
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then
          return
        end
        -- With --shuffle mpv briefly reports only the unexpanded directory entry.
        if err or #data == 0 or (#data == 1 and vim.fn.isdirectory(data[1].filename) == 1) then
          if attempt < 50 then
            vim.defer_fn(function() load(attempt + 1) end, 100)
          else
            vim.notify("vune: mpv playlist is empty for " .. dir, vim.log.levels.ERROR)
          end
          return
        end
        local lines = {}
        for i, e in ipairs(data) do
          lines[i] = e.filename
        end
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
        vim.bo[buf].modified = false
        if vune.on_change then
          vune.on_change("playlist-pos", vune.state.pos)
        end
      end)
    end)
  end
  load(0)
end

return M
