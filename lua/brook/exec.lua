--- Asynchronous ripgrep execution with quickfix integration.
---
--- This module provides functions to run ripgrep searches asynchronously,
--- incrementally adding results into Neovim's quickfix list using cooperative
--- scheduling. It bypasses the shell for security and portability.
---
--- Implementation Notes and Workflow
--- ---------------------------------
---
--- Constraints:
---
--- * Ripgrep often produces matches faster than Neovim can populate the
---   quickfix list. Unlike Unix pipelines, Neovim job channels do not provide
---   backpressure for stdout; instead, the stdout handler will continue to be
---   triggered at the pace of the external command.
---
--- * The quickfix list is not designed for streaming, or for a large number
---   of results. Large lists use a lot of memory and degrade overall editor
---   performance even after the job exits. This module therefore enforces an
---   upper bound to the maximum number of results; beyond that limit, the
---   ripgrep process is stopped.
---
--- * Neovim can only redraw when the main loop becomes idle; if work is already
---   scheduled in response to stdout events, the Neovim event loop will
---   prioritize that work over re-rendering the corresponding buffer with the
---   new information. In this case the UI cannot reflect the results processed
---   so far. This is a scenario known as "redraw starvation".
---
--- * The mitigation is not to force redraws, but to ensure that
---   - consumer work is bounded per tick of the Neovim event loop, and yields
---     back to the main loop frequently
---   - at most one flush-related task is pending at any given time
---
--- Workflow:
---
--- To preserve perceived responsiveness without forcing redraws, results are
--- handled via a producer/consumer pipeline and three consumer phases.
---
--- Producer and consumer keep track of the entries separately:
---
---   * Job orchestration is based on the total number of results received and
---     parsed
---
---   * UI-related operations (phase completion, resizing) are based on flushed
---     items, rather than parsed items
---
--- The pipeline consists of five actors.
---
---   1. Producer (`on_stdout`):
---
---      - parses stdout lines emitted by ripgrep
---      - enqueues quickfix entries into a FIFO queue
---      - triggers the appropriate consumer based on the current phase
---
---      The producer does not encode UI logic (resizing, redraw timing,
---      batching strategy). Its only responsibility is to ingest results and
---      notify the consumer that work is available.
---
---   2. FIFO queue:
---
---      - decouples producer cadence (ripgrep output rate) from consumer cadence
---        (Neovim UI update rate)
---
---      - allows the consumer to flush entries at its own pace
---
---      Usage by phase:
---
---        * phase 1 uses `pull(n)` to flush just enough entries to fill the
---          visible quickfix window, providing immediate feedback
---
---        * phase 2 uses `pull(max_batch_size)` repeatedly to flush bounded
---          batches, yielding to the main loop between batches
---
---        * phase 3 uses `pull(max_batch_size * 10)` to drain quickly after
---          ripgrep exits
---
---   3. Phase-1 consumer (`flush_phase1`):
---
---      - performs the first meaningful “paint”
---      - flushes at most the number of entries needed to fill the visible
---        quickfix window (above the fold)
---      - never self-schedules (no recursion, timers, or deferred callbacks)
---      - always runs synchronously on the main loop
---
---      Because phase 1 runs synchronously and then returns control to the
---      main loop, Neovim naturally reaches an idle point and redraws the UI.
---      This effectively simulates backpressure for the first visible results
---      without forcing redraws.
---
---      Phase 1 owns the phase transition: once the visible region is filled,
---      it switches the consumer into phase 2 and triggers it.
---
---      NOTE:
---      Results are parsed and enqueued on the main loop by design. This keeps
---      phase-1 rendering synchronous and predictable. The overhead is
---      negligible relative to quickfix and UI updates, while offloading
---      parsing would require more complex orchestration and the performance
---      gains would be undetectable even by a keen human eye.
---
---   4. Phase-2 consumer (`flush_phase2`):
---
---      - flushes remaining queued entries in bounded batches
---      - schedules at most one flush-related task at any given time
---      - flushes exactly one batch per scheduled callback invocation
---      - yields back to Neovim’s main loop between batches
---
---      Phase 2 is throughput-oriented: it self-schedules additional work
---      using `vim.schedule`, ensuring that the main loop regains control
---      between batches so redraws can occur.
---
---      However, it optionally introduces a very small delay between batches,
---      to prevent schedule chaining and give the UI time to redraw in
---      extra-fast output scenarios.
---
---      Only phases 2 and 3 are allowed to self-schedule follow-up flushing.
---
---   5. Phase-3 consumer (`flush_phase3`):
---
---      - triggered by `on_exit` when ripgrep finishes
---      - drains remaining queued entries quickly using larger batches
---        (10x max_batch_size) and a minimal interval (1ms)
---      - still yields to the event loop between batches to allow UI redraws
---      - notifies the user of completion once the queue is fully drained
---
---      Phase 3 exists because phase 2's throttling, while useful during active
---      search to preserve responsiveness, would feel sluggish once the search
---      is complete. Users expect the final results to appear promptly.
---
---@module 'brook.exec'

