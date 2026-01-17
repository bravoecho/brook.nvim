-- lua/brook/pattern/parser.lua

--- Parser phase of the pattern translation pipeline.
---
--- Takes tokens from the tokeniser and annotates them with semantic information:
--- - Classifies escape sequences (shorthand, boundary, anchor, backref, etc.)
--- - Computes wordness for each token
--- - Annotates \b tokens with prev_wordness and next_wordness
--- - Detects unsupported constructs and returns errors
--- - Collects warnings for translatable-with-caveats constructs
---
---@module 'brook.pattern.parser'
local M = {}

local types = require('brook.pattern.types')

-- Shorthand references
local T = types.token_type
local CC = types.cc_token_type
local GK = types.group_kind
local EC = types.escape_class
local W = types.wordness

--------------------------------------------------------------------------------
--- Escape Classification ------------------------------------------------------
--------------------------------------------------------------------------------

--- Classify an escape sequence and return its class and wordness.
---@param value string The escape sequence (e.g., '\\w', '\\b', '\\p{L}')
---@return brook.pattern.EscapeClass? escape_class
---@return brook.pattern.Wordness? wordness
---@return string? error Error message if unsupported
---@return string? warning Warning message if translatable with caveats
local function classify_escape(value)
  -- Handle single backslash (trailing backslash edge case)
  if value == '\\' then
    return EC.escaped_literal, W.non_word, nil, nil
  end

  local char = value:sub(2, 2)

  -- Word shorthands
  if char == 'w' then
    return EC.shorthand_word, W.word, nil, nil
  end
  if char == 'd' then
    return EC.shorthand_word, W.word, nil, nil
  end

  -- Non-word shorthands
  if char == 's' then
    return EC.shorthand_nonword, W.non_word, nil, nil
  end
  if char == 'W' then
    return EC.shorthand_nonword, W.non_word, nil, nil
  end
  if char == 't' then
    return EC.shorthand_nonword, W.non_word, nil, nil
  end
  if char == 'n' then
    return EC.shorthand_nonword, W.non_word, nil, nil
  end
  if char == 'r' then
    return EC.shorthand_nonword, W.non_word, nil, nil
  end

  -- Unknown shorthands (match both word and non-word)
  if char == 'S' then
    return EC.shorthand_unknown, W.unknown, nil, nil
  end
  if char == 'D' then
    return EC.shorthand_unknown, W.unknown, nil, nil
  end

  -- Word boundary
  if char == 'b' then
    return EC.boundary, nil, nil, nil -- wordness computed separately
  end

  -- Negative word boundary (unsupported)
  if char == 'B' then
    return EC.boundary_neg, nil, '\\B not supported', nil
  end

  -- Anchors
  if char == 'A' then
    return EC.anchor_start, W.non_word, nil, '\\A treated as ^'
  end
  if char == 'z' then
    return EC.anchor_end, W.non_word, nil, '\\z treated as $'
  end

  -- Unicode properties (unsupported)
  if char == 'p' or char == 'P' then
    return EC.unicode_prop, nil, 'unicode properties not supported', nil
  end

  -- Backreferences (unsupported) - \1 through \9
  if char >= '1' and char <= '9' then
    return EC.backref, nil, 'backreferences require PCRE2', nil
  end

  -- Everything else is an escaped literal
  -- Determine wordness based on what character is being escaped
  local escaped_char = char
  local wordness
  if types.word_chars[escaped_char] then
    wordness = W.word
  else
    wordness = W.non_word
  end

  return EC.escaped_literal, wordness, nil, nil
end

--------------------------------------------------------------------------------
--- Literal Wordness -----------------------------------------------------------
--------------------------------------------------------------------------------

--- Compute wordness for a literal token.
---@param value string The literal character
---@return brook.pattern.Wordness
local function literal_wordness(value)
  -- Dot matches any character
  if value == '.' then
    return W.unknown
  end

  -- Word characters
  if types.word_chars[value] then
    return W.word
  end

  -- Everything else is non-word
  return W.non_word
end

--------------------------------------------------------------------------------
--- Character Class Wordness ---------------------------------------------------
--------------------------------------------------------------------------------

-- ASCII byte values for word character range boundaries.
-- Word characters are: 0-9, A-Z, a-z, and underscore.
local byte = {
  ['0'] = 48,
  ['9'] = 57,
  A = 65,
  Z = 90,
  a = 97,
  z = 122,
}

