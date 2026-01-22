-- tests/pattern/parser_wordness_test.lua
-- Wordness computation tests for the parser.
--
-- The parser assigns a `wordness` field to tokens that can appear adjacent
-- to `\b`. This determines how word boundaries are translated to Vim regex.
--
-- Run with:
--   nvim --headless -u NONE -c "set rtp+=." -c "luafile tests/pattern/parser_wordness_test.lua"

local h = require('tests.harness')
local test = h.test
local eq = h.eq
local types = require('brook.pattern.types')

local parser = require('brook.pattern.parser')

local parse = parser.parse

local T = types.token_type
local CC = types.cc_token_type
local GK = types.group_kind
local W = types.wordness

--------------------------------------------------------------------------------
--- Literal wordness -----------------------------------------------------------
--------------------------------------------------------------------------------

test('literal wordness: a is word', function()
  local result = parse({
    { type = T.literal, value = 'a', pos = 1 },
  })
  eq(result.tokens[1].wordness, W.word)
end)

test('literal wordness: Z is word', function()
  local result = parse({
    { type = T.literal, value = 'Z', pos = 1 },
  })
  eq(result.tokens[1].wordness, W.word)
end)

test('literal wordness: 0 is word', function()
  local result = parse({
    { type = T.literal, value = '0', pos = 1 },
  })
  eq(result.tokens[1].wordness, W.word)
end)

test('literal wordness: 9 is word', function()
  local result = parse({
    { type = T.literal, value = '9', pos = 1 },
  })
  eq(result.tokens[1].wordness, W.word)
end)

test('literal wordness: _ is word', function()
  local result = parse({
    { type = T.literal, value = '_', pos = 1 },
  })
  eq(result.tokens[1].wordness, W.word)
end)

test('literal wordness: space is non_word', function()
  local result = parse({
    { type = T.literal, value = ' ', pos = 1 },
  })
  eq(result.tokens[1].wordness, W.non_word)
end)

test('literal wordness: hyphen is non_word', function()
  local result = parse({
    { type = T.literal, value = '-', pos = 1 },
  })
  eq(result.tokens[1].wordness, W.non_word)
end)

test('literal wordness: dot is non_word', function()
  local result = parse({
    { type = T.literal, value = '.', pos = 1 },
  })
  eq(result.tokens[1].wordness, W.non_word)
end)

test('literal wordness: exclamation is non_word', function()
  local result = parse({
    { type = T.literal, value = '!', pos = 1 },
  })
  eq(result.tokens[1].wordness, W.non_word)
end)

test('literal wordness: @ is non_word', function()
  local result = parse({
    { type = T.literal, value = '@', pos = 1 },
  })
  eq(result.tokens[1].wordness, W.non_word)
end)

--------------------------------------------------------------------------------
--- Dot metacharacter wordness -------------------------------------------------
--------------------------------------------------------------------------------

test('dot wordness: . is unknown', function()
  local result = parse({
    { type = T.dot, value = '.', pos = 1 },
  })
  eq(result.tokens[1].wordness, W.unknown)
end)

--------------------------------------------------------------------------------
--- Escape class wordness ------------------------------------------------------
--------------------------------------------------------------------------------

test('escape wordness: \\w is word', function()
  local result = parse({
    { type = T.escape_class, value = '\\w', pos = 1 },
  })
  eq(result.tokens[1].wordness, W.word)
end)

test('escape wordness: \\d is word', function()
  local result = parse({
    { type = T.escape_class, value = '\\d', pos = 1 },
  })
  eq(result.tokens[1].wordness, W.word)
end)

test('escape wordness: \\s is non_word', function()
  local result = parse({
    { type = T.escape_class, value = '\\s', pos = 1 },
  })
  eq(result.tokens[1].wordness, W.non_word)
end)

test('escape wordness: \\W is non_word', function()
  local result = parse({
    { type = T.escape_class, value = '\\W', pos = 1 },
  })
  eq(result.tokens[1].wordness, W.non_word)
end)

