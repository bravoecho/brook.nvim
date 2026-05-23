-- tests/pattern/tokenise_escapes_test.lua

-- Run with:
--   nvim --headless -u NONE -c "set rtp+=." -c "luafile tests/pattern/tokeniser_03_escapes_test.lua" -c "q"

local h = require('tests.harness')
local test = h.test
local deep_eq = h.deep_eq

local tokeniser = require('brook.pattern.tokeniser')

local types = require('brook.pattern.types')
local T = types.token_type

local tokenise = tokeniser.tokenise

--------------------------------------------------------------------------------
-- Escape sequences: boundaries ------------------------------------------------
--------------------------------------------------------------------------------

test('escape boundary: word boundary', function()
  deep_eq(tokenise('\\ba\\b'), {
    { type = T.escape_boundary, value = '\\b', pos = 1, boundary_kind = 'word' },
    { type = T.literal,         value = 'a',   pos = 3 },
    { type = T.escape_boundary, value = '\\b', pos = 4, boundary_kind = 'word' },
  })
end)

test('escape boundary: negated word boundary', function()
  deep_eq(tokenise('\\B'), {
    { type = T.escape_boundary, value = '\\B', pos = 1, boundary_kind = 'word_neg' },
  })
end)

test('escape boundary: start of string', function()
  deep_eq(tokenise('\\Aa'), {
    { type = T.escape_boundary, value = '\\A', pos = 1, boundary_kind = 'start' },
    { type = T.literal,         value = 'a',   pos = 3 },
  })
end)

test('escape boundary: end of string', function()
  deep_eq(tokenise('a\\z'), {
    { type = T.literal,         value = 'a',   pos = 1 },
    { type = T.escape_boundary, value = '\\z', pos = 2, boundary_kind = 'end' },
  })
end)

test('escape boundary: start-of-word', function()
  deep_eq(tokenise('\\<a'), {
    { type = T.escape_boundary, value = '\\<', pos = 1, boundary_kind = 'word_start' },
    { type = T.literal,         value = 'a',   pos = 3 },
  })
end)

test('escape boundary: end-of-word', function()
  deep_eq(tokenise('a\\>'), {
    { type = T.literal,         value = 'a',   pos = 1 },
    { type = T.escape_boundary, value = '\\>', pos = 2, boundary_kind = 'word_end' },
  })
end)

test('escape boundary: extended word start', function()
  deep_eq(tokenise('\\b{start}'), {
    { type = T.escape_boundary, value = '\\b{start}', pos = 1, boundary_kind = 'word_start' },
  })
end)

test('escape boundary: extended word end', function()
  deep_eq(tokenise('\\b{end}'), {
    { type = T.escape_boundary, value = '\\b{end}', pos = 1, boundary_kind = 'word_end' },
  })
end)

test('escape boundary: extended word start-half', function()
  deep_eq(tokenise('\\b{start-half}'), {
    { type = T.escape_boundary, value = '\\b{start-half}', pos = 1, boundary_kind = 'word_start_half' },
  })
end)

test('escape boundary: extended word end-half', function()
  deep_eq(tokenise('\\b{end-half}'), {
    { type = T.escape_boundary, value = '\\b{end-half}', pos = 1, boundary_kind = 'word_end_half' },
  })
end)

--------------------------------------------------------------------------------
-- Escape sequences: character classes -----------------------------------------
--------------------------------------------------------------------------------

test('escape class: digit', function()
  deep_eq(tokenise('\\d'), {
    { type = T.escape_class, value = '\\d', pos = 1 },
  })
end)

test('escape class: non-digit', function()
  deep_eq(tokenise('\\D'), {
    { type = T.escape_class, value = '\\D', pos = 1 },
  })
end)

test('escape class: word', function()
  deep_eq(tokenise('\\w'), {
    { type = T.escape_class, value = '\\w', pos = 1 },
  })
end)

test('escape class: non-word', function()
  deep_eq(tokenise('\\W'), {
    { type = T.escape_class, value = '\\W', pos = 1 },
  })
end)

test('escape class: whitespace', function()
  deep_eq(tokenise('\\s'), {
    { type = T.escape_class, value = '\\s', pos = 1 },
  })
end)

test('escape class: non-whitespace', function()
  deep_eq(tokenise('\\S'), {
    { type = T.escape_class, value = '\\S', pos = 1 },
  })
end)

test('escape class: horizontal whitespace', function()
  deep_eq(tokenise('\\h'), {
    { type = T.escape_class, value = '\\h', pos = 1 },
  })
end)

test('escape class: non-horizontal whitespace', function()
  deep_eq(tokenise('\\H'), {
    { type = T.escape_class, value = '\\H', pos = 1 },
  })
end)

test('escape class: vertical whitespace', function()
  deep_eq(tokenise('\\v'), {
    { type = T.escape_class, value = '\\v', pos = 1 },
  })
end)

