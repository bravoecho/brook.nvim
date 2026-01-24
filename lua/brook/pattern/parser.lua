-- lua/brook/pattern/parser.lua

--- Phase 2 of pattern translation: semantic analysis and annotation.
---
--- Responsibilities:
---   - Annotate \b tokens with prev_wordness and next_wordness
---   - Classify escape sequences semantically
---   - Compute wordness for all tokens
---   - Detect and reject unsupported constructs
---   - Collect warnings
---
---@module 'brook.pattern.parser'
local M = {}

local types = require('brook.pattern.types')

local T = types.token_type
local CC = types.cc_token_type
local W = types.wordness
local EC = types.escape_class

--------------------------------------------------------------------------------
--- Main parse function --------------------------------------------------------
--------------------------------------------------------------------------------

--- Unsupported group kinds.
local unsupported_groups = {
  [types.group_kind.lookahead_pos] = 'lookarounds and atomic groups not supported',
  [types.group_kind.lookahead_neg] = 'lookarounds and atomic groups not supported',
  [types.group_kind.lookbehind_pos] = 'lookarounds not supported',
  [types.group_kind.lookbehind_neg] = 'lookarounds not supported',
  [types.group_kind.atomic] = 'lookarounds and atomic groups not supported',
}

--- Parse and annotate tokens.
---
---@param tokens brook.pattern.Token[]
---@return brook.pattern.ParseResult
function M.parse(tokens)
  -- Start with incoming warnings
  local warnings = {}

  -- First pass: classify escapes and check for unsupported constructs
  for _, tok in ipairs(tokens) do
    if tok.type == T.escape_class then
      M._classify_escape_class_token(tok)
    elseif tok.type == T.escape_boundary then
      local err = M._classify_escape_boundary_token(tok, warnings)
      if err then
        return { error = err, warnings = warnings }
      end
    elseif tok.type == T.escape_literal then
      tok.escape_class = EC.escaped_literal
    elseif tok.type == T.escape_hex then
      tok.escape_class = EC.escaped_literal
    elseif tok.type == T.escape_unicode then
      tok.escape_class = EC.escaped_literal
    elseif tok.type == T.escape_octal then
      tok.escape_class = EC.escaped_literal
    elseif tok.type == T.escape_property then
      return { error = 'unicode properties not supported', warnings = warnings }
    elseif tok.type == T.escape_backref then
      return { error = 'backreferences require PCRE2', warnings = warnings }
    elseif tok.type == T.group_open then
      -- Check for unsupported group kinds
      local err = unsupported_groups[tok.kind]
      if err then
        return { error = err, warnings = warnings }
      end
      -- Named groups: warn (or error if empty name)
      if tok.kind == types.group_kind.named_python
          or tok.kind == types.group_kind.named_pcre then
        if tok.name == '' then
          return { error = 'invalid group name', warnings = warnings }
        end
        table.insert(warnings, 'named groups become numbered')
      end
    elseif tok.type == T.quantifier then
      if tok.possessive then
        return { error = 'possessive quantifiers not supported', warnings = warnings }
      end
    end
  end

  -- Second pass: assign wordness to all applicable tokens
  for i, _ in ipairs(tokens) do
    M._assign_token_wordness(tokens, i)
  end

  -- Third pass: annotate \b tokens with prev/next wordness
  for i, tok in ipairs(tokens) do
    if tok.type == T.escape_boundary and tok.boundary_kind == 'word' then
      tok.prev_wordness = M._find_prev_wordness(tokens, i)
      tok.next_wordness = M._find_next_wordness(tokens, i)
    end
  end

  return {
    tokens = tokens,
    warnings = warnings,
  }
end

