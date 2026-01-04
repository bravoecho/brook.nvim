--- Asynchronous ripgrep execution with streaming quickfix integration.
---
--- Challenges that can cause UI freeze (redraw starvation):
---
---   * ripgrep can produce results faster than Neovim can render them
---
---   * Neovim does not backpressure built in
---
---   * the quickfix list is memory-intensive
---
--- To provide consistent performance and responsiveness, this module:
---
---   * decouples producer (ripgrep's stdout) and consumer (quickfix rendering)
---     by interposing a queue, so that both can work at their optimal pace
---
---   * orchestrates quickfix updates in different phases
---     1. first paint
---     2. steady streaming (ripgrep still running)
---     3. turbo-drain (ripgrep has finished)
---
--- Other key features:
---
---   * capped results (configurable up to 10,000) to prevent memory bloat
---     and editor slowdown
---
---   * bypasss shell for compatibility and security
---
--- See the phases enum and individual phase functions for implementation
--- details.
---
---@module 'brook.exec'

local pattern = require('brook.pattern')
local fifo = require('brook.lib.fifo')
local types = require('brook.types')

local M = {}

--------------------------------------------------------------------------------
--- Module-level State ---------------------------------------------------------
--------------------------------------------------------------------------------

-- The module serves as a singleton, and this is the state that persists between
-- searches and to support cancellation.

---@type number|nil Vim job id returned by vim.fn.jobstart()
local active_rg_job_id = nil

--- Also used to guard the throttling use case (flush_throttle_ms > 0).
---@type uv.uv_timer_t|nil
local phase2_timer = nil

--- Used to guard the schedule-chaining use case (flush_throttle_ms == 0)
local phase2_scheduled = false

--- Timer for phase 3 (post-exit drain).
---@type uv.uv_timer_t|nil
local phase3_timer = nil

---@type brook.ExecSession
local current_session = nil

--------------------------------------------------------------------------------
--- Enums ----------------------------------------------------------------------
--------------------------------------------------------------------------------

--- Three-phase consumer strategy to avoid redraw starvation.
---
---@enum brook.ExecPhase
local phases = {
  --- First paint: flush just enough to fill the visible quickfix window.
  --- Runs synchronously when invoked by the producer, then returns to let
  --- the main loop redraw. Never self-schedules.
  phase_1 = 'phase-1',

  --- Streaming: flush queued items in bounded batches while ripgrep runs.
  --- Each batch schedules at most one successor, yielding to the main loop
  --- between updates.
  phase_2 = 'phase-2',

  --- Post-exit drain: ripgrep has finished but items remain queued. Uses
  --- shorter intervals and larger batches than phase 2 to drain quickly
  --- while still yielding for redraws.
  phase_3 = 'phase-3',

  done = 'done',
}

---@enum brook.QuickfixOperation
local qf_operation = {
  replace = 'r',
  append = 'a',
}

--------------------------------------------------------------------------------
--- Typedefs -------------------------------------------------------------------
--------------------------------------------------------------------------------

--- Context object for ripgrep execution (parameters for _exec).
---
---@class brook.SearchContext
---@field args string[] Shell-unquoted command tokens to be passed to `rg`
---@field parsed_args brook.ParsedArgs Subset of command arguments needed to integrate the command correctly
---@field cfg brook.ExecConfig Control how search is performed and results displayed

---@class brook.ExecSession State of a search command execution
---@field is_first_batch boolean
---@field qf_operation brook.QuickfixOperation First time replace the content, then switch to append
---@field total_results number Number of matches parsed from ripgrep (producer-side)
---@field flushed_results number Number of entries actually pushed into quickfix (consumer-side, UI)
---@field stopped_at_limit boolean
---@field stopped_by_user boolean
---@field did_resize boolean Whether the quickfix window has rearched its target height
---@field current_phase brook.ExecPhase
---@field queue brook.Fifo FIFO queue between rg and quickfix, decouples producer (rg's stdout) from consumer (quickfix)
---@field stdout_buffer string Last segment of the previous stdout batch. See :h channel-lines
---@field stderr_lines string[]
---@field exit_code number|nil

--------------------------------------------------------------------------------
--- Entry Point ----------------------------------------------------------------
--------------------------------------------------------------------------------

--- Runs ripgrep with the given argument array.
---
--- This function bypasses the shell, by forwarding an array of arguments
--- directly to jobstart(), which uses execve() under the hood. This avoids some
--- common areas for error with shells:
---   - escaping
---   - compatibility issues (Fish and POSIX-like have different rules)
---   - shell injection vulnerabilities
---
---@param ctx brook.SearchContext Search context with all execution parameters
---@return function|nil cancel_fn
function M._exec(ctx)
  -- Cleanup previous search
  --------------------------
  M._cancel_phase2_scheduling()
  M._cancel_phase3_scheduling()

  if active_rg_job_id then
    vim.fn.jobstop(active_rg_job_id)
    active_rg_job_id = nil
  end

  -- Initialise session
  ---------------------
  ---@type brook.ExecSession
  current_session = {
    is_first_batch = true,
    qf_operation = qf_operation.replace,
    total_results = 0,
    flushed_results = 0,
    stopped_at_limit = false,
    stopped_by_user = false,
    did_resize = false,
    current_phase = phases.phase_1,
    queue = fifo.new(),
    stdout_buffer = '',
    stderr_lines = {},
    exit_code = nil,
  }

  local parse_line = ctx.cfg.output_format == types.output_format.unique_lines
      and M._parse_line_number
      or M._parse_vimgrep

  vim.notify('rg ' .. ctx.parsed_args.raw, vim.log.levels.INFO)

  -- Run ripgrep
  --------------
  active_rg_job_id = vim.fn.jobstart(M._build_rg_cmd(ctx), {
    -- Close stdin immediately: ripgrep waits on stdin indefinitely when
    -- invoked programmatically.
    stdin = 'null',

    on_stdout = vim.schedule_wrap(function(_, data, _)
      M._on_stdout(data, ctx, current_session, parse_line)
    end),

    -- Buffer stderr to receive all error output in a single callback.
    stderr_buffered = true,

    on_stderr = function(_, data, _)
      M._on_stderr(data, current_session)
    end,

    on_exit = vim.schedule_wrap(function(_, exit_code, _)
      M._on_exit(exit_code, ctx, current_session)
    end),
  })

  if active_rg_job_id <= 0 then
    vim.notify('rg: failed to start: is ripgrep installed?', vim.log.levels.ERROR)
    active_rg_job_id = nil
    return nil
  end

  -- Set up cancellation
  ----------------------
  return M._user_cancel_function(active_rg_job_id, current_session)
end

---@param ctx brook.SearchContext Search context with all execution parameters
---@return string[] cmd Command table for jobstart()
function M._build_rg_cmd(ctx)
  local cmd = {
    'rg',
    '--no-multiline',
    '--engine', 'default',
    '--max-columns', tostring(ctx.cfg.max_preview_chars),
    '--max-columns-preview',
    '--color', 'never',
  }

  -- When output_format is 'unique-lines', use --line-number instead of --vimgrep.
  -- This omits the column number, causing ripgrep to emit each line only once
  -- regardless of how many matches it contains.
  if ctx.cfg.output_format == types.output_format.unique_lines then
    table.insert(cmd, '--line-number')
  else
    table.insert(cmd, '--vimgrep')
  end

  if ctx.parsed_args.word then
    table.insert(cmd, '--word-regexp')
  end

  if ctx.parsed_args.fixed then
    table.insert(cmd, '--fixed-strings')
  end

  if ctx.parsed_args.case == types.search_case.sensitive then
    table.insert(cmd, '--case-sensitive')
  elseif ctx.parsed_args.case == types.search_case.insensitive then
    table.insert(cmd, '--ignore-case')
  end

  for _, arg in ipairs(ctx.args) do
    table.insert(cmd, arg)
  end

  return cmd
end

---@param job_id number|nil ID of the job to cancel
---@param session brook.ExecSession Session to invalidate
---@return function
function M._user_cancel_function(job_id, session)
  return function()
    M._cancel_phase2_scheduling()
    M._cancel_phase3_scheduling()

    if job_id and job_id == active_rg_job_id then
      session.stopped_by_user = true
      vim.fn.jobstop(job_id)
      active_rg_job_id = nil
    end
  end
end

--------------------------------------------------------------------------------
--- Producer -------------------------------------------------------------------
--------------------------------------------------------------------------------

--- The stdout handler callback:
---   * parses and enqueues results
---   * triggers the consumer
---
---@param data string[] stdout segments yielded by the on_stdout callaback. See :h channel-lines
---@param ctx brook.SearchContext
---@param session brook.ExecSession
---@param parse_line function The appropriate parser based on output format
function M._on_stdout(data, ctx, session, parse_line)
  if not active_rg_job_id then
    return
  end

  -- Should never happen according to docs.
  if not data then
    return
  end

  -- Handle incomplete segments and EOF. What remains are all fully-formed lines.
  if #data == 1 and data[1] == '' then
    -- EOF and no dangling buffer: nothing else to do.
    if session.stdout_buffer == '' then return end
    -- EOF, but there's still a result in the buffer: put it back into `data`
    data[1] = session.stdout_buffer
    session.stdout_buffer = ''
  else
    -- Handle ongoing stream
    -- 1. Complete the first segment using the last one from the previous batch.
    data[1] = session.stdout_buffer .. data[1]
    -- 2. Pop the last (potentially incomplete) segment of this batch.
    session.stdout_buffer = table.remove(data)
  end

  -- NOTE: After removing the last (potentially incomplete) element, data may
  -- be empty. This is expected when we receive a single partial segment; it
  -- will be completed and processed when the next stdout event arrives.
  if #data == 0 then
    return
  end

  for _, line in ipairs(data) do
    if session.total_results >= ctx.cfg.max_results then
      -- Quickfix lists are memory-heavy. We stop early to cap memory bloat
      -- and to avoid leaving Neovim in a slowed state after the search.
      session.stopped_at_limit = true
      M._request_flush(ctx, session)
      if active_rg_job_id then
        vim.fn.jobstop(active_rg_job_id)
        active_rg_job_id = nil
      end
      break
    end

    local entry = parse_line(line)
    if entry then
      session.queue.push(entry)
      session.total_results = session.total_results + 1
    end

    -- Don't wait until the entire result batch is processed, if there are
    -- already enough results to flush.
    if session.queue.len() >= ctx.cfg.max_batch_size then
      M._request_flush(ctx, session)
    end
  end

  M._request_flush(ctx, session)
end

--- Parses a vimgrep-format result line into a quickfix entry.
---
--- Format: "file:line:col:text" (default, --vimgrep)
--- Example: "some/path/to/file.txt:137:42:the red fox jumped"
---
---@param result string A line in vimgrep format
---@return vim.quickfix.entry|nil entry Quickfix entry, or nil if parsing fails
function M._parse_vimgrep(result)
  -- Note: Unix filenames can contain colons, so we can't simply split on ':'.
  -- Instead, we locate the :line:col: pattern and extract components by position.
  local start_pos, end_pos, lnum, col = result:find(':(%d+):(%d+):')
  if not start_pos then
    return nil
  end

  local filename = result:sub(1, start_pos - 1)
  local text = result:sub(end_pos + 1)

  return {
    filename = filename,
    lnum = tonumber(lnum),
    col = tonumber(col),
    text = text,
  }
end

--- Parses a line-number-format result line into a quickfix entry.
---
--- Format: "file:line:text" (unique-lines mode, --line-number)
--- Example: "some/path/to/file.txt:137:the red fox jumped"
---
---@param result string A line in line-number format
---@return vim.quickfix.entry|nil entry Quickfix entry, or nil if parsing fails
function M._parse_line_number(result)
  -- Note: Unix filenames can contain colons, so we can't simply split on ':'.
  -- Instead, we locate the :line: pattern and extract components by position.
  local start_pos, end_pos, lnum = result:find(':(%d+):')
  if not start_pos then
    return nil
  end

  local filename = result:sub(1, start_pos - 1)
  local text = result:sub(end_pos + 1)

  return {
    filename = filename,
    lnum = tonumber(lnum),
    col = 1, -- Default to column 1 when no column info available
    text = text,
  }
end

-- stderr is buffered (see jobstart options below), so this callback
-- receives all stderr output in a single call when the job exits.
--
---@param data string[]
---@param session brook.ExecSession
function M._on_stderr(data, session)
  if not data or #data == 0 then
    return
  end
  if data[#data] == '' then
    table.remove(data)
  end
  session.stderr_lines = data
end

--- on_exit is a final trigger for consumers: it ensures anything still in
--- the stdout buffer/queue becomes visible even if rg stops suddenly.
---
---@param exit_code number
---@param ctx brook.SearchContext
---@param session brook.ExecSession
function M._on_exit(exit_code, ctx, session)
  -- Capture exit state for notify_completion (called at end of phase 3).
  session.exit_code = exit_code
  if session.current_phase == phases.phase_1 then
    -- Handle edge case where ripgrep exited before the quickfix window was
    -- fully populated. Flush synchronously to ensure results are visible.
    M._flush_phase1(ctx, session)
  end

  M._start_phase3(ctx, session)
end

--------------------------------------------------------------------------------
--- Consumer: Dispatch ---------------------------------------------------------
--------------------------------------------------------------------------------

--- request_flush will either
---
---   - flush synchronously (phase 1)...
---   - ...or schedule a flush (phase 2)
---
--- Since it may run synchronously (depending on phase) it must be called from
--- a scheduled context (Neovim's main loop).
---
---@param ctx brook.SearchContext
---@param session brook.ExecSession
function M._request_flush(ctx, session)
  if session.current_phase == phases.phase_1 then
    M._flush_phase1(ctx, session)
  elseif session.current_phase == phases.phase_2 then
    M._schedule_flush_phase2(ctx, session)
  end
end

--------------------------------------------------------------------------------
--- Consumer: Phase 1 (First Paint) --------------------------------------------
--------------------------------------------------------------------------------

--- Phase-1 consumer: perform the first meaningful "paint".
---
---   * Flushes *at most* the number of items needed to reach the visible
---     quickfix window height (above the fold).
---
---   * Never self-schedules (no timers/recursion/defer_fn). This function must
---     run synchronously and return control to the main loop so Neovim can
---     become idle and redraw.
---
---   * Owns the phase transition: when the visible region is filled, it moves
---     the consumer into phase2 (throughput mode).
---
--- See also the `phases` enum.
---
---@param ctx brook.SearchContext
---@param session brook.ExecSession
function M._flush_phase1(ctx, session)
  if session.current_phase ~= phases.phase_1 or session.queue.is_empty() then
    return
  end

  local remaining_visible_slots = M._remaining_visible_slots(ctx, session)
  if remaining_visible_slots == 0 then
    M._start_phase2(ctx, session)
    return
  end

  -- Pull only the minimum necessary to fill the quickfix window above the
  -- fold.
  M._update_quickfix(session.queue.pull(remaining_visible_slots), ctx, session)

  -- If phase 1 has finished, kick off phase 2 anyway, no need to wait for
  -- the next `on_stdout` run.
  if M._remaining_visible_slots(ctx, session) == 0 then
    M._start_phase2(ctx, session)
  end
end

--- Counts how many results are still missing before reaching the target
--- quickfix window height.
function M._remaining_visible_slots(ctx, session)
  return math.max(0, ctx.cfg.qf_win_height - session.flushed_results)
end

--------------------------------------------------------------------------------
--- Consumer: Phase 2 (Streaming) ----------------------------------------------
--------------------------------------------------------------------------------

--- Phase 2 consumer: flush while ripgrep is still running.
---
---   * Pulls batches of results from the queue and renders them.
---
---   * Is triggered by phase 1.
---
---   * Reschedules itself if there are pending entries in the queue.
---
--- See also the `phases` enum.
---
---@param ctx brook.SearchContext
---@param session brook.ExecSession
function M._flush_phase2(ctx, session)
  if session.current_phase ~= phases.phase_2 or session.queue.is_empty() then
    return
  end

  M._update_quickfix(session.queue.pull(ctx.cfg.max_batch_size), ctx, session)

  -- Wait until quickfix is updated before unlocking next flush.
  phase2_scheduled = false

  if not session.queue.is_empty() then
    M._schedule_flush_phase2(ctx, session)
  end
end

--- Schedules the next flush in phase 2.
---
--- Guards against multiple concurrent schedules: in timer mode, the timer
--- itself is the guard; in schedule mode, phase2_scheduled prevents duplicates.
---
--- Called both by the producer (to trigger phase-2 work) and by flush_phase2
--- itself (to schedule the next batch).
---
---@param ctx brook.SearchContext
---@param session brook.ExecSession
function M._schedule_flush_phase2(ctx, session)
  if ctx.cfg.flush_throttle_ms > 0 then
    -- In timer/throttle mode the timer itself is the guard.
    -- ensure at most one timer is present at any given time
    if phase2_timer then
      return
    end

    phase2_timer = vim.defer_fn(function()
      -- timer has triggered, can be removed
      phase2_timer = nil
      M._flush_phase2(ctx, session)
    end, ctx.cfg.flush_throttle_ms)
  else
    -- In schedule mode: a separate guard is needed to prevent multiple schedules.
    if phase2_scheduled then
      return
    end
    phase2_scheduled = true
    vim.schedule(function()
      M._flush_phase2(ctx, session)
    end)
  end
end

---@param ctx brook.SearchContext
---@param session brook.ExecSession
function M._start_phase2(ctx, session)
  session.current_phase = phases.phase_2
  M._schedule_flush_phase2(ctx, session)
end

--- Cancels flush scheduling, both in timer/throttling mode and in schedule mode.
function M._cancel_phase2_scheduling()
  if phase2_timer then
    phase2_timer:stop()
    phase2_timer = nil
  end
  phase2_scheduled = false
end

--------------------------------------------------------------------------------
--- Consumer: Phase 3 (Post-exit Drain) ----------------------------------------
--------------------------------------------------------------------------------

--- Phase-3 consumer: drains the queue quickly after ripgrep has exited.
---
---   * Triggered by `on_exit`.
---
---   * Self-reschedules until the queue is drained.
---
---   * Notifies user of completion.
---
--- See also the `phases` enum.
---
---@param ctx brook.SearchContext
---@param session brook.ExecSession
function M._flush_phase3(ctx, session)
  M._update_quickfix(session.queue.pull(ctx.cfg.phase3_batch_size), ctx, session)

  if session.queue.is_empty() then
    session.current_phase = phases.done
    M._notify_completion(ctx, session)
    return
  end

  phase3_timer = vim.defer_fn(function()
    M._flush_phase3(ctx, session)
  end, ctx.cfg.phase3_throttle_ms)
end

--- Starts phase 3: cancels phase 2 and begins fast drain.
---@param ctx brook.SearchContext
---@param session brook.ExecSession
function M._start_phase3(ctx, session)
  M._cancel_phase2_scheduling()
  session.current_phase = phases.phase_3
  M._flush_phase3(ctx, session)
end

--- Cancels phase 3 scheduling.
function M._cancel_phase3_scheduling()
  if phase3_timer then
    phase3_timer:stop()
    phase3_timer = nil
  end
end

--------------------------------------------------------------------------------
--- Consumer: UI Utils ---------------------------------------------------------
--------------------------------------------------------------------------------

--- Performs Neovim-side side effects:
---   * setqflist(...) updates the quickfix list
---   * optional copen + window resizing for first results
---@param items vim.quickfix.entry[]
---@param ctx brook.SearchContext
---@param session brook.ExecSession
function M._update_quickfix(items, ctx, session)
  -- i. Populate
  --------------
  local current_buffer_size = #items
  if current_buffer_size == 0 then
    return
  end
  vim.fn.setqflist({}, session.qf_operation, { title = 'rg: results', items = items })
  session.qf_operation = qf_operation.append
  local previous_flushed = session.flushed_results
  session.flushed_results = session.flushed_results + current_buffer_size

  -- ii. Open (on new searches)
  ------------------------------
  if session.is_first_batch then
    if ctx.cfg.qf_open then
      if ctx.cfg.qf_auto_resize then
        -- Open directly with the size corresponding to initial content, to
        -- avoid "flickering".
        vim.cmd('copen ' .. current_buffer_size)
      else
        -- Set the final height right away if the user has disabled auto-resizing.
        vim.cmd('copen ' .. ctx.cfg.qf_win_height)
      end
    end
    if ctx.cfg.set_search_register then
      M._set_search_register(ctx.parsed_args.pattern, {
        word = ctx.parsed_args.word,
        fixed = ctx.parsed_args.fixed,
        case = ctx.parsed_args.case,
      })
    end
    session.is_first_batch = false
  end

  -- iii. Resize
  --------------
  -- Respect user config if auto-resizing was disabled.
  if not ctx.cfg.qf_auto_resize then
    return
  end

  -- Avoid resizing after the final height was reached, in case the user has
  -- resized manually since.
  if session.did_resize then
    return
  end

  if previous_flushed < ctx.cfg.qf_win_height then
    local qf_winid = vim.fn.getqflist({ winid = 0 }).winid
    if qf_winid ~= 0 then
      vim.api.nvim_win_set_height(qf_winid, math.min(session.flushed_results, ctx.cfg.qf_win_height))
      if session.flushed_results >= ctx.cfg.qf_win_height then
        session.did_resize = true
      end
    end
  end
end

--- Sets Vim's search register to the given ripgrep pattern.
---
--- Translates the ripgrep pattern to Vim regex syntax, sets the search register,
--- adds the pattern to search history, and enables hlsearch.
---
---
--- Notifies the user of any pattern translation issues.
---
---@param rg_pattern string|nil The ripgrep search pattern
---@param pattern_opts brook.PatternOpts Options affecting pattern translation
function M._set_search_register(rg_pattern, pattern_opts)
  if not rg_pattern then
    return
  end

  local result = pattern.rg_to_vim(rg_pattern, pattern_opts)

  if result.warning then
    vim.notify('rg: pattern translation: ' .. result.warning, vim.log.levels.WARN)
  end

  if not result.pattern or result.pattern == '' then
    return
  end

  vim.fn.setreg('/', result.pattern)
  vim.fn.histadd('/', result.pattern)
  vim.opt.hlsearch = true
end

--- Shows the final notification once all results have been flushed.
---@param ctx brook.SearchContext
---@param session brook.ExecSession
function M._notify_completion(ctx, session)
  if not session.exit_code then
    return
  end

  if session.exit_code == 0 then
    vim.notify(string.format('rg: %d matches', session.total_results), vim.log.levels.INFO)
    return
  end

  if session.exit_code == 1 then
    vim.notify('rg: no matches', vim.log.levels.WARN)
    return
  end

  if session.stopped_at_limit then
    local msg = 'rg: stopped at limit (' .. ctx.cfg.max_results .. ')'
    if ctx.cfg.max_results < types.validations.max_results.max then
      msg = msg .. ' (configure in setup)'
    end
    if #session.stderr_lines > 0 then
      table.insert(session.stderr_lines, msg)
      msg = table.concat(session.stderr_lines, '\n')
    end
    vim.notify(msg, vim.log.levels.WARN)
    return
  end

  if session.stopped_by_user then
    local msg = 'rg: stopped manually'
    if #session.stderr_lines > 0 then
      table.insert(session.stderr_lines, msg)
      msg = table.concat(session.stderr_lines, '\n')
    end
    vim.notify(msg, vim.log.levels.WARN)
    return
  end

  table.insert(session.stderr_lines, 'rg: exited with code ' .. session.exit_code)
  vim.notify(table.concat(session.stderr_lines, '\n'), vim.log.levels.ERROR)
end

return M