test('escape class: non-vertical whitespace', function()
  deep_eq(tokenise('\\V'), {
    { type = T.escape_class, value = '\\V', pos = 1 },
  })
end)

--------------------------------------------------------------------------------
-- Escape sequences: literals --------------------------------------------------
--------------------------------------------------------------------------------

test('escape literal: newline', function()
  deep_eq(tokenise('\\n'), {
    { type = T.escape_literal, value = '\\n', pos = 1 },
  })
end)

test('escape literal: tab', function()
  deep_eq(tokenise('\\t'), {
    { type = T.escape_literal, value = '\\t', pos = 1 },
  })
end)

test('escape literal: carriage return', function()
  deep_eq(tokenise('\\r'), {
    { type = T.escape_literal, value = '\\r', pos = 1 },
  })
end)

test('escape literal: form feed', function()
  deep_eq(tokenise('\\f'), {
    { type = T.escape_literal, value = '\\f', pos = 1 },
  })
end)

test('escape literal: bell', function()
  deep_eq(tokenise('\\a'), {
    { type = T.escape_literal, value = '\\a', pos = 1 },
  })
end)

test('escape literal: escape character', function()
  deep_eq(tokenise('\\e'), {
    { type = T.escape_literal, value = '\\e', pos = 1 },
  })
end)

test('escape literal: backslash', function()
  deep_eq(tokenise('\\\\'), {
    { type = T.escape_literal, value = '\\\\', pos = 1 },
  })
end)

test('escape literal: backslash between words', function()
  deep_eq(tokenise('foo\\bar'), {
    { type = T.literal,         value = 'f',   pos = 1 },
    { type = T.literal,         value = 'o',   pos = 2 },
    { type = T.literal,         value = 'o',   pos = 3 },
    { type = T.escape_boundary, value = '\\b', pos = 4, boundary_kind = 'word' },
    { type = T.literal,         value = 'a',   pos = 6 },
    { type = T.literal,         value = 'r',   pos = 7 },
  })
end)

test('escape literal: dot', function()
  deep_eq(tokenise('\\.'), {
    { type = T.escape_literal, value = '\\.', pos = 1 },
  })
end)

test('escape literal: star', function()
  deep_eq(tokenise('\\*'), {
    { type = T.escape_literal, value = '\\*', pos = 1 },
  })
end)

test('escape literal: plus', function()
  deep_eq(tokenise('\\+'), {
    { type = T.escape_literal, value = '\\+', pos = 1 },
  })
end)

test('escape literal: question', function()
  deep_eq(tokenise('\\?'), {
    { type = T.escape_literal, value = '\\?', pos = 1 },
  })
end)

test('escape literal: caret', function()
  deep_eq(tokenise('\\^'), {
    { type = T.escape_literal, value = '\\^', pos = 1 },
  })
end)

test('escape literal: dollar', function()
  deep_eq(tokenise('\\$'), {
    { type = T.escape_literal, value = '\\$', pos = 1 },
  })
end)

test('escape literal: pipe', function()
  deep_eq(tokenise('\\|'), {
    { type = T.escape_literal, value = '\\|', pos = 1 },
  })
end)

test('escape literal: open paren', function()
  deep_eq(tokenise('\\('), {
    { type = T.escape_literal, value = '\\(', pos = 1 },
  })
end)

test('escape literal: close paren', function()
  deep_eq(tokenise('\\)'), {
    { type = T.escape_literal, value = '\\)', pos = 1 },
  })
end)

test('escape literal: open bracket', function()
  deep_eq(tokenise('\\['), {
    { type = T.escape_literal, value = '\\[', pos = 1 },
  })
end)

test('escape literal: close bracket', function()
  deep_eq(tokenise('\\]'), {
    { type = T.escape_literal, value = '\\]', pos = 1 },
  })
end)

test('escape literal: open brace', function()
  deep_eq(tokenise('\\{'), {
    { type = T.escape_literal, value = '\\{', pos = 1 },
  })
end)

test('escape literal: close brace', function()
  deep_eq(tokenise('\\}'), {
    { type = T.escape_literal, value = '\\}', pos = 1 },
  })
end)

test('escape literal: slash', function()
  deep_eq(tokenise('\\/'), {
    { type = T.escape_literal, value = '\\/', pos = 1 },
  })
end)

--------------------------------------------------------------------------------
-- Escape sequences: hex -------------------------------------------------------
--------------------------------------------------------------------------------

test('escape hex: two-digit', function()
  deep_eq(tokenise('\\x7F'), {
    { type = T.escape_hex, value = '\\x7F', pos = 1 },
  })
end)

test('escape hex: braced', function()
  deep_eq(tokenise('\\x{10FFFF}'), {
    { type = T.escape_hex, value = '\\x{10FFFF}', pos = 1 },
  })
end)

test('escape hex: short braced', function()
  deep_eq(tokenise('\\x{A}'), {
    { type = T.escape_hex, value = '\\x{A}', pos = 1 },
  })
end)

