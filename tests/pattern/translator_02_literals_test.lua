-- tests/pattern/translator_literals_test.lua
-- Translator tests for literals, vim-special characters, and basic metacharacters.
--
-- These tests verify correct handling of literal characters and characters that
-- need escaping in Vim's very magic mode.
--
-- Run with:
--   nvim --headless -u NONE -c "set rtp+=." -c "luafile tests/pattern/translator_literals_test.lua"

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
local W = types.wordness

--------------------------------------------------------------------------------
--- Literals: pass through -----------------------------------------------------
--------------------------------------------------------------------------------

test('literal: single letter', function()
  local result = translate({
    { type = T.literal, value = 'a', pos = 1, wordness = W.word },
  }, {})
  eq(pattern(result), '\\va')
end)

test('literal: multiple letters', function()
  local result = translate({
    { type = T.literal, value = 'a', pos = 1, wordness = W.word },
    { type = T.literal, value = 'b', pos = 2, wordness = W.word },
    { type = T.literal, value = 'c', pos = 3, wordness = W.word },
  }, {})
  eq(pattern(result), '\\vabc')
end)

test('literal: digits', function()
  local result = translate({
    { type = T.literal, value = '1', pos = 1, wordness = W.word },
    { type = T.literal, value = '2', pos = 2, wordness = W.word },
    { type = T.literal, value = '3', pos = 3, wordness = W.word },
  }, {})
  eq(pattern(result), '\\v123')
end)

test('literal: underscore', function()
  local result = translate({
    { type = T.literal, value = '_', pos = 1, wordness = W.word },
  }, {})
  eq(pattern(result), '\\v_')
end)

test('literal: space', function()
  local result = translate({
    { type = T.literal, value = ' ', pos = 1, wordness = W.non_word },
  }, {})
  eq(pattern(result), '\\v ')
end)

test('literal: hyphen', function()
  local result = translate({
    { type = T.literal, value = '-', pos = 1, wordness = W.non_word },
  }, {})
  eq(pattern(result), '\\v-')
end)

--------------------------------------------------------------------------------
--- Vim-special characters (need escaping outside char classes) ----------------
--------------------------------------------------------------------------------

test('vimspecial: equals sign', function()
  local result = translate({
    { type = T.literal, value = 'f', pos = 1, wordness = W.word },
    { type = T.literal, value = 'o', pos = 2, wordness = W.word },
    { type = T.literal, value = 'o', pos = 3, wordness = W.word },
    { type = T.literal, value = '=', pos = 4, wordness = W.non_word },
    { type = T.literal, value = 'b', pos = 5, wordness = W.word },
    { type = T.literal, value = 'a', pos = 6, wordness = W.word },
    { type = T.literal, value = 'r', pos = 7, wordness = W.word },
  }, {})
  eq(pattern(result), '\\vfoo\\=bar')
end)

test('vimspecial: tilde', function()
  local result = translate({
    { type = T.literal, value = 'x', pos = 1, wordness = W.word },
    { type = T.literal, value = '~', pos = 2, wordness = W.non_word },
    { type = T.literal, value = 'y', pos = 3, wordness = W.word },
  }, {})
  eq(pattern(result), '\\vx\\~y')
end)

test('vimspecial: at sign', function()
  local result = translate({
    { type = T.literal, value = 'a', pos = 1, wordness = W.word },
    { type = T.literal, value = '@', pos = 2, wordness = W.non_word },
    { type = T.literal, value = 'b', pos = 3, wordness = W.word },
  }, {})
  eq(pattern(result), '\\va\\@b')
end)

test('vimspecial: ampersand', function()
  local result = translate({
    { type = T.literal, value = 'a', pos = 1, wordness = W.word },
    { type = T.literal, value = '&', pos = 2, wordness = W.non_word },
    { type = T.literal, value = 'b', pos = 3, wordness = W.word },
  }, {})
  eq(pattern(result), '\\va\\&b')
end)

test('vimspecial: less than', function()
  local result = translate({
    { type = T.literal, value = 'a', pos = 1, wordness = W.word },
    { type = T.literal, value = '<', pos = 2, wordness = W.non_word },
    { type = T.literal, value = 'b', pos = 3, wordness = W.word },
  }, {})
  eq(pattern(result), '\\va\\<b')
end)

test('vimspecial: greater than', function()
  local result = translate({
    { type = T.literal, value = 'x', pos = 1, wordness = W.word },
    { type = T.literal, value = '>', pos = 2, wordness = W.non_word },
    { type = T.literal, value = 'y', pos = 3, wordness = W.word },
  }, {})
  eq(pattern(result), '\\vx\\>y')
end)

