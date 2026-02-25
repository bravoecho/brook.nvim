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
---   * orchestrates quickfix updates in different stages
---     1. first paint
---     2. steady streaming (ripgrep still running)
---     3. turbo-drain (ripgrep has finished)
---
--- Other key features:
---
---   * capped results (configurable) to prevent memory bloat
---     and editor slowdown
---
---   * bypasss shell for compatibility and security
---
--- See the `state` enum and individual flush functions for implementation
--- details.
---
---@module 'brook.rg.exec'

local pattern = require('brook.pattern')
local fifo = require('brook.lib.fifo')
local args_types = require('brook.args.types')

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
local flush_timer = nil

--- Used to guard the schedule-chaining use case (flush_throttle_ms == 0)
local flush_scheduled = false

--- Store the last context to support "repeat last search"
---@type brook.SearchContext|nil
local last_search_context = nil

---@return brook.SearchContext|nil
function M.last_search_context()
  return last_search_context
end

--------------------------------------------------------------------------------
--- Enums ----------------------------------------------------------------------
--------------------------------------------------------------------------------

--- Three-stage consumer strategy to avoid redraw starvation.
---
---@enum brook.ExecState
local state = {
  --- First paint: flush just enough to fill the visible quickfix window.
  --- Runs synchronously when invoked by the producer, then returns to let
  --- the main loop redraw. Never self-schedules.
  first_paint = 'first-paint',

  --- Streaming: flush queued items in bounded batches while ripgrep runs.
  --- Each batch schedules at most one successor, yielding to the main loop
  --- between updates.
  streaming = 'streaming',

  --- Post-exit drain: ripgrep has finished but items remain queued. Uses
  --- shorter intervals and larger batches than the 'streaming', to drain quickly
  --- while still yielding for redraws.
  draining = 'draining',

  --- Done means that not only has the ripgrep command exited, but the queue has
  --- also been drained and the rendering of results completed.
  done = 'done',
}

---@enum brook.QuickfixOperation
local qf_operation = {
  create = ' ',
  append = 'a',
}

--------------------------------------------------------------------------------
--- Typedefs -------------------------------------------------------------------
--------------------------------------------------------------------------------

--- Context object for ripgrep execution (parameters for _exec).
---
---@class brook.SearchContext
---@field args string[] Shell-unquoted command tokens to be passed to `rg`
---@field parsed_args brook.args.ParsedArgs Subset of command arguments needed to integrate the command correctly
---@field cfg brook.rg.ExecConfig Control how search is performed and results displayed

--------------------------------------------------------------------------------