--- Find the effective wordness looking backward from a boundary.
---
--- Skips over boundaries and quantifiers to find the meaningful predecessor.
---
---@param tokens brook.pattern.Token[]
---@param boundary_idx integer Index of the \b token
---@return brook.pattern.Wordness?
function M._find_prev_wordness(tokens, boundary_idx)
  local i = boundary_idx - 1

  while i >= 1 do
    local tok = tokens[i]

    if tok.type == T.escape_boundary then
      -- Skip past other boundaries
      i = i - 1
    elseif tok.type == T.quantifier then
      -- Quantifier: look at what it quantifies
      i = i - 1
    elseif tok.type == T.char_class_close then
      -- Find matching open
      local depth = 1
      i = i - 1
      while i >= 1 and depth > 0 do
        if tokens[i].type == T.char_class_close then
          depth = depth + 1
        elseif tokens[i].type == T.char_class_open then
          depth = depth - 1
        end
        if depth > 0 then
          i = i - 1
        end
      end
      -- Now at char_class_open
      if i >= 1 then
        return M._token_wordness(tokens, i)
      end
      return nil
    else
      return M._token_wordness(tokens, i)
    end
  end

  return nil
end

--- Find the effective wordness looking forward from a boundary.
---
--- Skips over boundaries to find the meaningful successor.
---
---@param tokens brook.pattern.Token[]
---@param boundary_idx integer Index of the \b token
---@return brook.pattern.Wordness?
function M._find_next_wordness(tokens, boundary_idx)
  local i = boundary_idx + 1

  while i <= #tokens do
    local tok = tokens[i]

    if tok.type == T.escape_boundary then
      -- Skip past other boundaries
      i = i + 1
    elseif tok.type == T.quantifier then
      -- A quantifier after \b is unusual but skip it
      i = i + 1
    elseif tok.type == T.char_class_open then
      -- Wordness of the class
      return M._token_wordness(tokens, i)
    else
      return M._token_wordness(tokens, i)
    end
  end

  return nil
end

--- Get wordness of a token at a given index.
---
--- Structural tokens (groups, alternation, anchors) return non_word.
--- This matches the behaviour expected by word boundary translation.
---
---@param tokens brook.pattern.Token[]
---@param idx integer Token index
---@return brook.pattern.Wordness?
function M._token_wordness(tokens, idx)
  if idx < 1 or idx > #tokens then
    return nil
  end

  local tok = tokens[idx]
  local tt = tok.type

  if tt == T.literal then
    return M._char_wordness(tok.value)
  elseif tt == T.escape_class then
    return M._escape_class_wordness(tok.value)
  elseif tt == T.escape_literal then
    local escaped = tok.value:sub(2)
    if escaped == 'n' or escaped == 't' or escaped == 'r' then
      return W.non_word
    end
    return M._char_wordness(escaped)
  elseif tt == T.dot then
    return W.unknown
  elseif tt == T.char_class_open then
    return M._classify_char_class(tokens, idx)
  elseif tt == T.quantifier then
    -- Quantifier inherits wordness from its target (previous non-quantifier)
    local target_idx = idx - 1
    while target_idx >= 1 and tokens[target_idx].type == T.quantifier do
      target_idx = target_idx - 1
    end
    if target_idx >= 1 then
      return M._token_wordness(tokens, target_idx)
    end
    return nil
  elseif tt == T.group_open or tt == T.group_close then
    return W.non_word
  elseif tt == T.alternation then
    return W.non_word
  elseif tt == T.anchor then
    return W.non_word
  elseif tt == T.escape_boundary then
    -- Boundaries themselves don't have wordness for adjacency purposes
    -- When looking past a boundary, continue to next/prev token
    return nil
  elseif tt == T.char_class_close then
    -- Should not be reached directly, but handle it
    return nil
  elseif tt == T.escape_hex or tt == T.escape_octal or tt == T.escape_unicode then
    -- Numeric escapes could be word or non-word
    return W.unknown
  elseif tt == T.escape_property then
    return W.unknown
  elseif tt == T.escape_backref then
    return W.unknown
  elseif tt == T.slash then
    return W.non_word
  end

  return W.unknown
end

--------------------------------------------------------------------------------
--- Token wordness annotation --------------------------------------------------
--------------------------------------------------------------------------------

