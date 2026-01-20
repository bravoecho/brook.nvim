-- tests/pattern/translator_escapes_test.lua
-- Translator tests for escape sequences.
--
-- Tests translation of various escape types: shorthands, literals, hex, unicode,
-- octal. Each escape type has specific fields set by the parser.
--
-- Run with:
--   nvim --headless -u NONE -c "set rtp+=." -c "luafile tests/pattern/translator_escapes_test.lua"

local h = require('tests.harness')
local test = h.test
local eq = h.eq
local deep_eq = h.deep_eq
local types = require('brook.pattern.types')

local ok, translator = pcall(require, 'brook.pattern.translator')
if not ok then
  print('SKIP: brook.pattern.translator not yet implemented')
  print('0/0 tests passed')
  vim.cmd('cquit 0')
  return
end

local translate = translator.translate

local T = types.token_type
local EC = types.escape_class
local W = types.wordness

--------------------------------------------------------------------------------
--- Shorthand word escapes -----------------------------------------------------
--------------------------------------------------------------------------------

test('escape: \\w passes through', function()
  local result = translate({
    { type = T.escape_class, value = '\\w', pos = 1, escape_class = EC.shorthand_word, wordness = W.word },
  }, {})
  eq(result.pattern, '\\v\\w')
end)

test('escape: \\d passes through', function()
  local result = translate({
    { type = T.escape_class, value = '\\d', pos = 1, escape_class = EC.shorthand_word, wordness = W.word },
  }, {})
  eq(result.pattern, '\\v\\d')
end)

--------------------------------------------------------------------------------
--- Shorthand non-word escapes -------------------------------------------------
--------------------------------------------------------------------------------

test('escape: \\s passes through', function()
  local result = translate({
    { type = T.escape_class, value = '\\s', pos = 1, escape_class = EC.shorthand_nonword, wordness = W.non_word },
  }, {})
  eq(result.pattern, '\\v\\s')
end)

test('escape: \\W passes through', function()
  local result = translate({
    { type = T.escape_class, value = '\\W', pos = 1, escape_class = EC.shorthand_nonword, wordness = W.non_word },
  }, {})
  eq(result.pattern, '\\v\\W')
end)

--------------------------------------------------------------------------------
--- Shorthand unknown escapes --------------------------------------------------
--------------------------------------------------------------------------------

test('escape: \\S passes through', function()
  local result = translate({
    { type = T.escape_class, value = '\\S', pos = 1, escape_class = EC.shorthand_unknown, wordness = W.unknown },
  }, {})
  eq(result.pattern, '\\v\\S')
end)

test('escape: \\D passes through', function()
  local result = translate({
    { type = T.escape_class, value = '\\D', pos = 1, escape_class = EC.shorthand_unknown, wordness = W.unknown },
  }, {})
  eq(result.pattern, '\\v\\D')
end)

--------------------------------------------------------------------------------
--- Escape literals ------------------------------------------------------------
--------------------------------------------------------------------------------

test('escape: \\n passes through', function()
  local result = translate({
    { type = T.escape_literal, value = '\\n', pos = 1, escape_class = EC.escaped_literal, wordness = W.non_word },
  }, {})
  eq(result.pattern, '\\v\\n')
end)

test('escape: \\t passes through', function()
  local result = translate({
    { type = T.escape_literal, value = '\\t', pos = 1, escape_class = EC.escaped_literal, wordness = W.non_word },
  }, {})
  eq(result.pattern, '\\v\\t')
end)

test('escape: \\r passes through', function()
  local result = translate({
    { type = T.escape_literal, value = '\\r', pos = 1, escape_class = EC.escaped_literal, wordness = W.non_word },
  }, {})
  eq(result.pattern, '\\v\\r')
end)

test('escape: \\\\ passes through', function()
  local result = translate({
    { type = T.escape_literal, value = '\\\\', pos = 1, escape_class = EC.escaped_literal, wordness = W.non_word },
  }, {})
  eq(result.pattern, '\\v\\\\')
end)

test('escape: \\. passes through', function()
  local result = translate({
    { type = T.escape_literal, value = '\\.', pos = 1, escape_class = EC.escaped_literal, wordness = W.non_word },
  }, {})
  eq(result.pattern, '\\v\\.')
end)

test('escape: \\* passes through', function()
  local result = translate({
    { type = T.escape_literal, value = '\\*', pos = 1, escape_class = EC.escaped_literal, wordness = W.non_word },
  }, {})
  eq(result.pattern, '\\v\\*')
end)

test('escape: \\+ passes through', function()
  local result = translate({
    { type = T.escape_literal, value = '\\+', pos = 1, escape_class = EC.escaped_literal, wordness = W.non_word },
  }, {})
  eq(result.pattern, '\\v\\+')
end)

test('escape: \\? passes through', function()
  local result = translate({
    { type = T.escape_literal, value = '\\?', pos = 1, escape_class = EC.escaped_literal, wordness = W.non_word },
  }, {})
  eq(result.pattern, '\\v\\?')
end)

test('escape: \\( passes through', function()
  local result = translate({
    { type = T.escape_literal, value = '\\(', pos = 1, escape_class = EC.escaped_literal, wordness = W.non_word },
  }, {})
  eq(result.pattern, '\\v\\(')
end)

