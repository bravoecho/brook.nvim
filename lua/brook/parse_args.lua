-- Load a pre-built sets of valid ripgrep flags and options, extracted from the
-- ripgrep help.
local rg_named_args        = require('brook.lib.rg_named_args')
local types                = require('brook.types')
local rg_flags             = rg_named_args.flags
local rg_options           = rg_named_args.options

local M                    = {}

local POSITIONAL_SEPARATOR = '--'

--- Extracts search patterns and search-related flags from a list of ripgrep
--- command-line tokens.
---
--- Patterns can be specified either via the `-e`/`--regexp` options, or as the
--- first positional argument. This function handles both cases, as well as
--- stacked short arguments and quoted tokens.
---
--- NOTE: The tokens must be already shell-unquoted (call shell_unquote_all to
--- pre-process them).
---
---@param unquoted_tokens string[]|nil A list of shell-unquoted command-line tokens
---@return brook.ParsedArgs|nil result Parsed arguments, or nil if malformed
function M.parse_args(unquoted_tokens)
  if unquoted_tokens == nil or #unquoted_tokens == 0 then
    return nil
  end

  -- Step 1 (pre-processing): expand tokens
  -----------------------------------------
  -- Split into separate tokens all the tokens that contain multiple flags, an
  -- option and optionally a value.
  unquoted_tokens = M._expand_all(unquoted_tokens)

  -- Step 2 (short-circuit): use the search pattern option
  --------------------------------------------------------
  -- search for patterns specified with the -e or --regexp options
  local i = 1

  ---@type brook.ParsedArgs
  local result = {
    patterns = {},
    fixed = false,
    word = false,
    case = types.search_case.unset,
  }

  while i <= #unquoted_tokens do
    local token = unquoted_tokens[i]
    if token == POSITIONAL_SEPARATOR then
      -- we must NOT try to interpret tokens as named arguments after the
      -- positional separator
      break
    end
    if token == '-e' or token == '--regexp' then
      -- the pattern is the following token
      local pattern = unquoted_tokens[i + 1]
      if not pattern then
        -- if a pattern option if not followed by a pattern, then the command is
        -- malformed
        return nil
      end
      table.insert(result.patterns, pattern)
      i = i + 2
    elseif token == '-F' or token == '--fixed-strings' then
      result.fixed = true
      i = i + 1
    elseif token == '-w' or token == '--word-regexp' then
      result.word = true
      i = i + 1
    elseif token == '-s' or token == '--case-sensitive' then
      result.case = types.search_case.sensitive
      i = i + 1
    elseif token == '-i' or token == '--ignore-case' then
      result.case = types.search_case.insensitive
      i = i + 1
    elseif token == '-S' or token == '--smart-case' then
      result.case = types.search_case.unset
      i = i + 1
    else
      i = i + 1
    end
  end

  if #(result.patterns) > 0 then
    return result
  end

  -- Step 3: categorise tokens and select first positional argument
  -----------------------------------------------------------------
  -- finally, if we still have no patterns, the pattern must be the first
  -- positional argument: start the search from the beginning
  i = 1

  while i <= #unquoted_tokens do
    local token = unquoted_tokens[i]
    if rg_flags[token] then
      -- if it's a token, discard it
      i = i + 1
    elseif rg_options[token] then
      -- if it's an option, discard it with its value
      i = i + 2
    elseif token == POSITIONAL_SEPARATOR then
      local pattern = unquoted_tokens[i + 1]
      if not pattern then
        return nil
      else
        result.patterns = { pattern }
        return result
      end
    elseif M._is_unknown_named_arg(token) then
      -- if the flag is unknown, it's either
      -- - a typo, in which case the command is malformed
      -- - ...or a new flag we don't know about in a recent version of ripgrep,
      --   the command would succeed, but we can't tell for sure if it's a flag
      --   or an option, so it's better to highlight nothing than getting it
      --   wrong and confuse the user
      return nil
    else
      -- return the first positional argument
      result.patterns = { token }
      return result
    end
  end
end

--- Checks if the given token looks like a flag or option, but is neither
---
--- @param token string The token to check
--- @return boolean
function M._is_unknown_named_arg(token)
  -- check whether it starts with one or two hyphens, and has at least one other
  -- non-hyphen character after that
  local looks_like_named_arg = token:match('^(%-%-?[^-])')
  if not looks_like_named_arg then
    return false
  end

  return (not rg_flags[token] and not rg_options[token])
