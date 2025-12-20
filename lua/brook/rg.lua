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
local shell_unquote_all = require('brook.shell_unquote')._shell_unquote_all
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
---@param plugin_opts? brook.BrookOpts Plugin options
function M.selection(text, plugin_opts)
  plugin_opts = plugin_opts or {}

  ---@type brook.SearchOpts
  local search_opts = { word = false, fixed = true, case = 'unset' }

  local on_first_result = function()
    M._set_search_register(text, search_opts)
  end

  M._exec({ '--', text }, on_first_result, search_opts, plugin_opts)
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
---@param plugin_opts? brook.BrookOpts Plugin options
function M.word(word, plugin_opts)
  plugin_opts = plugin_opts or {}

  local search_opts = { word = true, fixed = true, case = 'unset' }

  local on_first_result = function()
    M._set_search_register(word, search_opts)
  end

  M._exec({ '--', word }, on_first_result, search_opts, plugin_opts)
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
---@param plugin_opts? brook.BrookOpts Plugin options
function M.raw(cmd_args, plugin_opts)
  plugin_opts = plugin_opts or {}

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

  -- Step 3: Build deferred callback
  ----------------------------------
  -- Remaining operations can be performed lazily, only when and if results
  -- are received. This way...
  --   - we can be confident that the arguments were formally correct, because
  --     the command succeeded and has matches: this simplifies parsing, no need
  --     for extra validation
  --   - we don't risk to reset the search register inappropriately
  --   - we avoid unnecessary work
  local on_first_result = function()
    -- Minimal parsing, just enough to support Neovim features
    local parsed_args = parse_args(rg_args)
    if not parsed_args then
      vim.notify('rg: malformed command: could not parse', vim.log.levels.ERROR)
      return
    end
    -- NOTE: Currently only the first pattern is used (even when the original
    -- command specified multiple with -e/--regexp). Support to combine multiple
    -- patterns in an alternation for more accurate highlighting may be added in
    -- the future.
    local rg_pattern = nil
    if parsed_args.patterns and #(parsed_args.patterns) > 0 then
      rg_pattern = parsed_args.patterns[1]
    end
    if not rg_pattern then
      return
    end
    M._set_search_register(rg_pattern, {
      word = parsed_args.word,
      fixed = parsed_args.fixed,
      case = parsed_args.case,
    })
  end

  -- no need to specify programmatic search options, if any are present, they
  -- will come from the args provided by the user
  M._exec(rg_args, on_first_result, {}, plugin_opts)
end

