-- tests/pattern/parser_complex_test.lua
-- Complex pattern tests for the parser.
--
-- These tests verify the parser handles realistic patterns correctly,
-- combining multiple features and edge cases.
--
-- Run with:
--   nvim --headless -u NONE -c "set rtp+=." -c "luafile tests/pattern/parser_complex_test.lua"

local h = require('tests.harness')
local test = h.test
local eq = h.eq
local deep_eq = h.deep_eq
local types = require('brook.pattern.types')

local ok, parser = pcall(require, 'brook.pattern.parser')
if not ok then
  print('SKIP: brook.pattern.parser not yet implemented')
  print('0/0 tests passed')
  vim.cmd('cquit 0')
  return
end

local parse = parser.parse

local T = types.token_type
local CC = types.cc_token_type
local GK = types.group_kind
local EC = types.escape_class
local W = types.wordness

--------------------------------------------------------------------------------
--- Realistic patterns ---------------------------------------------------------
--------------------------------------------------------------------------------

test('complex: \\bfoo\\b word boundary pattern', function()
  local result = parse({
    { type = T.escape_boundary, value = '\\b', pos = 1, boundary_kind = 'word' },
    { type = T.literal, value = 'f', pos = 3 },
    { type = T.literal, value = 'o', pos = 4 },
    { type = T.literal, value = 'o', pos = 5 },
    { type = T.escape_boundary, value = '\\b', pos = 6, boundary_kind = 'word' },
  })
  eq(result.error, nil)
  -- First \b: prev=nil, next=word (f)
  eq(result.tokens[1].prev_wordness, nil)
  eq(result.tokens[1].next_wordness, W.word)
  -- Last \b: prev=word (o), next=nil
  eq(result.tokens[5].prev_wordness, W.word)
  eq(result.tokens[5].next_wordness, nil)
end)

test('complex: [a-zA-Z_][a-zA-Z0-9_]* identifier pattern', function()
  local result = parse({
    { type = T.char_class_open, value = '[', pos = 1, negated = false },
    { type = CC.cc_range, value = 'a-z', pos = 2, from = 'a', to = 'z' },
    { type = CC.cc_range, value = 'A-Z', pos = 5, from = 'A', to = 'Z' },
    { type = CC.cc_literal, value = '_', pos = 8 },
    { type = T.char_class_close, value = ']', pos = 9 },
    { type = T.char_class_open, value = '[', pos = 10, negated = false },
    { type = CC.cc_range, value = 'a-z', pos = 11, from = 'a', to = 'z' },
    { type = CC.cc_range, value = 'A-Z', pos = 14, from = 'A', to = 'Z' },
    { type = CC.cc_range, value = '0-9', pos = 17, from = '0', to = '9' },
    { type = CC.cc_literal, value = '_', pos = 20 },
    { type = T.char_class_close, value = ']', pos = 21 },
    { type = T.quantifier, value = '*', pos = 22, greedy = true },
  })
  eq(result.error, nil)
  -- First class: word (all word chars)
  eq(result.tokens[1].wordness, W.word)
  -- Second class: word (all word chars)
  eq(result.tokens[6].wordness, W.word)
  -- Quantifier inherits word
  eq(result.tokens[12].wordness, W.word)
end)

test('complex: https?://\\S+ URL pattern', function()
  local result = parse({
    { type = T.literal, value = 'h', pos = 1 },
    { type = T.literal, value = 't', pos = 2 },
    { type = T.literal, value = 't', pos = 3 },
    { type = T.literal, value = 'p', pos = 4 },
    { type = T.literal, value = 's', pos = 5 },
    { type = T.quantifier, value = '?', pos = 6, greedy = true },
    { type = T.literal, value = ':', pos = 7 },
    { type = T.literal, value = '/', pos = 8 },
    { type = T.literal, value = '/', pos = 9 },
    { type = T.escape_class, value = '\\S', pos = 10 },
    { type = T.quantifier, value = '+', pos = 12, greedy = true },
  })
  eq(result.error, nil)
  -- s is word, ? inherits word
  eq(result.tokens[5].wordness, W.word)
  eq(result.tokens[6].wordness, W.word)
  -- : and / are non_word
  eq(result.tokens[7].wordness, W.non_word)
  eq(result.tokens[8].wordness, W.non_word)
  -- \S is unknown, + inherits unknown
  eq(result.tokens[10].wordness, W.unknown)
  eq(result.tokens[11].wordness, W.unknown)
end)

