--- Public search interface:
---
---   * visual selection (literal)
---   * current word (literal, with word boundaries)
---   * user-provided search command
---
--- Delegates to the exec.lua module.
---
---@module 'brook.rg'

local exec_module = require('brook.rg.exec')
local exec = exec_module._exec
local tokenise = require('brook.args.tokeniser').tokenise
local posix_unquote_all = require('brook.args.unquoter').posix_unquote_all
local parse_args = require('brook.args.parser').parse_args

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
---@param cfg brook.rg.ExecConfig Plugin options
---@return function|nil cancel_fn Function to use to cancel the current job
function M.selection(text, cfg)
  local history_cmd = 'Rg -F ' .. M._quote_for_history(text)
  M._add_to_history(history_cmd)

  return exec({
    args = { '--', text },
    parsed_args = {
      patterns = { text },
      word = false,
      fixed = true,
      case = nil,
      output_format = nil,
      multiline = false,
      pcre2 = false,
      raw = '-F ' .. text,
    },
    cfg = cfg,
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
---@param cfg brook.rg.ExecConfig Plugin options
---@return function|nil cancel_fn Function to use to cancel the current job
function M.word(word, cfg)
  local history_cmd = 'Rg -w ' .. M._quote_for_history(word)
  M._add_to_history(history_cmd)

  return exec({
    args = { '--', word },
    parsed_args = {
      patterns = { word },
      word = true,
      fixed = true,
      case = nil,
      output_format = nil,
      multiline = false,
      pcre2 = false,
      raw = '-w ' .. word,
    },
    cfg = cfg,
  })
end

--- Searches with user-defined arguments.
---
--- The raw command string is tokenised using POSIX shell rules, then each token
--- is unquoted before being passed to rg. This simulates what a shell would do,
--- but without actually invoking a shell process.
---
--- Unquoting is necessary here because the user types their command using shell
--- syntax. When they type `:Rg 'hello world' src/`, they expect the quotes to
--- be *syntax* (grouping words), not *content*. The search pattern should be
--- `hello world`, not `'hello world'`. This is different from selection() and
--- word(), where we have Lua strings that go directly to rg without any shell
--- syntax involved.
---
---@param opts brook.rg.RawOpts The raw command-line arguments
---@param cfg brook.rg.ExecConfig Plugin options
---@return function|nil cancel_fn Function to use to cancel the current job
function M.raw(opts, cfg)
  -- 1. Tokenise
  --------------
  -- Tokenise the command string (split on whitespace, respect quotes)
  local tokens = tokenise(opts.args_string, cfg.strict_posix_quoting)

  if not tokens or #tokens == 0 then
    vim.notify('rg: no arguments provided', vim.log.levels.ERROR)
    return nil
  end

  -- 2. Unquote
  -------------
  -- Unquote each token (interprets shell quoting rules)
  local rg_args = posix_unquote_all(tokens, cfg.strict_posix_quoting)
  -- If any token was malformed (unterminated quotes, trailing backslashes...),
  -- we cannot run the `rg` command: notify and bail out.
  if rg_args == nil then
    vim.notify('rg: malformed command: could not unquote', vim.log.levels.ERROR)
    return nil
  end

  -- 3. Parse ripgrep arguments
  -----------------------------
  -- Minimal parsing, just enough to support Neovim features
  local parsed_args = parse_args(rg_args, opts.args_string)

  -- 4. Enforce single-line search
  --------------------------------
  if parsed_args.multiline then
    vim.notify('rg: multiline search not supported', vim.log.levels.ERROR)
    return nil
  end

  -- 5. Enforce default regexp engine (no PCRE2 support)
  ------------------------------------------------------
  if parsed_args.pcre2 then
    vim.notify('rg: PCRE2 not supported', vim.log.levels.ERROR)
    return nil
  end

  if #parsed_args.patterns == 0
      and opts.fallback_word
      and opts.fallback_word ~= ''
  then
    parsed_args.patterns = { opts.fallback_word }
    parsed_args.fixed = true
    parsed_args.word = true
    parsed_args.raw = parsed_args.raw .. opts.fallback_word
    table.insert(rg_args, opts.fallback_word)
  end

  -- 6. Run the search
  --------------------

  -- Give precedence to output format specified in the command, if present.
  cfg = vim.tbl_extend('force', {}, cfg, {
    output_format = parsed_args.output_format or cfg.output_format,
  })

  return exec({
    args = rg_args,
    parsed_args = parsed_args,
    cfg = cfg,
  })
end

--- Repeats the last performed search.
---
---@return function|nil cancel_fn Function to use to cancel the current job
function M.repeat_last()
  local last_ctx = exec_module.last_search_context()
  if not last_ctx then
    vim.notify('rg: no previous search to repeat', vim.log.levels.WARN)
    return nil
  end
  return exec(last_ctx)
end

--------------------------------------------------------------------------------
--- Helpers --------------------------------------------------------------------
--------------------------------------------------------------------------------

--- Quotes a string for use in command history.
---
--- Uses double quotes so the tokeniser preserves the text as a single token.
--- Internal double quotes and backslashes are escaped.
---
---@param s string The string to quote
---@return string
function M._quote_for_history(s)
  local needs_quoting = s:find('[%s\\"\']')
  if not needs_quoting then
    return s
  end
  local escaped = s:gsub('[\\"]', '\\%0')
  return '"' .. escaped .. '"'
end

--- Adds an entry to Neovim's command-line history.
---
--- This allows word and selection searches to be recalled and edited via
--- command history (arrow keys or q:), just like manually typed :Rg commands.
---
---@param cmd string The command string (without leading colon)
function M._add_to_history(cmd)
  vim.fn.histadd('cmd', cmd)
end

return M