--- Check if a range spans only word characters.
---@param from string Start of range
---@param to string End of range
---@return brook.pattern.Wordness
local function range_wordness(from, to)
  local from_byte = string.byte(from)
  local to_byte = string.byte(to)

  -- Pure lowercase letters (a-z)
  if from_byte >= byte.a and to_byte <= byte.z then
    return W.word
  end

  -- Pure uppercase letters (A-Z)
  if from_byte >= byte.A and to_byte <= byte.Z then
    return W.word
  end

  -- Pure digits (0-9)
  if from_byte >= byte['0'] and to_byte <= byte['9'] then
    return W.word
  end

  -- Check if range crosses a gap containing non-word characters.
  -- Gaps: 58-64 (between '9' and 'A'), 91-96 (between 'Z' and 'a')

  -- Crossing from digits to uppercase (spans : ; < = > ? @)
  if from_byte <= byte['9'] and to_byte >= byte.A then
    return W.unknown
  end

  -- Crossing from uppercase to lowercase (spans [ \ ] ^ _ `)
  if from_byte <= byte.Z and to_byte >= byte.a then
    return W.unknown
  end

  -- Entirely in a non-word region
  if to_byte < byte['0'] then
    return W.non_word
  end
  if from_byte > byte['9'] and to_byte < byte.A then
    return W.non_word
  end
  if from_byte > byte.Z and to_byte < byte.a then
    return W.non_word
  end
  if from_byte > byte.z then
    return W.non_word
  end

  -- Default to unknown for any other cases
  return W.unknown
end

--- Compute wordness for a cc_escape token.
---@param value string The escape sequence
---@return brook.pattern.Wordness
local function cc_escape_wordness(value)
  if types.word_escapes[value] then
    return W.word
  end
  if types.non_word_escapes[value] then
    return W.non_word
  end
  if types.unknown_escapes[value] then
    return W.unknown
  end

  -- Escaped literal - check the escaped character
  if #value >= 2 then
    local escaped_char = value:sub(2, 2)
    if types.word_chars[escaped_char] then
      return W.word
    end
  end

  return W.non_word
end

--- Compute wordness for a cc_literal token.
---@param value string The literal character
---@return brook.pattern.Wordness
local function cc_literal_wordness(value)
  if types.word_chars[value] then
    return W.word
  end
  return W.non_word
end

--- Compute wordness for an entire character class.
--- Examines tokens between char_class_open and char_class_close.
---@param tokens brook.pattern.Token[] The token list
---@param start_idx integer Index of char_class_open token
---@param end_idx integer Index of char_class_close token (or #tokens if unclosed)
---@return brook.pattern.Wordness
local function compute_class_wordness(tokens, start_idx, end_idx)
  local open_token = tokens[start_idx]

  -- Negated classes are always unknown
  if open_token.negated then
    return W.unknown
  end

  local has_word = false
  local has_non_word = false
  local has_unknown = false

  for i = start_idx + 1, end_idx - 1 do
    local tok = tokens[i]
    if not tok then
      break
    end

    local wordness

    if tok.type == CC.cc_literal then
      wordness = cc_literal_wordness(tok.value)
    elseif tok.type == CC.cc_range then
      wordness = range_wordness(tok.from, tok.to)
    elseif tok.type == CC.cc_escape then
      wordness = cc_escape_wordness(tok.value)
    end

    if wordness == W.word then
      has_word = true
    elseif wordness == W.non_word then
      has_non_word = true
    elseif wordness == W.unknown then
      has_unknown = true
    end
  end

  -- If any unknown, result is unknown
  if has_unknown then
    return W.unknown
  end

  -- If mixed word and non-word, result is unknown
  if has_word and has_non_word then
    return W.unknown
  end

  -- Pure word
  if has_word then
    return W.word
  end

  -- Pure non-word
  if has_non_word then
    return W.non_word
  end

  -- Empty class (shouldn't happen, but default to unknown)
  return W.unknown
end

--------------------------------------------------------------------------------
--- Group Validation -----------------------------------------------------------
--------------------------------------------------------------------------------

--- Check if a group kind is unsupported.
---@param kind brook.pattern.GroupKind
---@return string? error Error message if unsupported
---@return string? warning Warning message if translatable with caveats
local function validate_group(kind, name)
  -- Unsupported: lookarounds and atomic groups
  if kind == GK.lookahead_pos or kind == GK.lookahead_neg or kind == GK.atomic then
    return 'lookarounds and atomic groups not supported', nil
  end
  if kind == GK.lookbehind_pos or kind == GK.lookbehind_neg then
    return 'lookarounds not supported', nil
  end

  -- Named groups: supported with warning
  if kind == GK.named_python or kind == GK.named_pcre then
    -- Empty name is invalid
    if name == '' then
      return 'invalid group name', nil
    end
    return nil, 'named groups become numbered'
  end

  -- Capturing and non-capturing are fully supported
  return nil, nil
end

--------------------------------------------------------------------------------
--- Quantifier Validation ------------------------------------------------------
--------------------------------------------------------------------------------

--- Check if a quantifier is unsupported.
---@param token brook.pattern.QuantifierToken
---@return string? error Error message if unsupported
local function validate_quantifier(token)
  if token.possessive then
    return 'possessive quantifiers not supported'
  end
  return nil
end

--------------------------------------------------------------------------------
--- Main Parse Function --------------------------------------------------------
--------------------------------------------------------------------------------

--- Parse tokens and annotate with semantic information.
---@param tokens brook.pattern.Token[] Input tokens from tokeniser
---@return brook.pattern.ParseResult
function M.parse(tokens)
  -- Handle empty input
  if #tokens == 0 then
    return { tokens = {}, warnings = {} }
  end

  local result_tokens = {}
  local warnings = {}
  local boundary_indices = {} -- Track positions of \b tokens for second pass

  -- First pass: classify tokens and compute wordness
  local i = 1
  while i <= #tokens do
    local tok = tokens[i]
    local new_tok = {}

    -- Copy base fields
    for k, v in pairs(tok) do
      new_tok[k] = v
    end

    if tok.type == T.escape then
      -- Classify escape sequence
      local escape_class, wordness, err, warning = classify_escape(tok.value)

      if err then
        return {
          tokens = nil,
          warnings = warnings,
          error = err,
        }
      end

      new_tok.escape_class = escape_class
      if wordness then
        new_tok.wordness = wordness
      end

      if warning then
        table.insert(warnings, warning)
      end

      -- Track boundary positions for second pass
      if escape_class == EC.boundary then
        table.insert(boundary_indices, #result_tokens + 1)
      end

    elseif tok.type == T.literal then
      new_tok.wordness = literal_wordness(tok.value)

    elseif tok.type == T.anchor then
      new_tok.wordness = W.non_word

    elseif tok.type == T.alternation then
      new_tok.wordness = W.non_word

    elseif tok.type == T.group_open then
      local err, warning = validate_group(tok.kind, tok.name)
      if err then
        return {
          tokens = nil,
          warnings = warnings,
          error = err,
        }
      end
      if warning then
        table.insert(warnings, warning)
      end
      new_tok.wordness = W.non_word

    elseif tok.type == T.group_close then
      new_tok.wordness = W.non_word

    elseif tok.type == T.slash then
      new_tok.wordness = W.non_word

    elseif tok.type == T.quantifier then
      local err = validate_quantifier(tok)
      if err then
        return {
          tokens = nil,
          warnings = warnings,
          error = err,
        }
      end
      -- Quantifier wordness is inherited from preceding token (done after this loop)

    elseif tok.type == T.char_class_open then
      -- Find matching close
      local close_idx = #tokens + 1 -- Default if unclosed
      for j = i + 1, #tokens do
        if tokens[j].type == T.char_class_close then
          close_idx = j
          break
        end
      end

      -- Compute class wordness from contents
      local class_wordness = compute_class_wordness(tokens, i, close_idx)
      new_tok.wordness = class_wordness

      -- Process all tokens until close
      table.insert(result_tokens, new_tok)

      -- Process inner tokens
      for j = i + 1, close_idx - 1 do
        local inner_tok = {}
        for k, v in pairs(tokens[j]) do
          inner_tok[k] = v
        end
        table.insert(result_tokens, inner_tok)
      end

      -- Process close token if present
      if close_idx <= #tokens then
        local close_tok = {}
        for k, v in pairs(tokens[close_idx]) do
          close_tok[k] = v
        end
        close_tok.wordness = class_wordness
        table.insert(result_tokens, close_tok)
        i = close_idx
      else
        i = #tokens
      end

      i = i + 1
      goto continue
    end

    table.insert(result_tokens, new_tok)
    i = i + 1
    ::continue::
  end

  -- Second pass: inherit quantifier wordness from preceding token
  for idx = 1, #result_tokens do
    local tok = result_tokens[idx]
    if tok.type == T.quantifier then
      if idx > 1 then
        local prev = result_tokens[idx - 1]
        tok.wordness = prev.wordness or W.unknown
      else
        tok.wordness = W.unknown
      end
    end
  end

  -- Third pass: annotate \b tokens with prev_wordness and next_wordness
  for _, idx in ipairs(boundary_indices) do
    local tok = result_tokens[idx]

    -- Find previous non-structural atom
    local prev_wordness = nil
    for j = idx - 1, 1, -1 do
      local prev = result_tokens[j]
      if prev.wordness then
        prev_wordness = prev.wordness
        break
      end
    end
    tok.prev_wordness = prev_wordness

    -- Find next non-structural atom
    local next_wordness = nil
    for j = idx + 1, #result_tokens do
      local nxt = result_tokens[j]
      -- Skip quantifiers - they don't count as the "next" atom for boundary purposes
      if nxt.type ~= T.quantifier and nxt.wordness then
        next_wordness = nxt.wordness
        break
      end
    end
    tok.next_wordness = next_wordness
  end

  return {
    tokens = result_tokens,
    warnings = warnings,
  }
end

return M