---@type number|nil Vim job id returned by vim.fn.jobstart()
local active_rg_job_id = nil

--- Also used to guard the throttling use case (flush_throttle_ms > 0).
---@type uv.uv_timer_t|nil
local phase2_timer = nil

--- Used to guard the schedule chaining use case (flush_throttle_ms == 0)
local phase2_scheduled = false

--- Timer for phase 3 (post-exit drain).
---@type uv.uv_timer_t|nil
local phase3_timer = nil

--- Cancels flush scheduling, both in timer/throttling mode and in schedule mode.
local cancel_phase2_scheduling = function()
  if phase2_timer then
    phase2_timer:stop()
    phase2_timer = nil
  end
  phase2_scheduled = false
end

--- Cancels phase 3 scheduling.
local cancel_phase3_scheduling = function()
  if phase3_timer then
    phase3_timer:stop()
    phase3_timer = nil
  end
end

local pattern = require('brook.pattern')
local fifo = require('brook.lib.fifo')
local types = require('brook.types')

local M = {}

--- Context object for ripgrep execution (parameters for _exec).
---
---@class brook.SearchContext
---@field args string[] Shell-unquoted command tokens to be passed to `rg`
---@field parsed_args brook.ParsedArgs Subset of command arguments needed to integrate the command correctly
---@field cfg brook.ExecConfig Control how search is performed and results displayed

--- Phases
---
--- Three-phase consumer strategy to avoid redraw starvation without forcing
--- redraws:
---
---   * Phase 1 (first paint): flush just enough items to fill the target
---     quickfix window height. Phase 1 never self-schedules (no timers,
---     recursion or defer_fn): it runs only when invoked by the producer, and
---     then returns, allowing the main loop to become idle and redraw. See
---     also flush_phase1.
---
---   * Phase 2 (ripgrep running): flushes remaining queued items in bounded
---     batches (max_batch_size) using cooperative scheduling.
---     Each batch schedules at most one subsequent batch, ensuring the main
---     loop gets chances to redraw between updates.
---
---   * Phase 3 (post-exit drain): when ripgrep finishes, any entries still
---     in the queue need to be flushed. Phase 2's throttling, useful to
---     preserve responsiveness, would feel sluggish once the search is
---     complete. So phase 3 uses a much shorter interval (1ms) and larger
---     batches (10x max_batch_size), to drain quickly while still yielding
---     to the event loop for UI redraws.
---
--- Only phases 2 and 3 may schedule flushing.
---
---@enum brook.ExecPhase
local phases = {
  phase_1 = 'phase-1',
  phase_2 = 'phase-2',
  phase_3 = 'phase-3',
  done = 'done',
}

---@enum brook.QuickfixOperation
local qf_operation = {
  replace = 'r',
  append = 'a',
}

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

---@type brook.ExecSession
local current_session = nil

---@param job_id number|nil ID of the job to cancel
---@param session brook.ExecSession Session to invalidate
---@return function
function M._user_cancel_function(job_id, session)
  return function()
    cancel_phase2_scheduling()
    cancel_phase3_scheduling()

    if job_id and job_id == active_rg_job_id then
      session.stopped_by_user = true
      vim.fn.jobstop(job_id)
      active_rg_job_id = nil
    end
  end
end

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
  -- 0. Cleanup
  -------------
  cancel_phase2_scheduling()
  cancel_phase3_scheduling()

  if active_rg_job_id then
    vim.fn.jobstop(active_rg_job_id)
    active_rg_job_id = nil
  end

  -- 1. Init
  ----------

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

  -- Select the appropriate parser based on output format
  local parse_line = ctx.cfg.output_format == types.output_format.unique_lines
      and M._parse_line_number
      or M._parse_vimgrep

  -- Echo the original command back to the user.
  vim.notify('rg ' .. ctx.parsed_args.raw, vim.log.levels.INFO)

  -- 2. Build command array
  -------------------------

  local cmd = M._build_rg_cmd(ctx)

  -- 3. Result stream handling
  ----------------------------

  local on_stdout = vim.schedule_wrap(function(_, data, _)
    M._on_stdout(data, ctx, current_session, parse_line)
  end)

  -- 4. Error message handling
  ----------------------------

  local on_stderr = function(_, data, _)
    M._on_stderr(data, current_session)
  end

  -- 5. Command exit handling
  ---------------------------

  local on_exit = vim.schedule_wrap(function(_, exit_code, _)
    M._on_exit(exit_code, ctx, current_session)
  end)

  -- 6. Run command
  -----------------
  active_rg_job_id = vim.fn.jobstart(cmd, {
    -- NOTE: Close stdin immediately. Unlike tools like ag, ripgrep waits on
    -- stdin indefinitely, when invoked programmatically. Without this, the job
    -- never exits (it remains alive until Neovim itself terminates).
    stdin = 'null',
    on_stdout = on_stdout,
    -- NOTE: Buffer stderr so we receive all error output in a single callback.
    -- This avoids partial-line issues without the complexity of manual
    -- buffering, since stderr is typically small (error messages or lists of
    -- unreadable files).
    stderr_buffered = true,
    on_stderr = on_stderr,
    on_exit = on_exit,
  })

  if active_rg_job_id <= 0 then
    vim.notify('rg: failed to start: is ripgrep installed?', vim.log.levels.ERROR)
    active_rg_job_id = nil
    return nil
  end

  -- 7. Set up cancellation
  return M._user_cancel_function(active_rg_job_id, current_session)