---@class brook.ExecSession State of a search command execution
---@field is_first_batch boolean
---@field max_batch_size number Batch size for streaming or draining
---@field flush_throttle_ms number Delay between flushes for streaming or draining
---@field qf_operation brook.QuickfixOperation First time create a new list, then switch to append
---@field total_results number Number of raw lines enqueued from ripgrep (producer-side)
---@field flushed_results number Number of entries actually pushed into quickfix (consumer-side, UI)
---@field stopped_at_limit boolean
---@field stopped_by_user boolean
---@field did_resize boolean Whether the quickfix window has rearched its target height
---@field current_state brook.ExecState
---@field queue brook.Fifo FIFO queue of raw result lines, decouples producer (rg's stdout) from consumer (quickfix)
---@field parse_line fun(line: string): vim.quickfix.entry|nil Parser for the current output format
---@field bufnr_cache table<string, number> filename/bufnr cache, avoids repeated O(n) buffer list scans in setqflist()
---@field stdout_buffer string Last segment of the previous stdout batch. See :h channel-lines
---@field stderr_lines string[]
---@field exit_code number|nil
---@field bench brook.BenchData|nil Benchmarking data (present when benchmarking is enabled)

--- Benchmarking data collected during execution.
---
---@class brook.BenchData
---@field raw string Search command
---@field t_start number hrtime at jobstart (nanoseconds)
---@field t_rg_exit number|nil hrtime at on_exit callback
---@field t_done number|nil hrtime at final flush completion
---@field setqflist_calls number Number of vim.fn.setqflist() invocations
---@field setqflist_ns number Cumulative nanoseconds spent inside setqflist()
---@field stdout_callbacks number Number of on_stdout invocations
---@field stdout_lines number Total lines processed across all callbacks
---@field stdout_max_batch number Largest single data array after buffer stitching
---@field first_paint_items number Items flushed during the first paint
---@field streamed_items number Items flushed during streaming
---@field drained_items number Items flushed during draining

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
  -- Store context for repeat
  ---------------------------
  last_search_context = ctx

  -- Cleanup previous search
  --------------------------
  M._cancel_flush_scheduling()

  if active_rg_job_id then
    vim.fn.jobstop(active_rg_job_id)
    active_rg_job_id = nil
  end

  -- Initialise session
  ---------------------
  local parse_line = ctx.cfg.output_format == args_types.output_format.unique_lines
      and M._parse_line_number
      or M._parse_vimgrep

  ---@type brook.ExecSession
  local session = {
    is_first_batch = true,
    max_batch_size = ctx.cfg.max_batch_size,
    flush_throttle_ms = ctx.cfg.flush_throttle_ms,
    qf_operation = qf_operation.create,
    total_results = 0,
    flushed_results = 0,
    stopped_at_limit = false,
    stopped_by_user = false,
    did_resize = false,
    -- Skip first paint when qf_open is false: there is no visible window
    -- to fill above the fold, so go straight into streaming.
    current_state = ctx.cfg.qf_open and state.first_paint or state.streaming,
    queue = fifo.new(),
    bufnr_cache = {},
    stdout_buffer = '',
    stderr_lines = {},
    exit_code = nil,
    parse_line = parse_line,
    bench = {
      raw = ctx.parsed_args.raw,
      t_start = vim.uv.hrtime(),
      t_rg_exit = nil,
      t_done = nil,
      setqflist_calls = 0,
      setqflist_ns = 0,
      stdout_callbacks = 0,
      stdout_lines = 0,
      stdout_max_batch = 0,
      first_paint_items = 0,
      streamed_items = 0,
      drained_items = 0,
    },
  }

  -- Run ripgrep
  --------------
  active_rg_job_id = vim.fn.jobstart(M._build_rg_cmd(ctx), {
    -- Close stdin immediately: ripgrep waits on stdin indefinitely when
    -- invoked programmatically.
    stdin = 'null',

    on_stdout = vim.schedule_wrap(function(_, data, _)
      M._on_stdout(data, ctx, session)
    end),

    -- Buffer stderr to receive all error output in a single callback.
    stderr_buffered = true,

    on_stderr = function(_, data, _)
      M._on_stderr(data, session)
    end,

    on_exit = vim.schedule_wrap(function(_, exit_code, _)
      M._on_exit(exit_code, ctx, session)
    end),
  })

  if active_rg_job_id <= 0 then
    vim.notify('rg: failed to start: is ripgrep installed?', vim.log.levels.ERROR)
    active_rg_job_id = nil
    return nil
  end

  -- Set up cancellation
  ----------------------
  return M._user_cancel_function(active_rg_job_id, session)
end

-- Use a definite field separator in the results, to make parsing deterministic.
local ASCII_UNIT_SEPARATOR = '\31'

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
    '--field-match-separator', ASCII_UNIT_SEPARATOR
  }

  -- When output_format is 'unique-lines', use --line-number instead of --vimgrep.
  -- This omits the column number, causing ripgrep to emit each line only once
  -- regardless of how many matches it contains.
  if ctx.cfg.output_format == args_types.output_format.unique_lines then
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

  if ctx.parsed_args.case == args_types.search_case.sensitive then
    table.insert(cmd, '--case-sensitive')
  elseif ctx.parsed_args.case == args_types.search_case.insensitive then
    table.insert(cmd, '--ignore-case')
  end

  for _, arg in ipairs(ctx.args) do
    table.insert(cmd, arg)
  end

  return cmd