test('escape wordness: \\S is unknown', function()
  local result = parse({
    { type = T.escape_class, value = '\\S', pos = 1 },
  })
  eq(result.tokens[1].wordness, W.unknown)
end)

test('escape wordness: \\D is unknown', function()
  local result = parse({
    { type = T.escape_class, value = '\\D', pos = 1 },
  })
  eq(result.tokens[1].wordness, W.unknown)
end)

test('escape wordness: \\h is unknown', function()
  local result = parse({
    { type = T.escape_class, value = '\\h', pos = 1 },
  })
  eq(result.tokens[1].wordness, W.unknown)
end)

test('escape wordness: \\H is unknown', function()
  local result = parse({
    { type = T.escape_class, value = '\\H', pos = 1 },
  })
  eq(result.tokens[1].wordness, W.unknown)
end)

test('escape wordness: \\v is unknown', function()
  local result = parse({
    { type = T.escape_class, value = '\\v', pos = 1 },
  })
  eq(result.tokens[1].wordness, W.unknown)
end)

test('escape wordness: \\V is unknown', function()
  local result = parse({
    { type = T.escape_class, value = '\\V', pos = 1 },
  })
  eq(result.tokens[1].wordness, W.unknown)
end)

--------------------------------------------------------------------------------
--- Escape literal wordness ----------------------------------------------------
--------------------------------------------------------------------------------

test('escape literal wordness: \\n is non_word', function()
  local result = parse({
    { type = T.escape_literal, value = '\\n', pos = 1 },
  })
  eq(result.tokens[1].wordness, W.non_word)
end)

test('escape literal wordness: \\t is non_word', function()
  local result = parse({
    { type = T.escape_literal, value = '\\t', pos = 1 },
  })
  eq(result.tokens[1].wordness, W.non_word)
end)

test('escape literal wordness: \\r is non_word', function()
  local result = parse({
    { type = T.escape_literal, value = '\\r', pos = 1 },
  })
  eq(result.tokens[1].wordness, W.non_word)
end)

test('escape literal wordness: \\\\ is non_word', function()
  local result = parse({
    { type = T.escape_literal, value = '\\\\', pos = 1 },
  })
  eq(result.tokens[1].wordness, W.non_word)
end)

test('escape literal wordness: \\. is non_word', function()
  local result = parse({
    { type = T.escape_literal, value = '\\.', pos = 1 },
  })
  eq(result.tokens[1].wordness, W.non_word)
end)

test('escape literal wordness: \\a is word (escaped word char)', function()
  local result = parse({
    { type = T.escape_literal, value = '\\a', pos = 1 },
  })
  eq(result.tokens[1].wordness, W.word)
end)

test('escape literal wordness: \\e is word (escaped word char)', function()
  local result = parse({
    { type = T.escape_literal, value = '\\e', pos = 1 },
  })
  eq(result.tokens[1].wordness, W.word)
end)

test('escape literal wordness: \\f is word (escaped word char)', function()
  local result = parse({
    { type = T.escape_literal, value = '\\f', pos = 1 },
  })
  eq(result.tokens[1].wordness, W.word)
end)

--------------------------------------------------------------------------------
--- Structural token wordness --------------------------------------------------
--------------------------------------------------------------------------------

test('anchor wordness: ^ is non_word', function()
  local result = parse({
    { type = T.anchor, value = '^', pos = 1 },
  })
  eq(result.tokens[1].wordness, W.non_word)
end)

test('anchor wordness: $ is non_word', function()
  local result = parse({
    { type = T.anchor, value = '$', pos = 1 },
  })
  eq(result.tokens[1].wordness, W.non_word)
end)

test('alternation wordness: | is non_word', function()
  local result = parse({
    { type = T.alternation, value = '|', pos = 1 },
  })
  eq(result.tokens[1].wordness, W.non_word)
end)

