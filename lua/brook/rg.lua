--- Asynchronous ripgrep execution with quickfix integration.
---
--- This module provides functions to run ripgrep searches asynchronously,
--- incrementally adding results into Neovim's quickfix list. It bypasses the
--- shell for security and portability.
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
--- Workflow:
---
--- To preserve perceived responsiveness without forcing redraws, results are
--- handled via a producer/consumer pipeline and two consumer phases.
---
--- Producer and consumer keep track of the entries separately:
---
---   * Job orchestration is based on the total number of results received and
---     parsed
---
---   * UI-related operations (phase completion, resizing) are based on flushed
---     items, rather than parsed items
---
--- The pipeline consists of four actors.
---
---   1. Producer (`on_stdout`): parses stdout lines and enqueues quickfix
---      entries; it also triggers the consumers.
---
---   2. FIFO queue: decouples producer and consumer, allowing them to process
---      entries each according to their own cadence.
---
---   3. Phase-1 consumer (`flush_phase1`):
---
---      - performs the first meaningful "paints", by flushing just enough
---        entries to fill the visible quickfix height
---
---      - phase 1 never uses timers/recursion to self-schedule
---
---      - must run synchronously, and therefore must be invoked from the main
---        loop (scheduled context)
---
---      - the fact that it's synchronous is what allows Neovim to trigger
---        redraws organically, because it simulates backpressure: each run of
---        the scheduled stdout handler runs on the main event loop, so any
---        operation will have to run to completion (including Neovim API calls
---        such as setqflist), giving Neovim time to redraw, even if more stdout
---        callback instances are already queued up in the background
---
---      - NOTE: as a consequence of this design choice, parsing and storing of
---        results happens on the main loop. This is theoretically inefficient,
---        but it allows this simpler model of synchronous rendering, and those
---        operations have negligible impact over quickfix manipulation and UI
---        rendering. Sending parsing and storing into the background, would
---        require even more complex orchestration and additional semaphores,
---        because in that case also phase-1 consumer operations would need to
---        be asynchronous.
---
---   4. Phase-2 consumer (`flush_phase2`):
---
---      - drains remaining entries asynchronously, in batches, and with a
---        debounce
---
---      - prioritizes throughput
---
---      - on extremely fast bursts, redraw starvation can still happen, but at
---        this point the initial results are already rendered, and the rest
---        will become available quickly, in larger batches; in other words,
---        redraw starvation is acceptable for off-screen items (below the fold
---        of the quickfix window)
---
---      - only phase 2 is allowed to schedule deferred flushing
---
---@module 'brook.rg'

---@type integer|nil Vim job id returned by vim.fn.jobstart()
local active_rg_job_id = nil

--- Whether the user_stop() function was called.
local stopped_by_user = false

local pattern = require('brook.pattern')
local tokenise = require('brook.tokenise').tokenise
local shell_unquote_all = require('brook.shell_unquote').shell_unquote_all
local parse_args = require('brook.parse_args').parse_args
local fifo = require('brook.lib.fifo')
local types = require('brook.types')

local M = {}

function M.user_stop()
  if active_rg_job_id then
    stopped_by_user = true
    vim.fn.jobstop(active_rg_job_id)
    active_rg_job_id = nil
  end
end

--- Searches for a literal pattern using ripgrep.
---
--- The text is passed directly to rg as an array element, bypassing the shell
--- entirely. This is safe even for arbitrary visual selections containing
--- special characters, because no shell interpretation occurs.
---
--- No unquoting is performed here: if the user selects the literal text
--- `'hello'` (with quotes), they want to search for exactly that string,
--- quotes included.
---
---@param text string The literal text to search for
---@param cfg? brook.ExecConfig Plugin options
function M.selection(text, cfg)
  M._exec({
    args = { '--', text },
    parsed_args = {
      pattern = text,
      word = false,
      fixed = true,
      case = nil,
      output_format = nil,
      multiline = false,
    },
    cfg = cfg or {},
    title = 'rg -F ' .. text,
  })
