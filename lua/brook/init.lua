local M = {}

local rg_exec = require('brook.rg_exec')
local rg_raw = rg_exec.rg_raw
local rg_selection = rg_exec.rg_selection
local rg_word = rg_exec.rg_word
local get_visual_selection = require('brook.utils').get_visual_selection

--- @param plugin_opts? brook.PluginOpts
function M.setup(plugin_opts)
  plugin_opts = plugin_opts or {}
  local keymap = plugin_opts.keymap or '<leader>g'
  local max_results = plugin_opts.max_results or 1000

  ---------------
  --- Command ---
  ---------------
  vim.api.nvim_create_user_command('Rg', function(cmd_opts)
    local args = vim.trim(cmd_opts.args)

    -- Special case: search for current word when no arguments are provided
    -----------------------------------------------------------------------
    if args == '' then
      local word = vim.fn.expand('<cword>')
      if word == '' then
        vim.notify('No word under the cursor', vim.log.levels.INFO)
        return
      end

      rg_word(word, { max_results = max_results })
      return
    end

    -- General case: forward command arguments to ripgrep
    -----------------------------------------------------
    rg_raw(cmd_opts.args, { max_results = max_results })
  end, { nargs = '*', desc = 'Grep with ripgrep', complete = 'file' })

  ------------------------
  --- Command shortcut ---
  ------------------------
  vim.keymap.set({ 'n' }, keymap, ':Rg ', { desc = 'Grep with rg' })

  --------------------------------------
  --- Visual selection (single line) ---
  --------------------------------------
  vim.keymap.set({ 'x' }, keymap, function()
    local text = get_visual_selection()

    if text:find('\n') then
      vim.notify('Multi-line selections are not supported', vim.log.levels.WARN)
      return
    end

    -- TODO: check if this can happen in practice
    if text == '' then
      vim.notify('Empty selection', vim.log.levels.WARN)
      return
    end

    rg_selection(text, { max_results = max_results })
  end, { desc = 'Grep visual selection with ripgrep' })
end

return M
