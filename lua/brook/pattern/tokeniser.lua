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
--- Main tokeniser -------------------------------------------------------------
--------------------------------------------------------------------------------

--- Tokenise a ripgrep regex pattern.
---
---@param input string The pattern to tokenise
---@return brook.pattern.Token[] tokens
function M.tokenise(input)
  local tokens = {}
  local pos = 1

  while M._in_bounds(input, pos) do
    local c = M._char_at(input, pos)
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
      local next_c = M._char_at(input, pos + 1)
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
      local value, end_pos = M._try_brace_quantifier(input, pos)
      if value and end_pos then
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
      token, pos = M._scan_group_open(input, pos)
    elseif c == ')' then
      token = { type = T.group_close, value = ')', pos = pos }
      pos = pos + 1
    elseif c == '[' then
      local cc_tokens, new_pos = M._scan_char_class(input, pos)
      for _, t in ipairs(cc_tokens) do
        tokens[#tokens+1] = t
      end
      pos = new_pos
      -- skip the token append below
      goto continue
    elseif c == '\\' then
      token, pos = M._scan_escape(input, pos)
    elseif not special[c] then
      token = { type = T.literal, value = c, pos = pos }
      pos = pos + 1
    else
      -- fallback for any unhandled special character
      token = { type = T.literal, value = c, pos = pos }
      pos = pos + 1
    end

    tokens[#tokens+1] = token
    ::continue::
  end

  return tokens
end

--------------------------------------------------------------------------------
--- Helpers --------------------------------------------------------------------
--------------------------------------------------------------------------------

--- Check if position is within bounds.
---
---@param input string
---@param pos integer
---@return boolean
function M._in_bounds(input, pos)
  return pos <= #input
end

--- Get character at position, or nil if out of bounds.
---
---@param input string
---@param pos integer
---@return string?
function M._char_at(input, pos)
  if not M._in_bounds(input, pos) then
    return nil
  end
  return input:sub(pos, pos)
end

--- Check if a character is a digit.
---
---@param c string?
---@return boolean
function M._is_digit(c)
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
function M._try_brace_quantifier(input, pos)
  local i = pos + 1 -- skip opening brace

  -- must start with a digit
  if not M._is_digit(M._char_at(input, i)) then
    return nil, nil
  end

  -- consume first number
  while M._is_digit(M._char_at(input, i)) do
    i = i + 1
  end

  local c = M._char_at(input, i)

  if c == '}' then
    -- {n} form
    i = i + 1
  elseif c == ',' then
    i = i + 1
    -- optional second number
    while M._is_digit(M._char_at(input, i)) do
      i = i + 1
    end
    if M._char_at(input, i) ~= '}' then
      return nil, nil
    end
    i = i + 1
  else
    return nil, nil
  end

  -- check for non-greedy or possessive modifier
  local next_c = M._char_at(input, i)
  if next_c == '?' or next_c == '+' then
    i = i + 1
  end

  return input:sub(pos, i - 1), i
end

--------------------------------------------------------------------------------
--- Escape sequence parsing ----------------------------------------------------
--------------------------------------------------------------------------------

--- Check if character is a hex digit.
---
---@param c string?
---@return boolean
function M._is_hex_digit(c)
  if c == nil then
    return false
  end
  return (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F')
end

--- Check if character is an octal digit.
---
---@param c string?
---@return boolean
function M._is_octal_digit(c)
  return c ~= nil and c >= '0' and c <= '7'
end

--- Escape characters that map to literal escapes (control chars and special).
local literal_escapes = {
  n = true,
  t = true,
  r = true,
  f = true,
  a = true,
  e = true, -- control
  ['\\'] = true,
  ['.'] = true,
  ['*'] = true,
  ['+'] = true,
  ['?'] = true,
  ['^'] = true,
  ['$'] = true,
  ['|'] = true,
  ['('] = true,
  [')'] = true,
  ['['] = true,
  [']'] = true,
  ['{'] = true,
  ['}'] = true,
  ['/'] = true,
}

--- Escape characters that map to character classes.
local class_escapes = {
  d = true,
  D = true,
  w = true,
  W = true,
  s = true,
  S = true,
  h = true,
  H = true,
  v = true,
  V = true,
}

--- Scan an escape sequence starting at pos (which points to the backslash).
---
---@param input string
---@param pos integer
---@return brook.pattern.Token token
---@return integer new_pos
function M._scan_escape(input, pos)
  local start_pos = pos
  local c = M._char_at(input, pos + 1)

  -- trailing backslash
  if c == nil then
    return { type = T.escape_literal, value = '\\', pos = start_pos }, pos + 1
  end

  -- word boundary: \b, \B, \b{...}
  if c == 'b' then
    -- check for extended form \b{...}
    if M._char_at(input, pos + 2) == '{' then
      local close = input:find('}', pos + 3, true)
      if close then
        local value = input:sub(start_pos, close)
        local kind_str = input:sub(pos + 3, close - 1)
        local boundary_kind
        if kind_str == 'start' then
          boundary_kind = 'word_start'
        elseif kind_str == 'end' then
          boundary_kind = 'word_end'
        elseif kind_str == 'start-half' then
          boundary_kind = 'word_start_half'
        elseif kind_str == 'end-half' then
          boundary_kind = 'word_end_half'
        else
          boundary_kind = 'word' -- unknown, default to word
        end
        return { type = T.escape_boundary, value = value, pos = start_pos, boundary_kind = boundary_kind }, close + 1
      end
    end
    return { type = T.escape_boundary, value = '\\b', pos = start_pos, boundary_kind = 'word' }, pos + 2
  end

  if c == 'B' then
    return { type = T.escape_boundary, value = '\\B', pos = start_pos, boundary_kind = 'word_neg' }, pos + 2
  end

  -- string anchors: \A, \z
  if c == 'A' then
    return { type = T.escape_boundary, value = '\\A', pos = start_pos, boundary_kind = 'start' }, pos + 2
  end

  if c == 'z' then
    return { type = T.escape_boundary, value = '\\z', pos = start_pos, boundary_kind = 'end' }, pos + 2
  end

  -- word boundary shortcuts: \<, \>
  if c == '<' then
    return { type = T.escape_boundary, value = '\\<', pos = start_pos, boundary_kind = 'word_start' }, pos + 2
  end

  if c == '>' then
    return { type = T.escape_boundary, value = '\\>', pos = start_pos, boundary_kind = 'word_end' }, pos + 2
  end

  -- character class escapes: \d, \D, \w, \W, \s, \S, \h, \H, \v, \V
  if class_escapes[c] then
    return { type = T.escape_class, value = '\\' .. c, pos = start_pos }, pos + 2
  end

  -- literal escapes: \n, \t, \r, etc. and escaped metacharacters
  if literal_escapes[c] then
    return { type = T.escape_literal, value = '\\' .. c, pos = start_pos }, pos + 2
  end

  -- hex: \xNN or \x{...}
  if c == 'x' then
    if M._char_at(input, pos + 2) == '{' then
      local close = input:find('}', pos + 3, true)
      if close then
        local value = input:sub(start_pos, close)
        return { type = T.escape_hex, value = value, pos = start_pos }, close + 1
      end
    else
      -- \xNN: exactly two hex digits
      if M._is_hex_digit(M._char_at(input, pos + 2)) and M._is_hex_digit(M._char_at(input, pos + 3)) then
        local value = input:sub(start_pos, pos + 3)
        return { type = T.escape_hex, value = value, pos = start_pos }, pos + 4
      end
    end
    -- invalid hex escape: treat as literal
    return { type = T.escape_literal, value = '\\x', pos = start_pos }, pos + 2
  end

  -- unicode: \uNNNN, \u{...}, \UNNNNNNNN, \U{...}
  if c == 'u' then
    if M._char_at(input, pos + 2) == '{' then
      local close = input:find('}', pos + 3, true)
      if close then
        local value = input:sub(start_pos, close)
        return { type = T.escape_unicode, value = value, pos = start_pos }, close + 1
      end
    else
      -- \uNNNN: exactly four hex digits
      local valid = true
      for i = 2, 5 do
        if not M._is_hex_digit(M._char_at(input, pos + i)) then
          valid = false
          break
        end
      end
      if valid then
        local value = input:sub(start_pos, pos + 5)
        return { type = T.escape_unicode, value = value, pos = start_pos }, pos + 6
      end
    end
    -- invalid: treat as literal
    return { type = T.escape_literal, value = '\\u', pos = start_pos }, pos + 2
  end

  if c == 'U' then
    if M._char_at(input, pos + 2) == '{' then
      local close = input:find('}', pos + 3, true)
      if close then
        local value = input:sub(start_pos, close)
        return { type = T.escape_unicode, value = value, pos = start_pos }, close + 1
      end
    else
      -- \UNNNNNNNN: exactly eight hex digits
      local valid = true
      for i = 2, 9 do
        if not M._is_hex_digit(M._char_at(input, pos + i)) then
          valid = false
          break
        end
      end
      if valid then
        local value = input:sub(start_pos, pos + 9)
        return { type = T.escape_unicode, value = value, pos = start_pos }, pos + 10
      end
    end
    -- invalid: treat as literal
    return { type = T.escape_literal, value = '\\U', pos = start_pos }, pos + 2
  end

  -- octal: \o{...} or \NNN (1-3 octal digits, but only if starts with 0-7)
  if c == 'o' and M._char_at(input, pos + 2) == '{' then
    local close = input:find('}', pos + 3, true)
    if close then
      local value = input:sub(start_pos, close)
      return { type = T.escape_octal, value = value, pos = start_pos }, close + 1
    end
    -- invalid: treat as literal
    return { type = T.escape_literal, value = '\\o', pos = start_pos }, pos + 2
  end

  -- octal or backref: \0-\7 start octal, \1-\9 could be backref
  -- rule: if multiple octal digits follow, it's octal; single digit 1-9 is backref
  if M._is_octal_digit(c) then
    local i = pos + 2
    local count = 1
    while count < 3 and M._is_octal_digit(M._char_at(input, i)) do
      i = i + 1
      count = count + 1
    end
    if count > 1 or c == '0' then
      -- multiple digits or starts with 0: octal
      local value = input:sub(start_pos, i - 1)
      return { type = T.escape_octal, value = value, pos = start_pos }, i
    else
      -- single digit 1-9: backref
      return { type = T.escape_backref, value = '\\' .. c, pos = start_pos }, pos + 2
    end
  end

  -- backref: \9 when not followed by octal digits (already handled above for 1-7)
  if c == '8' or c == '9' then
    return { type = T.escape_backref, value = '\\' .. c, pos = start_pos }, pos + 2
  end

  -- unicode properties: \p{...}, \P{...}
  if c == 'p' or c == 'P' then
    if M._char_at(input, pos + 2) == '{' then
      local close = input:find('}', pos + 3, true)
      if close then
        local value = input:sub(start_pos, close)
        local negated = (c == 'P')
        return { type = T.escape_property, value = value, pos = start_pos, negated = negated }, close + 1
      end
    end
    -- invalid: treat as literal
    return { type = T.escape_literal, value = '\\' .. c, pos = start_pos }, pos + 2
  end

  -- anything else: escaped literal
  return { type = T.escape_literal, value = '\\' .. c, pos = start_pos }, pos + 2
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
function M._is_flag_char(c)
  return c ~= nil and flag_chars[c] == true
end

--- Check if character is valid for group names (alphanumeric or underscore).
---
---@param c string?
---@return boolean
function M._is_name_char(c)
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
function M._is_name_start_char(c)
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
function M._scan_group_open(input, pos)
  local start_pos = pos
  local GK = types.group_kind

  -- simple capturing group
  if M._char_at(input, pos + 1) ~= '?' then
    return { type = T.group_open, value = '(', pos = start_pos, kind = GK.capturing }, pos + 1
  end

  local c2 = M._char_at(input, pos + 2)

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
    local c3 = M._char_at(input, pos + 3)
    if c3 == '=' then
      return { type = T.group_open, value = '(?<=', pos = start_pos, kind = GK.lookbehind_pos }, pos + 4
    elseif c3 == '!' then
      return { type = T.group_open, value = '(?<!', pos = start_pos, kind = GK.lookbehind_neg }, pos + 4
    elseif M._is_name_start_char(c3) then
      -- named PCRE: (?<name>
      local name_start = pos + 3
      local i = name_start
      while M._is_name_char(M._char_at(input, i)) do
        i = i + 1
      end
      if M._char_at(input, i) == '>' and i > name_start then
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
  if c2 == 'P' and M._char_at(input, pos + 3) == '<' then
    local c4 = M._char_at(input, pos + 4)
    if M._is_name_start_char(c4) then
      local name_start = pos + 4
      local i = name_start
      while M._is_name_char(M._char_at(input, i)) do
        i = i + 1
      end
      if M._char_at(input, i) == '>' and i > name_start then
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
  if M._is_flag_char(c2) or c2 == '-' then
    local i = pos + 2
    local flags_start = i

    -- consume positive flags
    while M._is_flag_char(M._char_at(input, i)) do
      i = i + 1
    end

    -- optional negation section
    if M._char_at(input, i) == '-' then
      i = i + 1
      while M._is_flag_char(M._char_at(input, i)) do
        i = i + 1
      end
    end

    local flags = input:sub(flags_start, i - 1)
    local next_c = M._char_at(input, i)

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
--- Character class parsing ----------------------------------------------------
--------------------------------------------------------------------------------

local CC = types.cc_token_type

--- Scan an escape sequence inside a character class.
--- Returns token and new position.
---
---@param input string
---@param pos integer Position of the backslash
---@return brook.pattern.Token token
---@return integer new_pos
function M._scan_cc_escape(input, pos)
  local start_pos = pos
  local c = M._char_at(input, pos + 1)

  if c == nil then
    return { type = CC.cc_literal, value = '\\', pos = start_pos }, pos + 1
  end

  -- character class escapes
  if class_escapes[c] then
    return { type = CC.cc_escape_class, value = '\\' .. c, pos = start_pos }, pos + 2
  end

  -- \b inside character class is literal 'b' (not word boundary)
  if c == 'b' then
    return { type = CC.cc_escape_literal, value = '\\b', pos = start_pos }, pos + 2
  end

  -- hex: \xNN or \x{...}
  if c == 'x' then
    if M._char_at(input, pos + 2) == '{' then
      local close = input:find('}', pos + 3, true)
      if close then
        return { type = CC.cc_escape_hex, value = input:sub(start_pos, close), pos = start_pos }, close + 1
      end
    elseif M._is_hex_digit(M._char_at(input, pos + 2)) and M._is_hex_digit(M._char_at(input, pos + 3)) then
      return { type = CC.cc_escape_hex, value = input:sub(start_pos, pos + 3), pos = start_pos }, pos + 4
    end
    return { type = CC.cc_escape_literal, value = '\\x', pos = start_pos }, pos + 2
  end

  -- unicode: \u{...}, \uNNNN, \U{...}, \UNNNNNNNN
  if c == 'u' then
    if M._char_at(input, pos + 2) == '{' then
      local close = input:find('}', pos + 3, true)
      if close then
        return { type = CC.cc_escape_unicode, value = input:sub(start_pos, close), pos = start_pos }, close + 1
      end
    else
      local valid = true
      for i = 2, 5 do
        if not M._is_hex_digit(M._char_at(input, pos + i)) then
          valid = false
          break
        end
      end
      if valid then
        return { type = CC.cc_escape_unicode, value = input:sub(start_pos, pos + 5), pos = start_pos }, pos + 6
      end
    end
    return { type = CC.cc_escape_literal, value = '\\u', pos = start_pos }, pos + 2
  end

  if c == 'U' then
    if M._char_at(input, pos + 2) == '{' then
      local close = input:find('}', pos + 3, true)
      if close then
        return { type = CC.cc_escape_unicode, value = input:sub(start_pos, close), pos = start_pos }, close + 1
      end
    else
      local valid = true
      for i = 2, 9 do
        if not M._is_hex_digit(M._char_at(input, pos + i)) then
          valid = false
          break
        end
      end
      if valid then
        return { type = CC.cc_escape_unicode, value = input:sub(start_pos, pos + 9), pos = start_pos }, pos + 10
      end
    end
    return { type = CC.cc_escape_literal, value = '\\U', pos = start_pos }, pos + 2
  end

  -- octal: \o{...} or \NNN
  if c == 'o' and M._char_at(input, pos + 2) == '{' then
    local close = input:find('}', pos + 3, true)
    if close then
      return { type = CC.cc_escape_octal, value = input:sub(start_pos, close), pos = start_pos }, close + 1
    end
    return { type = CC.cc_escape_literal, value = '\\o', pos = start_pos }, pos + 2
  end

  if M._is_octal_digit(c) then
    local i = pos + 2
    local count = 1
    while count < 3 and M._is_octal_digit(M._char_at(input, i)) do
      i = i + 1
      count = count + 1
    end
    return { type = CC.cc_escape_octal, value = input:sub(start_pos, i - 1), pos = start_pos }, i
  end

  -- unicode properties: \p{...}, \P{...}
  if c == 'p' or c == 'P' then
    if M._char_at(input, pos + 2) == '{' then
      local close = input:find('}', pos + 3, true)
      if close then
        return { type = CC.cc_escape_property, value = input:sub(start_pos, close), pos = start_pos, negated = (c == 'P') }, close + 1
      end
    end
    return { type = CC.cc_escape_literal, value = '\\' .. c, pos = start_pos }, pos + 2
  end

  -- everything else is an escaped literal
  return { type = CC.cc_escape_literal, value = '\\' .. c, pos = start_pos }, pos + 2
end

--- Try to scan a POSIX class at pos. Returns token and new pos, or nil.
---
---@param input string
---@param pos integer Position of the first '['
---@return brook.pattern.Token? token
---@return integer? new_pos
function M._try_posix_class(input, pos)
  if M._char_at(input, pos) ~= '[' or M._char_at(input, pos + 1) ~= ':' then
    return nil, nil
  end

  local negated = M._char_at(input, pos + 2) == '^'
  local name_start = negated and pos + 3 or pos + 2

  -- find closing :]
  local i = name_start
  while M._in_bounds(input, i) do
    local c = M._char_at(input, i)
    if c == ':' and M._char_at(input, i + 1) == ']' then
      local name = input:sub(name_start, i - 1)
      if #name > 0 then
        local value = input:sub(pos, i + 1)
        return { type = CC.cc_posix, value = value, pos = pos, class_name = name, negated = negated }, i + 2
      end
      return nil, nil
    elseif not ((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z')) then
      return nil, nil
    end
    i = i + 1
  end
  return nil, nil
end

--- Scan a character class starting at pos (which points to '[').
--- Returns list of tokens and new position.
---
---@param input string
---@param pos integer
---@return brook.pattern.Token[] tokens
---@return integer new_pos
function M._scan_char_class(input, pos)
  local tokens = {}
  local start_pos = pos
  local depth = 1 -- track nesting

  -- opening bracket
  local negated = M._char_at(input, pos + 1) == '^'
  if negated then
    tokens[#tokens+1] = { type = T.char_class_open, value = '[^', pos = start_pos, negated = true }
    pos = pos + 2
  else
    tokens[#tokens+1] = { type = T.char_class_open, value = '[', pos = start_pos, negated = false }
    pos = pos + 1
  end

  -- ] immediately after [ or [^ is a literal
  local first_char = true

  while M._in_bounds(input, pos) and depth > 0 do
    local c = M._char_at(input, pos)

    -- ] as first character is literal
    if c == ']' and first_char then
      tokens[#tokens+1] = { type = CC.cc_literal, value = ']', pos = pos }
      pos = pos + 1
      first_char = false

      -- closing bracket
    elseif c == ']' then
      depth = depth - 1
      if depth == 0 then
        tokens[#tokens+1] = { type = T.char_class_close, value = ']', pos = pos }
      else
        tokens[#tokens+1] = { type = CC.cc_nested_close, value = ']', pos = pos }
      end
      pos = pos + 1

      -- escape sequence
    elseif c == '\\' then
      local tok, new_pos = M._scan_cc_escape(input, pos)
      tokens[#tokens+1] = tok
      pos = new_pos
      first_char = false

      -- intersection: &&
    elseif c == '&' and M._char_at(input, pos + 1) == '&' then
      tokens[#tokens+1] = { type = CC.cc_intersection, value = '&&', pos = pos }
      pos = pos + 2
      first_char = false

      -- nested class or POSIX
    elseif c == '[' then
      -- try POSIX first
      local posix_tok, posix_end = M._try_posix_class(input, pos)
      if posix_tok and posix_end then
        tokens[#tokens+1] = posix_tok
        pos = posix_end
        first_char = false
      else
        -- nested class
        depth = depth + 1
        local nested_negated = M._char_at(input, pos + 1) == '^'
        if nested_negated then
          tokens[#tokens+1] = { type = CC.cc_nested_open, value = '[^', pos = pos, negated = true }
          pos = pos + 2
        else
          tokens[#tokens+1] = { type = CC.cc_nested_open, value = '[', pos = pos, negated = false }
          pos = pos + 1
        end
        first_char = true -- reset for nested class
      end

      -- range: check if this is start of a range (char-char)
    elseif M._char_at(input, pos + 1) == '-' and M._char_at(input, pos + 2) ~= ']' and M._char_at(input, pos + 2) ~= nil then
      local from_char = c
      local to_char = M._char_at(input, pos + 2)
      if to_char and to_char ~= '[' and to_char ~= '\\' then
        tokens[#tokens+1] = { type = CC.cc_range, value = from_char .. '-' .. to_char, pos = pos, from = from_char, to = to_char }
        pos = pos + 3
      else
        -- not a simple range, treat as literal
        tokens[#tokens+1] = { type = CC.cc_literal, value = c, pos = pos }
        pos = pos + 1
      end
      first_char = false

      -- literal
    else
      tokens[#tokens+1] = { type = CC.cc_literal, value = c, pos = pos }
      pos = pos + 1
      first_char = false
    end
  end

  return tokens, pos
end

return M
