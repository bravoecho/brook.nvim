-- tests/pattern/translator_complex_test.lua
-- Translator tests for complex, realistic patterns.
--
-- These tests verify the translator handles complete patterns correctly,
-- combining multiple features.
--
-- Run with:
--   nvim --headless -u NONE -c "set rtp+=." -c "luafile tests/pattern/translator_complex_test.lua"

local h = require('tests.harness')
local test = h.test
local eq = h.eq
local types = require('brook.pattern.types')

local translator = require('brook.pattern.translator')

local translate = translator.translate

local T = types.token_type
local CC = types.cc_token_type
local GK = types.group_kind
local EC = types.escape_class
local W = types.wordness

--------------------------------------------------------------------------------
--- Function call pattern ------------------------------------------------------
--------------------------------------------------------------------------------

test('complex: \\w+(.*) function call', function()
  local result = translate({
    { type = T.escape_class, value = '\\w', pos = 1, escape_class = EC.shorthand_word, wordness = W.word },
    { type = T.quantifier,   value = '+',   pos = 3, greedy = true,                    wordness = W.word },
    { type = T.group_open,   value = '(',   pos = 4, kind = GK.capturing,              wordness = W.non_word },
    { type = T.dot,          value = '.',   pos = 5, wordness = W.unknown },
    { type = T.quantifier,   value = '*',   pos = 6, greedy = true,                    wordness = W.unknown },
    { type = T.group_close,  value = ')',   pos = 7, wordness = W.non_word },
  }, {})
  eq(result.pattern, '\\v\\w+(.*)')
end)

--------------------------------------------------------------------------------
--- Email-like pattern ---------------------------------------------------------
--------------------------------------------------------------------------------

test('complex: [a-z]+@[a-z]+ email-like', function()
  local result = translate({
    { type = T.char_class_open,  value = '[',   pos = 1,  negated = false,      wordness = W.word },
    { type = CC.cc_range,        value = 'a-z', pos = 2,  from = 'a',           to = 'z' },
    { type = T.char_class_close, value = ']',   pos = 5 },
    { type = T.quantifier,       value = '+',   pos = 6,  greedy = true,        wordness = W.word },
    { type = T.literal,          value = '@',   pos = 7,  wordness = W.non_word },
    { type = T.char_class_open,  value = '[',   pos = 8,  negated = false,      wordness = W.word },
    { type = CC.cc_range,        value = 'a-z', pos = 9,  from = 'a',           to = 'z' },
    { type = T.char_class_close, value = ']',   pos = 12 },
    { type = T.quantifier,       value = '+',   pos = 13, greedy = true,        wordness = W.word },
  }, {})
  eq(result.pattern, '\\v[a-z]+\\@[a-z]+')
end)

--------------------------------------------------------------------------------
--- URL path pattern -----------------------------------------------------------
--------------------------------------------------------------------------------

test('complex: /api/v[0-9]+ URL path', function()
  local result = translate({
    { type = T.slash,            value = '/',   pos = 1,  wordness = W.non_word },
    { type = T.literal,          value = 'a',   pos = 2,  wordness = W.word },
    { type = T.literal,          value = 'p',   pos = 3,  wordness = W.word },
    { type = T.literal,          value = 'i',   pos = 4,  wordness = W.word },
    { type = T.slash,            value = '/',   pos = 5,  wordness = W.non_word },
    { type = T.literal,          value = 'v',   pos = 6,  wordness = W.word },
    { type = T.char_class_open,  value = '[',   pos = 7,  negated = false,      wordness = W.word },
    { type = CC.cc_range,        value = '0-9', pos = 8,  from = '0',           to = '9' },
    { type = T.char_class_close, value = ']',   pos = 11 },
    { type = T.quantifier,       value = '+',   pos = 12, greedy = true,        wordness = W.word },
  }, {})
  eq(result.pattern, '\\v\\/api\\/v[0-9]+')
end)

--------------------------------------------------------------------------------
--- Word boundary pattern ------------------------------------------------------
--------------------------------------------------------------------------------

