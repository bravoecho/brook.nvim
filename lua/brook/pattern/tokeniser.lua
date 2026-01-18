-- lua/brook/pattern/tokeniser.lua

--- Lexical analyser for ripgrep regex patterns.
---
--- Scans input and produces a flat list of tokens. Does not validate semantic
--- correctness: that's the parser's job. Recognises all ripgrep default regex
--- syntax, including constructs that may not be translatable to Vim.
---
---@module 'brook.pattern.tokeniser'
local M = {}

local types = require('brook.pattern.types')
local T = types.token_type

--------------------------------------------------------------------------------
--- Character sets -------------------------------------------------------------
--------------------------------------------------------------------------------

-- characters that are special outside character classes
local special = {
  ['.'] = true,
  ['^'] = true,
  ['$'] = true,
  ['|'] = true,
  ['*'] = true,
  ['+'] = true,
  ['?'] = true,
  ['('] = true,
  [')'] = true,
  ['['] = true,
  ['{'] = true,
  ['\\'] = true,
  ['/'] = true,
}

--------------------------------------------------------------------------------
--- Helpers --------------------------------------------------------------------
--------------------------------------------------------------------------------

--- Check if position is within bounds.
---
---@param input string
---@param pos integer
---@return boolean
local function in_bounds(input, pos)
  return pos <= #input
end

--- Get character at position, or nil if out of bounds.
---
---@param input string
---@param pos integer
---@return string?
local function char_at(input, pos)
  if not in_bounds(input, pos) then
    return nil
  end
  return input:sub(pos, pos)
end

--- Check if a character is a digit.
---
---@param c string?
---@return boolean
local function is_digit(c)
  return c ~= nil and c >= '0' and c <= '9'
end

--------------------------------------------------------------------------------
--- Brace quantifier parsing ---------------------------------------------------
--------------------------------------------------------------------------------

--- Try to parse a brace quantifier starting at pos.
--- Returns the full quantifier string and end position, or nil if invalid.
---
--- Valid forms: {n}, {n,}, {n,m}
--- Invalid: {}, {,n}, {abc}
---
---@param input string
---@param pos integer Position of the opening brace
---@return string? value The quantifier including braces and any modifier
---@return integer? end_pos Position after the quantifier
local function try_brace_quantifier(input, pos)
  local i = pos + 1 -- skip opening brace

  -- must start with a digit
  if not is_digit(char_at(input, i)) then
    return nil, nil
  end

  -- consume first number
  while is_digit(char_at(input, i)) do
    i = i + 1
  end

  local c = char_at(input, i)

  if c == '}' then
    -- {n} form
    i = i + 1
  elseif c == ',' then
    i = i + 1
    -- optional second number
    while is_digit(char_at(input, i)) do
      i = i + 1
    end
    if char_at(input, i) ~= '}' then
      return nil, nil
    end
    i = i + 1
  else
    return nil, nil
  end

  -- check for non-greedy or possessive modifier
  local next_c = char_at(input, i)
  if next_c == '?' or next_c == '+' then
    i = i + 1
  end

  return input:sub(pos, i - 1), i
end

--------------------------------------------------------------------------------
--- Main tokeniser -------------------------------------------------------------
--------------------------------------------------------------------------------

--- Tokenise a ripgrep regex pattern.
---
---@param input string The pattern to tokenise
---@return brook.pattern.Token[] tokens
function M.tokenise(input)
  local tokens = {}
  local pos = 1

  while in_bounds(input, pos) do
    local c = char_at(input, pos)
    local token

    if c == '.' then
      token = { type = T.dot, value = '.', pos = pos }
      pos = pos + 1

    elseif c == '^' or c == '$' then
      token = { type = T.anchor, value = c, pos = pos }
      pos = pos + 1

    elseif c == '|' then
      token = { type = T.alternation, value = '|', pos = pos }
      pos = pos + 1

    elseif c == '*' or c == '+' or c == '?' then
      -- simple quantifier, possibly with modifier
      local next_c = char_at(input, pos + 1)
      if next_c == '?' then
        token = { type = T.quantifier, value = c .. '?', pos = pos, greedy = false }
        pos = pos + 2
      elseif next_c == '+' and (c == '*' or c == '+') then
        token = { type = T.quantifier, value = c .. '+', pos = pos, greedy = true, possessive = true }
        pos = pos + 2
      else
        token = { type = T.quantifier, value = c, pos = pos, greedy = true }
        pos = pos + 1
      end

    elseif c == '{' then
      local value, end_pos = try_brace_quantifier(input, pos)
      if value then
        local greedy = true
        local possessive = nil
        if value:sub(-1) == '?' then
          greedy = false
        elseif value:sub(-1) == '+' then
          possessive = true
        end
        token = { type = T.quantifier, value = value, pos = pos, greedy = greedy }
        if possessive then
          token.possessive = true
        end
        pos = end_pos
      else
        -- invalid brace: treat as literal
        token = { type = T.literal, value = '{', pos = pos }
        pos = pos + 1
      end

    elseif c == '}' then
      -- standalone closing brace is a literal
      token = { type = T.literal, value = '}', pos = pos }
      pos = pos + 1

    elseif c == '/' then
      token = { type = T.slash, value = '/', pos = pos }
      pos = pos + 1

    elseif c == '(' then
      -- TODO: handle group opens with modifiers
      token = { type = T.group_open, value = '(', pos = pos, kind = types.group_kind.capturing }
      pos = pos + 1

    elseif c == ')' then
      token = { type = T.group_close, value = ')', pos = pos }
      pos = pos + 1

    elseif c == '[' then
      -- TODO: handle character classes
      local negated = char_at(input, pos + 1) == '^'
      if negated then
        token = { type = T.char_class_open, value = '[^', pos = pos, negated = true }
        pos = pos + 2
      else
        token = { type = T.char_class_open, value = '[', pos = pos, negated = false }
        pos = pos + 1
      end

    elseif c == '\\' then
      -- TODO: handle escape sequences
      local next_c = char_at(input, pos + 1)
      if next_c then
        token = { type = T.escape_literal, value = '\\' .. next_c, pos = pos }
        pos = pos + 2
      else
        -- trailing backslash: treat as literal
        token = { type = T.literal, value = '\\', pos = pos }
        pos = pos + 1
      end

    elseif not special[c] then
      token = { type = T.literal, value = c, pos = pos }
      pos = pos + 1

    else
      -- fallback for any unhandled special character
      token = { type = T.literal, value = c, pos = pos }
      pos = pos + 1
    end

    tokens[#tokens + 1] = token
  end

  return tokens
end

return M
