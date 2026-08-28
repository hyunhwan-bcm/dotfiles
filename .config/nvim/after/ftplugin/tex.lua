-- Insert real line breaks at 88 columns.
vim.opt_local.textwidth = 80

-- Automatically format normal prose while typing.
vim.opt_local.formatoptions:append("t")

-- Do not restrict wrapping to only newly entered whitespace or short lines.
vim.opt_local.formatoptions:remove({ "l", "v", "b" })

-- Do not add additional visual wrapping.
vim.opt_local.wrap = false

-- Display the target column.
vim.opt_local.colorcolumn = "80"