end

--- Parses a vimgrep-format result line into a quickfix entry.
---
--- Format: "file:line:col:text" (default, --vimgrep)
--- Example: "some/path/to/file.txt:137:42:the red fox jumped"
---
---@param line string A ripgrep result line in vimgrep format
---@return vim.quickfix.entry|nil entry Quickfix entry, or nil if parsing fails
function M._parse_vimgrep(line)
  -- plain mode is faster because it bypasses the regex engine
  local parts = vim.split(line, ASCII_UNIT_SEPARATOR, { plain = true })

  if #parts < 4 then
    return nil
  end

  -- Recombine text parts in the rare event that it contains the separator.
  local text = table.concat(parts, ASCII_UNIT_SEPARATOR, 4)

  return {
    filename = parts[1],
    lnum = tonumber(parts[2]),
    col = tonumber(parts[3]),
    text = text,
  }
end

--- Parses a line-number-format result line into a quickfix entry.
---
--- Format: "file:line:text" (unique-lines mode, --line-number)
--- Example: "some/path/to/file.txt:137:the red fox jumped"
---
---@param line string A ripgrep result line in vimgrep format
---@return vim.quickfix.entry|nil entry Quickfix entry, or nil if parsing fails
function M._parse_line_number(line)
  -- plain mode is faster because it bypasses the regex engine
  local parts = vim.split(line, ASCII_UNIT_SEPARATOR, { plain = true })

  if #parts < 3 then
    return nil
  end

  -- Recombine text parts in the rare event that it contains the separator.
  local text = table.concat(parts, ASCII_UNIT_SEPARATOR, 3)

  return {
    filename = parts[1],
    lnum = tonumber(parts[2]),
    col = 1, -- Default to column 1 when no column info available
    text = text,
  }
end

---@param job_id number|nil ID of the job to cancel
---@param session brook.ExecSession Session to invalidate
---@return function
function M._user_cancel_function(job_id, session)
  return function()
    M._cancel_flush_scheduling()

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
---   * stitches partial segments from the channel
---   * enqueues raw result lines (no parsing, no bufadd)
---   * triggers the consumer
---
--- Parsing and bufnr resolution are deferred to the consumer (flush
--- functions), so that the main loop is not blocked by per-line work.
--- This keeps streaming responsive even when ripgrep produces results
--- faster than Neovim can render them.
---
---@param data string[] stdout segments yielded by the on_stdout callback. See :h channel-lines
---@param ctx brook.SearchContext
---@param session brook.ExecSession
function M._on_stdout(data, ctx, session)
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

  -- BENCH: track on_stdout callback volume
  if session.bench then
    local n = #data
    session.bench.stdout_callbacks = session.bench.stdout_callbacks + 1
    session.bench.stdout_lines = session.bench.stdout_lines + n
    if n > session.bench.stdout_max_batch then
      session.bench.stdout_max_batch = n
    end
  end

  -- Enqueue raw lines. Parsing is deferred to the consumer.
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

    session.queue.push(line)
    session.total_results = session.total_results + 1
  end

  M._request_flush(ctx, session)
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
  -- Capture exit state for notify_completion (called at end of the draining stage).
  session.exit_code = exit_code

  -- BENCH: record ripgrep completion time
  if session.bench then
    session.bench.t_rg_exit = vim.uv.hrtime()
  end

  if session.current_state == state.first_paint then
    -- Handle edge case where ripgrep exited before the quickfix window was
    -- fully populated. Flush synchronously to ensure results are visible.
    M._flush_first_paint(ctx, session)
  end

  M._start_draining(ctx, session)
end

--------------------------------------------------------------------------------
--- Consumer: Dispatch ---------------------------------------------------------
--------------------------------------------------------------------------------

