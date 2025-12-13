--- Asynchronous ripgrep execution with quickfix integration.
---
--- This module provides functions to run ripgrep searches asynchronously,
--- streaming results into Neovim's quickfix list. It bypasses the shell
--- for security and portability.
---@module 'brook.rg_exec'

local current_job_id = nil

local rg_to_vim_pattern = require('brook.rg_to_vim_pattern')._rg_to_vim_pattern
local tokenise = require('brook.tokenise')._tokenise
local shell_unquote_all = require('brook.shell_unquote')._shell_unquote_all
local parse_args = require('brook.parse_args')._parse_args

local M = {}

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
---@param plugin_opts? brook.PluginOpts Plugin options
function M.rg_selection(text, plugin_opts)
  plugin_opts = plugin_opts or {}
  M._rg_exec({ '--', text }, text, { word = false, fixed = true }, plugin_opts)
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
---@param plugin_opts? brook.PluginOpts Plugin options
function M.rg_word(word, plugin_opts)
  plugin_opts = plugin_opts or {}
  M._rg_exec({ '--', word }, word, { word = true, fixed = true }, plugin_opts)
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
--- different from rg_selection() and rg_word(), where we have pre-built Lua
--- strings that go directly to rg without any shell syntax involved.
---
--- Examples:
---   `:Rg pattern src/`         -> `rg --vimgrep pattern src/`
---   `:Rg 'hello world' src/`   -> `rg --vimgrep "hello world" src/`
---   `:Rg -w 'foo bar'`         -> `rg --vimgrep -w "foo bar"`
---
---@param cmd_args string The raw command-line arguments string
---@param plugin_opts? brook.PluginOpts Plugin options
function M.rg_raw(cmd_args, plugin_opts)
  plugin_opts = plugin_opts or {}

  -- Tokenise the command string (split on whitespace, respect quotes)
  local tokens = tokenise(cmd_args)

  if not tokens or #tokens == 0 then
    vim.notify("brook: no arguments provided", vim.log.levels.ERROR)
    return
  end

  local categorised_args = parse_args(tokens)
  local rg_pattern = nil
  if categorised_args and categorised_args.patterns and #(categorised_args.patterns) > 0 then
    rg_pattern = categorised_args.patterns[1]
  end

  -- Unquote each token (interprets shell quoting rules)
  local rg_args = shell_unquote_all(tokens)

  -- If any token was malformed (unterminated quotes), notify and bail out
  if rg_args == nil then
    vim.notify("brook: malformed command", vim.log.levels.ERROR)
    return
  end

  M._rg_exec(
    rg_args,
    rg_pattern,
    { word = categorised_args.word, fixed = categorised_args.fixed },
    plugin_opts
  )
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
---@param args string[] Arguments to pass to rg (excluding 'rg' itself and derived flags)
---@param rg_pattern string|nil The search pattern (used only to set the search register)
---@param search_opts brook.SearchOpts Search options
---@param plugin_opts brook.PluginOpts Plugin options
function M._rg_exec(args, rg_pattern, search_opts, plugin_opts)
  if current_job_id then
    vim.fn.jobstop(current_job_id)
    current_job_id = nil
  end

  local max_results = plugin_opts.max_results

  -- Build the command array, deriving flags from search_opts
  local cmd = { 'rg', '--vimgrep' }

  if search_opts.word then
    table.insert(cmd, '--word-regexp')
  end

  if search_opts.fixed then
    table.insert(cmd, '--fixed-strings')
  end

  for _, arg in ipairs(args) do
    table.insert(cmd, arg)
  end

  local is_first_entry = true
  local result_count = 0
  local stopped_at_limit = false

  local on_stdout = vim.schedule_wrap(function(_, data, _)
    -- no data signifies EOF error (end of the stream)
    if not data then
      return
    end

    -- blank data happens when there were no results
    if M._data_blank(data) then
      return
    end

    if is_first_entry and #data > 0 then
      vim.fn.setqflist({}, 'r')
      vim.cmd('copen')
      is_first_entry = false
    end

    local entries = {}
    for _, line in ipairs(data) do
      if max_results and result_count >= max_results then
        break
      end

      local entry = M._vimgrep_to_qf_entry(line)
      if entry then
        table.insert(entries, entry)
        result_count = result_count + 1
      end
    end

    local initial_qf_size = #vim.fn.getqflist()

    vim.fn.setqflist(entries, 'a')

    -- Resize quickfix window, to make room for new entries, up to a maximum of 10.
    if initial_qf_size <= 10 then
      local current_qf_size = #vim.fn.getqflist()
      local qf_winid = vim.fn.getqflist({ winid = 0 }).winid
      if qf_winid ~= 0 then
        vim.api.nvim_win_set_height(qf_winid, math.min(current_qf_size, 10))
      end
    end

    -- Stop if we've hit the limit
    if max_results and result_count >= max_results and current_job_id then
      vim.fn.jobstop(current_job_id)
      current_job_id = nil
      stopped_at_limit = true
      vim.notify(
        string.format('rg: stopped after %d results (configure max_results in setup)', result_count),
        vim.log.levels.INFO
      )
    end
  end)

  local stderr_lines = {}

  local on_stderr = vim.schedule_wrap(function(_, data, _)
    for _, line in ipairs(data) do
      if line ~= '' then
        table.insert(stderr_lines, line)
      end
    end
  end)

  local on_exit = vim.schedule_wrap(function(_, exit_code, _)
    -- If we stopped at the limit, we still want to set the search register
    -- but skip the normal exit handling
    if stopped_at_limit then
      M._set_search_register(rg_pattern, search_opts)
      return
    end

    if exit_code == 0 then
      M._set_search_register(rg_pattern, search_opts)
      return
    end

    if exit_code == 1 then
      vim.notify("rg: no matches found", vim.log.levels.INFO)
      return
    end

    local msg = "rg exited with code " .. exit_code
    if #stderr_lines > 0 then
      msg = msg .. ':\n' .. table.concat(stderr_lines, '\n')
    end
    vim.notify(msg, vim.log.levels.ERROR)
  end)

  current_job_id = vim.fn.jobstart(cmd, {
    -- NOTE: Immediately close rg's stdin, or it will hang forever while we
    -- never send any data via stdin. This is specific to rg. Other tools like
    -- grep or ag don't exhibit this behaviour, they don't wait on stdin when
    -- they receive normal arguments.
    stdin = 'null',
    on_stdout = on_stdout,
    on_stderr = on_stderr,
    on_exit = on_exit,
  })

  if current_job_id <= 0 then
    vim.notify("failed to start rg", vim.log.levels.ERROR)
    current_job_id = nil
  end