end

--- Expands all tokens, splitting stacked short arguments and long arguments
--- with attached values.
---
--- Expansion examples:
---   - `-Hcefoo` becomes `-H`, `-c`, `-e`, `foo`
---   - `--regexp=pattern` becomes `--regexp`, `pattern`
---
--- Tokens after the positional separator (`--`) are not expanded.
---
---@param tokens string[] Input tokens
---@return string[] expanded Expanded tokens
function M._expand_all(tokens)
  local result = {}

  for i, token in ipairs(tokens) do
    if token == POSITIONAL_SEPARATOR then
      -- any argument after the separator must not be split, because it's
      -- positional, collect them all and return
      for j = i, #tokens do
        table.insert(result, tokens[j])
      end
      return result
    end

    local expanded = M._expand_token(token)
    for _, val in ipairs(expanded) do
      table.insert(result, val)
    end
  end

  return result
end

--- Expands a single token if it's a named argument.
---
--- Handles both short stacked arguments (e.g. `-abc`) and long arguments
--- with attached values (e.g. `--flag=value`).
---
---@param token string The token to expand
---@return string[] expanded One or more tokens after expansion
function M._expand_token(token)
  -- if it starts with a single hyphen, then it's a stack of short flags, plus
  -- possibly a short option
  if token:match('^%-[^-]+') then
    return M._expand_stacked_short_args(token)
  end

  -- if it starts with exactly two hyphens, that it's a long-form named argument
  if token:match('^%-%-[^-]+') then
    return M._expand_long_arg(token)
  end

  return { token }
end

--- Expands a stacked short argument into individual flags and options.
---
--- Iterates through characters after the hyphen, splitting each recognised
--- flag into its own token. Stops at the first option (which consumes the
--- remaining characters as its value) or at an unrecognised character.
---
--- Examples:
---   - `-Hc` with both being flags => `-H`, `-c`
---   - `-Hefoo` with `-H` flag and `-e` option => `-H`, `-e`, `foo`
---   - `-e=pattern` with `-e` option => `-e`, `pattern`
---
---@param token string A token starting with a single hyphen
---@return string[] expanded Expanded tokens
function M._expand_stacked_short_args(token)
  -- Match:
  -- - everything after a single hyphen
  -- - if the first character after the hyphen is alphanumeric or a dot
  --   (bizarrely, '-.' is the short version of the `--hidden` flag)
  local stack = token:match('^%-([%w%.].*)')

  if not stack then
    return { token }
  end

  local result = {}

  for i = 1, #stack do
    local ch = stack:sub(i, i)

    local arg = '-' .. ch

    if rg_flags[arg] then
      -- if it's a flag, just isolate it and continue
      table.insert(result, arg)
    elseif rg_options[arg] then
      -- if it's an option, isolate the option and its value, and return the
      -- expanded list
      table.insert(result, arg)

      local rest = stack:sub(i + 1)

      -- if the rest begins with an '=' sign, then we discard the '=' and we use
      -- the rest as the value
      if rest:sub(1, 1) == '=' then
        rest = rest:sub(2)
      end

      -- if the value is an empty string, it means that it was not attached to
      -- the option, but it might be in the subsequent token, so we ignore it,
      -- it will be dealt with by the token categorisation logic
      if rest == '' then
        return result
      end
      table.insert(result, rest)
      return result
    else
      -- we have encountered a character that is neither a flag nor an option:
      -- return the original token, let the token categorisation or ripgrep deal
      -- with it, it will probably error as invalid command anyway
      return { token }
    end
  end

  return result
end

--- Expands a long argument by splitting on the first `=` sign.
---
--- Example: `--regexp=foo=bar` becomes `--regexp`, `foo=bar`
---
---@param token string A token starting with `--`
---@return string[] expanded One or two tokens (argument and optional value)
function M._expand_long_arg(token)
  -- '--some-arg=foo=bar' => gets split into '--some-arg' and 'foo=bar'
  local arg, val = token:match('^(%-%-[^=]+)=(.*)')
  if arg and val then
    return { arg, val }
  end
  return { token }
end

return M