test('complex: ^\\s*#.*$ comment pattern', function()
  local result = parse({
    { type = T.anchor, value = '^', pos = 1 },
    { type = T.escape_class, value = '\\s', pos = 2 },
    { type = T.quantifier, value = '*', pos = 4, greedy = true },
    { type = T.literal, value = '#', pos = 5 },
    { type = T.dot, value = '.', pos = 6 },
    { type = T.quantifier, value = '*', pos = 7, greedy = true },
    { type = T.anchor, value = '$', pos = 8 },
  })
  eq(result.error, nil)
  eq(result.tokens[1].wordness, W.non_word)
  eq(result.tokens[2].wordness, W.non_word)
  eq(result.tokens[3].wordness, W.non_word)
  eq(result.tokens[4].wordness, W.non_word)
  eq(result.tokens[5].wordness, W.unknown)
  eq(result.tokens[6].wordness, W.unknown)
  eq(result.tokens[7].wordness, W.non_word)
end)

test('complex: (foo|bar|baz) alternation in group', function()
  local result = parse({
    { type = T.group_open, value = '(', pos = 1, kind = GK.capturing },
    { type = T.literal, value = 'f', pos = 2 },
    { type = T.literal, value = 'o', pos = 3 },
    { type = T.literal, value = 'o', pos = 4 },
    { type = T.alternation, value = '|', pos = 5 },
    { type = T.literal, value = 'b', pos = 6 },
    { type = T.literal, value = 'a', pos = 7 },
    { type = T.literal, value = 'r', pos = 8 },
    { type = T.alternation, value = '|', pos = 9 },
    { type = T.literal, value = 'b', pos = 10 },
    { type = T.literal, value = 'a', pos = 11 },
    { type = T.literal, value = 'z', pos = 12 },
    { type = T.group_close, value = ')', pos = 13 },
  })
  eq(result.error, nil)
  eq(result.tokens[1].wordness, W.non_word)
  eq(result.tokens[2].wordness, W.word)
  eq(result.tokens[5].wordness, W.non_word)
  eq(result.tokens[13].wordness, W.non_word)
end)

test('complex: \\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3} IP pattern', function()
  local result = parse({
    { type = T.escape_class, value = '\\d', pos = 1 },
    { type = T.quantifier, value = '{1,3}', pos = 3, greedy = true },
    { type = T.escape_literal, value = '\\.', pos = 8 },
    { type = T.escape_class, value = '\\d', pos = 10 },
    { type = T.quantifier, value = '{1,3}', pos = 12, greedy = true },
    { type = T.escape_literal, value = '\\.', pos = 17 },
    { type = T.escape_class, value = '\\d', pos = 19 },
    { type = T.quantifier, value = '{1,3}', pos = 21, greedy = true },
    { type = T.escape_literal, value = '\\.', pos = 26 },
    { type = T.escape_class, value = '\\d', pos = 28 },
    { type = T.quantifier, value = '{1,3}', pos = 30, greedy = true },
  })
  eq(result.error, nil)
  -- \d is word, quantifier inherits
  eq(result.tokens[1].wordness, W.word)
  eq(result.tokens[2].wordness, W.word)
  -- \. is non_word (escaped dot is literal dot)
  eq(result.tokens[3].wordness, W.non_word)
end)

--------------------------------------------------------------------------------
--- Boundary in complex contexts -----------------------------------------------
--------------------------------------------------------------------------------

