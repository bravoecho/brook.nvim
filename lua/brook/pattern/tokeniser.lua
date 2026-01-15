-- This file: lua/brook/pattern/tokenise.lua

--- Lexical analysis for ripgrep regex patterns.
---
--- Identifies token boundaries without semantic interpretation. Produces a flat
--- list of tokens that the parser will classify and annotate.
---
---@module 'brook.pattern.tokenise'
local M = {}

local types = require('brook.pattern.types')

local T = types.token_type
local CC = types.cc_token_type
local GK = types.group_kind

--------------------------------------------------------------------------------
--- Token construction helpers -------------------------------------------------
--------------------------------------------------------------------------------

---@param token_type brook.pattern.TokenType|brook.pattern.CCTokenType
---@param value string
---@param pos integer
---@param extra? table
---@return brook.pattern.Token
local function tok(token_type, value, pos, extra)
  local t = { type = token_type, value = value, pos = pos }
  if extra then
    for k, v in pairs(extra) do
      t[k] = v
    end
  end
  return t
end

--------------------------------------------------------------------------------
--- Character predicates -------------------------------------------------------
--------------------------------------------------------------------------------

--- Check if character can start a quantifier.
---@param c string Single character
---@return boolean
local function is_quantifier_char(c)
  return c == '*' or c == '+' or c == '?' or c == '{'
end

