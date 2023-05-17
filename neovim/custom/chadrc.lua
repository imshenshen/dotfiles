local M = {}
M.ui = {
  theme = "wombat",
  statusline = {
    theme = "minimal",
    -- separator_style = "round"
  }
}

M.mappings = require "custom.mappings"
M.plugins = "custom.plugins"

return M
