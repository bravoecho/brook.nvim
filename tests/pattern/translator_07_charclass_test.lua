-- tests/pattern/translator_charclass_test.lua
-- Translator tests for character classes.
--
-- Character class contents pass through mostly unchanged. Forward slash needs
-- escaping inside classes. Vim-special chars do not need escaping inside.
--
-- Run with:
--   nvim --headless -u NONE -c "set rtp+=." -c "luafile tests/pattern/translator_charclass_test.lua"

local h = require('tests.harness')
local test = h.test
local eq = h.eq
local types = require('brook.pattern.types')

local translator = require('brook.pattern.translator')

local translate = translator.translate

--- Helper to get full pattern from translator result.
---@param result brook.pattern.TranslatorResult
---@return string
local function pattern(result)
  return result.prefix .. result.body
end

local T = types.token_type
local CC = types.cc_token_type
local W = types.wordness

--------------------------------------------------------------------------------
--- Basic character classes ----------------------------------------------------
--------------------------------------------------------------------------------

test('class: simple [abc]', function()
  local result = translate({
    { type = T.char_class_open,  value = '[', pos = 1, negated = false, wordness = W.word },
    { type = CC.cc_literal,      value = 'a', pos = 2 },
    { type = CC.cc_literal,      value = 'b', pos = 3 },
    { type = CC.cc_literal,      value = 'c', pos = 4 },
    { type = T.char_class_close, value = ']', pos = 5 },
  }, {})
  eq(pattern(result), '\\v[abc]')
end)

test('class: negated [^abc]', function()
  local result = translate({
    { type = T.char_class_open,  value = '[^', pos = 1, negated = true, wordness = W.unknown },
    { type = CC.cc_literal,      value = 'a',  pos = 3 },
    { type = CC.cc_literal,      value = 'b',  pos = 4 },
    { type = CC.cc_literal,      value = 'c',  pos = 5 },
    { type = T.char_class_close, value = ']',  pos = 6 },
  }, {})
  eq(pattern(result), '\\v[^abc]')
end)

--------------------------------------------------------------------------------
--- Ranges ---------------------------------------------------------------------
--------------------------------------------------------------------------------

test('class: range [a-z]', function()
  local result = translate({
    { type = T.char_class_open,  value = '[',   pos = 1, negated = false, wordness = W.word },
    { type = CC.cc_range,        value = 'a-z', pos = 2, from = 'a',      to = 'z' },
    { type = T.char_class_close, value = ']',   pos = 5 },
  }, {})
  eq(pattern(result), '\\v[a-z]')
end)

test('class: multiple ranges [a-zA-Z0-9]', function()
  local result = translate({
    { type = T.char_class_open,  value = '[',   pos = 1, negated = false, wordness = W.word },
    { type = CC.cc_range,        value = 'a-z', pos = 2, from = 'a',      to = 'z' },
    { type = CC.cc_range,        value = 'A-Z', pos = 5, from = 'A',      to = 'Z' },
    { type = CC.cc_range,        value = '0-9', pos = 8, from = '0',      to = '9' },
    { type = T.char_class_close, value = ']',   pos = 11 },
  }, {})
  eq(pattern(result), '\\v[a-zA-Z0-9]')
end)

test('class: range with underscore [a-zA-Z0-9_]', function()
  local result = translate({
    { type = T.char_class_open,  value = '[',   pos = 1, negated = false, wordness = W.word },
    { type = CC.cc_range,        value = 'a-z', pos = 2, from = 'a',      to = 'z' },
    { type = CC.cc_range,        value = 'A-Z', pos = 5, from = 'A',      to = 'Z' },
    { type = CC.cc_range,        value = '0-9', pos = 8, from = '0',      to = '9' },
    { type = CC.cc_literal,      value = '_',   pos = 11 },
    { type = T.char_class_close, value = ']',   pos = 12 },
  }, {})
  eq(pattern(result), '\\v[a-zA-Z0-9_]')
end)

--------------------------------------------------------------------------------
--- Special characters inside classes ------------------------------------------
--------------------------------------------------------------------------------

