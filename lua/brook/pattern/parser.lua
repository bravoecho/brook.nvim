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
  local warnings = {}

  -- State for single-pass boundary annotation.
  --
  -- Word boundaries need prev/next wordness from effective tokens (those that
  -- contribute to boundary context). We track the last effective token's
  -- wordness and accumulate pending boundaries until the next effective token
  -- resolves them.
  --
  -- Multiple pending boundaries can occur with consecutive \b tokens (e.g.
  -- \b\b\w). While semantically redundant, we handle it correctly rather than
  -- making assumptions about input validity.
  local prev_wordness = nil
  local pending_boundaries = {}

  -- State for character class wordness accumulation.
  --
  -- Character classes are processed incrementally: we track whether we've seen
  -- word and/or non-word members, then compute final wordness at close.
  local in_char_class = false
  local class_negated = false
  local class_has_word = false
  local class_has_non_word = false

  for _, tok in ipairs(tokens) do
    local tt = tok.type

    ------------------------------------------------------------------------
    -- Character class handling (must come first to avoid normal processing)
    ------------------------------------------------------------------------

    if tt == T.char_class_open then
      in_char_class = true
      class_negated = tok.negated
      class_has_word = false
      class_has_non_word = false
      -- No wordness on open token; it goes on close
      goto continue
    elseif tt == T.char_class_close then
      in_char_class = false
      -- Compute final wordness
      local wordness
      if class_negated then
        wordness = W.unknown
      elseif class_has_word and class_has_non_word then
        wordness = W.unknown
      elseif class_has_word then
        wordness = W.word
      elseif class_has_non_word then
        wordness = W.non_word
      else
        wordness = W.unknown
      end
      tok.wordness = wordness
      -- Update state: class close is effective
      if pending_boundaries[1] then
        for _, boundary in ipairs(pending_boundaries) do
          boundary.next_wordness = wordness
        end
        pending_boundaries = {}
      end
      prev_wordness = wordness
      goto continue
    elseif in_char_class then
      class_has_word, class_has_non_word =
          M._accumulate_class_member_wordness(tok, class_has_word, class_has_non_word)
      goto continue
    end

    ------------------------------------------------------------------------
    -- Unsupported construct detection and escape classification
    ------------------------------------------------------------------------

    if tt == T.escape_class then
      M._classify_escape_class_token(tok)
    elseif tt == T.escape_boundary then
      local err = M._classify_escape_boundary_token(tok, warnings)
      if err then
        return { error = err, warnings = warnings }
      end
    elseif tt == T.escape_literal then
      tok.escape_class = EC.escaped_literal
    elseif tt == T.escape_hex then
      tok.escape_class = EC.escaped_literal
    elseif tt == T.escape_unicode then
      tok.escape_class = EC.escaped_literal
    elseif tt == T.escape_octal then
      tok.escape_class = EC.escaped_literal
    elseif tt == T.escape_property then
      return { error = 'unicode properties not supported', warnings = warnings }
    elseif tt == T.escape_backref then
      return { error = 'backreferences require PCRE2', warnings = warnings }
    elseif tt == T.group_open then
      local err = unsupported_groups[tok.kind]
      if err then
        return { error = err, warnings = warnings }
      end
      if tok.kind == types.group_kind.named_python
          or tok.kind == types.group_kind.named_pcre then
        if tok.name == '' then
          return { error = 'invalid group name', warnings = warnings }
        end
        table.insert(warnings, 'named groups become numbered')
      end
    elseif tt == T.quantifier then
      if tok.possessive then
        return { error = 'possessive quantifiers not supported', warnings = warnings }
      end
    end

    ------------------------------------------------------------------------
    -- Wordness assignment and boundary state machine
    ------------------------------------------------------------------------

    if tt == T.escape_boundary then
      -- Boundaries don't have wordness themselves, but word boundaries
      -- need prev/next annotation
      if tok.boundary_kind == 'word' then
        tok.prev_wordness = prev_wordness
        table.insert(pending_boundaries, tok)
      end
    elseif tt == T.quantifier then
      -- Quantifiers inherit wordness from their target (already in prev_wordness)
      -- They don't update prev_wordness or resolve pending boundaries
      tok.wordness = prev_wordness or W.unknown
    else
      -- All other tokens: compute wordness, update state
      local wordness = M._compute_token_wordness(tok)
      tok.wordness = wordness

      -- Resolve pending boundaries
      if pending_boundaries[1] then
        for _, boundary in ipairs(pending_boundaries) do
          boundary.next_wordness = wordness
        end
        pending_boundaries = {}
      end
      prev_wordness = wordness
    end

    ::continue::
  end

  -- End of pattern: any remaining pending boundaries get nil for next_wordness
  -- (already nil by default, but explicit for clarity)
  for _, boundary in ipairs(pending_boundaries) do
    boundary.next_wordness = nil
  end

  return {
    tokens = tokens,
    warnings = warnings,
  }
