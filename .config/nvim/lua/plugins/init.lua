return {
  {
    "stevearc/conform.nvim",
    -- event = 'BufWritePre', -- uncomment for format on save
    opts = require "configs.conform",
  },

  {
    "neovim/nvim-lspconfig",
    config = function()
      require "configs.lspconfig"
    end,
  },

  {
    "tris203/precognition.nvim",
    event = "VeryLazy",
    opts = {

      startVisible = true,
      showBlankVirtLine = true,
      highlightColor = { link = "Comment" },
    },

    {
      "m4xshen/hardtime.nvim",
      lazy = false,
      dependencies = { "MunifTanjim/nui.nvim" },
      opts = {},
    },
  }

}
