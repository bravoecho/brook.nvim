---@module 'brook.rg'

local exec = require('brook.exec')._exec
local tokenise = require('brook.tokenise').tokenise
local posix_unquote_all = require('brook.posix_unquote').posix_unquote_all
local parse_args = require('brook.parse_args').parse_args

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
---@param cfg brook.ExecConfig Plugin options
---@return function|nil cancel_fn Function to use to cancel the current job
function M.selection(text, cfg)
  return exec({
    args = { '--', text },
    parsed_args = {
      pattern = text,
      word = false,
      fixed = true,
      case = nil,
      output_format = nil,
      multiline = false,
    },
    cfg = cfg,
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
---@param cfg brook.ExecConfig Plugin options
---@return function|nil cancel_fn Function to use to cancel the current job
function M.word(word, cfg)
  return exec({
    args = { '--', word },
    parsed_args = {
      pattern = word,
      word = true,
      fixed = true,
      case = nil,
      output_format = nil,
      multiline = false,
    },
    cfg = cfg,
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
---@param cfg brook.ExecConfig Plugin options
---@return function|nil cancel_fn Function to use to cancel the current job
function M.raw(cmd_args, cfg)
  -- 1. Tokenise
  --------------
  -- Tokenise the command string (split on whitespace, respect quotes)
  local tokens = tokenise(cmd_args)

  if not tokens or #tokens == 0 then
    vim.notify('rg: no arguments provided', vim.log.levels.ERROR)
    return nil
  end

  -- 2. Unquote
  -------------
  -- Unquote each token (interprets shell quoting rules)
  local rg_args = posix_unquote_all(tokens)
  -- If any token was malformed (unterminated quotes, trailing backslashes...),
  -- we cannot run the `rg` command: notify and bail out.
  if rg_args == nil then
    vim.notify('rg: malformed command: could not unquote', vim.log.levels.ERROR)
    return nil
  end

  -- 3. Parse ripgrep arguments
  -----------------------------
  -- Minimal parsing, just enough to support Neovim features
  local parsed_args = parse_args(rg_args)

  -- 4. Enforce single-line search
  --------------------------------
  if parsed_args.multiline then
    vim.notify('rg: multiline search not supported', vim.log.levels.ERROR)
    return nil
  end

  -- 5. Run the search
  --------------------

  -- Give precedence to output format specified in the command, if present.
  cfg.output_format = parsed_args.output_format or cfg.output_format

  return exec({
    args = rg_args,
    parsed_args = parsed_args,
    cfg = cfg,
    title = 'rg ' .. cmd_args,
  })
end

return M
