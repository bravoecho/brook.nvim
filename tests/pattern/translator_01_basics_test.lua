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

--- Helper to get full pattern from translator result.
---@param result brook.pattern.TranslatorResult
---@return string
local function pattern(result)
  return result.prefix .. result.body
end

local T = types.token_type
local EC = types.escape_class
local W = types.wordness
local GK = types.group_kind

--------------------------------------------------------------------------------
--- Empty input ----------------------------------------------------------------
--------------------------------------------------------------------------------

test('empty: empty token list produces \\v', function()
  local result = translate({}, {})
  eq(pattern(result), '\\v')
  deep_eq(result.warnings, {})
end)

test('empty: empty token list with fixed mode produces \\V', function()
  local result = translate({}, { fixed = true })
  eq(pattern(result), '\\V')
  deep_eq(result.warnings, {})
end)

--------------------------------------------------------------------------------
--- Case sensitivity -----------------------------------------------------------
--------------------------------------------------------------------------------

test('case: case-sensitive prefix', function()
  local result = translate({
    { type = T.literal, value = 'a', pos = 1, wordness = W.word },
  }, { case = 'case-sensitive' })
  eq(pattern(result), '\\C\\va')
end)

test('case: case-insensitive prefix', function()
  local result = translate({
    { type = T.literal, value = 'a', pos = 1, wordness = W.word },
  }, { case = 'case-insensitive' })
  eq(pattern(result), '\\c\\va')
end)

test('case: no case option means no case prefix', function()
  local result = translate({
    { type = T.literal, value = 'a', pos = 1, wordness = W.word },
  }, {})
  eq(pattern(result), '\\va')
end)

test('case: case-sensitive with fixed mode', function()
  local result = translate({
    { type = T.literal, value = 'a', pos = 1, wordness = W.word },
  }, { fixed = true, case = 'case-sensitive' })
  eq(pattern(result), '\\C\\Va')
end)

test('case: case-insensitive with fixed mode', function()
  local result = translate({
    { type = T.literal, value = 'a', pos = 1, wordness = W.word },
  }, { fixed = true, case = 'case-insensitive' })
  eq(pattern(result), '\\c\\Va')
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
  eq(pattern(result), '\\v<foo>')
end)

test('word: word boundary in fixed mode', function()
  local result = translate({
    { type = T.literal, value = 'f', pos = 1, wordness = W.word },
    { type = T.literal, value = 'o', pos = 2, wordness = W.word },
    { type = T.literal, value = 'o', pos = 3, wordness = W.word },
  }, { fixed = true, word = true })
  eq(pattern(result), '\\V\\<foo\\>')
end)

test('word: word boundary with case-sensitive', function()
  local result = translate({
    { type = T.literal, value = 'f', pos = 1, wordness = W.word },
    { type = T.literal, value = 'o', pos = 2, wordness = W.word },
    { type = T.literal, value = 'o', pos = 3, wordness = W.word },
  }, { word = true, case = 'case-sensitive' })
  eq(pattern(result), '\\C\\v<foo>')
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
  eq(pattern(result), '\\Vhello')
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
  eq(pattern(result), '\\Vfoo\\\\bar')
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
  eq(pattern(result), '\\Vfoo\\/bar')
end)

--------------------------------------------------------------------------------
--- Error and warning forwarding -----------------------------------------------
--------------------------------------------------------------------------------

test('forward: incoming warnings are preserved', function()
  local result = translate({
    { type = T.literal, value = 'a', pos = 1, wordness = W.word },
  }, {}, { 'parser warning 1', 'parser warning 2' })
  eq(pattern(result), '\\va')
  eq(#result.warnings, 2)
  eq(result.warnings[1], 'parser warning 1')
  eq(result.warnings[2], 'parser warning 2')
end)

test('forward: does not duplicate incoming warnings', function()
  -- It won't emit the '\\A treated as ^' warning, because that is the parser's
  -- responsibility.
  local result = translate({
    { type = T.escape_boundary, value = '\\A', pos = 1, escape_class = EC.anchor_start, wordness = W.non_word },
  }, {}, { 'parser warning' })
  eq(pattern(result), '\\v^')
  eq(#result.warnings, 1)
  eq(result.warnings[1], 'parser warning')
end)

test('translate: \\A does not add warning (parser responsibility)', function()
  local tokens = {
    { type = T.escape_boundary, value = '\\A', pos = 1, boundary_kind = 'start', escape_class = EC.anchor_start },
  }
  local result = translator.translate(tokens, {}, {}, nil)
  eq(#result.warnings, 0)
end)

test('translate: \\z does not add warning (parser responsibility)', function()
  local tokens = {
    { type = T.escape_boundary, value = '\\z', pos = 1, boundary_kind = 'end', escape_class = EC.anchor_end },
  }
  local result = translator.translate(tokens, {}, {}, nil)
  eq(#result.warnings, 0)
end)

test('translate: named group does not add warning (parser responsibility)', function()
  local tokens = {
    { type = T.group_open,  value = '(?P<name>', pos = 1, kind = GK.named_python, name = 'name' },
    { type = T.literal,     value = 'x',         pos = 10 },
    { type = T.group_close, value = ')',         pos = 11 },
  }
  local result = translator.translate(tokens, {}, {}, nil)
  eq(#result.warnings, 0)
end)

test('forward: incoming error returns early with empty pattern', function()
  local result = translate({
    { type = T.literal, value = 'a', pos = 1, wordness = W.word },
  }, {}, {}, 'parser error')
  eq(pattern(result), '')
  eq(result.error, 'parser error')
end)

test('forward: incoming error preserves warnings', function()
  local result = translate({
    { type = T.literal, value = 'a', pos = 1, wordness = W.word },
  }, {}, { 'warning before error' }, 'parser error')
  eq(pattern(result), '')
  eq(result.error, 'parser error')
  eq(#result.warnings, 1)
  eq(result.warnings[1], 'warning before error')
end)

test('forward: nil incoming warnings treated as empty', function()
  local result = translate({
    { type = T.literal, value = 'a', pos = 1, wordness = W.word },
  }, {}, nil, nil)
  eq(pattern(result), '\\va')
  deep_eq(result.warnings, {})
end)

test('forward: empty tokens with error returns early', function()
  local result = translate({}, {}, {}, 'unsupported construct')
  eq(pattern(result), '')
  eq(result.error, 'unsupported construct')
  deep_eq(result.warnings, {})
end)

--------------------------------------------------------------------------------
--- Summary --------------------------------------------------------------------
--------------------------------------------------------------------------------

h.summary()
