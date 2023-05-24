-- https://nvchad.com/docs/config/mappings
local M = {}

-- In order to disable a default keymap, use
M.disabled = {}

M.custom = {
    n = {
        ["<leader>p"] = {'"+p', "paste from clipboard"},
        ["<leader>P"] = {'"+P', "paste from clipboard"},
    },
    v = {
        ["<leader>y"] = {'"+y', "copy to clipboard"}
    }
}

return M
