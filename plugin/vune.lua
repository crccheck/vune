vim.api.nvim_create_user_command("VuneFollow", function()
  require("vune.ui").toggle_follow()
end, { desc = "Toggle cursor following the current track" })
