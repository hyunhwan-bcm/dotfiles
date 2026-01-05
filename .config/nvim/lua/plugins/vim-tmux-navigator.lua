return {
  {
    'christoomey/vim-tmux-navigator',

    init = function()
      vim.g.tmux_navigator_no_mappings = true
      vim.g.tmux_navigator_no_wrap = true
    end,

    config = function()
      vim.keymap.set('n', '<C-h>', ':<C-U>TmuxNavigateLeft<CR>', { silent = true })
      vim.keymap.set('n', '<C-j>', ':<C-U>TmuxNavigateDown<CR>', { silent = true })
      vim.keymap.set('n', '<C-k>', ':<C-U>TmuxNavigateUp<CR>', { silent = true })
      vim.keymap.set('n', '<C-l>', ':<C-U>TmuxNavigateRight<CR>', { silent = true })
    end,
  },
}