test('class: ] as first char', function()
  local result = translate({
    { type = T.char_class_open,  value = '[', pos = 1, negated = false, wordness = W.unknown },
    { type = CC.cc_literal,      value = ']', pos = 2 },
    { type = CC.cc_literal,      value = 'a', pos = 3 },
    { type = CC.cc_literal,      value = 'b', pos = 4 },
    { type = CC.cc_literal,      value = 'c', pos = 5 },
    { type = T.char_class_close, value = ']', pos = 6 },
  }, {})
  eq(pattern(result), '\\v[]abc]')
end)

test('class: vim-special chars do not need escaping inside', function()
  local result = translate({
    { type = T.char_class_open,  value = '[', pos = 1, negated = false, wordness = W.non_word },
    { type = CC.cc_literal,      value = '~', pos = 2 },
    { type = CC.cc_literal,      value = '=', pos = 3 },
    { type = CC.cc_literal,      value = '@', pos = 4 },
    { type = CC.cc_literal,      value = '&', pos = 5 },
    { type = CC.cc_literal,      value = '<', pos = 6 },
    { type = CC.cc_literal,      value = '>', pos = 7 },
    { type = T.char_class_close, value = ']', pos = 8 },
  }, {})
  eq(pattern(result), '\\v[~=@&<>]')
end)

test('class: forward slash needs escaping inside', function()
  local result = translate({
    { type = T.char_class_open,  value = '[', pos = 1, negated = false, wordness = W.non_word },
    { type = CC.cc_literal,      value = '/', pos = 2 },
    { type = T.char_class_close, value = ']', pos = 3 },
  }, {})
  eq(pattern(result), '\\v[\\/]')
end)

test('class: multiple slashes inside', function()
  local result = translate({
    { type = T.char_class_open,  value = '[', pos = 1, negated = false, wordness = W.non_word },
    { type = CC.cc_literal,      value = 'a', pos = 2 },
    { type = CC.cc_literal,      value = '/', pos = 3 },
    { type = CC.cc_literal,      value = 'b', pos = 4 },
    { type = T.char_class_close, value = ']', pos = 5 },
  }, {})
  eq(pattern(result), '\\v[a\\/b]')
end)

--------------------------------------------------------------------------------
--- Escape sequences inside classes --------------------------------------------
--------------------------------------------------------------------------------

test('class: shorthands [\\d\\w] pass through', function()
  local result = translate({
    { type = T.char_class_open,  value = '[',   pos = 1, negated = false, wordness = W.word },
    { type = CC.cc_escape_class, value = '\\d', pos = 2 },
    { type = CC.cc_escape_class, value = '\\w', pos = 4 },
    { type = T.char_class_close, value = ']',   pos = 6 },
  }, {})
  eq(pattern(result), '\\v[\\d\\w]')
end)

test('class: escaped literals [\\]\\\\] pass through', function()
  local result = translate({
    { type = T.char_class_open,    value = '[',    pos = 1, negated = false, wordness = W.non_word },
    { type = CC.cc_escape_literal, value = '\\]',  pos = 2 },
    { type = CC.cc_escape_literal, value = '\\\\', pos = 4 },
    { type = T.char_class_close,   value = ']',    pos = 6 },
  }, {})
  eq(pattern(result), '\\v[\\]\\\\]')
end)

test('class: \\b inside is literal b', function()
  local result = translate({
    { type = T.char_class_open,    value = '[',   pos = 1, negated = false, wordness = W.word },
    { type = CC.cc_escape_literal, value = '\\b', pos = 2 },
    { type = T.char_class_close,   value = ']',   pos = 4 },
  }, {})
  eq(pattern(result), '\\v[\\b]')
end)

test('class: hex escape [\\x41] passes through', function()
  local result = translate({
    { type = T.char_class_open,  value = '[',     pos = 1, negated = false, wordness = W.word },
    { type = CC.cc_escape_hex,   value = '\\x41', pos = 2 },
    { type = T.char_class_close, value = ']',     pos = 6 },
  }, {})
  eq(pattern(result), '\\v[\\x41]')
end)

--------------------------------------------------------------------------------
--- POSIX classes --------------------------------------------------------------
--------------------------------------------------------------------------------

