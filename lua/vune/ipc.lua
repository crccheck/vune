-- mpv JSON IPC client over a unix socket.
local uv = vim.uv

local M = {}
M.__index = M

---@param sock string socket path
---@param opts { on_event: fun(ev: table), on_close: fun()? }
function M.connect(sock, opts, cb)
  local self = setmetatable({
    pipe = uv.new_pipe(false),
    buf = "",
    next_id = 1,
    pending = {},
    on_event = opts.on_event,
    on_close = opts.on_close,
  }, M)
  self.pipe:connect(sock, function(err)
    if err then
      self.pipe:close()
      return cb(nil, err)
    end
    self.pipe:read_start(function(rerr, data)
      if rerr or not data then
        self:close()
        return
      end
      self:_feed(data)
    end)
    cb(self)
  end)
end

function M:_feed(data)
  self.buf = self.buf .. data
  while true do
    local nl = self.buf:find("\n", 1, true)
    if not nl then
      break
    end
    local line = self.buf:sub(1, nl - 1)
    self.buf = self.buf:sub(nl + 1)
    if line ~= "" then
      local ok, msg = pcall(vim.json.decode, line)
      if ok and type(msg) == "table" then
        self:_dispatch(msg)
      end
    end
  end
end

function M:_dispatch(msg)
  if msg.request_id then
    local cb = self.pending[msg.request_id]
    self.pending[msg.request_id] = nil
    if cb then
      cb(msg.error ~= "success" and msg.error or nil, msg.data)
    end
  elseif msg.event and self.on_event then
    self.on_event(msg)
  end
end

--- Send a command. `cb(err, data)` is optional; runs in the libuv callback.
---@param args any[]
function M:request(args, cb)
  local id = self.next_id
  self.next_id = id + 1
  if cb then
    self.pending[id] = cb
  end
  self.pipe:write(vim.json.encode({ command = args, request_id = id }) .. "\n")
end

function M:observe(id, name)
  self:request({ "observe_property", id, name })
end

function M:close()
  if self.pipe and not self.pipe:is_closing() then
    self.pipe:close()
    if self.on_close then
      self.on_close()
    end
  end
end

return M
