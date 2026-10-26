if vim.g.dbt_lens == nil then return end -- nothing to do unless the user configured the plugin
require('dbt_lens.keymaps').attach(vim.api.nvim_get_current_buf())