test('class: POSIX [:alpha:] passes through', function()
  local result = translate({
    { type = T.char_class_open,  value = '[',         pos = 1, negated = false,      wordness = W.word },
    { type = CC.cc_posix,        value = '[:alpha:]', pos = 2, class_name = 'alpha', negated = false },
    { type = T.char_class_close, value = ']',         pos = 11 },
  }, {})
  eq(pattern(result), '\\v[[:alpha:]]')
end)

test('class: negated POSIX [:^digit:] passes through', function()
  local result = translate({
    { type = T.char_class_open,  value = '[',          pos = 1, negated = false,      wordness = W.unknown },
    { type = CC.cc_posix,        value = '[:^digit:]', pos = 2, class_name = 'digit', negated = true },
    { type = T.char_class_close, value = ']',          pos = 12 },
  }, {})
  eq(pattern(result), '\\v[[:^digit:]]')
end)

--------------------------------------------------------------------------------
--- Set operations (intersection, nesting) -------------------------------------
--------------------------------------------------------------------------------

test('class: intersection [a-z&&[^aeiou]]', function()
  local result = translate({
    { type = T.char_class_open,  value = '[',   pos = 1, negated = false, wordness = W.word },
    { type = CC.cc_range,        value = 'a-z', pos = 2, from = 'a',      to = 'z' },
    { type = CC.cc_intersection, value = '&&',  pos = 5 },
    { type = CC.cc_nested_open,  value = '[',   pos = 7, negated = true },
    { type = CC.cc_literal,      value = 'a',   pos = 9 },
    { type = CC.cc_literal,      value = 'e',   pos = 10 },
    { type = CC.cc_literal,      value = 'i',   pos = 11 },
    { type = CC.cc_literal,      value = 'o',   pos = 12 },
    { type = CC.cc_literal,      value = 'u',   pos = 13 },
    { type = CC.cc_nested_close, value = ']',   pos = 14 },
    { type = T.char_class_close, value = ']',   pos = 15 },
  }, {})
  eq(pattern(result), '\\v[a-z&&[aeiou]]')
end)

--------------------------------------------------------------------------------
--- Character classes with quantifiers -----------------------------------------
--------------------------------------------------------------------------------

test('class: [a-z]+ with quantifier', function()
  local result = translate({
    { type = T.char_class_open,  value = '[',   pos = 1, negated = false, wordness = W.word },
    { type = CC.cc_range,        value = 'a-z', pos = 2, from = 'a',      to = 'z' },
    { type = T.char_class_close, value = ']',   pos = 5 },
    { type = T.quantifier,       value = '+',   pos = 6, greedy = true,   wordness = W.word },
  }, {})
  eq(pattern(result), '\\v[a-z]+')
end)

test('class: [^"]* non-greedy', function()
  local result = translate({
    { type = T.char_class_open,  value = '[^', pos = 1, negated = true, wordness = W.unknown },
    { type = CC.cc_literal,      value = '"',  pos = 3 },
    { type = T.char_class_close, value = ']',  pos = 4 },
    { type = T.quantifier,       value = '*?', pos = 5, greedy = false, wordness = W.unknown },
  }, {})
  eq(pattern(result), '\\v[^"]{-}')
end)

--------------------------------------------------------------------------------
--- Edge cases -----------------------------------------------------------------
--------------------------------------------------------------------------------

test('class: unclosed bracket (graceful handling)', function()
  local result = translate({
    { type = T.char_class_open, value = '[', pos = 1, negated = false, wordness = W.word },
    { type = CC.cc_literal,     value = 'a', pos = 2 },
    { type = CC.cc_literal,     value = 'b', pos = 3 },
    { type = CC.cc_literal,     value = 'c', pos = 4 },
  }, {})
  eq(pattern(result), '\\v[abc')
end)

test('class: empty class []', function()
  local result = translate({
    { type = T.char_class_open,  value = '[', pos = 1, negated = false, wordness = W.unknown },
    { type = T.char_class_close, value = ']', pos = 2 },
  }, {})
  eq(pattern(result), '\\v[]')
end)

--------------------------------------------------------------------------------
--- Summary --------------------------------------------------------------------
--------------------------------------------------------------------------------

h.summary()