test('group_open wordness: ( is non_word', function()
  local result = parse({
    { type = T.group_open, value = '(', pos = 1, kind = GK.capturing },
  })
  eq(result.tokens[1].wordness, W.non_word)
end)

test('group_open wordness: (?: is non_word', function()
  local result = parse({
    { type = T.group_open, value = '(?:', pos = 1, kind = GK.non_capturing },
  })
  eq(result.tokens[1].wordness, W.non_word)
end)

test('group_close wordness: ) is non_word', function()
  local result = parse({
    { type = T.group_close, value = ')', pos = 1 },
  })
  eq(result.tokens[1].wordness, W.non_word)
end)

--------------------------------------------------------------------------------
--- Quantifier wordness (inherits from preceding) ------------------------------
--------------------------------------------------------------------------------

test('quantifier wordness: * after \\w inherits word', function()
  local result = parse({
    { type = T.escape_class, value = '\\w', pos = 1 },
    { type = T.quantifier,   value = '*',   pos = 3, greedy = true },
  })
  eq(result.tokens[2].wordness, W.word)
end)

test('quantifier wordness: + after \\s inherits non_word', function()
  local result = parse({
    { type = T.escape_class, value = '\\s', pos = 1 },
    { type = T.quantifier,   value = '+',   pos = 3, greedy = true },
  })
  eq(result.tokens[2].wordness, W.non_word)
end)

test('quantifier wordness: ? after . inherits unknown', function()
  local result = parse({
    { type = T.dot,        value = '.', pos = 1 },
    { type = T.quantifier, value = '?', pos = 2, greedy = true },
  })
  eq(result.tokens[2].wordness, W.unknown)
end)

test('quantifier wordness: {2,3} after literal a inherits word', function()
  local result = parse({
    { type = T.literal,    value = 'a',     pos = 1 },
    { type = T.quantifier, value = '{2,3}', pos = 2, greedy = true },
  })
  eq(result.tokens[2].wordness, W.word)
end)

test('quantifier wordness: *? (non-greedy) after \\d inherits word', function()
  local result = parse({
    { type = T.escape_class, value = '\\d', pos = 1 },
    { type = T.quantifier,   value = '*?',  pos = 3, greedy = false },
  })
  eq(result.tokens[2].wordness, W.word)
end)

test('quantifier wordness: inherits non_word from group_close', function()
  local result = parse({
    { type = T.group_open,  value = '(', pos = 1, kind = GK.capturing },
    { type = T.literal,     value = 'a', pos = 2 },
    { type = T.group_close, value = ')', pos = 3 },
    { type = T.quantifier,  value = '+', pos = 4, greedy = true },
  })
  eq(result.tokens[4].wordness, W.non_word)
end)

test('quantifier wordness: inherits from char_class (word)', function()
  local result = parse({
    { type = T.char_class_open,  value = '[', pos = 1, negated = false },
    { type = CC.cc_literal,      value = 'a', pos = 2 },
    { type = T.char_class_close, value = ']', pos = 3 },
    { type = T.quantifier,       value = '+', pos = 4, greedy = true },
  })
  eq(result.tokens[4].wordness, W.word)
end)

test('quantifier wordness: inherits from char_class (unknown when negated)', function()
  local result = parse({
    { type = T.char_class_open,  value = '[^', pos = 1, negated = true },
    { type = CC.cc_literal,      value = 'a',  pos = 3 },
    { type = T.char_class_close, value = ']',  pos = 4 },
    { type = T.quantifier,       value = '*',  pos = 5, greedy = true },
  })
  eq(result.tokens[4].wordness, W.unknown)
end)

--------------------------------------------------------------------------------
--- Character class wordness: word-only ----------------------------------------
--------------------------------------------------------------------------------

test('class wordness: [a-z] is word', function()
  local result = parse({
    { type = T.char_class_open,  value = '[',   pos = 1, negated = false },
    { type = CC.cc_range,        value = 'a-z', pos = 2, from = 'a',     to = 'z' },
    { type = T.char_class_close, value = ']',   pos = 5 },
  })
  eq(result.tokens[1].wordness, W.word)
end)

