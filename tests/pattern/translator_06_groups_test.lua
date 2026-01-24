-- tests/pattern/translator_groups_test.lua
-- Translator tests for groups.
--
-- Capturing groups become (), non-capturing become %(), named groups become
-- numbered with a warning.
--
-- Run with:
--   nvim --headless -u NONE -c "set rtp+=." -c "luafile tests/pattern/translator_groups_test.lua"

local h = require('tests.harness')
local test = h.test
local eq = h.eq
local deep_eq = h.deep_eq
local types = require('brook.pattern.types')

local translator = require('brook.pattern.translator')

local translate = translator.translate

local T = types.token_type
local GK = types.group_kind
local W = types.wordness

--------------------------------------------------------------------------------
--- Capturing groups -----------------------------------------------------------
--------------------------------------------------------------------------------

test('group: capturing ( ... ) passes through', function()
  local result = translate({
    { type = T.group_open,  value = '(', pos = 1, kind = GK.capturing,  wordness = W.non_word },
    { type = T.literal,     value = 'a', pos = 2, wordness = W.word },
    { type = T.group_close, value = ')', pos = 3, wordness = W.non_word },
  }, {})
  eq(result.pattern, '\\v(a)')
  deep_eq(result.warnings, {})
end)

test('group: nested capturing groups', function()
  local result = translate({
    { type = T.group_open,  value = '(', pos = 1, kind = GK.capturing,  wordness = W.non_word },
    { type = T.group_open,  value = '(', pos = 2, kind = GK.capturing,  wordness = W.non_word },
    { type = T.literal,     value = 'a', pos = 3, wordness = W.word },
    { type = T.group_close, value = ')', pos = 4, wordness = W.non_word },
    { type = T.group_close, value = ')', pos = 5, wordness = W.non_word },
  }, {})
  eq(result.pattern, '\\v((a))')
end)

--------------------------------------------------------------------------------
--- Non-capturing groups -------------------------------------------------------
--------------------------------------------------------------------------------

test('group: non-capturing (?:...) becomes %(...)%)', function()
  local result = translate({
    { type = T.group_open,  value = '(?:', pos = 1, kind = GK.non_capturing, wordness = W.non_word },
    { type = T.literal,     value = 'a',   pos = 4, wordness = W.word },
    { type = T.group_close, value = ')',   pos = 5, wordness = W.non_word },
  }, {})
  eq(result.pattern, '\\v%(a)')
  deep_eq(result.warnings, {})
end)

test('group: nested non-capturing groups', function()
  local result = translate({
    { type = T.group_open,  value = '(?:', pos = 1, kind = GK.non_capturing, wordness = W.non_word },
    { type = T.group_open,  value = '(?:', pos = 4, kind = GK.non_capturing, wordness = W.non_word },
    { type = T.literal,     value = 'a',   pos = 7, wordness = W.word },
    { type = T.group_close, value = ')',   pos = 8, wordness = W.non_word },
    { type = T.group_close, value = ')',   pos = 9, wordness = W.non_word },
  }, {})
  eq(result.pattern, '\\v%(%(a))')
end)

test('group: mixed capturing and non-capturing', function()
  local result = translate({
    { type = T.group_open,  value = '(',   pos = 1, kind = GK.capturing,     wordness = W.non_word },
    { type = T.group_open,  value = '(?:', pos = 2, kind = GK.non_capturing, wordness = W.non_word },
    { type = T.literal,     value = 'a',   pos = 5, wordness = W.word },
    { type = T.group_close, value = ')',   pos = 6, wordness = W.non_word },
    { type = T.group_close, value = ')',   pos = 7, wordness = W.non_word },
  }, {})
  eq(result.pattern, '\\v(%(a))')
end)

--------------------------------------------------------------------------------
--- Named groups ---------------------------------------------------------------
--------------------------------------------------------------------------------