--- Runs ripgrep with the given argument array.
---
--- This function bypasses the shell, by forwarding an array of arguments
--- directly to jobstart(), which uses execve() under the hood. This means:
---   - No shell escaping is needed
---   - No shell compatibility issues (Fish, Bash, Zsh)
---   - No injection vulnerabilities
---   - Slightly faster (no shell process spawned)
---
---@param args string[] Shell-unquoted command tokens to pass to `rg`
---@param on_first_result function Callback to executed when first result is received
---@param search_opts brook.SearchOpts Search options (only used for programmatic searches)
---@param plugin_opts brook.BrookOpts Plugin options
function M._exec(args, on_first_result, search_opts, plugin_opts)
  terminated = false
  if current_job_id then
    vim.fn.jobstop(current_job_id)
    current_job_id = nil
  end

  local max_results = plugin_opts.max_results

  -- 1. Build command array
  -------------------------
  local cmd = { 'rg', '--vimgrep' }
  if search_opts.word then
    table.insert(cmd, '--word-regexp')
  end
  if search_opts.fixed then
    table.insert(cmd, '--fixed-strings')
  end
  if search_opts.case == types.search_case.sensitive then
    table.insert(cmd, '--case-sensitive')
  elseif search_opts.case == types.search_case.insensitive then
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

  --- Last chunk of the previous batch. See :h channel-lines.
  local stdout_buffer = ''

  local on_stdout = vim.schedule_wrap(function(_, data, _)
    if not data then
      return
    end

    -- Handle incomplete chunks and EOF.
    if #data == 1 and data[1] == '' and stdout_buffer == '' then
      -- EOF and no dangling buffer: nothing else to do.
      return
    elseif #data == 1 and data[1] == '' then
      -- EOF, but there's still a result in the buffer: put it back into `data`
      -- and proceed normally.
      data[1] = stdout_buffer
      stdout_buffer = ''
    else
      -- Handle ongoing stream
      -- 1. Complete the first chunk using the last one from the previous batch.
      data[1] = stdout_buffer .. data[1]
      -- Pop the last (potentially incomplete) chunk of this batch. What remains
      -- are all fully-formed lines.
      --
      -- NOTE: After removing the last (potentially incomplete) element, data
      -- may be empty. This is expected when we receive a single partial chunk;
      -- it will be completed and processed when the next stdout event arrives.
      stdout_buffer = table.remove(data)
    end

    if is_first_result and #data > 0 then
      -- Clear the quickfix list and open it
      vim.fn.setqflist({}, 'r')
      vim.cmd('copen')

      if on_first_result then
        on_first_result()
      end

      is_first_result = false
    end

    local previous_total = total_results

    local entries = {}
    for _, line in ipairs(data) do
      if max_results and total_results >= max_results then
        stopped_at_limit = true
        if current_job_id then
          vim.fn.jobstop(current_job_id)
          current_job_id = nil
        end
        break
      end

      local entry = M._parse_result(line)
      if entry then
        table.insert(entries, entry)
        total_results = total_results + 1
      end
    end

    vim.fn.setqflist(entries, 'a')

    -- Resize quickfix window, to make room for new entries, up to a maximum of 10.
    if previous_total <= 10 then
      local qf_winid = vim.fn.getqflist({ winid = 0 }).winid
      if qf_winid ~= 0 then
        vim.api.nvim_win_set_height(qf_winid, math.min(total_results, 10))
      end
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

  -- 4. Command completion handling
  ---------------------------------
  local on_exit = vim.schedule_wrap(function(_, exit_code, _)
    if exit_code == 0 then
      vim.notify(string.format('rg: %d matches', total_results), vim.log.levels.INFO)
      return
    end

    if exit_code == 1 then
      vim.notify('rg: no matches', vim.log.levels.INFO)
      return
    end

    local stopped_at_limit_msg = 'rg: stopped at limit (you can configure max_results in setup)'
    local terminated_msg = 'rg: process manually stopped'

    if stopped_at_limit and #stderr_lines > 0 then
      table.insert(stderr_lines, stopped_at_limit_msg)
      vim.notify(table.concat(stderr_lines, '\n'), vim.log.levels.ERROR)
      return
    end

    if stopped_at_limit and #stderr_lines == 0 then
      vim.notify(stopped_at_limit_msg, vim.log.levels.INFO)
      return
    end

    if terminated and #stderr_lines > 0 then
      table.insert(stderr_lines, terminated_msg)
      vim.notify(table.concat(stderr_lines, '\n'), vim.log.levels.WARN)
      return
    end

    if terminated and #stderr_lines == 0 then
      vim.notify(terminated_msg, vim.log.levels.INFO)
      return
    end

    table.insert(stderr_lines, 'rg: exited with code ' .. exit_code)
    vim.notify(table.concat(stderr_lines, '\n'), vim.log.levels.ERROR)
  end)

  -- 5. Start the job
  -------------------
  current_job_id = vim.fn.jobstart(cmd, {
    -- NOTE: Immediately close rg's stdin, or it will hang forever while we
    -- never send any data via stdin. This is specific to rg. Other tools like
    -- grep or ag don't exhibit this behaviour, they don't wait on stdin when
    -- they receive normal arguments.
    stdin = 'null',
    on_stdout = on_stdout,
    on_stderr = on_stderr,
    on_exit = on_exit,
    -- NOTE: Buffer stderr so we receive all error output in a single callback.
    -- This avoids partial-line issues without the complexity of manual
    -- buffering, since stderr is typically small (error messages or lists of
    -- unreadable files).
    stderr_buffered = true,
  })

  if current_job_id <= 0 then
    vim.notify('failed to start rg', vim.log.levels.ERROR)
    current_job_id = nil
  end
end

--- Parses a vimgrep-format result line into a quickfix entry.
---
--- Example input: "some/path/to/file.txt:137:42:the red fox jumped"
---
---@param vimgrep_result string A line in vimgrep format (filename:lnum:col:text)
---@return brook.QfEntry|nil entry Quickfix entry, or nil if parsing fails
function M._parse_result(vimgrep_result)
  local filename, lnum, col, text = vimgrep_result:match('([^:]+):(%d+):(%d+):(.*)')
  if not filename then
    return nil
  end

  return {
    filename = filename,
    lnum = tonumber(lnum),
    col = tonumber(col),
    text = text,
  }
end

--- Checks if stdout data contains only blank strings.
---
---@param data string[] Lines received from stdout
---@return boolean blank True if all lines are empty or whitespace-only
function M._data_blank(data)
  for _, line in ipairs(data) do
    if vim.trim(line) ~= '' then
      return false
    end
  end

  return true
end

--- Sets Vim's search register to the given ripgrep pattern.
---
--- Translates the ripgrep pattern to Vim regex syntax and enables hlsearch.
---
---@param rg_pattern string|nil The ripgrep search pattern
---@param search_opts brook.SearchOpts Options affecting pattern translation
function M._set_search_register(rg_pattern, search_opts)
  if not rg_pattern then
    return
  end

  local vim_pattern = pattern.rg_to_vim(rg_pattern, {
    word = search_opts.word,
    fixed = search_opts.fixed,
    case = search_opts.case,
  })

  if vim_pattern == '' then
    return
  end

  vim.fn.setreg('/', vim_pattern)
  vim.opt.hlsearch = true
end

return M
