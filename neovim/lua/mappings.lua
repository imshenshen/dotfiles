require "nvchad.mappings"

-- add yours here

local map = vim.keymap.set

map("n", ";", ":", { desc = "CMD enter command mode" })
map("i", "jk", "<ESC>")

map("n","<leader>p",'"+p')
map("n","<leader>P",'"+P')
map("v","<leader>y",'"+y')

-- map({ "n", "i", "v" }, "<C-s>", "<cmd> w <cr>")