--- Check if this position has something that can be quantified.
--- Quantifiers need a preceding atom (literal, escape, group close, class close).
--- Note: literal quantifier characters (+, *, ?) are not quantifiable themselves.
---@param tokens brook.pattern.Token[]
---@return boolean
local function can_quantify(tokens)
  if #tokens == 0 then
    return false
  end
  local last = tokens[#tokens]
  local t = last.type
  if t == T.escape or t == T.group_close or t == T.char_class_close then
    return true
  end
  if t == T.literal then
    -- Literal quantifier chars that ended up as literals (e.g., + at start)
    -- are not themselves quantifiable
    local v = last.value
    if v == '+' or v == '*' or v == '?' then
      return false
    end
    return true
  end
  return false
end

--------------------------------------------------------------------------------
--- Escape sequence extraction -------------------------------------------------
--------------------------------------------------------------------------------

--- Extract an escape sequence starting at position i.
--- Handles \p{...}, \P{...}, and simple two-character escapes.
---@param pattern string
---@param i integer Starting position (at the backslash)
---@return string value The complete escape sequence
---@return integer next_pos Position after the escape
local function extract_escape(pattern, i)
  local len = #pattern
  if i >= len then
    -- Trailing backslash
    return '\\', i + 1
  end

  local next_char = pattern:sub(i + 1, i + 1)

  -- Unicode property: \p{...} or \P{...}
  if (next_char == 'p' or next_char == 'P') and pattern:sub(i + 2, i + 2) == '{' then
    local close = pattern:find('}', i + 3, true)
    if close then
      return pattern:sub(i, close), close + 1
    else
      -- Unclosed brace - take what we have
      return pattern:sub(i, len), len + 1
    end
  end

  -- Simple two-character escape
  return pattern:sub(i, i + 1), i + 2
end

--------------------------------------------------------------------------------
--- Quantifier extraction ------------------------------------------------------
--------------------------------------------------------------------------------

--- Try to extract a quantifier starting at position i.
--- Handles *, +, ?, {n}, {n,}, {n,m} with optional ? (non-greedy) or + (possessive).
---@param pattern string
---@param i integer Starting position
---@return string|nil value The quantifier string, or nil if not a valid quantifier
---@return boolean greedy Whether it's greedy
---@return boolean possessive Whether it's possessive
---@return integer next_pos Position after the quantifier (or i if not a quantifier)
local function try_extract_quantifier(pattern, i)
  local c = pattern:sub(i, i)
  local len = #pattern

  if c == '*' or c == '+' or c == '?' then
    -- Check for modifier
    local next_c = i < len and pattern:sub(i + 1, i + 1) or ''
    if next_c == '?' then
      return c .. '?', false, false, i + 2
    elseif next_c == '+' then
      return c .. '+', true, true, i + 2
    else
      return c, true, false, i + 1
    end
  end

  -- Brace quantifier {n}, {n,}, {n,m} - must have at least one digit
  if c == '{' then
    -- Check there's at least one digit before any comma or close
    local first_content = i + 1 <= len and pattern:sub(i + 1, i + 1) or ''
    if not first_content:match('[0-9]') then
      -- Empty or starts with comma/other - not a valid quantifier
      return nil, false, false, i
    end

    -- Find closing brace
    local j = i + 1
    while j <= len do
      local bc = pattern:sub(j, j)
      if bc == '}' then
        local value = pattern:sub(i, j)
        -- Check for modifier
        local next_c = j < len and pattern:sub(j + 1, j + 1) or ''
        if next_c == '?' then
          return value .. '?', false, false, j + 2
        elseif next_c == '+' then
          return value .. '+', true, true, j + 2
        else
          return value, true, false, j + 1
        end
      elseif not (bc:match('[0-9,]')) then
        -- Invalid brace content - not a quantifier
        return nil, false, false, i
      end
      j = j + 1
    end
    -- Unclosed brace - not a quantifier
    return nil, false, false, i
  end

  -- Not a quantifier
  return nil, false, false, i
end

--------------------------------------------------------------------------------
--- Group opener extraction ----------------------------------------------------
--------------------------------------------------------------------------------

--- Extract a group opener starting at position i.
--- Handles (, (?:, (?P<name>, (?<name>, (?=, (?!, (?<=, (?<!, (?>.
---@param pattern string
---@param i integer Starting position (at the open paren)
---@return string value The group opener string
---@return brook.pattern.GroupKind kind The group kind
---@return string|nil name For named groups, the capture name
---@return integer next_pos Position after the opener
local function extract_group_open(pattern, i)
  local len = #pattern

  -- Simple capturing group
  if i >= len or pattern:sub(i + 1, i + 1) ~= '?' then
    return '(', GK.capturing, nil, i + 1
  end

  -- Extended group syntax (?...
  local third = pattern:sub(i + 2, i + 2)

  -- Non-capturing (?:
  if third == ':' then
    return '(?:', GK.non_capturing, nil, i + 3
  end

  -- Named Python style (?P<name>
  if third == 'P' and pattern:sub(i + 3, i + 3) == '<' then
    local close = pattern:find('>', i + 4, true)
    if close then
      local name = pattern:sub(i + 4, close - 1)
      return pattern:sub(i, close), GK.named_python, name, close + 1
    else
      -- No closing > - consume to end
      local name = pattern:sub(i + 4)
      return pattern:sub(i), GK.named_python, name, len + 1
    end
  end

  -- Named PCRE style (?<name> (not (?<= or (?<!)
  if third == '<' then
    local fourth = pattern:sub(i + 3, i + 3)
    if fourth ~= '=' and fourth ~= '!' then
      local close = pattern:find('>', i + 3, true)
      if close then
        local name = pattern:sub(i + 3, close - 1)
        return pattern:sub(i, close), GK.named_pcre, name, close + 1
      else
        local name = pattern:sub(i + 3)
        return pattern:sub(i), GK.named_pcre, name, len + 1
      end
    end
  end

  -- Lookahead positive (?=
  if third == '=' then
    return '(?=', GK.lookahead_pos, nil, i + 3
  end

  -- Lookahead negative (?!
  if third == '!' then
    return '(?!', GK.lookahead_neg, nil, i + 3
  end

  -- Lookbehind positive (?<=
  if third == '<' and pattern:sub(i + 3, i + 3) == '=' then
    return '(?<=', GK.lookbehind_pos, nil, i + 4
  end

  -- Lookbehind negative (?<!
  if third == '<' and pattern:sub(i + 3, i + 3) == '!' then
    return '(?<!', GK.lookbehind_neg, nil, i + 4
  end

  -- Atomic group (?>
  if third == '>' then
    return '(?>', GK.atomic, nil, i + 3
  end

  -- Unknown (? sequence - treat as capturing with literal ?
  -- Actually, just return the ( and let ? be handled separately
  return '(', GK.capturing, nil, i + 1
end

--------------------------------------------------------------------------------
--- Character class tokenisation -----------------------------------------------
--------------------------------------------------------------------------------

--- Tokenise the contents of a character class.
--- Called after [ or [^ has been consumed. Processes until ] or end of string.
---@param pattern string
---@param i integer Starting position (first char after [ or [^)
---@param tokens brook.pattern.Token[] Token list to append to
---@return integer next_pos Position after the closing ]
local function tokenise_char_class(pattern, i, tokens)
  local len = #pattern
  local first_content = true -- ] at start is literal

  while i <= len do
    local c = pattern:sub(i, i)

    -- Closing bracket (unless it's the first character)
    if c == ']' and not first_content then
      table.insert(tokens, tok(T.char_class_close, ']', i))
      return i + 1
    end

    -- Escape sequence
    if c == '\\' and i < len then
      local esc_value, next_pos = extract_escape(pattern, i)
      table.insert(tokens, tok(CC.cc_escape, esc_value, i))
      i = next_pos
      first_content = false
      -- Potential range: check if this is X-Y where Y is not ]
    elseif i + 2 <= len
        and pattern:sub(i + 1, i + 1) == '-'
        and pattern:sub(i + 2, i + 2) ~= ']'
    then
      -- It's a range
      local from_char = c
      local to_char = pattern:sub(i + 2, i + 2)
      -- Handle escaped to_char
      if to_char == '\\' and i + 3 <= len then
        -- Range to escaped char like a-\] is unusual but handle it
        -- Actually, in most regex engines a-\x is range from a to x
        -- We'll treat the escaped char as literal for range endpoint
        to_char = pattern:sub(i + 3, i + 3)
        local range_value = pattern:sub(i, i + 3)
        table.insert(tokens, tok(CC.cc_range, range_value, i, { from = from_char, to = to_char }))
        i = i + 4
      else
        local range_value = pattern:sub(i, i + 2)
        table.insert(tokens, tok(CC.cc_range, range_value, i, { from = from_char, to = to_char }))
        i = i + 3
      end
      first_content = false
    else
      -- Literal character (including ] at start, - at start/end)
      table.insert(tokens, tok(CC.cc_literal, c, i))
      i = i + 1
      first_content = false
    end
  end

  -- Unclosed character class - return position past end
  return i
end

--------------------------------------------------------------------------------
--- Main tokeniser -------------------------------------------------------------
--------------------------------------------------------------------------------

--- Tokenise a ripgrep regex pattern.
---
--- Performs pure lexical analysis: identifies where tokens begin and end without
--- semantic interpretation. The parser will classify escapes, compute wordness,
--- and validate constructs.
---
---@param pattern string The ripgrep regex pattern
---@return brook.pattern.Token[] tokens Ordered list of tokens
function M.tokenise(pattern)
  local tokens = {}
  local len = #pattern
  local i = 1

  while i <= len do
    local c = pattern:sub(i, i)

    -- Escape sequence
    if c == '\\' then
      local value, next_pos = extract_escape(pattern, i)
      table.insert(tokens, tok(T.escape, value, i))
      i = next_pos

      -- Character class
    elseif c == '[' then
      local negated = pattern:sub(i + 1, i + 1) == '^'
      if negated then
        table.insert(tokens, tok(T.char_class_open, '[^', i, { negated = true }))
        i = tokenise_char_class(pattern, i + 2, tokens)
      else
        table.insert(tokens, tok(T.char_class_open, '[', i, { negated = false }))
        i = tokenise_char_class(pattern, i + 1, tokens)
      end

      -- Group open
    elseif c == '(' then
      local value, kind, name, next_pos = extract_group_open(pattern, i)
      local extra = { kind = kind }
      if name then
        extra.name = name
      end
      table.insert(tokens, tok(T.group_open, value, i, extra))
      i = next_pos

      -- Group close
    elseif c == ')' then
      table.insert(tokens, tok(T.group_close, ')', i))
      i = i + 1

      -- Quantifiers (only valid after something to quantify)
    elseif is_quantifier_char(c) and can_quantify(tokens) then
      local value, greedy, possessive, next_pos = try_extract_quantifier(pattern, i)
      if value then
        local extra = { greedy = greedy }
        if possessive then
          extra.possessive = true
        end
        table.insert(tokens, tok(T.quantifier, value, i, extra))
        i = next_pos
      else
        -- Invalid brace sequence like {abc} - treat { as literal
        table.insert(tokens, tok(T.literal, c, i))
        i = i + 1
      end

      -- Alternation
    elseif c == '|' then
      table.insert(tokens, tok(T.alternation, '|', i))
      i = i + 1

      -- Anchors
    elseif c == '^' or c == '$' then
      table.insert(tokens, tok(T.anchor, c, i))
      i = i + 1

      -- Forward slash (search delimiter in Vim)
    elseif c == '/' then
      table.insert(tokens, tok(T.slash, '/', i))
      i = i + 1

      -- Literal character (including ., which is semantically special but lexically simple)
    else
      table.insert(tokens, tok(T.literal, c, i))
      i = i + 1
    end
  end

  return tokens
end

return M