end

--- Searches for a single word using ripgrep.
---
--- The word is passed directly to rg as an array element, bypassing the shell
--- entirely.
---
--- No unquoting is performed here: the word comes from Neovim's <cword>, which
--- is already a plain string without any shell quoting.
---
---@param word string The word to search for (typically from <cword>)
---@param cfg? brook.ExecConfig Plugin options
function M.word(word, cfg)
  M._exec({
    args = { '--', word },
    parsed_args = {
      pattern = word,
      word = true,
      fixed = true,
      case = nil,
      output_format = nil,
      multiline = false,
    },
    cfg = cfg or {},
    title = 'rg -w ' .. word,
  })
end

--- Searches with user-defined arguments.
---
--- The raw command string is tokenised using POSIX shell rules, then each token
--- is unquoted before being passed to rg. This simulates what a shell would do,
--- but without actually invoking a shell process.
---
--- Unquoting is necessary here because the user types their command using shell
--- syntax. When they type:
---
---     :Rg 'hello world' src/
---
--- ...they expect the quotes to be *syntax* (grouping words), not *content*.
--- The search pattern should be `hello world`, not `'hello world'`. This is
--- different from rg.selection() and rg.word(), where we have pre-built Lua
--- strings that go directly to rg without any shell syntax involved.
---
--- Examples:
---   `:Rg pattern src/`         -> `rg --vimgrep pattern src/`
---   `:Rg 'hello world' src/`   -> `rg --vimgrep "hello world" src/`
---   `:Rg -w 'foo bar'`         -> `rg --vimgrep -w "foo bar"`
---
---@param cmd_args string The raw command-line arguments
---@param cfg? brook.ExecConfig Plugin options
function M.raw(cmd_args, cfg)
  -- Step 1: Tokenise
  -------------------
  -- Tokenise the command string (split on whitespace, respect quotes)
  local tokens = tokenise(cmd_args)

  if not tokens or #tokens == 0 then
    vim.notify('rg: no arguments provided', vim.log.levels.ERROR)
    return
  end

  -- Step 2: Unquote
  ------------------
  -- Unquote each token (interprets shell quoting rules)
  local rg_args = shell_unquote_all(tokens)
  -- If any token was malformed (unterminated quotes, trailing backslashes...),
  -- we cannot run the `rg` command: notify and bail out.
  if rg_args == nil then
    vim.notify('rg: malformed command: could not unquote', vim.log.levels.ERROR)
    return
  end

  -- Step 3: Parse ripgrep arguments
  ----------------------------------
  -- Minimal parsing, just enough to support Neovim features
  local parsed_args = parse_args(rg_args)

  -- Step 4: Enforce single-line search
  -------------------------------------
  if parsed_args.multiline then
    vim.notify('rg: multiline search not supported', vim.log.levels.ERROR)
    return
  end

  -- Step 5: Run the search
  -------------------------
  M._exec({
    args = rg_args,
    parsed_args = parsed_args,
    cfg = cfg or {},
    title = 'rg ' .. cmd_args,
  })
end

