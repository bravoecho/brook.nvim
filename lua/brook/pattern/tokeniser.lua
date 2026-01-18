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
--- Group parsing --------------------------------------------------------------
--------------------------------------------------------------------------------

-- valid flag characters in ripgrep
local flag_chars = {
  i = true, m = true, s = true, U = true, u = true, x = true, R = true,
}

--- Check if character is a valid flag character.
---
---@param c string?
---@return boolean
local function is_flag_char(c)
  return c ~= nil and flag_chars[c] == true
end

--- Check if character is valid for group names (alphanumeric or underscore).
---
---@param c string?
---@return boolean
local function is_name_char(c)
  if c == nil then
    return false
  end
  return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z')
      or (c >= '0' and c <= '9') or c == '_'
end

--- Check if character is valid as first character of group name.
--- Names must start with letter or underscore, not digit.
---
---@param c string?
---@return boolean
local function is_name_start_char(c)
  if c == nil then
    return false
  end
  return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_'
end

--- Scan a group opening sequence starting at pos.
--- Returns the token and the new position.
---
---@param input string
---@param pos integer Position of the opening parenthesis
---@return brook.pattern.Token token
---@return integer new_pos
local function scan_group_open(input, pos)
  local start_pos = pos
  local GK = types.group_kind

  -- simple capturing group
  if char_at(input, pos + 1) ~= '?' then
    return { type = T.group_open, value = '(', pos = start_pos, kind = GK.capturing }, pos + 1
  end

  local c2 = char_at(input, pos + 2)

  -- non-capturing: (?:
  if c2 == ':' then
    return { type = T.group_open, value = '(?:', pos = start_pos, kind = GK.non_capturing }, pos + 3
  end

  -- positive lookahead: (?=
  if c2 == '=' then
    return { type = T.group_open, value = '(?=', pos = start_pos, kind = GK.lookahead_pos }, pos + 3
  end

  -- negative lookahead: (?!
  if c2 == '!' then
    return { type = T.group_open, value = '(?!', pos = start_pos, kind = GK.lookahead_neg }, pos + 3
  end

  -- lookbehind or named PCRE: (?< followed by = or ! or name
  if c2 == '<' then
    local c3 = char_at(input, pos + 3)
    if c3 == '=' then
      return { type = T.group_open, value = '(?<=', pos = start_pos, kind = GK.lookbehind_pos }, pos + 4
    elseif c3 == '!' then
      return { type = T.group_open, value = '(?<!', pos = start_pos, kind = GK.lookbehind_neg }, pos + 4
    elseif is_name_start_char(c3) then
      -- named PCRE: (?<name>
      local name_start = pos + 3
      local i = name_start
      while is_name_char(char_at(input, i)) do
        i = i + 1
      end
      if char_at(input, i) == '>' and i > name_start then
        local name = input:sub(name_start, i - 1)
        local value = input:sub(start_pos, i)
        return { type = T.group_open, value = value, pos = start_pos, kind = GK.named_pcre, name = name }, i + 1
      end
    end
    -- invalid (?< sequence: fall through to capturing
    return { type = T.group_open, value = '(', pos = start_pos, kind = GK.capturing }, pos + 1
  end

  -- atomic: (?>
  if c2 == '>' then
    return { type = T.group_open, value = '(?>', pos = start_pos, kind = GK.atomic }, pos + 3
  end

  -- named Python: (?P<name>
  if c2 == 'P' and char_at(input, pos + 3) == '<' then
    local c4 = char_at(input, pos + 4)
    if is_name_start_char(c4) then
      local name_start = pos + 4
      local i = name_start
      while is_name_char(char_at(input, i)) do
        i = i + 1
      end
      if char_at(input, i) == '>' and i > name_start then
        local name = input:sub(name_start, i - 1)
        local value = input:sub(start_pos, i)
        return { type = T.group_open, value = value, pos = start_pos, kind = GK.named_python, name = name }, i + 1
      end
    end
    -- invalid (?P< sequence: fall through to capturing
    return { type = T.group_open, value = '(', pos = start_pos, kind = GK.capturing }, pos + 1
  end

  -- flags: (?flags) or (?flags:
  -- flags can be: [imsUuxR] optionally followed by -[imsUuxR]
  if is_flag_char(c2) or c2 == '-' then
    local i = pos + 2
    local flags_start = i

    -- consume positive flags
    while is_flag_char(char_at(input, i)) do
      i = i + 1
    end

    -- optional negation section
    if char_at(input, i) == '-' then
      i = i + 1
      while is_flag_char(char_at(input, i)) do
        i = i + 1
      end
    end

    local flags = input:sub(flags_start, i - 1)
    local next_c = char_at(input, i)

    if next_c == ')' then
      -- standalone flags: (?i)
      local value = input:sub(start_pos, i)
      return { type = T.group_open, value = value, pos = start_pos, kind = GK.flags, flags = flags, scoped = false }, i + 1
    elseif next_c == ':' then
      -- scoped flags: (?i:
      local value = input:sub(start_pos, i)
      return { type = T.group_open, value = value, pos = start_pos, kind = GK.flags, flags = flags, scoped = true }, i + 1
    end

    -- didn't match a valid flag group: fall through to capturing
    return { type = T.group_open, value = '(', pos = start_pos, kind = GK.capturing }, pos + 1
  end

  -- unrecognised (? sequence: treat as capturing group
  return { type = T.group_open, value = '(', pos = start_pos, kind = GK.capturing }, pos + 1
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
      token, pos = scan_group_open(input, pos)

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
