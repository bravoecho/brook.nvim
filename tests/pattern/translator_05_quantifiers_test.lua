-- tests/pattern/translator_quantifiers_test.lua
-- Translator tests for quantifiers.
--
-- Greedy quantifiers pass through; non-greedy use Vim's {-} syntax.
--
-- Run with:
--   nvim --headless -u NONE -c "set rtp+=." -c "luafile tests/pattern/translator_quantifiers_test.lua"

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
local EC = types.escape_class
local W = types.wordness

--------------------------------------------------------------------------------
--- Greedy quantifiers: pass through -------------------------------------------
--------------------------------------------------------------------------------

test('quantifier: * passes through', function()
  local result = translate({
    { type = T.literal,    value = 'a', pos = 1, wordness = W.word },
    { type = T.quantifier, value = '*', pos = 2, greedy = true,    wordness = W.word },
  }, {})
  eq(pattern(result), '\\va*')
end)

test('quantifier: + passes through', function()
  local result = translate({
    { type = T.literal,    value = 'a', pos = 1, wordness = W.word },
    { type = T.quantifier, value = '+', pos = 2, greedy = true,    wordness = W.word },
  }, {})
  eq(pattern(result), '\\va+')
end)

test('quantifier: ? passes through', function()
  local result = translate({
    { type = T.literal,    value = 'a', pos = 1, wordness = W.word },
    { type = T.quantifier, value = '?', pos = 2, greedy = true,    wordness = W.word },
  }, {})
  eq(pattern(result), '\\va?')
end)

test('quantifier: {n} passes through', function()
  local result = translate({
    { type = T.literal,    value = 'a',   pos = 1, wordness = W.word },
    { type = T.quantifier, value = '{3}', pos = 2, greedy = true,    wordness = W.word },
  }, {})
  eq(pattern(result), '\\va{3}')
end)

test('quantifier: {n,} passes through', function()
  local result = translate({
    { type = T.literal,    value = 'a',    pos = 1, wordness = W.word },
    { type = T.quantifier, value = '{2,}', pos = 2, greedy = true,    wordness = W.word },
  }, {})
  eq(pattern(result), '\\va{2,}')
end)

test('quantifier: {n,m} passes through', function()
  local result = translate({
    { type = T.literal,    value = 'a',     pos = 1, wordness = W.word },
    { type = T.quantifier, value = '{2,5}', pos = 2, greedy = true,    wordness = W.word },
  }, {})
  eq(pattern(result), '\\va{2,5}')
end)

--------------------------------------------------------------------------------
--- Non-greedy quantifiers: {-} syntax -----------------------------------------
--------------------------------------------------------------------------------

test('quantifier: *? becomes {-}', function()
  local result = translate({
    { type = T.literal,    value = 'a',  pos = 1, wordness = W.word },
    { type = T.quantifier, value = '*?', pos = 2, greedy = false,   wordness = W.word },
  }, {})
  eq(pattern(result), '\\va{-}')
end)

test('quantifier: +? becomes {-1,}', function()
  local result = translate({
    { type = T.literal,    value = 'a',  pos = 1, wordness = W.word },
    { type = T.quantifier, value = '+?', pos = 2, greedy = false,   wordness = W.word },
  }, {})
  eq(pattern(result), '\\va{-1,}')
end)

test('quantifier: ?? becomes {-0,1}', function()
  local result = translate({
    { type = T.literal,    value = 'a',  pos = 1, wordness = W.word },
    { type = T.quantifier, value = '??', pos = 2, greedy = false,   wordness = W.word },
  }, {})
  eq(pattern(result), '\\va{-0,1}')
end)

test('quantifier: {n}? becomes {-n}', function()
  local result = translate({
    { type = T.literal,    value = 'a',    pos = 1, wordness = W.word },
    { type = T.quantifier, value = '{3}?', pos = 2, greedy = false,   wordness = W.word },
  }, {})
  eq(pattern(result), '\\va{-3}')
end)

test('quantifier: {n,}? becomes {-n,}', function()
  local result = translate({
    { type = T.literal,    value = 'a',     pos = 1, wordness = W.word },
    { type = T.quantifier, value = '{2,}?', pos = 2, greedy = false,   wordness = W.word },
  }, {})
  eq(pattern(result), '\\va{-2,}')
end)

test('quantifier: {n,m}? becomes {-n,m}', function()
  local result = translate({
    { type = T.literal,    value = 'a',      pos = 1, wordness = W.word },
    { type = T.quantifier, value = '{2,5}?', pos = 2, greedy = false,   wordness = W.word },
  }, {})
  eq(pattern(result), '\\va{-2,5}')
end)

--------------------------------------------------------------------------------
--- Quantifiers with different atoms -------------------------------------------
--------------------------------------------------------------------------------

test('quantifier: after dot', function()
  local result = translate({
    { type = T.dot,        value = '.', pos = 1, wordness = W.unknown },
    { type = T.quantifier, value = '*', pos = 2, greedy = true,       wordness = W.unknown },
  }, {})
  eq(pattern(result), '\\v.*')
end)

test('quantifier: after escape class', function()
  local result = translate({
    { type = T.escape_class, value = '\\w', pos = 1, escape_class = EC.shorthand_word, wordness = W.word },
    { type = T.quantifier,   value = '+',   pos = 3, greedy = true,                    wordness = W.word },
  }, {})
  eq(pattern(result), '\\v\\w+')
end)

test('quantifier: non-greedy after dot', function()
  local result = translate({
    { type = T.dot,        value = '.',  pos = 1, wordness = W.unknown },
    { type = T.quantifier, value = '*?', pos = 2, greedy = false,      wordness = W.unknown },
  }, {})
  eq(pattern(result), '\\v.{-}')
end)

--------------------------------------------------------------------------------
--- Complex quantifier patterns ------------------------------------------------
--------------------------------------------------------------------------------

test('quantifier: IP-like pattern', function()
  local result = translate({
    { type = T.escape_class,   value = '\\d',   pos = 1,  escape_class = EC.shorthand_word,  wordness = W.word },
    { type = T.quantifier,     value = '{1,3}', pos = 3,  greedy = true,                     wordness = W.word },
    { type = T.escape_literal, value = '\\.',   pos = 8,  escape_class = EC.escaped_literal, wordness = W.non_word },
    { type = T.escape_class,   value = '\\d',   pos = 10, escape_class = EC.shorthand_word,  wordness = W.word },
    { type = T.quantifier,     value = '{1,3}', pos = 12, greedy = true,                     wordness = W.word },
  }, {})
  eq(pattern(result), '\\v\\d{1,3}\\.\\d{1,3}')
end)

--------------------------------------------------------------------------------
--- Summary --------------------------------------------------------------------
--------------------------------------------------------------------------------

h.summary()