--- Context object for ripgrep execution (parameters for _exec).
---
---@class brook.SearchContext
---@field args string[] Shell-unquoted command tokens to be passed to `rg`
---@field parsed_args brook.ParsedArgs Subset of command arguments needed to integrate the command correctly
---@field cfg brook.ExecConfig Control how search is performed and results displayed
---@field title string Used to provide feedback to the user

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
function M._exec(ctx)
  stopped_by_user = false

  if active_rg_job_id then
    vim.fn.jobstop(active_rg_job_id)
    active_rg_job_id = nil
  end

  -- 0. Setup
  -----------

  local parsed_args = ctx.parsed_args
  local cfg = ctx.cfg
  local title = ctx.title

  local max_results = cfg.max_results
  local qf_win_height = cfg.qf_win_height
  local qf_open = cfg.qf_open
  local qf_auto_resize = cfg.qf_auto_resize
  local flush_threshold = cfg.buffer_size
  local flush_debounce_ms = cfg.debounce

  -- Determine output format: command-line flags override config.
  -- Precedence: parsed_args (command line) > opts (config) > default
  local output_format = parsed_args.output_format
      or cfg.output_format
      or types.output_format.one_line_per_match

  -- Select the appropriate parser based on output format
  local parse_line = output_format == types.output_format.unique_lines
      and M._parse_line_number
      or M._parse_vimgrep

  vim.notify(title, vim.log.levels.INFO)

  -- 1. Build command array
  -------------------------

  -- NOTE: Limit previews to 300 bytes, to avoid memory explosion on abnormally
  -- long lines. Matching will still include the whole, only the preview is
  -- truncated.
  local cmd = { 'rg', '--no-multiline', '--max-columns', '300', '--max-columns-preview', '--color', 'never' }

  -- When output_format is 'unique-lines', use --line-number instead of --vimgrep.
  -- This omits the column number, causing ripgrep to emit each line only once
  -- regardless of how many matches it contains.
  --
  -- Only add the flag if the user hasn't already specified one on the command
  -- line (parsed_args.output_format would be non-nil in that case).

  if parsed_args.output_format == nil then
    if output_format == types.output_format.unique_lines then
      table.insert(cmd, '--line-number')
    else
      table.insert(cmd, '--vimgrep')
    end
  end
  if parsed_args.word then
    table.insert(cmd, '--word-regexp')
  end
  if parsed_args.fixed then
    table.insert(cmd, '--fixed-strings')
  end
  if parsed_args.case == types.search_case.sensitive then
    table.insert(cmd, '--case-sensitive')
  elseif parsed_args.case == types.search_case.insensitive then
    table.insert(cmd, '--ignore-case')
  end
  for _, arg in ipairs(ctx.args) do
    table.insert(cmd, arg)
  end

  -- 2. Result stream handling
  ----------------------------

  local is_first_batch = true
  local qflist_operation = 'r' -- first time replace the content, then flip to 'a' (append)

  -- Counters and flags
  --
  -- Results are tracked separately for producer and consumer:
  --
  --   * total_results (producer-side): number of matches parsed from rg
  --
  --   * flushed_results (consumer-side): number of entries actually pushed into quickfix
  --
  -- `total_results` is not used for UI logic (resizing, phase transitions),
  -- because in fast-output scenarios it can jump far ahead of what has been
  -- flushed.

  local total_results = 0
  local flushed_results = 0
  local stopped_at_limit = false
  local did_resize = false

  -- Phases
  --
  -- Two-phase consumer strategy to avoid redraw starvation without forcing
  -- redraws:
  --
  --   * Phase 1 (first paint): flush just enough items to fill the target
  --     quickfix window height. Phase 1 never self-schedules (no timers,
  --     recursion or defer_fn): it runs only when invoked by the producer, and
  --     then returns, allowing the main loop to become idle and redraw. See
  --     also flush_phase1.
  --
  --   * Phase 2 (throughput): drain remaining queued items using a debounce
  --     timer. Redraw starvation is acceptable here because additional items
  --     are typically off-screen (below the quickfix fold).
  --
  -- Only phase 2 may schedule deferred flushing.
  ---@enum
  local phases = {
    phase_1 = 'phase-1',
    phase_2 = 'phase-2',
    done = 'done',
  }

  local current_phase = phases.phase_1

  -- FIFO queue between rg and quickfix.
  --
  -- The queue decouples parsing cadence from UI cadence:
  --   * phase 1 uses pull(n) to flush a bounded prefix quickly
  --   * phase 2 uses drain() to flush remaining items efficiently
  local queue = fifo.new()

  ---@type uv_timer_t|nil The luv timer returned by vim.defer_fn
  local flush_timer = nil

  --- Counts how many results are still missing before reaching the target
  --- quickfix window height.
  local remaining_visible_slots = function()
    return math.max(0, qf_win_height - flushed_results)
  end

  --- Performs Neovim-side side effects:
  ---   * setqflist(...) updates the quickfix list
  ---   * optional copen + window resizing for first results
  local update_quickfix = function(items)
    -- i. Populate
    --------------
    local current_buffer_size = #items
    if current_buffer_size == 0 then
      return
    end
    vim.fn.setqflist({}, qflist_operation, { title = 'rg: results', items = items })
    qflist_operation = 'a' -- make it an append for all subsequent runs
    local previous_flushed = flushed_results
    flushed_results = flushed_results + current_buffer_size

    -- ii. Open (on new searches)
    ------------------------------
    if is_first_batch then
      if qf_open then
        if qf_auto_resize then
          -- Open directly with the size corresponding to initial content, to
          -- avoid "flickering".
          vim.cmd('copen ' .. current_buffer_size)
        else
          -- Set the final height right away if the user has disabled auto-resizing.
          vim.cmd('copen ' .. qf_win_height)
        end
      end
      M._set_search_register(parsed_args.pattern, {
        word = parsed_args.word,
        fixed = parsed_args.fixed,
        case = parsed_args.case,
      })
      is_first_batch = false
    end

    -- iii. Resize
    --------------
    -- Respect user config if auto-resizing was disabled.
    if not qf_auto_resize then
      return
    end

    -- Avoid resizing after the final height was reached, in case the user has
    -- resized manually since.
    if did_resize then
      return
    end

    if previous_flushed < qf_win_height then
      local qf_winid = vim.fn.getqflist({ winid = 0 }).winid
      if qf_winid ~= 0 then
        vim.api.nvim_win_set_height(qf_winid, math.min(flushed_results, qf_win_height))
        if flushed_results >= qf_win_height then
          did_resize = true
        end
      end
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
  --- See also the Phases section above.
  local flush_phase1 = function()
    if current_phase ~= phases.phase_1 or queue.is_empty() then
      return
    end

    local remaining = remaining_visible_slots()
    if remaining == 0 then
      current_phase = phases.phase_2
      return
    end

    -- Pull only the minimum necessary to fill the quickfix window above the
    -- fold.
    local items = queue.pull(remaining)

    update_quickfix(items)

    if remaining_visible_slots() == 0 then
      current_phase = phases.phase_2
    end
  end

  --- Drains and renders all entries queued so far. May be scheduled.
  local flush_phase2 = function()
    if flush_timer then
      flush_timer:stop()
      flush_timer = nil
    end

    if queue.is_empty() then
      return
    end

    update_quickfix(queue.drain())
  end

  -- Phase-2 scheduling: only phase 2 may defer work. During phase 1 we avoid
  -- scheduling entirely so the main loop can become idle and redraw.
  local schedule_flush_phase2 = function()
    if flush_timer then
      return
    end

    flush_timer = vim.defer_fn(flush_phase2, flush_debounce_ms)
  end

  --- request_flush will either
  ---
  ---   - flush synchronously (phase 1)...
  ---   - ...or schedule a flush (phase 2)
  ---
  --- Since it may run synchronously (depending on phase) it must be called from
  --- a scheduled context (Neovim's main loop).
  local request_flush = function()
    if current_phase == phases.phase_1 then
      flush_phase1()
    elseif current_phase == phases.phase_2 then
      schedule_flush_phase2()
    end
  end

  --- Last chunk of the previous batch. See :h channel-lines.
  local stdout_buffer = ''

  -- Producer: stdout handler
  --
  -- This callback should stay "dumb": parse complete lines, enqueue entries,
  -- and then trigger the appropriate consumer. It intentionally does not
  -- encode UI logic (resizing, redraws, etc.).
  local on_stdout = vim.schedule_wrap(function(_, data, _)
    if not active_rg_job_id then
      return
    end

    -- Should never happen according to docs.
    if not data then
      return
    end

    -- Handle incomplete chunks and EOF. What remains are all fully-formed lines.
    if #data == 1 and data[1] == '' then
      -- EOF and no dangling buffer: nothing else to do.
      if stdout_buffer == '' then return end
      -- EOF, but there's still a result in the buffer: put it back into `data`
      data[1] = stdout_buffer
      stdout_buffer = ''
    else
      -- Handle ongoing stream
      -- 1. Complete the first chunk using the last one from the previous batch.
      data[1] = stdout_buffer .. data[1]
      -- 2. Pop the last (potentially incomplete) chunk of this batch.
      stdout_buffer = table.remove(data)
    end

    -- NOTE: After removing the last (potentially incomplete) element, data may
    -- be empty. This is expected when we receive a single partial chunk; it
    -- will be completed and processed when the next stdout event arrives.
    if #data == 0 then
      return
    end

    for _, line in ipairs(data) do
      if total_results >= max_results then
        -- Quickfix lists are memory-heavy. We stop early to cap memory bloat
        -- and to avoid leaving Neovim in a slowed state after the search.
        stopped_at_limit = true
        request_flush()
        if active_rg_job_id then
          vim.fn.jobstop(active_rg_job_id)
          active_rg_job_id = nil
        end
        break
      end

      local entry = parse_line(line)
      if entry then
        queue.push(entry)
        total_results = total_results + 1
      end

      -- Don't wait until the entire result batch is processed, if there are
      -- already enough results to flush.
      if queue.len() >= flush_threshold then
        request_flush()
      end
    end

    request_flush()
  end)

  -- 3. Error message handling
  ----------------------------
  -- NOTE: stderr is buffered (see jobstart options below), so this callback
  -- receives all stderr output in a single call when the job exits.
  local stderr_lines = {}
  local on_stderr = function(_, data, _)
    if not data or #data == 0 then
      return
    end
    if data[#data] == '' then
      table.remove(data)
    end
    stderr_lines = data
  end

  -- 4. Command exit handling
  ---------------------------

  --- Performs a final flush, both phase-1 and phase-2.
  local flush_final = function()
    if current_phase == phases.phase_1 then
      -- in the unlikely circumstance that the ripgrep process exits before
      -- Neovim had a chance to open the quickfix.
      flush_phase1()
    end
    flush_phase2() -- drain everything remaining in any case, no timer
    current_phase = phases.done
  end

  --- on_exit is a final "trigger" for consumers: it ensures anything still in
  --- the stdout buffer/queue becomes visible even if rg stops suddenly.
  local on_exit = vim.schedule_wrap(function(_, exit_code, _)
    flush_final()

    if exit_code == 0 then
      vim.notify(string.format('rg: %d matches', total_results), vim.log.levels.INFO)
      return
    end

    if exit_code == 1 then
      vim.notify('rg: no matches', vim.log.levels.WARN)
      return
    end

    if stopped_at_limit then
      local msg = 'rg: stopped at limit (' .. max_results .. ')'
      if max_results < types.max_max_results then
        msg = msg .. ' (configure in setup)'
      end
      if #stderr_lines > 0 then
        table.insert(stderr_lines, msg)
        msg = table.concat(stderr_lines, '\n')
      end
      vim.notify(msg, vim.log.levels.WARN)
      return
    end

    if stopped_by_user then
      local msg = 'rg: stopped manually'
      if #stderr_lines > 0 then
        table.insert(stderr_lines, msg)
        msg = table.concat(stderr_lines, '\n')
      end
      vim.notify(msg, vim.log.levels.WARN)
      return
    end

    table.insert(stderr_lines, 'rg: exited with code ' .. exit_code)
    vim.notify(table.concat(stderr_lines, '\n'), vim.log.levels.ERROR)
  end)

  -- 5. Run command
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
    vim.notify('failed to start rg', vim.log.levels.ERROR)
    active_rg_job_id = nil
  end
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
--- Translates the ripgrep pattern to Vim regex syntax and enables hlsearch.
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
  vim.opt.hlsearch = true
end

return M