end

--- Currently only the first pattern is returned (even when the original command
--- specified multiple with -e/--regexp). Support to combine multiple patterns
--- in an alternation for more accurate highlighting may be added in the future.
---@param tokens string[] the 'args' string from the opts of the command callback
function M._extract_rg_pattern(tokens)
  if not tokens or #tokens == 0 then
    return nil
  end

  local categorised_args = parse_args(tokens)
  if categorised_args and #(categorised_args.patterns) > 0 then
    return categorised_args.patterns[1]
  end

  return nil
end

--- Parses a vimgrep-format result line into a quickfix entry.
---
--- Example input: "some/path/to/file.txt:137:42:the red fox jumped"
---
---@param vimgrep_result string A line in vimgrep format (filename:lnum:col:text)
---@return brook.QfEntry|nil entry Quickfix entry, or nil if parsing fails
function M._vimgrep_to_qf_entry(vimgrep_result)
  local filename, lnum, col, text = vimgrep_result:match("([^:]+):(%d+):(%d+):(.*)")
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

  local vim_pattern = rg_to_vim_pattern(rg_pattern, {
    word = search_opts.word,
    fixed = search_opts.fixed,
  })

  if vim_pattern == '' then
    return
  end

  vim.fn.setreg('/', vim_pattern)
  vim.opt.hlsearch = true
end

return M