test('complex: \\b(\\w+)\\b word with capture', function()
  local result = parse({
    { type = T.escape_boundary, value = '\\b', pos = 1, boundary_kind = 'word' },
    { type = T.group_open, value = '(', pos = 3, kind = GK.capturing },
    { type = T.escape_class, value = '\\w', pos = 4 },
    { type = T.quantifier, value = '+', pos = 6, greedy = true },
    { type = T.group_close, value = ')', pos = 7 },
    { type = T.escape_boundary, value = '\\b', pos = 8, boundary_kind = 'word' },
  })
  eq(result.error, nil)
  -- First \b looks past ( to \w
  eq(result.tokens[1].prev_wordness, nil)
  eq(result.tokens[1].next_wordness, W.word)
  -- Last \b looks past ) to \w+
  eq(result.tokens[6].prev_wordness, W.word)
  eq(result.tokens[6].next_wordness, nil)
end)

test('complex: (?:^|\\s)foo(?:\\s|$) word at boundary', function()
  local result = parse({
    { type = T.group_open, value = '(?:', pos = 1, kind = GK.non_capturing },
    { type = T.anchor, value = '^', pos = 4 },
    { type = T.alternation, value = '|', pos = 5 },
    { type = T.escape_class, value = '\\s', pos = 6 },
    { type = T.group_close, value = ')', pos = 8 },
    { type = T.literal, value = 'f', pos = 9 },
    { type = T.literal, value = 'o', pos = 10 },
    { type = T.literal, value = 'o', pos = 11 },
    { type = T.group_open, value = '(?:', pos = 12, kind = GK.non_capturing },
    { type = T.escape_class, value = '\\s', pos = 15 },
    { type = T.alternation, value = '|', pos = 17 },
    { type = T.anchor, value = '$', pos = 18 },
    { type = T.group_close, value = ')', pos = 19 },
  })
  eq(result.error, nil)
  deep_eq(result.warnings, {})
end)

--------------------------------------------------------------------------------
--- Non-greedy quantifiers -----------------------------------------------------
--------------------------------------------------------------------------------

test('complex: <.*?> non-greedy HTML tag', function()
  local result = parse({
    { type = T.literal, value = '<', pos = 1 },
    { type = T.dot, value = '.', pos = 2 },
    { type = T.quantifier, value = '*?', pos = 3, greedy = false },
    { type = T.literal, value = '>', pos = 5 },
  })
  eq(result.error, nil)
  eq(result.tokens[3].greedy, false)
  eq(result.tokens[3].wordness, W.unknown)
end)

test('complex: "([^"]*?)" non-greedy quoted string', function()
  local result = parse({
    { type = T.literal, value = '"', pos = 1 },
    { type = T.group_open, value = '(', pos = 2, kind = GK.capturing },
    { type = T.char_class_open, value = '[^', pos = 3, negated = true },
    { type = CC.cc_literal, value = '"', pos = 5 },
    { type = T.char_class_close, value = ']', pos = 6 },
    { type = T.quantifier, value = '*?', pos = 7, greedy = false },
    { type = T.group_close, value = ')', pos = 9 },
    { type = T.literal, value = '"', pos = 10 },
  })
  eq(result.error, nil)
  -- Negated class is unknown
  eq(result.tokens[3].wordness, W.unknown)
  -- Quantifier inherits unknown
  eq(result.tokens[6].wordness, W.unknown)
end)

--------------------------------------------------------------------------------
--- Mixed warnings and valid constructs ----------------------------------------
--------------------------------------------------------------------------------

