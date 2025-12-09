require("neotest").setup({
  adapters = {
    require("neotest-python")({
      dap = { justMyCode = false },

      args = { "--log-level", "DEBUG" },

      runner = "pytest",

      python = ".venv/bin/python",

      is_test_file = function(file_path)
        -- You MUST replace this, otherwise Lua errors.
        -- Minimal example:
        return file_path:match("_test%.py$") or file_path:match("^test_.*%.py$")
      end,

      pytest_discover_instances = true,
    }),
  },
})