test('group: Python named (?P<n>...) becomes numbered with no additional warning', function()
  -- The warning for this case is the parser's responsibility.
  local result = translate({
    { type = T.group_open,  value = '(?P<name>', pos = 1,  kind = GK.named_python, name = 'name', wordness = W.non_word },
    { type = T.literal,     value = 'a',         pos = 10, wordness = W.word },
    { type = T.group_close, value = ')',         pos = 11, wordness = W.non_word },
  }, {})
  eq(result.pattern, '\\v(a)')
  eq(#result.warnings, 0)
end)

test('group: PCRE named (?<n>...) becomes numbered with no additional warning', function()
  -- The warning for this case is the parser's responsibility.
  local result = translate({
    { type = T.group_open,  value = '(?<name>', pos = 1,  kind = GK.named_pcre, name = 'name', wordness = W.non_word },
    { type = T.literal,     value = 'a',        pos = 9,  wordness = W.word },
    { type = T.group_close, value = ')',        pos = 10, wordness = W.non_word },
  }, {})
  eq(result.pattern, '\\v(a)')
  eq(#result.warnings, 0)
end)

test('group: multiple named groups generate multiple no additional warnings', function()
  -- The warnings for this case are the parser's responsibility.
  local result = translate({
    { type = T.group_open,  value = '(?P<first>',  pos = 1,  kind = GK.named_python, name = 'first',  wordness = W.non_word },
    { type = T.literal,     value = 'a',           pos = 11, wordness = W.word },
    { type = T.group_close, value = ')',           pos = 12, wordness = W.non_word },
    { type = T.group_open,  value = '(?P<second>', pos = 13, kind = GK.named_python, name = 'second', wordness = W.non_word },
    { type = T.literal,     value = 'b',           pos = 24, wordness = W.word },
    { type = T.group_close, value = ')',           pos = 25, wordness = W.non_word },
  }, {})
  eq(result.pattern, '\\v(a)(b)')
  eq(#result.warnings, 0)
end)

--------------------------------------------------------------------------------
--- Flag groups ----------------------------------------------------------------
--------------------------------------------------------------------------------

test('group: standalone flag group (?i)', function()
  local result = translate({
    { type = T.group_open, value = '(?i)', pos = 1, kind = GK.flags,  flags = 'i', scoped = false, wordness = W.non_word },
    { type = T.literal,    value = 'a',    pos = 5, wordness = W.word },
  }, {})
  eq(result.pattern, '\\v(?i)a')
end)

test('group: scoped flag group (?i:...)', function()
  local result = translate({
    { type = T.group_open,  value = '(?i:', pos = 1, kind = GK.flags,      flags = 'i', scoped = true, wordness = W.non_word },
    { type = T.literal,     value = 'a',    pos = 5, wordness = W.word },
    { type = T.group_close, value = ')',    pos = 6, wordness = W.non_word },
  }, {})
  eq(result.pattern, '\\v(?i:a)')
end)

--------------------------------------------------------------------------------
--- Groups with alternation ----------------------------------------------------
--------------------------------------------------------------------------------

test('group: alternation inside capturing', function()
  local result = translate({
    { type = T.group_open,  value = '(', pos = 1, kind = GK.capturing,  wordness = W.non_word },
    { type = T.literal,     value = 'a', pos = 2, wordness = W.word },
    { type = T.alternation, value = '|', pos = 3, wordness = W.non_word },
    { type = T.literal,     value = 'b', pos = 4, wordness = W.word },
    { type = T.group_close, value = ')', pos = 5, wordness = W.non_word },
  }, {})
  eq(result.pattern, '\\v(a|b)')
end)

test('group: alternation inside non-capturing', function()
  local result = translate({
    { type = T.group_open,  value = '(?:', pos = 1, kind = GK.non_capturing, wordness = W.non_word },
    { type = T.literal,     value = 'a',   pos = 4, wordness = W.word },
    { type = T.alternation, value = '|',   pos = 5, wordness = W.non_word },
    { type = T.literal,     value = 'b',   pos = 6, wordness = W.word },
    { type = T.alternation, value = '|',   pos = 7, wordness = W.non_word },
    { type = T.literal,     value = 'c',   pos = 8, wordness = W.word },
    { type = T.group_close, value = ')',   pos = 9, wordness = W.non_word },
  }, {})
  eq(result.pattern, '\\v%(a|b|c)')
end)

--------------------------------------------------------------------------------
--- Groups with quantifiers ----------------------------------------------------
--------------------------------------------------------------------------------

test('group: quantifier after group', function()
  local result = translate({
    { type = T.group_open,  value = '(', pos = 1, kind = GK.capturing,  wordness = W.non_word },
    { type = T.literal,     value = 'a', pos = 2, wordness = W.word },
    { type = T.literal,     value = 'b', pos = 3, wordness = W.word },
    { type = T.group_close, value = ')', pos = 4, wordness = W.non_word },
    { type = T.quantifier,  value = '+', pos = 5, greedy = true,        wordness = W.non_word },
  }, {})
  eq(result.pattern, '\\v(ab)+')
end)

test('group: non-greedy quantifier after group', function()
  local result = translate({
    { type = T.group_open,  value = '(?:', pos = 1, kind = GK.non_capturing, wordness = W.non_word },
    { type = T.literal,     value = 'a',   pos = 4, wordness = W.word },
    { type = T.group_close, value = ')',   pos = 5, wordness = W.non_word },
    { type = T.quantifier,  value = '*?',  pos = 6, greedy = false,          wordness = W.non_word },
  }, {})
  eq(result.pattern, '\\v%(a){-}')
end)

--------------------------------------------------------------------------------
--- Edge cases -----------------------------------------------------------------
--------------------------------------------------------------------------------

test('group: unclosed group (graceful handling)', function()
  local result = translate({
    { type = T.group_open, value = '(', pos = 1, kind = GK.capturing, wordness = W.non_word },
    { type = T.literal,    value = 'f', pos = 2, wordness = W.word },
    { type = T.literal,    value = 'o', pos = 3, wordness = W.word },
    { type = T.literal,    value = 'o', pos = 4, wordness = W.word },
  }, {})
  eq(result.pattern, '\\v(foo')
end)

--------------------------------------------------------------------------------
--- Summary --------------------------------------------------------------------
--------------------------------------------------------------------------------

h.summary()