test('complex: \\A(?P<n>\\w+)\\z pattern with warnings', function()
  local result = parse({
    { type = T.escape_boundary, value = '\\A', pos = 1, boundary_kind = 'start' },
    { type = T.group_open, value = '(?P<n>', pos = 3, kind = GK.named_python, name = 'name' },
    { type = T.escape_class, value = '\\w', pos = 12 },
    { type = T.quantifier, value = '+', pos = 14, greedy = true },
    { type = T.group_close, value = ')', pos = 15 },
    { type = T.escape_boundary, value = '\\z', pos = 16, boundary_kind = 'end' },
  })
  eq(result.error, nil)
  -- Should have warnings for \A, \z, and named group
  eq(#result.warnings >= 2, true)
end)

--------------------------------------------------------------------------------
--- Escape sequences in various contexts ---------------------------------------
--------------------------------------------------------------------------------

test('complex: hex escapes in pattern', function()
  local result = parse({
    { type = T.escape_hex, value = '\\x00', pos = 1 },
    { type = T.escape_hex, value = '\\x{1F600}', pos = 5 },
  })
  eq(result.error, nil)
  eq(result.tokens[1].escape_class, EC.escaped_literal)
  eq(result.tokens[2].escape_class, EC.escaped_literal)
end)

test('complex: octal escapes in pattern', function()
  local result = parse({
    { type = T.escape_octal, value = '\\0', pos = 1 },
    { type = T.escape_octal, value = '\\177', pos = 3 },
  })
  eq(result.error, nil)
  eq(result.tokens[1].escape_class, EC.escaped_literal)
  eq(result.tokens[2].escape_class, EC.escaped_literal)
end)

--------------------------------------------------------------------------------
--- Character class edge cases -------------------------------------------------
--------------------------------------------------------------------------------

test('complex: character class with ] as first char', function()
  local result = parse({
    { type = T.char_class_open, value = '[', pos = 1, negated = false },
    { type = CC.cc_literal, value = ']', pos = 2 },
    { type = CC.cc_literal, value = 'a', pos = 3 },
    { type = T.char_class_close, value = ']', pos = 4 },
  })
  eq(result.error, nil)
  -- ] is non_word, a is word: mixed => unknown
  eq(result.tokens[1].wordness, W.unknown)
end)

test('complex: character class with escaped characters', function()
  local result = parse({
    { type = T.char_class_open, value = '[', pos = 1, negated = false },
    { type = CC.cc_escape_literal, value = '\\]', pos = 2 },
    { type = CC.cc_escape_literal, value = '\\\\', pos = 4 },
    { type = CC.cc_escape_literal, value = '\\-', pos = 6 },
    { type = T.char_class_close, value = ']', pos = 8 },
  })
  eq(result.error, nil)
  -- All escaped chars are non-word
  eq(result.tokens[1].wordness, W.non_word)
end)

test('complex: character class with \\b (literal b in Rust regex)', function()
  local result = parse({
    { type = T.char_class_open, value = '[', pos = 1, negated = false },
    { type = CC.cc_escape_literal, value = '\\b', pos = 2 },
    { type = T.char_class_close, value = ']', pos = 4 },
  })
  eq(result.error, nil)
  -- \b inside class is literal 'b', which is a word char
  eq(result.tokens[1].wordness, W.word)
end)

--------------------------------------------------------------------------------
--- Empty and minimal patterns -------------------------------------------------
--------------------------------------------------------------------------------

test('complex: single character class', function()
  local result = parse({
    { type = T.char_class_open, value = '[', pos = 1, negated = false },
    { type = CC.cc_literal, value = 'x', pos = 2 },
    { type = T.char_class_close, value = ']', pos = 3 },
  })
  eq(result.error, nil)
  eq(result.tokens[1].wordness, W.word)
end)

test('complex: single escape', function()
  local result = parse({
    { type = T.escape_class, value = '\\w', pos = 1 },
  })
  eq(result.error, nil)
  eq(result.tokens[1].wordness, W.word)
  eq(result.tokens[1].escape_class, EC.shorthand_word)
end)

test('complex: single quantified dot', function()
  local result = parse({
    { type = T.dot, value = '.', pos = 1 },
    { type = T.quantifier, value = '*', pos = 2, greedy = true },
  })
  eq(result.error, nil)
  eq(result.tokens[1].wordness, W.unknown)
  eq(result.tokens[2].wordness, W.unknown)
end)

--------------------------------------------------------------------------------
--- Summary --------------------------------------------------------------------
--------------------------------------------------------------------------------

h.summary()
