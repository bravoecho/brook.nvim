local M = {}

local rg = require('brook.rg')
local util = require('brook.util')

--- @param plugin_opts? brook.BrookOpts
function M.setup(plugin_opts)
  plugin_opts = plugin_opts or {}
  local keymap = plugin_opts.keymap or '<leader>g'
  local max_results = plugin_opts.max_results
  if max_results == nil then
    max_results = 1000
  end
  local buffer_size = plugin_opts.buffer_size
  if buffer_size == nil then
    buffer_size = 100
  end
  local debounce = plugin_opts.debounce
  if debounce == nil then
    debounce = 80
  end

  ---@type brook.ExecOpts
  local exec_opts = {
    max_results = max_results,
    buffer_size = buffer_size,
    debounce = debounce,
  }

  ------------------------------------------------------------------------------
  --- Commands -----------------------------------------------------------------
  ------------------------------------------------------------------------------

  -- Search command
  ------------------------------------------------------------------------------
  vim.api.nvim_create_user_command('Rg', function(cmd_opts)
    local args = vim.trim(cmd_opts.args)

    -- Special case: current word
    -----------------------------
    if args == '' then
      local word = vim.fn.expand('<cword>')
      if word == '' then
        vim.notify('rg: no word under the cursor', vim.log.levels.WARN)
        return
      end

      rg.word(word, exec_opts)
      return
    end

    -- General case
    ---------------
    rg.raw(cmd_opts.args, exec_opts)
  end, { nargs = '*', desc = 'Grep with ripgrep', complete = 'file' })

  -- Stop command
  ------------------------------------------------------------------------------
  vim.api.nvim_create_user_command('RgStop', rg.stop, { desc = 'Stop current ripgrep search' })

  ------------------------------------------------------------------------------
  --- Keymaps ------------------------------------------------------------------
  ------------------------------------------------------------------------------

  -- Open command
  ------------------------------------------------------------------------------
  vim.keymap.set({ 'n' }, keymap, ':Rg ', { desc = 'Grep with rg' })

  -- Visual selection (single line)
  ---------------------------------
  vim.keymap.set({ 'x' }, keymap, function()
    local text = util.get_visual_selection()

    if text:find('\n') then
      vim.notify('rg: multi-line selection not supported', vim.log.levels.WARN)
      return
    end

    -- TODO: check if this can happen in practice
    if text == '' then
      vim.notify('rg: empty selection', vim.log.levels.WARN)
      return
    end

    rg.selection(text, exec_opts)
  end, { desc = 'Grep visual selection with ripgrep' })
end

return M