test('class wordness: [A-Z] is word', function()
  local result = parse({
    { type = T.char_class_open,  value = '[',   pos = 1, negated = false },
    { type = CC.cc_range,        value = 'A-Z', pos = 2, from = 'A',     to = 'Z' },
    { type = T.char_class_close, value = ']',   pos = 5 },
  })
  eq(result.tokens[1].wordness, W.word)
end)

test('class wordness: [0-9] is word', function()
  local result = parse({
    { type = T.char_class_open,  value = '[',   pos = 1, negated = false },
    { type = CC.cc_range,        value = '0-9', pos = 2, from = '0',     to = '9' },
    { type = T.char_class_close, value = ']',   pos = 5 },
  })
  eq(result.tokens[1].wordness, W.word)
end)

test('class wordness: [a-zA-Z0-9_] is word', function()
  local result = parse({
    { type = T.char_class_open,  value = '[',   pos = 1, negated = false },
    { type = CC.cc_range,        value = 'a-z', pos = 2, from = 'a',     to = 'z' },
    { type = CC.cc_range,        value = 'A-Z', pos = 5, from = 'A',     to = 'Z' },
    { type = CC.cc_range,        value = '0-9', pos = 8, from = '0',     to = '9' },
    { type = CC.cc_literal,      value = '_',   pos = 11 },
    { type = T.char_class_close, value = ']',   pos = 12 },
  })
  eq(result.tokens[1].wordness, W.word)
end)

test('class wordness: [abc] is word', function()
  local result = parse({
    { type = T.char_class_open,  value = '[', pos = 1, negated = false },
    { type = CC.cc_literal,      value = 'a', pos = 2 },
    { type = CC.cc_literal,      value = 'b', pos = 3 },
    { type = CC.cc_literal,      value = 'c', pos = 4 },
    { type = T.char_class_close, value = ']', pos = 5 },
  })
  eq(result.tokens[1].wordness, W.word)
end)

test('class wordness: [\\w] is word', function()
  local result = parse({
    { type = T.char_class_open,  value = '[',   pos = 1, negated = false },
    { type = CC.cc_escape_class, value = '\\w', pos = 2 },
    { type = T.char_class_close, value = ']',   pos = 4 },
  })
  eq(result.tokens[1].wordness, W.word)
end)

test('class wordness: [\\d] is word', function()
  local result = parse({
    { type = T.char_class_open,  value = '[',   pos = 1, negated = false },
    { type = CC.cc_escape_class, value = '\\d', pos = 2 },
    { type = T.char_class_close, value = ']',   pos = 4 },
  })
  eq(result.tokens[1].wordness, W.word)
end)

test('class wordness: [\\b] is word (literal b in Rust regex)', function()
  local result = parse({
    { type = T.char_class_open,    value = '[',   pos = 1, negated = false },
    { type = CC.cc_escape_literal, value = '\\b', pos = 2 },
    { type = T.char_class_close,   value = ']',   pos = 4 },
  })
  eq(result.tokens[1].wordness, W.word)
end)

test('class wordness: [\\a] is word (escaped word char)', function()
  local result = parse({
    { type = T.char_class_open,    value = '[',   pos = 1, negated = false },
    { type = CC.cc_escape_literal, value = '\\a', pos = 2 },
    { type = T.char_class_close,   value = ']',   pos = 4 },
  })
  eq(result.tokens[1].wordness, W.word)
end)

test('class wordness: [\\5] is word (escaped digit)', function()
  local result = parse({
    { type = T.char_class_open,    value = '[',   pos = 1, negated = false },
    { type = CC.cc_escape_literal, value = '\\5', pos = 2 },
    { type = T.char_class_close,   value = ']',   pos = 4 },
  })
  eq(result.tokens[1].wordness, W.word)
end)