--------------------------------------------------------------------------------
-- Escape sequences: unicode ---------------------------------------------------
--------------------------------------------------------------------------------

test('escape unicode: four-digit', function()
  deep_eq(tokenise('\\u007F'), {
    { type = T.escape_unicode, value = '\\u007F', pos = 1 },
  })
end)

test('escape unicode: braced lowercase', function()
  deep_eq(tokenise('\\u{7F}'), {
    { type = T.escape_unicode, value = '\\u{7F}', pos = 1 },
  })
end)

test('escape unicode: eight-digit', function()
  deep_eq(tokenise('\\U0000007F'), {
    { type = T.escape_unicode, value = '\\U0000007F', pos = 1 },
  })
end)

test('escape unicode: braced uppercase', function()
  deep_eq(tokenise('\\U{7F}'), {
    { type = T.escape_unicode, value = '\\U{7F}', pos = 1 },
  })
end)

--------------------------------------------------------------------------------
-- Escape sequences: octal -----------------------------------------------------
--------------------------------------------------------------------------------

test('escape octal: single digit', function()
  deep_eq(tokenise('\\0'), {
    { type = T.escape_octal, value = '\\0', pos = 1 },
  })
end)

test('escape octal: two digit', function()
  deep_eq(tokenise('\\00'), {
    { type = T.escape_octal, value = '\\00', pos = 1 },
  })
end)

test('escape octal: three digit', function()
  deep_eq(tokenise('\\123'), {
    { type = T.escape_octal, value = '\\123', pos = 1 },
  })
end)

test('escape octal: max three digits', function()
  -- \\1234 should be \\123 followed by literal 4
  deep_eq(tokenise('\\1234'), {
    { type = T.escape_octal, value = '\\123', pos = 1 },
    { type = T.literal,      value = '4',     pos = 5 },
  })
end)

test('escape octal: braced', function()
  deep_eq(tokenise('\\o{177}'), {
    { type = T.escape_octal, value = '\\o{177}', pos = 1 },
  })
end)

test('escape octal: short braced', function()
  deep_eq(tokenise('\\o{0}'), {
    { type = T.escape_octal, value = '\\o{0}', pos = 1 },
  })
end)

--------------------------------------------------------------------------------
-- Escape sequences: unicode properties ----------------------------------------
--------------------------------------------------------------------------------

test('escape property: simple', function()
  deep_eq(tokenise('\\p{L}'), {
    { type = T.escape_property, value = '\\p{L}', negated = false, pos = 1 },
  })
end)

test('escape property: negated', function()
  deep_eq(tokenise('\\P{L}'), {
    { type = T.escape_property, value = '\\P{L}', negated = true, pos = 1 },
  })
end)

test('escape property: long name', function()
  deep_eq(tokenise('\\p{Letter}'), {
    { type = T.escape_property, value = '\\p{Letter}', negated = false, pos = 1 },
  })
end)

test('escape property: script', function()
  deep_eq(tokenise('\\p{Greek}'), {
    { type = T.escape_property, value = '\\p{Greek}', negated = false, pos = 1 },
  })
end)

test('escape property: with value', function()
  deep_eq(tokenise('\\p{Script=Greek}'), {
    { type = T.escape_property, value = '\\p{Script=Greek}', negated = false, pos = 1 },
  })
end)

test('escape property: negated with value', function()
  deep_eq(tokenise('\\P{Script=Latin}'), {
    { type = T.escape_property, value = '\\P{Script=Latin}', negated = true, pos = 1 },
  })
end)

--------------------------------------------------------------------------------
-- Escape sequences: backreferences --------------------------------------------
--------------------------------------------------------------------------------

test('escape backref: single digit', function()
  deep_eq(tokenise('\\1'), {
    { type = T.escape_backref, value = '\\1', pos = 1 },
  })
end)

test('escape backref: digit 9', function()
  deep_eq(tokenise('\\9'), {
    { type = T.escape_backref, value = '\\9', pos = 1 },
  })
end)

-- NOTE: \\10 and above are ambiguous with octal; tokeniser picks octal.
-- This matches rust regex behaviour where backrefs are 1-9 only.

--------------------------------------------------------------------------------
-- Forward slash ---------------------------------------------------------------
--------------------------------------------------------------------------------

test('slash: standalone', function()
  deep_eq(tokenise('/'), {
    { type = T.slash, value = '/', pos = 1 },
  })
end)

test('slash: in pattern', function()
  deep_eq(tokenise('a/b'), {
    { type = T.literal, value = 'a', pos = 1 },
    { type = T.slash,   value = '/', pos = 2 },
    { type = T.literal, value = 'b', pos = 3 },
  })
end)

--------------------------------------------------------------------------------
-- Summary ---------------------------------------------------------------------
--------------------------------------------------------------------------------

h.summary()
