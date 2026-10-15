-- Playback indicator: extmarks + winbar. Never changes buffer text.
local vune = require("vune")

local M = {}

local ns = vim.api.nvim_create_namespace("vune")
local CUR_ID = 1000000000

M.follow = true

local function define_highlights()
  vim.api.nvim_set_hl(0, "VuneCurrent", { link = "CursorLine", default = true })
  vim.api.nvim_set_hl(0, "VunePlayed", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "VuneVirt", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "VuneSign", { link = "DiagnosticOk", default = true })
end

local function fmt_time(s)
  if type(s) ~= "number" then
    return "--:--"
  end
  s = math.floor(s)
  return string.format("%02d:%02d", math.floor(s / 60), s % 60)
end

--- Case-insensitive tag lookup; tag keys differ by format.
local function tag(meta, name)
  for k, v in pairs(meta or {}) do
    if k:lower() == name then
      return v
    end
  end
end

local function title_text()
  local st = vune.state
  local artist, title = tag(st.metadata, "artist"), tag(st.metadata, "title")
  if artist and title then
    return artist .. " - " .. title
  end
  return title or st.media_title or ""
end

local function sign()
  return vune.state.paused and "⏸" or "▶"
end

---@param buf integer
local function render_current(buf)
  local st = vune.state
  local pos = st.pos
  vim.api.nvim_buf_del_extmark(buf, ns, CUR_ID)
  if not pos or pos < 0 or pos >= vim.api.nvim_buf_line_count(buf) then
    return
  end
  vim.api.nvim_buf_set_extmark(buf, ns, pos, 0, {
    id = CUR_ID,
    sign_text = sign(),
    sign_hl_group = "VuneSign",
    line_hl_group = "VuneCurrent",
    virt_text = { { fmt_time(st.time) .. " / " .. fmt_time(st.duration), "VuneVirt" } },
    virt_text_pos = "eol",
  })
end

---@param buf integer
local function render_all(buf)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local pos = vune.state.pos
  if pos and pos > 0 then
    for l = 0, math.min(pos, vim.api.nvim_buf_line_count(buf)) - 1 do
      vim.api.nvim_buf_set_extmark(buf, ns, l, 0, { line_hl_group = "VunePlayed" })
    end
  end
  render_current(buf)
end

---@param win integer
local function render_winbar(win)
  local st = vune.state
  local text = string.format("%s %s  %s/%s", sign(), title_text(), fmt_time(st.time), fmt_time(st.duration))
  vim.wo[win].winbar = text:gsub("%%", "%%%%")
end

---@param buf integer
function M.bind(buf)
  define_highlights()
  local win = vim.fn.bufwinid(buf)
  if win ~= -1 then
    vim.wo[win].signcolumn = "yes"
  end

  local function refresh(name)
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    local w = vim.fn.bufwinid(buf)
    if name == "time-pos" or name == "duration" then
      render_current(buf)
    else
      render_all(buf)
      if name == "playlist-pos" and M.follow and w ~= -1 then
        local pos = vune.state.pos
        if pos and pos >= 0 and pos < vim.api.nvim_buf_line_count(buf) then
          vim.api.nvim_win_set_cursor(w, { pos + 1, 0 })
        end
      end
    end
    if w ~= -1 then
      render_winbar(w)
    end
  end

  vune.on_change = refresh
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    buffer = buf,
    group = vim.api.nvim_create_augroup("vune_ui_" .. buf, { clear = true }),
    callback = function() render_all(buf) end,
  })
  render_all(buf)
  if win ~= -1 then
    render_winbar(win)
  end
end

function M.toggle_follow()
  M.follow = not M.follow
  vim.notify("vune: follow " .. (M.follow and "on" or "off"))
end

return M
