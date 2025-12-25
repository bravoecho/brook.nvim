local M = {}

local rg = require('brook.rg')
local util = require('brook.util')
local types = require('brook.types')

--- Valid values for output_format config option.
local valid_output_formats = {
  [types.output_format.one_line_per_match] = true,
  [types.output_format.unique_lines] = true,
}

--- @param cfg? brook.Config User-provided configuration
function M.setup(cfg)
  cfg = vim.tbl_deep_extend('force', types.defaults, cfg or {})

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

  ---@type brook.ExecOpts
  local exec_opts = {
    max_results = cfg.max_results,
    buffer_size = cfg.buffer_size,
    debounce = cfg.debounce,
    qf_open = cfg.qf_open,
    qf_auto_resize = cfg.qf_auto_resize,
    qf_win_height = cfg.qf_win_height,
    output_format = cfg.output_format,
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
  vim.keymap.set({ 'n' }, cfg.keymap, ':Rg ', { desc = 'Grep with rg' })

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

    rg.selection(text, exec_opts)
  end, { desc = 'Grep visual selection with ripgrep' })
end

return M