test('vimspecial: all special chars together', function()
  local result = translate({
    { type = T.literal, value = '~', pos = 1, wordness = W.non_word },
    { type = T.literal, value = '=', pos = 2, wordness = W.non_word },
    { type = T.literal, value = '@', pos = 3, wordness = W.non_word },
    { type = T.literal, value = '&', pos = 4, wordness = W.non_word },
    { type = T.literal, value = '<', pos = 5, wordness = W.non_word },
    { type = T.literal, value = '>', pos = 6, wordness = W.non_word },
  }, {})
  eq(pattern(result), '\\v\\~\\=\\@\\&\\<\\>')
end)

--------------------------------------------------------------------------------
--- Forward slash (search delimiter) -------------------------------------------
--------------------------------------------------------------------------------

test('slash: forward slash escaped', function()
  local result = translate({
    { type = T.literal, value = 'f', pos = 1, wordness = W.word },
    { type = T.literal, value = 'o', pos = 2, wordness = W.word },
    { type = T.literal, value = 'o', pos = 3, wordness = W.word },
    { type = T.slash,   value = '/', pos = 4, wordness = W.non_word },
    { type = T.literal, value = 'b', pos = 5, wordness = W.word },
    { type = T.literal, value = 'a', pos = 6, wordness = W.word },
    { type = T.literal, value = 'r', pos = 7, wordness = W.word },
  }, {})
  eq(pattern(result), '\\vfoo\\/bar')
end)

test('slash: multiple slashes', function()
  local result = translate({
    { type = T.slash,   value = '/', pos = 1, wordness = W.non_word },
    { type = T.literal, value = 'a', pos = 2, wordness = W.word },
    { type = T.literal, value = 'p', pos = 3, wordness = W.word },
    { type = T.literal, value = 'i', pos = 4, wordness = W.word },
    { type = T.slash,   value = '/', pos = 5, wordness = W.non_word },
    { type = T.literal, value = 'v', pos = 6, wordness = W.word },
    { type = T.literal, value = '1', pos = 7, wordness = W.word },
  }, {})
  eq(pattern(result), '\\v\\/api\\/v1')
end)

--------------------------------------------------------------------------------
--- Dot metacharacter ----------------------------------------------------------
--------------------------------------------------------------------------------

test('dot: passes through', function()
  local result = translate({
    { type = T.dot, value = '.', pos = 1, wordness = W.unknown },
  }, {})
  eq(pattern(result), '\\v.')
end)

test('dot: in context', function()
  local result = translate({
    { type = T.literal, value = 'a', pos = 1, wordness = W.word },
    { type = T.dot,     value = '.', pos = 2, wordness = W.unknown },
    { type = T.literal, value = 'b', pos = 3, wordness = W.word },
  }, {})
  eq(pattern(result), '\\va.b')
end)

--------------------------------------------------------------------------------
--- Anchors --------------------------------------------------------------------
--------------------------------------------------------------------------------

test('anchor: caret passes through', function()
  local result = translate({
    { type = T.anchor, value = '^', pos = 1, wordness = W.non_word },
  }, {})
  eq(pattern(result), '\\v^')
end)

test('anchor: dollar passes through', function()
  local result = translate({
    { type = T.anchor, value = '$', pos = 1, wordness = W.non_word },
  }, {})
  eq(pattern(result), '\\v$')
end)

test('anchor: both anchors', function()
  local result = translate({
    { type = T.anchor,  value = '^', pos = 1, wordness = W.non_word },
    { type = T.literal, value = 'f', pos = 2, wordness = W.word },
    { type = T.literal, value = 'o', pos = 3, wordness = W.word },
    { type = T.literal, value = 'o', pos = 4, wordness = W.word },
    { type = T.anchor,  value = '$', pos = 5, wordness = W.non_word },
  }, {})
  eq(pattern(result), '\\v^foo$')
end)

--------------------------------------------------------------------------------
--- Alternation ----------------------------------------------------------------
--------------------------------------------------------------------------------

test('alternation: simple', function()
  local result = translate({
    { type = T.literal,     value = 'a', pos = 1, wordness = W.word },
    { type = T.alternation, value = '|', pos = 2, wordness = W.non_word },
    { type = T.literal,     value = 'b', pos = 3, wordness = W.word },
  }, {})
  eq(pattern(result), '\\va|b')
end)

test('alternation: multiple', function()
  local result = translate({
    { type = T.literal,     value = 'a', pos = 1, wordness = W.word },
    { type = T.alternation, value = '|', pos = 2, wordness = W.non_word },
    { type = T.literal,     value = 'b', pos = 3, wordness = W.word },
    { type = T.alternation, value = '|', pos = 4, wordness = W.non_word },
    { type = T.literal,     value = 'c', pos = 5, wordness = W.word },
  }, {})
  eq(pattern(result), '\\va|b|c')
end)

--------------------------------------------------------------------------------
--- Summary --------------------------------------------------------------------
--------------------------------------------------------------------------------

h.summary()
