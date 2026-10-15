local ipc = require("vune.ipc")

local M = {}

local PROPS = {
  "time-pos", "duration", "percent-pos", "pause", "playlist-pos", "metadata",
  "media-title", "volume", "mute", "loop-playlist", "idle-active",
}

--- Single state table; mutated from scheduled callbacks only.
M.state = {
  pos = nil, time = nil, duration = nil, paused = nil, volume = nil,
  metadata = nil, media_title = nil, mute = nil, loop = nil, idle = nil,
}

local FIELD = {
  ["time-pos"] = "time", duration = "duration", pause = "paused",
  ["playlist-pos"] = "pos", metadata = "metadata", ["media-title"] = "media_title",
  volume = "volume", mute = "mute", ["loop-playlist"] = "loop", ["idle-active"] = "idle",
}

M.client = nil
--- Optional hook: fun(name, value) called after each state change.
M.on_change = nil

---@param sock string
---@param opts { dir: string?, on_attach: fun(client: table?, err: string?)? }
function M.attach(sock, opts)
  opts = opts or {}
  ipc.connect(sock, {
    on_event = function(ev)
      if ev.event == "property-change" and FIELD[ev.name] then
        vim.schedule(function()
          M.state[FIELD[ev.name]] = ev.data
          if M.on_change then
            M.on_change(ev.name, ev.data)
          end
        end)
      end
    end,
    on_close = function()
      vim.schedule(function()
        M.client = nil
      end)
    end,
  }, function(client, err)
    vim.schedule(function()
      if not client then
        vim.notify("vune: cannot connect to " .. sock .. ": " .. tostring(err), vim.log.levels.ERROR)
        if opts.on_attach then opts.on_attach(nil, err) end
        return
      end
      M.client = client
      vim.api.nvim_create_autocmd("VimLeavePre", {
        group = vim.api.nvim_create_augroup("vune_shutdown", { clear = true }),
        callback = M.shutdown,
      })
      for i, name in ipairs(PROPS) do
        client:observe(i, name)
      end
      local playlist = require("vune.playlist")
      if opts.dir then
        playlist.bind_dir(vim.api.nvim_get_current_buf(), opts.dir)
      elseif vim.bo.filetype == "vune" then
        playlist.bind(vim.api.nvim_get_current_buf())
      end
      if opts.on_attach then opts.on_attach(client) end
    end)
  end)
end

---@param args any[]
function M.cmd(args, cb)
  assert(M.client, "vune: not attached")
  M.client:request(args, cb)
end

--- Stop the mpv daemon. Waits for the write so it is sent before Neovim exits.
function M.shutdown()
  if not M.client then
    return
  end
  local done = false
  M.client.pipe:write(vim.json.encode({ command = { "quit" } }) .. "\n", function()
    done = true
  end)
  vim.wait(500, function() return done end)
end

return M