end

---@param ctx brook.SearchContext Search context with all execution parameters
---@return string[] cmd Command table for jobstart()
function M._build_rg_cmd(ctx)
  -- NOTE: Limit previews to 300 characters, to avoid memory explosion on
  -- abnormally long lines. Matching will still include the whole line, only
  -- the preview is truncated.
  local max_preview_chars = '300'

  local cmd = {
    'rg',
    '--no-multiline',
    '--max-columns', max_preview_chars,
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

--- Producer: stdout handler
---
--- This callback should stay "dumb": parse complete lines, enqueue entries,
--- and then trigger the appropriate consumer. It intentionally does not
--- encode UI logic (resizing, redraws, etc.).
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

--- Performs Neovim-side side effects:
---   * setqflist(...) updates the quickfix list
---   * optional copen + window resizing for first results
---@param items vim.quickfix.entry[] TODO: assign correct type
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

---@param ctx brook.SearchContext
---@param session brook.ExecSession
function M._request_flush(ctx, session)
  --- request_flush will either
  ---
  ---   - flush synchronously (phase 1)...
  ---   - ...or schedule a flush (phase 2)
  ---
  --- Since it may run synchronously (depending on phase) it must be called from
  --- a scheduled context (Neovim's main loop).
  if session.current_phase == phases.phase_1 then
    M._flush_phase1(ctx, session)
  elseif session.current_phase == phases.phase_2 then
    M._schedule_flush_phase2(ctx, session)
  end
end

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
  -- TODO: check if phase check is needed (it's already guarded at call sites).
  if session.current_phase ~= phases.phase_1 or session.queue.is_empty() then
    return
  end

  local remaining = M._remaining_visible_slots(ctx, session)
  if remaining == 0 then
    M._start_phase2(ctx, session)
    return
  end

  -- Pull only the minimum necessary to fill the quickfix window above the
  -- fold.
  M._update_quickfix(session.queue.pull(remaining), ctx, session)

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

--- Phase-3 consumer: drains the queue quickly after ripgrep has exited.
---
---   * Triggered by `on_exit`.
---
---   * Self-reschedules until the queue is drained.
---
---   * Notifies user of completion.
---
--- See also the `phases` enum.
---@param ctx brook.SearchContext
---@param session brook.ExecSession
function M._flush_phase3(ctx, session)
  -- Batch size for phase 3. Larger than phase 2 because ripgrep has finished
  -- and we want to drain quickly. Each batch still yields to the event loop,
  -- so larger batches just mean fewer round-trips.
  local phase3_batch_size = ctx.cfg.max_batch_size * 10
  local phase3_drain_interval_ms = 1

  M._update_quickfix(session.queue.pull(phase3_batch_size), ctx, session)

  if session.queue.is_empty() then
    session.current_phase = phases.done
    M._notify_completion(ctx, session)
    return
  end

  phase3_timer = vim.defer_fn(function()
    M._flush_phase3(ctx, session)
  end, phase3_drain_interval_ms)
end

--- Starts phase 3: cancels phase 2 and begins fast drain.
---@param ctx brook.SearchContext
---@param session brook.ExecSession
function M._start_phase3(ctx, session)
  cancel_phase2_scheduling()
  session.current_phase = phases.phase_3
  M._flush_phase3(ctx, session)
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
    if ctx.cfg.max_results < types.max_max_results then
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

--- Sets Vim's search register to the given ripgrep pattern.
---
--- Translates the ripgrep pattern to Vim regex syntax, sets the search register,
--- adds the pattern to search history, and enables hlsearch.
---
---@param rg_pattern string|nil The ripgrep search pattern
---@param pattern_opts brook.PatternOpts Options affecting pattern translation
function M._set_search_register(rg_pattern, pattern_opts)
  if not rg_pattern then
    return
  end

  local vim_pattern = pattern.rg_to_vim(rg_pattern, pattern_opts)

  if vim_pattern == '' then
    return
  end

  vim.fn.setreg('/', vim_pattern)
  vim.fn.histadd('/', vim_pattern)
  vim.opt.hlsearch = true
end

return M