test('escape: \\) passes through', function()
  local result = translate({
    { type = T.escape_literal, value = '\\)', pos = 1, escape_class = EC.escaped_literal, wordness = W.non_word },
  }, {})
  eq(result.pattern, '\\v\\)')
end)

test('escape: \\[ passes through', function()
  local result = translate({
    { type = T.escape_literal, value = '\\[', pos = 1, escape_class = EC.escaped_literal, wordness = W.non_word },
  }, {})
  eq(result.pattern, '\\v\\[')
end)

test('escape: \\] passes through', function()
  local result = translate({
    { type = T.escape_literal, value = '\\]', pos = 1, escape_class = EC.escaped_literal, wordness = W.non_word },
  }, {})
  eq(result.pattern, '\\v\\]')
end)

test('escape: \\{ passes through', function()
  local result = translate({
    { type = T.escape_literal, value = '\\{', pos = 1, escape_class = EC.escaped_literal, wordness = W.non_word },
  }, {})
  eq(result.pattern, '\\v\\{')
end)

test('escape: \\} passes through', function()
  local result = translate({
    { type = T.escape_literal, value = '\\}', pos = 1, escape_class = EC.escaped_literal, wordness = W.non_word },
  }, {})
  eq(result.pattern, '\\v\\}')
end)

test('escape: \\| passes through', function()
  local result = translate({
    { type = T.escape_literal, value = '\\|', pos = 1, escape_class = EC.escaped_literal, wordness = W.non_word },
  }, {})
  eq(result.pattern, '\\v\\|')
end)

test('escape: \\^ passes through', function()
  local result = translate({
    { type = T.escape_literal, value = '\\^', pos = 1, escape_class = EC.escaped_literal, wordness = W.non_word },
  }, {})
  eq(result.pattern, '\\v\\^')
end)

test('escape: \\$ passes through', function()
  local result = translate({
    { type = T.escape_literal, value = '\\$', pos = 1, escape_class = EC.escaped_literal, wordness = W.non_word },
  }, {})
  eq(result.pattern, '\\v\\$')
end)

--------------------------------------------------------------------------------
--- Hex escapes ----------------------------------------------------------------
--------------------------------------------------------------------------------

test('escape: \\x7F passes through', function()
  local result = translate({
    { type = T.escape_hex, value = '\\x7F', pos = 1, escape_class = EC.escaped_literal, wordness = W.unknown },
  }, {})
  eq(result.pattern, '\\v\\x7F')
end)

test('escape: \\x{0041} passes through', function()
  local result = translate({
    { type = T.escape_hex, value = '\\x{0041}', pos = 1, escape_class = EC.escaped_literal, wordness = W.word },
  }, {})
  eq(result.pattern, '\\v\\x{0041}')
end)

--------------------------------------------------------------------------------
--- Unicode escapes ------------------------------------------------------------
--------------------------------------------------------------------------------

test('escape: \\u0041 passes through', function()
  local result = translate({
    { type = T.escape_unicode, value = '\\u0041', pos = 1, escape_class = EC.escaped_literal, wordness = W.word },
  }, {})
  eq(result.pattern, '\\v\\u0041')
end)

test('escape: \\u{41} passes through', function()
  local result = translate({
    { type = T.escape_unicode, value = '\\u{41}', pos = 1, escape_class = EC.escaped_literal, wordness = W.word },
  }, {})
  eq(result.pattern, '\\v\\u{41}')
end)

--------------------------------------------------------------------------------
--- Octal escapes --------------------------------------------------------------
--------------------------------------------------------------------------------

test('escape: \\0 passes through', function()
  local result = translate({
    { type = T.escape_octal, value = '\\0', pos = 1, escape_class = EC.escaped_literal, wordness = W.non_word },
  }, {})
  eq(result.pattern, '\\v\\0')
end)

test('escape: \\123 passes through', function()
  local result = translate({
    { type = T.escape_octal, value = '\\123', pos = 1, escape_class = EC.escaped_literal, wordness = W.word },
  }, {})
  eq(result.pattern, '\\v\\123')
end)

--------------------------------------------------------------------------------
--- Trailing backslash ---------------------------------------------------------
--------------------------------------------------------------------------------

test('escape: trailing backslash passes through', function()
  local result = translate({
    { type = T.literal, value = 'a', pos = 1, wordness = W.word },
    { type = T.escape_literal, value = '\\', pos = 2, escape_class = EC.escaped_literal, wordness = W.non_word },
  }, {})
  eq(result.pattern, '\\va\\')
end)

--------------------------------------------------------------------------------
--- Consecutive escapes --------------------------------------------------------
--------------------------------------------------------------------------------

test('escape: consecutive escapes', function()
  local result = translate({
    { type = T.escape_literal, value = '\\\\', pos = 1, escape_class = EC.escaped_literal, wordness = W.non_word },
    { type = T.escape_class, value = '\\d', pos = 3, escape_class = EC.shorthand_word, wordness = W.word },
  }, {})
  eq(result.pattern, '\\v\\\\\\d')
end)

--------------------------------------------------------------------------------
--- Summary --------------------------------------------------------------------
--------------------------------------------------------------------------------

h.summary()
