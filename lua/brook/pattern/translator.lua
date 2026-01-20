-- lua/brook/pattern/translator.lua

--- Phase 3: Translate annotated tokens to Vim regex.
---
--- Takes the output from the parser (annotated tokens with wordness and semantic
--- classifications) and mechanically generates Vim regex syntax.
---
--- Responsibilities:
--- - Emit mode prefix (\v or \V)
--- - Emit case modifier (\C or \c) if specified
--- - Transform tokens to Vim equivalents
--- - Apply word boundary wrapping if requested
--- - Format warnings
---
--- Does NOT:
--- - Re-examine token semantics
--- - Make decisions about what tokens mean
--- - Validate token sequences
---
---@module 'brook.pattern.translator'
local M = {}

local types = require('brook.pattern.types')
local T = types.token_type
local EC = types.escape_class
local W = types.wordness
local GK = types.group_kind
local CC = types.cc_token_type

--- Translate annotated tokens to Vim regex pattern.
---
--- This is a mechanical transformation: tokens have already been validated and
--- annotated by the parser. The translator walks the token list and emits the
--- corresponding Vim regex syntax.
---
---@param tokens brook.pattern.Token[] Annotated tokens from parser
---@param opts brook.pattern.TranslateOpts Translation options
---@return brook.pattern.TranslatorResult
function M.translate(tokens, opts)
  opts = opts or {}

  local warnings = {}
  local parts = {}

  -- Emit case prefix if specified
  if opts.case == 'case-sensitive' then
    table.insert(parts, '\\C')
  elseif opts.case == 'case-insensitive' then
    table.insert(parts, '\\c')
  end

  -- Emit mode prefix
  if opts.fixed then
    table.insert(parts, '\\V')
  else
    table.insert(parts, '\\v')
  end

  -- Emit word boundary if requested
  if opts.word then
    if opts.fixed then
      table.insert(parts, '\\<')
    else
      table.insert(parts, '<')
    end
  end

  -- Walk tokens and emit Vim equivalents
  for _, token in ipairs(tokens) do
    if token.type == T.literal then
      -- In fixed mode, all literals are literal
      -- In regex mode, some need escaping for very magic mode
      if opts.fixed then
        table.insert(parts, token.value)
      else
        -- Very magic mode requires escaping: = ~ @ & < >
        local escaped = token.value:gsub('[=~@&<>]', '\\%1')
        table.insert(parts, escaped)
      end
    elseif token.type == T.char_class_open then
      -- Character class open: [ or [^
      table.insert(parts, token.value)
    elseif token.type == T.char_class_close then
      -- Character class close: ]
      table.insert(parts, ']')
    elseif token.type == CC.cc_literal then
      -- Literal inside character class
      -- Forward slash needs escaping, others pass through
      if token.value == '/' then
        table.insert(parts, '\\/')
      else
        table.insert(parts, token.value)
      end
    elseif token.type == CC.cc_range then
      -- Range inside character class: a-z
      table.insert(parts, token.value)
    elseif token.type == CC.cc_escape_class then
      -- Escape class inside character class: \d, \w, etc.
      table.insert(parts, token.value)
    elseif token.type == CC.cc_escape_literal then
      -- Escape literal inside character class: \], \\, \b (literal b)
      table.insert(parts, token.value)
    elseif token.type == CC.cc_escape_hex then
      -- Hex escape inside character class: \x41
      table.insert(parts, token.value)
    elseif token.type == CC.cc_escape_unicode then
      -- Unicode escape inside character class: \u{41}
      table.insert(parts, token.value)
    elseif token.type == CC.cc_escape_octal then
      -- Octal escape inside character class: \0, \123
      table.insert(parts, token.value)
    elseif token.type == CC.cc_posix then
      -- POSIX class: [:alpha:], [:^digit:]
      table.insert(parts, token.value)
    elseif token.type == CC.cc_intersection then
      -- Set intersection: &&
      table.insert(parts, '&&')
    elseif token.type == CC.cc_nested_open then
      -- Nested character class open: [
      -- Note: negated nested classes lose the ^ in Vim
      -- [a-z&&[^aeiou]] becomes [a-z&&[aeiou]]
      table.insert(parts, '[')
    elseif token.type == CC.cc_nested_close then
      -- Nested character class close: ]
      table.insert(parts, ']')
    elseif token.type == T.group_open then
      -- Group openers: different kinds have different translations
      if token.kind == GK.capturing then
        -- Capturing group: ( ... )
        table.insert(parts, '(')
      elseif token.kind == GK.non_capturing then
        -- Non-capturing group: (?:...) => %(...)
        table.insert(parts, '%(')
      elseif token.kind == GK.named_python or token.kind == GK.named_pcre then
        -- Named groups: (?P<name>...) or (?<name>...) => (...)
        -- Emit warning about losing the name
        table.insert(parts, '(')
        table.insert(warnings, 'named groups become numbered')
      elseif token.kind == GK.flags then
        -- Flag groups: (?i) or (?i:...)
        -- Pass through unchanged in very magic mode
        table.insert(parts, token.value)
      else
        -- Other group kinds (lookarounds, atomic) shouldn't reach here
        -- (parser should reject them), but handle gracefully
        table.insert(parts, token.value)
      end
    elseif token.type == T.group_close then
      -- Group close: always )
      table.insert(parts, ')')
    elseif token.type == T.quantifier then
      -- Quantifiers: greedy pass through, non-greedy use {-} syntax
      if token.greedy then
        -- Greedy quantifiers work the same in both syntaxes
        table.insert(parts, token.value)
      else
        -- Non-greedy quantifiers need translation to Vim's {-} syntax
        local val = token.value

        -- Strip the trailing ? from the value to get the base quantifier
        -- (The tokeniser includes the ? in the value for non-greedy)
        if val == '*?' then
          table.insert(parts, '{-}')
        elseif val == '+?' then
          table.insert(parts, '{-1,}')
        elseif val == '??' then
          table.insert(parts, '{-0,1}')
        elseif val:match('^{%d+}%?$') then
          -- {n}? => {-n}
          local n = val:match('^{(%d+)}%?$')
          table.insert(parts, '{-' .. n .. '}')
        elseif val:match('^{%d+,}%?$') then
          -- {n,}? => {-n,}
          local n = val:match('^{(%d+),}%?$')
          table.insert(parts, '{-' .. n .. ',}')
        elseif val:match('^{%d+,%d+}%?$') then
          -- {n,m}? => {-n,m}
          local n, m = val:match('^{(%d+),(%d+)}%?$')
          table.insert(parts, '{-' .. n .. ',' .. m .. '}')
        else
          -- Fallback: shouldn't happen with valid tokeniser output
          table.insert(parts, val)
        end
      end
    elseif token.type == T.escape_boundary then
      -- Word boundaries and anchors
      if token.escape_class == EC.boundary then
        -- \b translation depends on context (prev_wordness and next_wordness)
        local prev = token.prev_wordness
        local next = token.next_wordness

        -- Determine boundary type based on wordness context
        -- < for word start: non-word (or nil) before, word after
        -- > for word end: word before, non-word (or nil) after
        -- %(<|>) for ambiguous cases

        if (prev == nil or prev == W.non_word) and next == W.word then
          -- Word start boundary
          table.insert(parts, '<')
        elseif prev == W.word and (next == nil or next == W.non_word) then
          -- Word end boundary
          table.insert(parts, '>')
        else
          -- Ambiguous: could be either start or end
          -- This includes: both unknown, both word, both non-word, or mixed unknown
          table.insert(parts, '%(<|>)')
        end
      elseif token.escape_class == EC.anchor_start then
        -- \A => ^ with warning
        table.insert(parts, '^')
        table.insert(warnings, '\\A treated as ^')
      elseif token.escape_class == EC.anchor_end then
        -- \z => $ with warning
        table.insert(parts, '$')
        table.insert(warnings, '\\z treated as $')
      end
    elseif token.type == T.escape_class then
      -- Character class shorthands: \w, \d, \s, \W, \D, \S
      -- These work identically in Rust regex and Vim very magic mode
      table.insert(parts, token.value)
    elseif token.type == T.escape_literal then
      -- Escaped literals like \n, \t, \\, \., \*, etc.
      if opts.fixed then
        -- In fixed mode, we need to escape backslashes
        if token.value == '\\\\' then
          table.insert(parts, '\\\\')
        else
          -- Other escape literals: just emit the literal value
          table.insert(parts, token.value)
        end
      else
        -- In regex mode, emit as-is
        table.insert(parts, token.value)
      end
    elseif token.type == T.escape_hex then
      -- Hex escapes: \x7F, \x{0041}
      -- Pass through unchanged
      table.insert(parts, token.value)
    elseif token.type == T.escape_unicode then
      -- Unicode escapes: \u0041, \u{41}
      -- Pass through unchanged
      table.insert(parts, token.value)
    elseif token.type == T.escape_octal then
      -- Octal escapes: \0, \123
      -- Pass through unchanged
      table.insert(parts, token.value)
    elseif token.type == T.slash then
      -- Forward slash must be escaped in Vim search patterns
      table.insert(parts, '\\/')
    elseif token.type == T.dot then
      -- Dot passes through in regex mode
      table.insert(parts, '.')
    elseif token.type == T.anchor then
      -- Anchors (^ and $) pass through in regex mode
      table.insert(parts, token.value)
    elseif token.type == T.alternation then
      -- Alternation passes through in regex mode
      table.insert(parts, '|')
    else
      -- For now, unhandled token types (we'll add more as we go)
      -- This shouldn't happen with the current test suite
      table.insert(parts, token.value)
    end
  end

  -- Close word boundary if requested
  if opts.word then
    if opts.fixed then
      table.insert(parts, '\\>')
    else
      table.insert(parts, '>')
    end
  end

  return {
    pattern = table.concat(parts),
    warnings = warnings,
  }
end

return M
