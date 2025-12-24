--- Asynchronous ripgrep execution with quickfix integration.
---
--- This module provides functions to run ripgrep searches asynchronously,
--- streaming results into Neovim's quickfix list. It bypasses the shell
--- for security and portability.
---@module 'brook.rg'

local current_job_id    = nil
--- Whether the stop() function was called.
local terminated        = false

local pattern           = require('brook.pattern')
local tokenise          = require('brook.tokenise').tokenise
local shell_unquote_all = require('brook.shell_unquote').shell_unquote_all
local parse_args        = require('brook.parse_args').parse_args
local types             = require('brook.types')

local M                 = {}

function M.stop()
  if current_job_id then
    terminated = true
    vim.fn.jobstop(current_job_id)
    current_job_id = nil
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
---@param exec_opts? brook.ExecOpts Plugin options
function M.selection(text, exec_opts)
  M._exec({
    args = { '--', text },
    parsed_args = {
      pattern = text,
      word = false,
      fixed = true,
      case = nil,
      unique_lines = false,
      multiline = false,
    },
    opts = exec_opts or {},
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
---@param exec_opts? brook.ExecOpts Plugin options
function M.word(word, exec_opts)
  M._exec({
    args = { '--', word },
    parsed_args = {
      pattern = word,
      word = true,
      fixed = true,
      case = nil,
      unique_lines = false,
      multiline = false,
    },
    opts = exec_opts or {},
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
---@param exec_opts? brook.ExecOpts Plugin options
function M.raw(cmd_args, exec_opts)
  exec_opts = exec_opts or {}

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
  -- FIXME: revise this
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
    opts = exec_opts,
    title = 'rg ' .. cmd_args,
  })
end

--- Context object for ripgrep execution (parameters for _exec).
---
---@class brook.SearchContext
---@field args string[] Shell-unquoted command tokens to be passed to `rg`
---@field parsed_args brook.ParsedArgs Subset of command arguments needed to integrate the command correctly
---@field opts brook.ExecOpts Control how search is performed and results displayed
---@field title string Used to provide feedback to the user

--- Runs ripgrep with the given argument array.
---
--- This function bypasses the shell, by forwarding an array of arguments
--- directly to jobstart(), which uses execve() under the hood. This means:
---   - No shell escaping is needed
---   - No shell compatibility issues (Fish, Bash, Zsh)
---   - No injection vulnerabilities
---   - Slightly faster (no shell process spawned)
---
---@param ctx brook.SearchContext Search context with all execution parameters
function M._exec(ctx)
  terminated = false
  if current_job_id then
    vim.fn.jobstop(current_job_id)
    current_job_id = nil
  end

  local args = ctx.args
  local parsed_args = ctx.parsed_args
  local opts = ctx.opts
  local title = ctx.title

  local max_results = opts.max_results
  local qf_win_height = opts.qf_win_height
  local qf_open = opts.qf_open
  local qf_auto_resize = opts.qf_auto_resize

  -- Allow command line arguments to override global config.
  local unique_lines = opts.unique_lines
  unique_lines = parsed_args.unique_lines

  vim.notify(title, vim.log.levels.INFO)

  -- 1. Build command array
  -------------------------
  -- NOTE: Limit previews to 300 bytes, to avoid memory explosion on abnormally
  -- long lines. Matching will still include the whole, only the preview is
  -- truncated.
  local cmd = { 'rg', '--no-multiline', '--max-columns', '300', '--max-columns-preview', '--color', 'never' }
  -- When unique_lines is enabled, use --line-number instead of --vimgrep.
  -- This omits the column number, causing ripgrep to emit each line only once
  -- regardless of how many matches it contains.
  if unique_lines then
    table.insert(cmd, '--line-number')
  else
    table.insert(cmd, '--vimgrep')
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
  for _, arg in ipairs(args) do
    table.insert(cmd, arg)
  end

  -- 2. Result stream handling
  ----------------------------
  local is_first_result = true
  local total_results = 0
  local stopped_at_limit = false
  local did_resize = false

  -- Select the appropriate parser based on output format
  local parse_result = unique_lines and M._parse_line_number or M._parse_vimgrep

  local buffer_size = opts.buffer_size
  local flush_debounce = opts.debounce

  ---@type vim.quickfix.entry
  local entry_buffer = {}

  ---@type uv_timer_t?
  local flush_timer = nil

  --- Displays results in the quickfix list
  local flush = function()
    if flush_timer then
      flush_timer:stop()
    end

    if #entry_buffer == 0 then
      return
    end

    -- i. Clear
    -----------
    if is_first_result then
      -- Clear the quickfix list.
      vim.fn.setqflist({}, 'r', { title = 'rg: results', items = {} })
    end

    -- ii. Populate
    ---------------
    local current_buffer_size = #entry_buffer
    vim.fn.setqflist(entry_buffer, 'a')
    local previous_total = total_results - current_buffer_size
    entry_buffer = {}

    -- iii. Open (on new searches)
    ------------------------------
    if is_first_result then
      if qf_open then
        if qf_auto_resize then
          -- Open directly with the size correspoding to initial content, to
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
      is_first_result = false
    end

    -- iv. Resize
    -------------
    -- Respect user config if auto-resizing was disabled.
    if not qf_auto_resize then
      return
    end

    -- Avoid resizing after the final height was reached, in case the user has
    -- resized manually since.
    if did_resize then
      return
    end

    if previous_total < qf_win_height then
      local qf_winid = vim.fn.getqflist({ winid = 0 }).winid
      if qf_winid ~= 0 then
        vim.api.nvim_win_set_height(qf_winid, math.min(total_results, qf_win_height))
        if total_results >= qf_win_height then
          did_resize = true
        end
      end
    end
  end

  local schedule_flush = function()
    if flush_timer then
      flush_timer:stop()
    end

    flush_timer = vim.defer_fn(flush, flush_debounce)
  end

  --- Last chunk of the previous batch. See :h channel-lines.
  local stdout_buffer = ''

  local on_stdout = vim.schedule_wrap(function(_, data, _)
    -- Should never happen according to docs.
    if not data then
      return
    end

    -- Handle incomplete chunks and EOF.
    if #data == 1 and data[1] == '' then
      -- EOF and no dangling buffer: nothing else to do.
      if stdout_buffer == '' then
        return
      end
      -- EOF, but there's still a result in the buffer: put it back into `data`
      -- and proceed normally.
      data[1] = stdout_buffer
      stdout_buffer = ''
    else
      -- Handle ongoing stream
      -- 1. Complete the first chunk using the last one from the previous batch.
      data[1] = stdout_buffer .. data[1]
      -- 2. Pop the last (potentially incomplete) chunk of this batch. What
      --    remains are all fully-formed lines.
      stdout_buffer = table.remove(data)
    end

    -- NOTE: After removing the last (potentially incomplete) element, data may
    -- be empty. This is expected when we receive a single partial chunk; it
    -- will be completed and processed when the next stdout event arrives.
    if #data == 0 then
      return
    end

    for _, line in ipairs(data) do
      if max_results and total_results >= max_results then
        stopped_at_limit = true
        flush()
        if current_job_id then
          vim.fn.jobstop(current_job_id)
          current_job_id = nil
        end
        break
      end

      local entry = parse_result(line)
      if entry then
        table.insert(entry_buffer, entry)
        total_results = total_results + 1
      end

      -- Don't wait until the entire result batch is processed, if there are
      -- already enough results to flush.
      if #entry_buffer >= buffer_size then
        flush()
      end
    end

    -- Display first few results immediately regardless of buffer size, for
    -- increased responsiveness.
    if total_results < qf_win_height then
      flush()
    else
      schedule_flush()
    end
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
  local on_exit = vim.schedule_wrap(function(_, exit_code, _)
    -- Ensure any remaining buffered results are displayed.
    flush()

    if exit_code == 0 then
      vim.notify(string.format('rg: %d matches', total_results), vim.log.levels.INFO)
      return
    end

    if exit_code == 1 then
      vim.notify('rg: no matches', vim.log.levels.INFO)
      return
    end

    local stopped_at_limit_msg = 'rg: stopped at limit (configure max_results in setup)'
    local terminated_msg = 'rg: stopped manually'

    if stopped_at_limit and #stderr_lines > 0 then
      table.insert(stderr_lines, stopped_at_limit_msg)
      vim.notify(table.concat(stderr_lines, '\n'), vim.log.levels.WARN)
      return
    end

    if stopped_at_limit and #stderr_lines == 0 then
      vim.notify(stopped_at_limit_msg, vim.log.levels.WARN)
      return
    end

    if terminated and #stderr_lines > 0 then
      table.insert(stderr_lines, terminated_msg)
      vim.notify(table.concat(stderr_lines, '\n'), vim.log.levels.WARN)
      return
    end

    if terminated and #stderr_lines == 0 then
      vim.notify(terminated_msg, vim.log.levels.WARN)
      return
    end

    table.insert(stderr_lines, 'rg: exited with code ' .. exit_code)
    vim.notify(table.concat(stderr_lines, '\n'), vim.log.levels.ERROR)
  end)

  -- 5. Run command
  -----------------
  current_job_id = vim.fn.jobstart(cmd, {
    -- NOTE: Immediately close rg's stdin, or it will hang forever while we
    -- never send any data via stdin. This is specific to rg. Other tools like
    -- grep or ag don't exhibit this behaviour, they don't wait on stdin when
    -- they receive normal arguments.
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

  if current_job_id <= 0 then
    vim.notify('failed to start rg', vim.log.levels.ERROR)
    current_job_id = nil
  end
end

--- Parses a vimgrep-format result line into a quickfix entry.
---
--- Format: "file:line:col:text" (default, --vimgrep)
--- Example: "some/path/to/file.txt:137:42:the red fox jumped"
---
--- Note: Unix filenames can contain colons, so we can't simply split on ':'.
--- Instead, we locate the :line:col: pattern and extract components by position.
---
---@param result string A line in vimgrep format
---@return vim.quickfix.entry|nil entry Quickfix entry, or nil if parsing fails
function M._parse_vimgrep(result)
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
--- Format: "file:line:text" (unique_lines mode, --line-number)
--- Example: "some/path/to/file.txt:137:the red fox jumped"
---
--- Note: Unix filenames can contain colons, so we can't simply split on ':'.
--- Instead, we locate the :line: pattern and extract components by position.
---
---@param result string A line in line-number format
---@return vim.quickfix.entry|nil entry Quickfix entry, or nil if parsing fails
function M._parse_line_number(result)
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