test('class wordness: [\\_] is word (escaped underscore)', function()
  local result = parse({
    { type = T.char_class_open,    value = '[',   pos = 1, negated = false },
    { type = CC.cc_escape_literal, value = '\\_', pos = 2 },
    { type = T.char_class_close,   value = ']',   pos = 4 },
  })
  eq(result.tokens[1].wordness, W.word)
end)

--------------------------------------------------------------------------------
--- Character class wordness: non-word-only ------------------------------------
--------------------------------------------------------------------------------

test('class wordness: [ \\t\\n] is non_word', function()
  local result = parse({
    { type = T.char_class_open,    value = '[',   pos = 1, negated = false },
    { type = CC.cc_literal,        value = ' ',   pos = 2 },
    { type = CC.cc_escape_literal, value = '\\t', pos = 3 },
    { type = CC.cc_escape_literal, value = '\\n', pos = 5 },
    { type = T.char_class_close,   value = ']',   pos = 7 },
  })
  eq(result.tokens[1].wordness, W.non_word)
end)

test('class wordness: [\\s] is non_word', function()
  local result = parse({
    { type = T.char_class_open,  value = '[',   pos = 1, negated = false },
    { type = CC.cc_escape_class, value = '\\s', pos = 2 },
    { type = T.char_class_close, value = ']',   pos = 4 },
  })
  eq(result.tokens[1].wordness, W.non_word)
end)

test('class wordness: [\\W] is non_word', function()
  local result = parse({
    { type = T.char_class_open,  value = '[',   pos = 1, negated = false },
    { type = CC.cc_escape_class, value = '\\W', pos = 2 },
    { type = T.char_class_close, value = ']',   pos = 4 },
  })
  eq(result.tokens[1].wordness, W.non_word)
end)

test('class wordness: [.!@#] is non_word', function()
  local result = parse({
    { type = T.char_class_open,  value = '[', pos = 1, negated = false },
    { type = CC.cc_literal,      value = '.', pos = 2 },
    { type = CC.cc_literal,      value = '!', pos = 3 },
    { type = CC.cc_literal,      value = '@', pos = 4 },
    { type = CC.cc_literal,      value = '#', pos = 5 },
    { type = T.char_class_close, value = ']', pos = 6 },
  })
  eq(result.tokens[1].wordness, W.non_word)
end)

--------------------------------------------------------------------------------
--- Character class wordness: unknown (mixed or negated) -----------------------
--------------------------------------------------------------------------------

test('class wordness: [^a-z] is unknown (negated)', function()
  local result = parse({
    { type = T.char_class_open,  value = '[^',  pos = 1, negated = true },
    { type = CC.cc_range,        value = 'a-z', pos = 3, from = 'a',    to = 'z' },
    { type = T.char_class_close, value = ']',   pos = 6 },
  })
  eq(result.tokens[1].wordness, W.unknown)
end)

test('class wordness: [a-z.] is unknown (mixed)', function()
  local result = parse({
    { type = T.char_class_open,  value = '[',   pos = 1, negated = false },
    { type = CC.cc_range,        value = 'a-z', pos = 2, from = 'a',     to = 'z' },
    { type = CC.cc_literal,      value = '.',   pos = 5 },
    { type = T.char_class_close, value = ']',   pos = 6 },
  })
  eq(result.tokens[1].wordness, W.unknown)
end)

test('class wordness: [-a-z] is unknown (leading hyphen)', function()
  local result = parse({
    { type = T.char_class_open,  value = '[',   pos = 1, negated = false },
    { type = CC.cc_literal,      value = '-',   pos = 2 },
    { type = CC.cc_range,        value = 'a-z', pos = 3, from = 'a',     to = 'z' },
    { type = T.char_class_close, value = ']',   pos = 6 },
  })
  eq(result.tokens[1].wordness, W.unknown)
end)