--- request_flush will either
---
---   - flush synchronously (first paint)...
---   - ...or schedule a flush (streaming and draining)
---
--- Since it may run synchronously (depending on the pipeline stage) it must
--- be called from a scheduled context (Neovim's main loop).
---
---@param ctx brook.SearchContext
---@param session brook.ExecSession
function M._request_flush(ctx, session)
  if session.current_state == state.first_paint then
    M._flush_first_paint(ctx, session)
  elseif session.current_state == state.streaming
      or session.current_state == state.draining then
    M._schedule_flush(ctx, session)
  end
end

--------------------------------------------------------------------------------
--- Consumer: First Paint ------------------------------------------------------
--------------------------------------------------------------------------------

--- First-paint consumer: perform the first meaningful "paint".
---
---   * Flushes *at most* the number of items needed to reach the visible
---     quickfix window height (above the fold).
---
---   * Never self-schedules (no timers/recursion/defer_fn). This function must
---     run synchronously and return control to the main loop so Neovim can
---     become idle and redraw.
---
---   * Owns the state transition: when the visible region is filled, it moves
---     the consumer into streaming mode.
---
--- See also the `state` enum.
---
---@param ctx brook.SearchContext
---@param session brook.ExecSession
function M._flush_first_paint(ctx, session)
  if session.current_state ~= state.first_paint or session.queue.is_empty() then
    return
  end

  local remaining_visible_slots = M._remaining_visible_slots(ctx, session)
  if remaining_visible_slots == 0 then
    M._start_streaming(ctx, session)
    return
  end

  -- Pull only the minimum necessary to fill the quickfix window above the
  -- fold.
  M._update_quickfix(M._parse_batch(remaining_visible_slots, session), ctx, session)

  -- If first paint has finished, kick off streaming anyway, no need to wait for
  -- the next `on_stdout` run.
  if M._remaining_visible_slots(ctx, session) == 0 then
    M._start_streaming(ctx, session)
  end
end

--- Counts how many results are still missing before reaching the target
--- quickfix window height.
function M._remaining_visible_slots(ctx, session)
  return math.max(0, ctx.cfg.qf_win_height - session.flushed_results)
end

--------------------------------------------------------------------------------
--- Consumer: Streaming --------------------------------------------------------
--------------------------------------------------------------------------------

--- Streaming consumer: flush after first paint. It runs while ripgrep is still
--- returning results (state == streaming), and after it's exited
--- (state == draining). The difference is only in the values for batch size
--- and throttle.
---
---   * Pulls batches of results from the queue and renders them.
---
---   * Is triggered at the end of the first paint
---
---   * Reschedules itself if there are pending entries in the queue.
---
--- See also the `state` enum.
---
---@param ctx brook.SearchContext
---@param session brook.ExecSession
function M._flush_streaming(ctx, session)
  if session.current_state == state.done then
    return
  end

  if session.queue.is_empty() and session.current_state == state.draining then
    M._notify_completion(ctx, session)
    return
  elseif session.queue.is_empty() then
    return
  end

  local batch_size = M._with_jitter(session.max_batch_size, ctx.cfg.batch_jitter)
  M._update_quickfix(M._parse_batch(batch_size, session), ctx, session)

  -- Wait until quickfix is updated before unlocking next flush.
  flush_scheduled = false

  if session.queue.is_empty() and session.current_state == state.draining then
    M._notify_completion(ctx, session)
    return
  end

  if not session.queue.is_empty() then
    M._schedule_flush(ctx, session)
  end
end

--- Schedules the next flush for the streaming and draining modes.
---
--- Guards against multiple concurrent schedules: in timer mode, the timer
--- itself is the guard; in schedule mode, flush_scheduled prevents duplicates.
---
--- Called both by the producer (to trigger streaming work) and by
--- _flush_streaming itself (to schedule the next batch).
---
---@param ctx brook.SearchContext
---@param session brook.ExecSession
function M._schedule_flush(ctx, session)
  if session.flush_throttle_ms > 0 then
    -- In timer/throttle mode the timer itself is the guard.
    -- ensure at most one timer is present at any given time
    if flush_timer then
      return
    end

    flush_timer = vim.defer_fn(function()
      -- timer has triggered, can be removed
      flush_timer = nil
      M._flush_streaming(ctx, session)
    end, session.flush_throttle_ms)
  else
    -- In schedule mode: a separate guard is needed to prevent multiple schedules.
    if flush_scheduled then
      return
    end
    flush_scheduled = true
    vim.schedule(function()
      M._flush_streaming(ctx, session)
    end)
  end
end

---@param ctx brook.SearchContext
---@param session brook.ExecSession
function M._start_streaming(ctx, session)
  session.current_state = state.streaming
  M._schedule_flush(ctx, session)
end

--- Cancels flush scheduling, both in timer/throttling mode and in schedule mode.
function M._cancel_flush_scheduling()
  if flush_timer then
    flush_timer:stop()
    flush_timer = nil
  end
  flush_scheduled = false
end

--------------------------------------------------------------------------------
--- Consumer: Post-exit Drain --------------------------------------------------
--------------------------------------------------------------------------------

--- Starts draining: cancels streaming and begins fast drain.
---@param ctx brook.SearchContext
---@param session brook.ExecSession
function M._start_draining(ctx, session)
  M._cancel_flush_scheduling()
  session.current_state = state.draining
  session.max_batch_size = ctx.cfg.drain_phase_max_batch_size
  session.flush_throttle_ms = ctx.cfg.drain_phase_flush_throttle_ms

  M._flush_streaming(ctx, session)
end

--------------------------------------------------------------------------------
--- Consumer: Parsing ----------------------------------------------------------
--------------------------------------------------------------------------------

---@param base_size integer Base batch size
---@param amplitude number Jitter amplitude (e.g. 0.1 for +/- 10%)
---@return integer jittered_size Batch size with random variation applied
function M._with_jitter(base_size, amplitude)
  local multiplier = (1 - amplitude) + math.random() * (2 * amplitude)
  return math.floor(base_size * multiplier + 0.5)
end

--- Pulls raw lines from the queue, parses them into quickfix entries, and
--- resolves filenames to buffer numbers.
---
--- This is the consumer-side counterpart to the lightweight `_on_stdout`
--- producer. By doing parsing and `bufadd()` here rather than in the
--- producer, the expensive per-line work runs in bounded batches with idle
--- gaps between them, preventing main-loop starvation.
---
---@param n number Maximum number of raw lines to pull
---@param session brook.ExecSession
---@return vim.quickfix.entry[] entries Parsed quickfix entries (may be fewer than n if lines fail to parse)
function M._parse_batch(n, session)
  local raw_lines = session.queue.pull(n)
  local entries = {}
  for _, line in ipairs(raw_lines) do
    local entry = session.parse_line(line)
    if entry then
      -- Resolve filename to bufnr before enqueueing. This bypasses
      -- setqflist()'s internal O(n*m) filename search, by passing a bufnr,
      -- which Neovim can resolve in O(1).
      entry.bufnr = M._resolve_bufnr(entry.filename, session.bufnr_cache)
      entry.filename = nil
      entries[#entries+1] = entry
    end
  end
  return entries
end

--- Resolves a filename to a buffer number, caching the result.
---
--- `vim.fn.bufadd()` creates the buffer if absent, or returns the existing
--- bufnr. We call it once per unique filename rather than letting
--- `setqflist()` call `buflist_findname_stat()` once per match — turning
--- O(total_matches * buffer_count) into O(unique_files * buffer_count).
---
---@param filename string
---@param cache table<string, number>
---@return number bufnr
function M._resolve_bufnr(filename, cache)
  local bufnr = cache[filename]
  if not bufnr then
    bufnr = vim.fn.bufadd(filename)
    cache[filename] = bufnr
  end
  return bufnr
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

  -- BENCH: time the setqflist call
  local t0 = session.bench and vim.uv.hrtime() or nil
  vim.fn.setqflist({}, session.qf_operation, {
    title = 'rg ' .. ctx.parsed_args.raw,
    items = items,
  })
  if session.bench and t0 then
    session.bench.setqflist_ns = session.bench.setqflist_ns + (vim.uv.hrtime() - t0)
    session.bench.setqflist_calls = session.bench.setqflist_calls + 1

    if session.current_state == state.first_paint then
      session.bench.first_paint_items = session.bench.first_paint_items + current_buffer_size
    elseif session.current_state == state.streaming then
      session.bench.streamed_items = session.bench.streamed_items + current_buffer_size
    else
      session.bench.drained_items = session.bench.drained_items + current_buffer_size
    end
  end
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
      M._set_search_register(ctx.parsed_args.patterns, {
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
---@param rg_patterns string[]|nil The ripgrep search pattern
---@param pattern_opts brook.pattern.TranslateOpts Options affecting pattern translation
function M._set_search_register(rg_patterns, pattern_opts)
  if not rg_patterns then
    return
  end

  local result = pattern.rg_to_vim(rg_patterns, pattern_opts)

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
  -- TODO: review and reconsider defensive checks for conditions that cannot happen
  if not session.exit_code then
    return
  end

  session.current_state = state.done

  -- BENCH: emit timing summary
  if ctx.cfg._benchmark then
    M._emit_bench_summary(session)
  end

  if session.exit_code == 1 then
    vim.notify('rg: no matches', vim.log.levels.WARN)
    return
  end

  if session.stopped_at_limit then
    local msg = 'rg: stopped at limit (' .. ctx.cfg.max_results .. ')'
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

  if session.exit_code ~= 0 then
    table.insert(session.stderr_lines, 'rg: exited with code ' .. session.exit_code)
    vim.notify(table.concat(session.stderr_lines, '\n'), vim.log.levels.ERROR)
  end
end

--- Formats and prints benchmarking data to :messages.
---@param session brook.ExecSession
function M._emit_bench_summary(session)
  local b = session.bench
  if not b then
    return
  end

  b.t_done = vim.uv.hrtime()

  local function ms(ns)
    return string.format('%.1f ms', ns / 1e6)
  end

  local total_ns = b.t_done - b.t_start
  local rg_ns = b.t_rg_exit and (b.t_rg_exit - b.t_start) or 0
  local drain_ns = b.t_rg_exit and (b.t_done - b.t_rg_exit) or 0

  local lines = {
    '',
    '── brook.nvim bench ──────────────────────────────────',
    '  search command:             ' .. ':Rg ' .. b.raw,
    '  total wall time:            ' .. ms(total_ns),
    '  ripgrep (start --> exit):   ' .. ms(rg_ns),
    '  drain (exit --> done):      ' .. ms(drain_ns),
    '  setqflist() cumulative:     ' .. ms(b.setqflist_ns)
    .. '  (' .. b.setqflist_calls .. ' calls)',
    '  on_stdout:                  '
    .. b.stdout_callbacks .. ' callbacks'
    .. '  ' .. b.stdout_lines .. ' lines'
    .. '  max_batch=' .. b.stdout_max_batch,
    '  items by stage:             '
    .. 'first-paint=' .. b.first_paint_items
    .. '  streamed=' .. b.streamed_items
    .. '  drained=' .. b.drained_items
    .. '  total=' .. session.flushed_results,
    '  buffers:                    ' .. #vim.fn.getbufinfo(),
    '──────────────────────────────────────────────────────',
  }

  -- Print to :messages so it doesn't interfere with vim.notify
  for _, line in ipairs(lines) do
    print(line)
  end
end

return M
