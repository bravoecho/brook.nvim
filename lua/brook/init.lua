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
local args_types = require('brook.args.types')
local types = require('brook.types')

--- Valid values for output_format config option.
local valid_output_formats = {
  [args_types.output_format.one_line_per_match] = true,
  [args_types.output_format.unique_lines] = true,
}

--- @param cfg? brook.UserConfig User-provided configuration
function M.setup(cfg)
  ------------------------------------------------------------------------------
  --- Defaults -----------------------------------------------------------------
  ------------------------------------------------------------------------------

  ---@type brook.UserConfig
  local defaults = {
    keymap_cword = '<leader>g',
    keymap_visual = '<leader>g',
    keymap_prompt = '<leader>/',
    keymap_stop = '<leader>G',
    keymap_repeat = '<leader>r',
    max_results = 1000,
    max_batch_size = 100,
    flush_throttle_ms = 10,
    qf_open = true,
    qf_auto_resize = true,
    qf_win_height = 10,
    output_format = args_types.output_format.one_line_per_match,
    set_search_register = true,
    max_preview_chars = 200,
    wipe_unlisted_buffers = true,
  }

  ---@type brook.UserConfig
  cfg = vim.tbl_deep_extend('force', defaults, cfg or {})

  if not cfg.drain_phase_max_batch_size then
    cfg.drain_phase_max_batch_size = cfg.max_batch_size * 5
  end

  if not cfg.drain_phase_flush_throttle_ms then
    cfg.drain_phase_flush_throttle_ms = math.floor(cfg.flush_throttle_ms / 2)
  end

  ------------------------------------------------------------------------------
  --- Validations --------------------------------------------------------------
  ------------------------------------------------------------------------------

  -- Validate max_results
  -----------------------
  local valid_max_results = types.validations.max_results
  if type(cfg.max_results) ~= 'number'
      or cfg.max_results > valid_max_results.max
      or cfg.max_results < valid_max_results.min
  then
    vim.notify(
      string.format(
        'brook.nvim: max_results range %d-%d',
        valid_max_results.min,
        valid_max_results.max
      ),
      vim.log.levels.ERROR
    )
    return
  end

  -- Validate output_format
  -------------------------
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

  -- Validate max_preview_chars
  -----------------------------
  local valid_preview_chars = types.validations.max_preview_chars
  if type(cfg.max_preview_chars) ~= 'number'
      or cfg.max_preview_chars < valid_preview_chars.min
      or cfg.max_preview_chars > valid_preview_chars.max
  then
    vim.notify(
      string.format(
        'brook.nvim: max_preview_chars range: %d-%d',
        valid_preview_chars.min,
        valid_preview_chars.max
      ),
      vim.log.levels.ERROR
    )
    return
  end

  -- Validate max_batch_size
  --------------------------
  local valid_max_batch_size = types.validations.max_batch_size
  if type(cfg.max_batch_size) ~= 'number'
      or cfg.max_batch_size < valid_max_batch_size.min
      or cfg.max_batch_size > valid_max_batch_size.max
  then
    vim.notify(
      string.format(
        'brook.nvim: max_batch_size range: %d-%d',
        valid_max_batch_size.min,
        valid_max_batch_size.max
      ),
      vim.log.levels.ERROR
    )
    return
  end

  ------------------------------------------------------------------------------
  --- Command configuration ----------------------------------------------------
  ------------------------------------------------------------------------------

  ---@type brook.rg.ExecConfig
  local exec_cfg = {
    max_results = cfg.max_results,
    max_batch_size = cfg.max_batch_size,
    batch_jitter = 0.1,
    flush_throttle_ms = cfg.flush_throttle_ms,
    qf_open = cfg.qf_open,
    qf_auto_resize = cfg.qf_auto_resize,
    qf_win_height = cfg.qf_win_height,
    output_format = cfg.output_format,
    set_search_register = cfg.set_search_register,
    drain_phase_max_batch_size = cfg.drain_phase_max_batch_size,
    drain_phase_flush_throttle_ms = cfg.drain_phase_flush_throttle_ms,
    max_preview_chars = cfg.max_preview_chars,
    wipe_unlisted_buffers = cfg.wipe_unlisted_buffers,
    _benchmark = false,
  }

  ---@type function|nil Function to be used to cancel any current job
  local cancel_fn = nil

  ------------------------------------------------------------------------------
  --- Commands -----------------------------------------------------------------
  ------------------------------------------------------------------------------

  local command_desc = {
    search = 'Search with ripgrep',
    stop = 'Stop ripgrep search',
    repeat_last = 'Repeat last ripgrep search',
  }

  -- Search command
  -----------------
  vim.api.nvim_create_user_command('Rg', function(cmd_opts)
    local args = vim.trim(cmd_opts.args)
    local cword = vim.fn.expand('<cword>')

    -- Special case: current word
    -----------------------------
    if args == '' then
      if cword == '' then
        vim.notify('rg: no word under the cursor', vim.log.levels.ERROR)
        return
      end

      cancel_fn = rg.word(cword, exec_cfg)
      return
    end

    -- General case
    ---------------
    ---@type brook.rg.RawOpts
    local raw_opts = {
      args_string = cmd_opts.args,
      fallback_word = cword,
    }
    cancel_fn = rg.raw(raw_opts, exec_cfg)
  end, { nargs = '*', desc = command_desc.search, complete = 'file' })

  -- Stop command
  ---------------
  vim.api.nvim_create_user_command('RgStop', function()
    if cancel_fn then
      cancel_fn()
      cancel_fn = nil
    end
  end, { desc = command_desc.stop })

  -- Repeat command
  -----------------
  vim.api.nvim_create_user_command('RgRepeat', function()
    cancel_fn = rg.repeat_last()
  end, { desc = command_desc.repeat_last })

  ------------------------------------------------------------------------------
  --- Keymaps ------------------------------------------------------------------
  ------------------------------------------------------------------------------

  local keymap_desc = {
    cword = 'Search for current word with ripgrep',
    visual = 'Search for visual selection with ripgrep',
    prompt = 'Open ripgrep prompt',
    stop = 'Stop ripgrep search',
    repeat_last = 'Repeat last ripgrep search',
  }

  -- Current word
  ---------------
  if cfg.keymap_cword then
    vim.keymap.set({ 'n' }, cfg.keymap_cword, function()
      local cword = vim.fn.expand('<cword>')
      if cword == '' then
        vim.notify('rg: no word under the cursor', vim.log.levels.ERROR)
        return
      end

      cancel_fn = rg.word(cword, exec_cfg)
    end, { desc = keymap_desc.cword })
  end

  -- Visual selection
  -------------------
  if cfg.keymap_visual then
    vim.keymap.set({ 'x' }, cfg.keymap_visual, function()
      local text = util.get_visual_selection()

      if text:find('\n') then
        vim.notify('rg: multi-line selection not supported', vim.log.levels.ERROR)
        return
      end

      if text == '' then
        vim.notify('rg: empty selection', vim.log.levels.ERROR)
        return
      end

      cancel_fn = rg.selection(text, exec_cfg)
    end, { desc = keymap_desc.visual })
  end

  -- Open prompt
  --------------
  if cfg.keymap_prompt then
    vim.keymap.set({ 'n' }, cfg.keymap_prompt, ':Rg ', { desc = keymap_desc.prompt })
  end

  -- Stop current search
  ----------------------
  if cfg.keymap_stop then
    vim.keymap.set({ 'n' }, cfg.keymap_stop, function()
      if cancel_fn then
        cancel_fn()
        cancel_fn = nil
      else
        vim.notify('rg: no search in progress', vim.log.levels.WARN)
      end
    end, { desc = keymap_desc.stop })
  end

  -- Repeat last search
  ---------------------
  if cfg.keymap_repeat then
    vim.keymap.set({ 'n' }, cfg.keymap_repeat, function()
      cancel_fn = rg.repeat_last()
    end, { desc = keymap_desc.repeat_last })
  end
end

return M
