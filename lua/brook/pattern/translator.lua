-- lua/brook/pattern/translator.lua

--- Translator phase of the pattern translation pipeline.
---
--- Takes annotated tokens from the parser and emits Vim regex syntax.
--- Pure mechanical transformation: no semantic decisions are made here.
---
---@module 'brook.pattern.translator'
local M = {}

local types = require('brook.pattern.types')

local T = types.token_type
local CC = types.cc_token_type
local GK = types.group_kind
local EC = types.escape_class
local W = types.wordness

--------------------------------------------------------------------------------
--- Constants ------------------------------------------------------------------
--------------------------------------------------------------------------------

-- Characters that need escaping in very magic mode (outside char classes).
local vim_special = {
  ['='] = true,
  ['~'] = true,
  ['@'] = true,
  ['&'] = true,
  ['<'] = true,
  ['>'] = true,
}

--------------------------------------------------------------------------------
--- Quantifier Translation -----------------------------------------------------
--------------------------------------------------------------------------------

--- Translate a quantifier token to Vim syntax.
--- Greedy quantifiers pass through; non-greedy use {-} syntax.
---@param tok table Quantifier token with value and greedy fields
---@return string Vim quantifier syntax
local function translate_quantifier(tok)
  if tok.greedy then
    return tok.value
  end

  local val = tok.value

  -- Non-greedy: remove trailing ?
  local base = val:sub(1, -2)

  if base == '*' then
    return '{-}'
  elseif base == '+' then
    return '{-1,}'
  elseif base == '?' then
    return '{-0,1}'
  elseif base:match('^{%d+}$') then
    -- {n}? => {-n}
    local n = base:match('^{(%d+)}$')
    return '{-' .. n .. '}'
  elseif base:match('^{%d+,}$') then
    -- {n,}? => {-n,}
    local n = base:match('^{(%d+),}$')
    return '{-' .. n .. ',}'
  elseif base:match('^{%d+,%d+}$') then
    -- {n,m}? => {-n,m}
    local n, m = base:match('^{(%d+),(%d+)}$')
    return '{-' .. n .. ',' .. m .. '}'
  end

  -- Fallback: shouldn't happen with well-formed input
  return tok.value
end

--------------------------------------------------------------------------------
--- Boundary Translation -------------------------------------------------------
--------------------------------------------------------------------------------

--- Translate a word boundary (\b) based on surrounding wordness.
--- Returns <, >, or %(<|>) depending on context.
---@param tok table Boundary token with prev_wordness and next_wordness
---@return string Vim boundary syntax
local function translate_boundary(tok)
  local prev = tok.prev_wordness
  local next = tok.next_wordness

  -- At start of pattern (no prev) with word following => word start
  if prev == nil and next == W.word then
    return '<'
  end

  -- At end of pattern (no next) with word preceding => word end
  if next == nil and prev == W.word then
    return '>'
  end

  -- Non-word before, word after => word start
  if prev == W.non_word and next == W.word then
    return '<'
  end

  -- Word before, non-word after => word end
  if prev == W.word and next == W.non_word then
    return '>'
  end

  -- Ambiguous cases: word-word, unknown involved, or both nil
  -- Use fallback that matches either boundary
  return '%(<|>)'
end

--------------------------------------------------------------------------------
--- Group Translation ----------------------------------------------------------
--------------------------------------------------------------------------------

--- Translate a group opener based on its kind.
--- Returns the Vim equivalent and optionally a warning.
---@param tok table Group open token with kind field
---@return string Vim group syntax
---@return string? warning Warning message if applicable
local function translate_group_open(tok)
  local kind = tok.kind

  if kind == GK.capturing then
    return '('
  elseif kind == GK.non_capturing then
    return '%('
  elseif kind == GK.named_python or kind == GK.named_pcre then
    -- Named groups become numbered groups with a warning
    return '(', 'named groups become numbered'
  end

  -- Unsupported group kinds should have been rejected by parser
  -- but handle gracefully
  return '('
end

--------------------------------------------------------------------------------
--- Token Translation ----------------------------------------------------------
--------------------------------------------------------------------------------

