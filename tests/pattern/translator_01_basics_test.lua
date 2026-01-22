-- tests/pattern/translator_basics_test.lua
-- Basic translator tests: mode prefixes, case, fixed strings.
--
-- The translator receives annotated tokens from the parser and emits Vim regex.
-- These tests cover fundamental operation: prefixes, modes, and basic options.
--
-- Run with:
--   nvim --headless -u NONE -c "set rtp+=." -c "luafile tests/pattern/translator_basics_test.lua"

local h = require('tests.harness')
local test = h.test
local eq = h.eq
local deep_eq = h.deep_eq
local types = require('brook.pattern.types')

local translator = require('brook.pattern.translator')

local translate = translator.translate

local T = types.token_type
local EC = types.escape_class
local W = types.wordness

--------------------------------------------------------------------------------
--- Empty input ----------------------------------------------------------------
--------------------------------------------------------------------------------

test('empty: empty token list produces \\v', function()
  local result = translate({}, {})
  eq(result.pattern, '\\v')
  deep_eq(result.warnings, {})
end)

test('empty: empty token list with fixed mode produces \\V', function()
  local result = translate({}, { fixed = true })
  eq(result.pattern, '\\V')
  deep_eq(result.warnings, {})
end)

--------------------------------------------------------------------------------
--- Case sensitivity -----------------------------------------------------------
--------------------------------------------------------------------------------

test('case: case-sensitive prefix', function()
  local result = translate({
    { type = T.literal, value = 'a', pos = 1, wordness = W.word },
  }, { case = 'case-sensitive' })
  eq(result.pattern, '\\C\\va')
end)

test('case: case-insensitive prefix', function()
  local result = translate({
    { type = T.literal, value = 'a', pos = 1, wordness = W.word },
  }, { case = 'case-insensitive' })
  eq(result.pattern, '\\c\\va')
end)

test('case: no case option means no case prefix', function()
  local result = translate({
    { type = T.literal, value = 'a', pos = 1, wordness = W.word },
  }, {})
  eq(result.pattern, '\\va')
end)

test('case: case-sensitive with fixed mode', function()
  local result = translate({
    { type = T.literal, value = 'a', pos = 1, wordness = W.word },
  }, { fixed = true, case = 'case-sensitive' })
  eq(result.pattern, '\\C\\Va')
end)

test('case: case-insensitive with fixed mode', function()
  local result = translate({
    { type = T.literal, value = 'a', pos = 1, wordness = W.word },
  }, { fixed = true, case = 'case-insensitive' })
  eq(result.pattern, '\\c\\Va')
end)

--------------------------------------------------------------------------------
--- Word boundary option -------------------------------------------------------
--------------------------------------------------------------------------------

test('word: word boundary in regex mode', function()
  local result = translate({
    { type = T.literal, value = 'f', pos = 1, wordness = W.word },
    { type = T.literal, value = 'o', pos = 2, wordness = W.word },
    { type = T.literal, value = 'o', pos = 3, wordness = W.word },
  }, { word = true })
  eq(result.pattern, '\\v<foo>')
end)

test('word: word boundary in fixed mode', function()
  local result = translate({
    { type = T.literal, value = 'f', pos = 1, wordness = W.word },
    { type = T.literal, value = 'o', pos = 2, wordness = W.word },
    { type = T.literal, value = 'o', pos = 3, wordness = W.word },
  }, { fixed = true, word = true })
  eq(result.pattern, '\\V\\<foo\\>')
end)

test('word: word boundary with case-sensitive', function()
  local result = translate({
    { type = T.literal, value = 'f', pos = 1, wordness = W.word },
    { type = T.literal, value = 'o', pos = 2, wordness = W.word },
    { type = T.literal, value = 'o', pos = 3, wordness = W.word },
  }, { word = true, case = 'case-sensitive' })
  eq(result.pattern, '\\C\\v<foo>')
end)

--------------------------------------------------------------------------------
--- Fixed string mode ----------------------------------------------------------
--------------------------------------------------------------------------------

test('fixed: simple literal', function()
  local result = translate({
    { type = T.literal, value = 'h', pos = 1, wordness = W.word },
    { type = T.literal, value = 'e', pos = 2, wordness = W.word },
    { type = T.literal, value = 'l', pos = 3, wordness = W.word },
    { type = T.literal, value = 'l', pos = 4, wordness = W.word },
    { type = T.literal, value = 'o', pos = 5, wordness = W.word },
  }, { fixed = true })
  eq(result.pattern, '\\Vhello')
end)

test('fixed: escapes backslashes', function()
  local result = translate({
    { type = T.literal,        value = 'f',    pos = 1, wordness = W.word },
    { type = T.literal,        value = 'o',    pos = 2, wordness = W.word },
    { type = T.literal,        value = 'o',    pos = 3, wordness = W.word },
    { type = T.escape_literal, value = '\\\\', pos = 4, escape_class = EC.escaped_literal, wordness = W.non_word },
    { type = T.literal,        value = 'b',    pos = 6, wordness = W.word },
    { type = T.literal,        value = 'a',    pos = 7, wordness = W.word },
    { type = T.literal,        value = 'r',    pos = 8, wordness = W.word },
  }, { fixed = true })
  eq(result.pattern, '\\Vfoo\\\\bar')
end)

test('fixed: escapes forward slashes', function()
  local result = translate({
    { type = T.literal, value = 'f', pos = 1, wordness = W.word },
    { type = T.literal, value = 'o', pos = 2, wordness = W.word },
    { type = T.literal, value = 'o', pos = 3, wordness = W.word },
    { type = T.slash,   value = '/', pos = 4, wordness = W.non_word },
    { type = T.literal, value = 'b', pos = 5, wordness = W.word },
    { type = T.literal, value = 'a', pos = 6, wordness = W.word },
    { type = T.literal, value = 'r', pos = 7, wordness = W.word },
  }, { fixed = true })
  eq(result.pattern, '\\Vfoo\\/bar')
end)

--------------------------------------------------------------------------------
--- Summary --------------------------------------------------------------------
--------------------------------------------------------------------------------

h.summary()