end

--------------------------------------------------------------------------------
--- Token wordness computation -------------------------------------------------
--------------------------------------------------------------------------------

--- Compute wordness for a non-class, non-quantifier, non-boundary token.
---
---@param tok brook.pattern.Token
---@return brook.pattern.Wordness
function M._compute_token_wordness(tok)
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
  elseif tt == T.group_open or tt == T.group_close then
    return W.non_word
  elseif tt == T.alternation then
    return W.non_word
  elseif tt == T.anchor then
    return W.non_word
  elseif tt == T.slash then
    return W.non_word
  elseif tt == T.escape_hex or tt == T.escape_octal or tt == T.escape_unicode then
    return W.unknown
  elseif tt == T.escape_property then
    return W.unknown
  elseif tt == T.escape_backref then
    return W.unknown
  end

  return W.unknown
end

--------------------------------------------------------------------------------
--- Character class member wordness --------------------------------------------
--------------------------------------------------------------------------------

--- Accumulate wordness from a character class member token.
---
---@param tok brook.pattern.Token
---@param has_word boolean Current state
---@param has_non_word boolean Current state
---@return boolean has_word Updated state
---@return boolean has_non_word Updated state
function M._accumulate_class_member_wordness(tok, has_word, has_non_word)
  local tt = tok.type

  if tt == CC.cc_literal then
    local w = M._char_wordness(tok.value)
    if w == W.word then
      return true, has_non_word
    elseif w == W.non_word then
      return has_word, true
    end
  elseif tt == CC.cc_range then
    local from_byte = string.byte(tok.from)
    local to_byte = string.byte(tok.to)
    local hw, hnw = has_word, has_non_word
    for b = from_byte, to_byte do
      local c = string.char(b)
      if types.word_chars[c] then
        hw = true
      else
        hnw = true
      end
      if hw and hnw then
        break
      end
    end
    return hw, hnw
  elseif tt == CC.cc_escape_class then
    local w = M._escape_class_wordness(tok.value)
    if w == W.word then
      return true, has_non_word
    elseif w == W.non_word then
      return has_word, true
    else
      return true, true
    end
  elseif tt == CC.cc_escape_literal then
    local escaped_char = tok.value:sub(2)
    if escaped_char == 'n' or escaped_char == 't' or escaped_char == 'r' then
      return has_word, true
    elseif escaped_char == 'b' then
      -- \b inside char class is literal 'b', a word char
      return true, has_non_word
    else
      local w = M._char_wordness(escaped_char)
      if w == W.word then
        return true, has_non_word
      else
        return has_word, true
      end
    end
  elseif tt == CC.cc_posix then
    local name = tok.class_name
    if tok.negated then
      return true, true
    elseif name == 'alpha' or name == 'alnum' or name == 'digit'
        or name == 'word' or name == 'xdigit' then
      return true, has_non_word
    elseif name == 'space' or name == 'blank' or name == 'cntrl'
        or name == 'punct' then
      return has_word, true
    else
      -- [:ascii:], [:graph:], [:print:], [:lower:], [:upper:] can vary
      return true, true
    end
  elseif tt == CC.cc_escape_hex or tt == CC.cc_escape_octal
      or tt == CC.cc_escape_unicode then
    return true, true
  elseif tt == CC.cc_escape_property then
    return true, true
  elseif tt == CC.cc_nested_open then
    return true, true
  elseif tt == CC.cc_intersection then
    return true, true
  end

  return has_word, has_non_word
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