test('class wordness: [a-z-] is unknown (trailing hyphen)', function()
  local result = parse({
    { type = T.char_class_open,  value = '[',   pos = 1, negated = false },
    { type = CC.cc_range,        value = 'a-z', pos = 2, from = 'a',     to = 'z' },
    { type = CC.cc_literal,      value = '-',   pos = 5 },
    { type = T.char_class_close, value = ']',   pos = 6 },
  })
  eq(result.tokens[1].wordness, W.unknown)
end)

test('class wordness: [A-z] is unknown (range spans word/non-word)', function()
  local result = parse({
    { type = T.char_class_open,  value = '[',   pos = 1, negated = false },
    { type = CC.cc_range,        value = 'A-z', pos = 2, from = 'A',     to = 'z' },
    { type = T.char_class_close, value = ']',   pos = 5 },
  })
  eq(result.tokens[1].wordness, W.unknown)
end)

test('class wordness: [0-Z] is unknown (range digit to letter via gap)', function()
  local result = parse({
    { type = T.char_class_open,  value = '[',   pos = 1, negated = false },
    { type = CC.cc_range,        value = '0-Z', pos = 2, from = '0',     to = 'Z' },
    { type = T.char_class_close, value = ']',   pos = 5 },
  })
  eq(result.tokens[1].wordness, W.unknown)
end)

test('class wordness: [\\S] is unknown', function()
  local result = parse({
    { type = T.char_class_open,  value = '[',   pos = 1, negated = false },
    { type = CC.cc_escape_class, value = '\\S', pos = 2 },
    { type = T.char_class_close, value = ']',   pos = 4 },
  })
  eq(result.tokens[1].wordness, W.unknown)
end)

test('class wordness: [\\D] is unknown', function()
  local result = parse({
    { type = T.char_class_open,  value = '[',   pos = 1, negated = false },
    { type = CC.cc_escape_class, value = '\\D', pos = 2 },
    { type = T.char_class_close, value = ']',   pos = 4 },
  })
  eq(result.tokens[1].wordness, W.unknown)
end)

test('class wordness: [\\w\\s] is unknown (mixed word and non-word)', function()
  local result = parse({
    { type = T.char_class_open,  value = '[',   pos = 1, negated = false },
    { type = CC.cc_escape_class, value = '\\w', pos = 2 },
    { type = CC.cc_escape_class, value = '\\s', pos = 4 },
    { type = T.char_class_close, value = ']',   pos = 6 },
  })
  eq(result.tokens[1].wordness, W.unknown)
end)

--------------------------------------------------------------------------------
--- Slash token wordness -------------------------------------------------------
--------------------------------------------------------------------------------

test('slash wordness: / is non_word', function()
  local result = parse({
    { type = T.slash, value = '/', pos = 1 },
  })
  eq(result.tokens[1].wordness, W.non_word)
end)

--------------------------------------------------------------------------------
--- Complex pattern wordness ---------------------------------------------------
--------------------------------------------------------------------------------

test('pattern wordness: foo has all word tokens', function()
  local result = parse({
    { type = T.literal, value = 'f', pos = 1 },
    { type = T.literal, value = 'o', pos = 2 },
    { type = T.literal, value = 'o', pos = 3 },
  })
  eq(result.tokens[1].wordness, W.word)
  eq(result.tokens[2].wordness, W.word)
  eq(result.tokens[3].wordness, W.word)
end)

test('pattern wordness: <.*?> has mixed wordness', function()
  local result = parse({
    { type = T.literal,    value = '<',  pos = 1 },
    { type = T.dot,        value = '.',  pos = 2 },
    { type = T.quantifier, value = '*?', pos = 3, greedy = false },
    { type = T.literal,    value = '>',  pos = 5 },
  })
  eq(result.tokens[1].wordness, W.non_word)
  eq(result.tokens[2].wordness, W.unknown)
  eq(result.tokens[3].wordness, W.unknown)
  eq(result.tokens[4].wordness, W.non_word)
end)

--------------------------------------------------------------------------------
--- Summary --------------------------------------------------------------------
--------------------------------------------------------------------------------

h.summary()