--- Assign wordness to a single token.
---
--- For most tokens, this is straightforward classification. For quantifiers,
--- we need to look at the preceding token. For char_class_open, we analyse
--- the class contents.
---
---@param tokens brook.pattern.Token[]
---@param idx integer
function M._assign_token_wordness(tokens, idx)
  local tok = tokens[idx]
  local tt = tok.type

  if tt == T.literal then
    tok.wordness = M._char_wordness(tok.value)
  elseif tt == T.escape_class then
    tok.wordness = M._escape_class_wordness(tok.value)
  elseif tt == T.escape_literal then
    local escaped = tok.value:sub(2)
    if escaped == 'n' or escaped == 't' or escaped == 'r' then
      tok.wordness = W.non_word
    else
      tok.wordness = M._char_wordness(escaped)
    end
  elseif tt == T.dot then
    tok.wordness = W.unknown
  elseif tt == T.char_class_open then
    tok.wordness = M._classify_char_class(tokens, idx)
  elseif tt == T.quantifier then
    -- Look backward for the quantified atom
    local target_idx = idx - 1
    while target_idx >= 1 and tokens[target_idx].type == T.quantifier do
      target_idx = target_idx - 1
    end
    if target_idx >= 1 then
      -- For char_class, we need the open token
      if tokens[target_idx].type == T.char_class_close then
        -- Find matching open
        local depth = 1
        local search_idx = target_idx - 1
        while search_idx >= 1 and depth > 0 do
          if tokens[search_idx].type == T.char_class_close then
            depth = depth + 1
          elseif tokens[search_idx].type == T.char_class_open then
            depth = depth - 1
          end
          if depth > 0 then
            search_idx = search_idx - 1
          end
        end
        if search_idx >= 1 and tokens[search_idx].wordness then
          tok.wordness = tokens[search_idx].wordness
        else
          tok.wordness = W.unknown
        end
      elseif tokens[target_idx].wordness then
        tok.wordness = tokens[target_idx].wordness
      else
        tok.wordness = W.unknown
      end
    else
      tok.wordness = W.unknown
    end
  elseif tt == T.group_open or tt == T.group_close then
    tok.wordness = W.non_word
  elseif tt == T.alternation then
    tok.wordness = W.non_word
  elseif tt == T.anchor then
    tok.wordness = W.non_word
  elseif tt == T.slash then
    tok.wordness = W.non_word
  elseif tt == T.escape_hex or tt == T.escape_octal or tt == T.escape_unicode then
    tok.wordness = W.unknown
  elseif tt == T.escape_property then
    tok.wordness = W.unknown
  elseif tt == T.escape_backref then
    tok.wordness = W.unknown
  end
  -- Note: escape_boundary, char_class_close, and cc_* tokens don't get wordness
end

--------------------------------------------------------------------------------
--- Wordness classification ----------------------------------------------------
--------------------------------------------------------------------------------