test('complex: \\b\\w{3,5}\\b word with length constraint', function()
  local result = translate({
    { type = T.escape_boundary, value = '\\b',   pos = 1,  escape_class = EC.boundary,       prev_wordness = nil,    next_wordness = W.word },
    { type = T.escape_class,    value = '\\w',   pos = 3,  escape_class = EC.shorthand_word, wordness = W.word },
    { type = T.quantifier,      value = '{3,5}', pos = 5,  greedy = true,                    wordness = W.word },
    { type = T.escape_boundary, value = '\\b',   pos = 10, escape_class = EC.boundary,       prev_wordness = W.word, next_wordness = nil },
  }, {})
  eq(result.pattern, '\\v<\\w{3,5}>')
end)

--------------------------------------------------------------------------------
--- Quoted string non-greedy ---------------------------------------------------
--------------------------------------------------------------------------------

test('complex: "[^"]*?" quoted string', function()
  local result = translate({
    { type = T.literal,          value = '"',  pos = 1, wordness = W.non_word },
    { type = T.char_class_open,  value = '[^', pos = 2, negated = true,       wordness = W.unknown },
    { type = CC.cc_literal,      value = '"',  pos = 4 },
    { type = T.char_class_close, value = ']',  pos = 5 },
    { type = T.quantifier,       value = '*?', pos = 6, greedy = false,       wordness = W.unknown },
    { type = T.literal,          value = '"',  pos = 8, wordness = W.non_word },
  }, {})
  eq(result.pattern, '\\v"[^"]{-}"')
end)

--------------------------------------------------------------------------------
--- HTML tag non-greedy --------------------------------------------------------
--------------------------------------------------------------------------------

test('complex: <.*?> non-greedy HTML tag', function()
  local result = translate({
    { type = T.literal,    value = '<',  pos = 1, wordness = W.non_word },
    { type = T.dot,        value = '.',  pos = 2, wordness = W.unknown },
    { type = T.quantifier, value = '*?', pos = 3, greedy = false,       wordness = W.unknown },
    { type = T.literal,    value = '>',  pos = 5, wordness = W.non_word },
  }, {})
  eq(result.pattern, '\\v\\<.{-}\\>')
end)

--------------------------------------------------------------------------------
--- Comment pattern ------------------------------------------------------------
--------------------------------------------------------------------------------

test('complex: ^\\s*#.*$ comment line', function()
  local result = translate({
    { type = T.anchor,       value = '^',   pos = 1, wordness = W.non_word },
    { type = T.escape_class, value = '\\s', pos = 2, escape_class = EC.shorthand_nonword, wordness = W.non_word },
    { type = T.quantifier,   value = '*',   pos = 4, greedy = true,                       wordness = W.non_word },
    { type = T.literal,      value = '#',   pos = 5, wordness = W.non_word },
    { type = T.dot,          value = '.',   pos = 6, wordness = W.unknown },
    { type = T.quantifier,   value = '*',   pos = 7, greedy = true,                       wordness = W.unknown },
    { type = T.anchor,       value = '$',   pos = 8, wordness = W.non_word },
  }, {})
  eq(result.pattern, '\\v^\\s*#.*$')
end)

--------------------------------------------------------------------------------
--- Identifier pattern ---------------------------------------------------------
--------------------------------------------------------------------------------

test('complex: [a-zA-Z_][a-zA-Z0-9_]* identifier', function()
  local result = translate({
    { type = T.char_class_open,  value = '[',   pos = 1,  negated = false, wordness = W.word },
    { type = CC.cc_range,        value = 'a-z', pos = 2,  from = 'a',      to = 'z' },
    { type = CC.cc_range,        value = 'A-Z', pos = 5,  from = 'A',      to = 'Z' },
    { type = CC.cc_literal,      value = '_',   pos = 8 },
    { type = T.char_class_close, value = ']',   pos = 9 },
    { type = T.char_class_open,  value = '[',   pos = 10, negated = false, wordness = W.word },
    { type = CC.cc_range,        value = 'a-z', pos = 11, from = 'a',      to = 'z' },
    { type = CC.cc_range,        value = 'A-Z', pos = 14, from = 'A',      to = 'Z' },
    { type = CC.cc_range,        value = '0-9', pos = 17, from = '0',      to = '9' },
    { type = CC.cc_literal,      value = '_',   pos = 20 },
    { type = T.char_class_close, value = ']',   pos = 21 },
    { type = T.quantifier,       value = '*',   pos = 22, greedy = true,   wordness = W.word },
  }, {})
  eq(result.pattern, '\\v[a-zA-Z_][a-zA-Z0-9_]*')
end)