--- Translate a single token to Vim syntax.
--- Also collects warnings for translatable-with-caveats constructs.
---@param tok table Token from parser
---@param in_char_class boolean Whether we are inside a character class
---@param fixed boolean Whether we are in fixed string mode
---@return string Vim syntax for this token
---@return string? warning Warning message if applicable
local function translate_token(tok, in_char_class, fixed)
  local typ = tok.type

  -- Literals
  if typ == T.literal then
    local ch = tok.value
    if in_char_class then
      -- Inside character class, only / needs escaping
      if ch == '/' then
        return '\\/'
      end
      return ch
    end
    -- Outside char class: escape vim-special chars
    if vim_special[ch] then
      return '\\' .. ch
    end
    return ch
  end

  -- Forward slash
  if typ == T.slash then
    return '\\/'
  end

  -- Anchors
  if typ == T.anchor then
    return tok.value
  end

  -- Escapes
  if typ == T.escape then
    local ec = tok.escape_class

    -- Shorthands pass through
    if ec == EC.shorthand_word or ec == EC.shorthand_nonword or ec == EC.shorthand_unknown then
      return tok.value
    end

    -- Escaped literals pass through
    if ec == EC.escaped_literal then
      return tok.value
    end

    -- Word boundary
    if ec == EC.boundary then
      return translate_boundary(tok)
    end

    -- Anchors with warnings
    if ec == EC.anchor_start then
      return '^', '\\A treated as ^'
    end
    if ec == EC.anchor_end then
      return '$', '\\z treated as $'
    end

    -- Fallback for unexpected escape classes
    return tok.value
  end

  -- Quantifiers
  if typ == T.quantifier then
    return translate_quantifier(tok)
  end

  -- Groups
  if typ == T.group_open then
    return translate_group_open(tok)
  end
  if typ == T.group_close then
    return ')'
  end

  -- Alternation
  if typ == T.alternation then
    return '|'
  end

  -- Character class boundaries
  if typ == T.char_class_open then
    if tok.negated then
      return '[^'
    end
    return '['
  end
  if typ == T.char_class_close then
    return ']'
  end

  -- Character class contents
  if typ == CC.cc_literal then
    local ch = tok.value
    if ch == '/' then
      return '\\/'
    end
    return ch
  end
  if typ == CC.cc_range then
    return tok.value
  end
  if typ == CC.cc_escape then
    return tok.value
  end

  -- Unknown token type: pass through value
  return tok.value or ''
end

--------------------------------------------------------------------------------
--- Main Translation -----------------------------------------------------------
--------------------------------------------------------------------------------

--- Translation options.
---@alias brook.pattern.TranslateOpts brook.pattern.TranslateOpts

--- Translate annotated tokens to Vim regex.
---
--- Returns full warnings array for caller to format as needed.
---
---@param tokens brook.pattern.Token[] Annotated tokens from parser
---@param opts brook.pattern.TranslateOpts Translation options
---@return brook.pattern.TranslatorResult
function M.translate(tokens, opts)
  opts = opts or {}

  local parts = {}
  local warnings = {}

  -- Mode prefix: case modifier first, then magic mode
  if opts.case == 'case-sensitive' then
    parts[#parts+1] = '\\C'
  elseif opts.case == 'case-insensitive' then
    parts[#parts+1] = '\\c'
  end

  -- Magic mode
  if opts.fixed then
    parts[#parts+1] = '\\V'
  else
    parts[#parts+1] = '\\v'
  end

  -- Word boundary prefix (in \V mode need backslash, in \v mode don't)
  if opts.word then
    if opts.fixed then
      parts[#parts+1] = '\\<'
    else
      parts[#parts+1] = '<'
    end
  end

  -- Track char class state
  local in_char_class = false

  -- Translate each token
  for _, tok in ipairs(tokens) do
    -- Track char class state
    if tok.type == T.char_class_open then
      in_char_class = true
    elseif tok.type == T.char_class_close then
      in_char_class = false
    end

    local translated, warning = translate_token(tok, in_char_class, opts.fixed)
    parts[#parts+1] = translated

    if warning then
      warnings[#warnings+1] = warning
    end
  end

  -- Word boundary suffix (in \V mode need backslash, in \v mode don't)
  if opts.word then
    if opts.fixed then
      parts[#parts+1] = '\\>'
    else
      parts[#parts+1] = '>'
    end
  end

  return {
    pattern = table.concat(parts),
    warnings = warnings,
  }
end

return M