--- Classify wordness of a character class based on its contents.
---
--- A non-negated class is:
---   - word if ALL members are word characters
---   - non_word if ALL members are non-word characters
---   - unknown otherwise
---
--- A negated class is always unknown (could match anything not in the set).
---
---@param tokens brook.pattern.Token[] All tokens
---@param open_idx integer Index of char_class_open token
---@return brook.pattern.Wordness
function M._classify_char_class(tokens, open_idx)
  local open_token = tokens[open_idx]
  if open_token.negated then
    return W.unknown
  end

  local has_word = false
  local has_non_word = false

  local i = open_idx + 1
  while i <= #tokens do
    local tok = tokens[i]

    if tok.type == T.char_class_close then
      break
    end

    if tok.type == CC.cc_literal then
      local w = M._char_wordness(tok.value)
      if w == W.word then
        has_word = true
      elseif w == W.non_word then
        has_non_word = true
      end
    elseif tok.type == CC.cc_range then
      -- Check every char in range for word/non-word
      local from_byte = string.byte(tok.from)
      local to_byte = string.byte(tok.to)
      for b = from_byte, to_byte do
        local c = string.char(b)
        if types.word_chars[c] then
          has_word = true
        else
          has_non_word = true
        end
        if has_word and has_non_word then
          break
        end
      end
    elseif tok.type == CC.cc_escape_class then
      local w = M._escape_class_wordness(tok.value)
      if w == W.word then
        has_word = true
      elseif w == W.non_word then
        has_non_word = true
      else
        has_word = true
        has_non_word = true
      end
    elseif tok.type == CC.cc_escape_literal then
      -- \n, \t, \r are non-word; \b inside class is literal 'b' (word)
      local escaped_char = tok.value:sub(2)
      if escaped_char == 'n' or escaped_char == 't' or escaped_char == 'r' then
        has_non_word = true
      elseif escaped_char == 'b' then
        -- \b inside char class is literal 'b', a word char
        has_word = true
      else
        -- Other escaped literals: classify the char itself
        local w = M._char_wordness(escaped_char)
        if w == W.word then
          has_word = true
        else
          has_non_word = true
        end
      end
    elseif tok.type == CC.cc_posix then
      -- POSIX classes: [:alpha:], [:digit:], [:space:], etc
      local name = tok.class_name
      if tok.negated then
        has_word = true
        has_non_word = true
      elseif name == 'alpha' or name == 'alnum' or name == 'digit'
          or name == 'word' or name == 'xdigit' then
        has_word = true
      elseif name == 'space' or name == 'blank' or name == 'cntrl'
          or name == 'punct' then
        has_non_word = true
      else
        -- [:ascii:], [:graph:], [:print:], [:lower:], [:upper:] can vary
        has_word = true
        has_non_word = true
      end
    elseif tok.type == CC.cc_escape_hex or tok.type == CC.cc_escape_octal
        or tok.type == CC.cc_escape_unicode then
      -- Numeric escapes: could be word or non-word, treat as unknown
      has_word = true
      has_non_word = true
    elseif tok.type == CC.cc_escape_property then
      -- Unicode properties: treat as unknown
      has_word = true
      has_non_word = true
    elseif tok.type == CC.cc_nested_open then
      -- Nested class: treat as unknown for simplicity
      has_word = true
      has_non_word = true
    elseif tok.type == CC.cc_intersection then
      -- Intersection: treat as unknown
      has_word = true
      has_non_word = true
    end

    i = i + 1
  end

  if has_word and has_non_word then
    return W.unknown
  elseif has_word then
    return W.word
  elseif has_non_word then
    return W.non_word
  end
  -- Empty class (unlikely but handle it)
  return W.unknown
end

--------------------------------------------------------------------------------
--- Wordness helpers -----------------------------------------------------------
--------------------------------------------------------------------------------

--- Classify wordness of a literal character.
---
---@param char string Single character
---@return brook.pattern.Wordness
function M._char_wordness(char)
  if types.word_chars[char] then
    return W.word
  end
  return W.non_word
end

--- Classify wordness of an escape class token (\w, \d, \s, etc).
---
---@param value string The escape sequence (e.g. "\\w")
---@return brook.pattern.Wordness
function M._escape_class_wordness(value)
  if types.word_escapes[value] then
    return W.word
  elseif types.non_word_escapes[value] then
    return W.non_word
  elseif types.unknown_escapes[value] then
    return W.unknown
  end
  -- Default to unknown for unrecognised escapes (\h, \H, \v, \V, etc)
  return W.unknown
end

--------------------------------------------------------------------------------
--- Escape classification ------------------------------------------------------
--------------------------------------------------------------------------------

--- Classify an escape_class token semantically.
---
---@param tok brook.pattern.Token
function M._classify_escape_class_token(tok)
  local value = tok.value
  if value == '\\w' or value == '\\d' then
    tok.escape_class = EC.shorthand_word
  elseif value == '\\s' or value == '\\W' then
    tok.escape_class = EC.shorthand_nonword
  elseif value == '\\S' or value == '\\D' then
    tok.escape_class = EC.shorthand_unknown
  end
  -- \h, \H, \v, \V don't get escape_class (not in the enum)
end

--- Classify an escape_boundary token semantically.
---
---@param tok brook.pattern.Token
---@param warnings string[]
---@return string? error message if unsupported
function M._classify_escape_boundary_token(tok, warnings)
  local kind = tok.boundary_kind
  if kind == 'word' then
    tok.escape_class = EC.boundary
  elseif kind == 'word_neg' then
    return '\\B not supported'
  elseif kind == 'start' then
    tok.escape_class = EC.anchor_start
    table.insert(warnings, '\\A treated as ^')
  elseif kind == 'end' then
    tok.escape_class = EC.anchor_end
    table.insert(warnings, '\\z treated as $')
  end
  return nil
end

return M
