require "nvchad.mappings"

-- add yours here
local map = vim.keymap.set
local opts = { noremap = true, silent = true }

-- Disable arrow keys (Hard Mode)
vim.keymap.set({ "n", "i", "v" }, "<Up>", "<Nop>", opts)
vim.keymap.set({ "n", "i", "v" }, "<Down>", "<Nop>", opts)
vim.keymap.set({ "n", "i", "v" }, "<Left>", "<Nop>", opts)
vim.keymap.set({ "n", "i", "v" }, "<Right>", "<Nop>", opts)

-- Window navigation is handled by vim-tmux-navigator plugin

vim.keymap.set("n", "<leader>e", ":Neotree toggle<CR>", { silent = true })
