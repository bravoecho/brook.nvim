--- brook.nvim: fast and minimalist ripgrep wrapper for Neovim.
---
---   * passes arguments to ripgrep with minimal transformation
---   * integrates results into Neovim's native quickfix list
---   * sets the search register for n/N navigation
---
--- Setup and configuration.
---
---@module 'brook'
local M = {}

local rg = require('brook.rg')
local util = require('brook.util')
local types = require('brook.types')

--- Valid values for output_format config option.
local valid_output_formats = {
  [types.output_format.one_line_per_match] = true,
  [types.output_format.unique_lines] = true,
}

--- @param cfg? brook.UserConfig User-provided configuration
function M.setup(cfg)
  ---@type brook.UserConfig
  local defaults = {
    keymap = '<leader>g',
    stop_keymap = '<leader>G',
    max_results = 1000,
    max_batch_size = 100,
    flush_throttle_ms = 10,
    qf_open = true,
    qf_auto_resize = true,
    qf_win_height = 10,
    output_format = types.output_format.one_line_per_match,
    set_search_register = true,
  }

  ---@type brook.UserConfig
  cfg = vim.tbl_deep_extend('force', defaults, cfg or {})

  -- Validate max_results
  if type(cfg.max_results) ~= 'number'
      or cfg.max_results > types.max_max_results
      or cfg.max_results < 1
  then
    vim.notify(
      'brook.nvim: max_results must be a number between 1 and ' .. types.max_max_results,
      vim.log.levels.ERROR
    )
    return
  end

  -- Validate output_format
  if cfg.output_format ~= nil and not valid_output_formats[cfg.output_format] then
    vim.notify(
      string.format(
        "brook: invalid output_format '%s', expected '%s' or '%s'",
        tostring(cfg.output_format),
        types.output_format.one_line_per_match,
        types.output_format.unique_lines
      ),
      vim.log.levels.ERROR
    )
    return
  end

  ---@type brook.ExecConfig
  local exec_cfg = {
    max_results = cfg.max_results,
    max_batch_size = cfg.max_batch_size,
    flush_throttle_ms = cfg.flush_throttle_ms,
    qf_open = cfg.qf_open,
    qf_auto_resize = cfg.qf_auto_resize,
    qf_win_height = cfg.qf_win_height,
    output_format = cfg.output_format,
    set_search_register = cfg.set_search_register,
    phase3_batch_size = cfg.max_batch_size * 10,
    phase3_throttle_ms = 1,
  }

  local desc = {
    search = 'Search with ripgrep',
    selection = 'Search selection with ripgrep',
    stop = 'Stop ripgrep search',
  }

  ---@type function|nil Function to be used to cancel any current job
  local cancel_fn = nil

  ------------------------------------------------------------------------------
  --- Commands -----------------------------------------------------------------
  ------------------------------------------------------------------------------

  -- Search command
  -----------------
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

      cancel_fn = rg.word(word, exec_cfg)
      return
    end

    -- General case
    ---------------
    cancel_fn = rg.raw(cmd_opts.args, exec_cfg)
  end, { nargs = '*', desc = desc.search, complete = 'file' })

  -- Stop command
  ---------------
  vim.api.nvim_create_user_command('RgStop', function()
    if cancel_fn then
      cancel_fn()
      cancel_fn = nil
    end
  end, { desc = desc.stop })

  ------------------------------------------------------------------------------
  --- Keymaps ------------------------------------------------------------------
  ------------------------------------------------------------------------------

  -- Open command
  ---------------
  vim.keymap.set({ 'n' }, cfg.keymap, ':Rg ', { desc = desc.search })

  -- Visual selection (single line)
  ---------------------------------
  vim.keymap.set({ 'x' }, cfg.keymap, function()
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

    cancel_fn = rg.selection(text, exec_cfg)
  end, { desc = desc.selection })

  -- Stop command
  ---------------
  vim.keymap.set({ 'n' }, cfg.stop_keymap, function()
    if cancel_fn then
      cancel_fn()
      cancel_fn = nil
    end
  end, { desc = desc.stop })
end

return M