--------------------------------------------------------------------------------
--- Alternation pattern --------------------------------------------------------
--------------------------------------------------------------------------------

test('complex: (foo|bar|baz) alternation', function()
  local result = translate({
    { type = T.group_open,  value = '(', pos = 1,  kind = GK.capturing,  wordness = W.non_word },
    { type = T.literal,     value = 'f', pos = 2,  wordness = W.word },
    { type = T.literal,     value = 'o', pos = 3,  wordness = W.word },
    { type = T.literal,     value = 'o', pos = 4,  wordness = W.word },
    { type = T.alternation, value = '|', pos = 5,  wordness = W.non_word },
    { type = T.literal,     value = 'b', pos = 6,  wordness = W.word },
    { type = T.literal,     value = 'a', pos = 7,  wordness = W.word },
    { type = T.literal,     value = 'r', pos = 8,  wordness = W.word },
    { type = T.alternation, value = '|', pos = 9,  wordness = W.non_word },
    { type = T.literal,     value = 'b', pos = 10, wordness = W.word },
    { type = T.literal,     value = 'a', pos = 11, wordness = W.word },
    { type = T.literal,     value = 'z', pos = 12, wordness = W.word },
    { type = T.group_close, value = ')', pos = 13, wordness = W.non_word },
  }, {})
  eq(result.pattern, '\\v(foo|bar|baz)')
end)

--------------------------------------------------------------------------------
--- IP address pattern ---------------------------------------------------------
--------------------------------------------------------------------------------

test('complex: \\d{1,3}\\.\\d{1,3} partial IP', function()
  local result = translate({
    { type = T.escape_class,   value = '\\d',   pos = 1,  escape_class = EC.shorthand_word,  wordness = W.word },
    { type = T.quantifier,     value = '{1,3}', pos = 3,  greedy = true,                     wordness = W.word },
    { type = T.escape_literal, value = '\\.',   pos = 8,  escape_class = EC.escaped_literal, wordness = W.non_word },
    { type = T.escape_class,   value = '\\d',   pos = 10, escape_class = EC.shorthand_word,  wordness = W.word },
    { type = T.quantifier,     value = '{1,3}', pos = 12, greedy = true,                     wordness = W.word },
  }, {})
  eq(result.pattern, '\\v\\d{1,3}\\.\\d{1,3}')
end)

--------------------------------------------------------------------------------
--- Pattern with multiple warnings ---------------------------------------------
--------------------------------------------------------------------------------

test('complex: \\A(?P<n>x)\\z with three warnings', function()
  local result = translate({
    { type = T.escape_boundary, value = '\\A',    pos = 1,  escape_class = EC.anchor_start, wordness = W.non_word },
    { type = T.group_open,      value = '(?P<n>', pos = 3,  kind = GK.named_python,         name = 'n',           wordness = W.non_word },
    { type = T.literal,         value = 'x',      pos = 9,  wordness = W.word },
    { type = T.group_close,     value = ')',      pos = 10, wordness = W.non_word },
    { type = T.escape_boundary, value = '\\z',    pos = 11, escape_class = EC.anchor_end,   wordness = W.non_word },
  }, {})
  eq(result.pattern, '\\v^(x)$')
  eq(#result.warnings, 3)
  eq(result.warnings[1], '\\A treated as ^')
  eq(result.warnings[2], 'named groups become numbered')
  eq(result.warnings[3], '\\z treated as $')
end)

--------------------------------------------------------------------------------
--- Edge cases: metacharacters as literals -------------------------------------
--------------------------------------------------------------------------------

test('complex: +?| literal metacharacters', function()
  local result = translate({
    { type = T.literal,     value = '+', pos = 1, wordness = W.non_word },
    { type = T.literal,     value = '?', pos = 2, wordness = W.non_word },
    { type = T.alternation, value = '|', pos = 3, wordness = W.non_word },
  }, {})
  eq(result.pattern, '\\v+?|')
end)

--------------------------------------------------------------------------------
--- Summary --------------------------------------------------------------------
--------------------------------------------------------------------------------

h.summary()
