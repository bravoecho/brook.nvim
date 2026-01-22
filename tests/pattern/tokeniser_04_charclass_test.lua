-- tests/pattern/tokenise_charclass_test.lua

-- Run with:
--   nvim --headless -c "luafile tests/pattern/tokeniser_charclass_test.lua" -c "q"

local h = require('tests.harness')
local test = h.test
local deep_eq = h.deep_eq

local tokeniser = require('brook.pattern.tokeniser')

local tokenise = tokeniser.tokenise
local types = require('brook.pattern.types')
local T = types.token_type
local CC = types.cc_token_type

--------------------------------------------------------------------------------
-- Character classes: basics ---------------------------------------------------
--------------------------------------------------------------------------------

test('charclass: simple', function()
  deep_eq(tokenise('[abc]'), {
    { type = T.char_class_open,  value = '[', pos = 1, negated = false },
    { type = CC.cc_literal,      value = 'a', pos = 2 },
    { type = CC.cc_literal,      value = 'b', pos = 3 },
    { type = CC.cc_literal,      value = 'c', pos = 4 },
    { type = T.char_class_close, value = ']', pos = 5 },
  })
end)

test('charclass: negated', function()
  deep_eq(tokenise('[^a]'), {
    { type = T.char_class_open,  value = '[^', pos = 1, negated = true },
    { type = CC.cc_literal,      value = 'a',  pos = 3 },
    { type = T.char_class_close, value = ']',  pos = 4 },
  })
end)

test('charclass: bracket at start as literal', function()
  deep_eq(tokenise('[]a]'), {
    { type = T.char_class_open,  value = '[', pos = 1, negated = false },
    { type = CC.cc_literal,      value = ']', pos = 2 },
    { type = CC.cc_literal,      value = 'a', pos = 3 },
    { type = T.char_class_close, value = ']', pos = 4 },
  })
end)

test('charclass: bracket after negation as literal', function()
  deep_eq(tokenise('[^]a]'), {
    { type = T.char_class_open,  value = '[^', pos = 1, negated = true },
    { type = CC.cc_literal,      value = ']',  pos = 3 },
    { type = CC.cc_literal,      value = 'a',  pos = 4 },
    { type = T.char_class_close, value = ']',  pos = 5 },
  })
end)

test('charclass: hyphen at start as literal', function()
  deep_eq(tokenise('[-a]'), {
    { type = T.char_class_open,  value = '[', pos = 1, negated = false },
    { type = CC.cc_literal,      value = '-', pos = 2 },
    { type = CC.cc_literal,      value = 'a', pos = 3 },
    { type = T.char_class_close, value = ']', pos = 4 },
  })
end)

test('charclass: hyphen at end as literal', function()
  deep_eq(tokenise('[a-]'), {
    { type = T.char_class_open,  value = '[', pos = 1, negated = false },
    { type = CC.cc_literal,      value = 'a', pos = 2 },
    { type = CC.cc_literal,      value = '-', pos = 3 },
    { type = T.char_class_close, value = ']', pos = 4 },
  })
end)

--------------------------------------------------------------------------------
-- Character classes: ranges ---------------------------------------------------
--------------------------------------------------------------------------------

test('charclass range: simple', function()
  deep_eq(tokenise('[a-z]'), {
    { type = T.char_class_open,  value = '[',   pos = 1, negated = false },
    { type = CC.cc_range,        value = 'a-z', pos = 2, from = 'a',     to = 'z' },
    { type = T.char_class_close, value = ']',   pos = 5 },
  })
end)

test('charclass range: digits', function()
  deep_eq(tokenise('[0-9]'), {
    { type = T.char_class_open,  value = '[',   pos = 1, negated = false },
    { type = CC.cc_range,        value = '0-9', pos = 2, from = '0',     to = '9' },
    { type = T.char_class_close, value = ']',   pos = 5 },
  })
end)

test('charclass range: multiple', function()
  deep_eq(tokenise('[a-zA-Z]'), {
    { type = T.char_class_open,  value = '[',   pos = 1, negated = false },
    { type = CC.cc_range,        value = 'a-z', pos = 2, from = 'a',     to = 'z' },
    { type = CC.cc_range,        value = 'A-Z', pos = 5, from = 'A',     to = 'Z' },
    { type = T.char_class_close, value = ']',   pos = 8 },
  })
end)

test('charclass range: followed by literal', function()
  deep_eq(tokenise('[a-z_]'), {
    { type = T.char_class_open,  value = '[',   pos = 1, negated = false },
    { type = CC.cc_range,        value = 'a-z', pos = 2, from = 'a',     to = 'z' },
    { type = CC.cc_literal,      value = '_',   pos = 5 },
    { type = T.char_class_close, value = ']',   pos = 6 },
  })
end)

-- TODO: add more ranges, for example spanning punctuation, or partial alphabet,
-- or even just a range with same start and end. Doesn't matter if they are no
-- valid.

--------------------------------------------------------------------------------
-- Character classes: escapes --------------------------------------------------
--------------------------------------------------------------------------------

test('charclass escape: class inside', function()
  deep_eq(tokenise('[\\d]'), {
    { type = T.char_class_open,  value = '[',   pos = 1, negated = false },
    { type = CC.cc_escape_class, value = '\\d', pos = 2 },
    { type = T.char_class_close, value = ']',   pos = 4 },
  })
end)

test('charclass escape: multiple classes', function()
  deep_eq(tokenise('[\\w\\s]'), {
    { type = T.char_class_open,  value = '[',   pos = 1, negated = false },
    { type = CC.cc_escape_class, value = '\\w', pos = 2 },
    { type = CC.cc_escape_class, value = '\\s', pos = 4 },
    { type = T.char_class_close, value = ']',   pos = 6 },
  })
end)

test('charclass escape: bracket', function()
  deep_eq(tokenise('[\\]]'), {
    { type = T.char_class_open,    value = '[',   pos = 1, negated = false },
    { type = CC.cc_escape_literal, value = '\\]', pos = 2 },
    { type = T.char_class_close,   value = ']',   pos = 4 },
  })
end)

test('charclass escape: backslash', function()
  deep_eq(tokenise('[\\\\]'), {
    { type = T.char_class_open,    value = '[',    pos = 1, negated = false },
    { type = CC.cc_escape_literal, value = '\\\\', pos = 2 },
    { type = T.char_class_close,   value = ']',    pos = 4 },
  })
end)

test('charclass escape: \\b as literal b', function()
  -- in rust regex, \\b inside [...] is literal b, not backspace
  deep_eq(tokenise('[\\b]'), {
    { type = T.char_class_open,    value = '[',   pos = 1, negated = false },
    { type = CC.cc_escape_literal, value = '\\b', pos = 2 },
    { type = T.char_class_close,   value = ']',   pos = 4 },
  })
end)

test('charclass escape: hyphen', function()
  deep_eq(tokenise('[\\-]'), {
    { type = T.char_class_open,    value = '[',   pos = 1, negated = false },
    { type = CC.cc_escape_literal, value = '\\-', pos = 2 },
    { type = T.char_class_close,   value = ']',   pos = 4 },
  })
end)

test('charclass escape: hex', function()
  deep_eq(tokenise('[\\x7F]'), {
    { type = T.char_class_open,  value = '[',     pos = 1, negated = false },
    { type = CC.cc_escape_hex,   value = '\\x7F', pos = 2 },
    { type = T.char_class_close, value = ']',     pos = 6 },
  })
end)

test('charclass escape: unicode', function()
  deep_eq(tokenise('[\\u{20}]'), {
    { type = T.char_class_open,    value = '[',       pos = 1, negated = false },
    { type = CC.cc_escape_unicode, value = '\\u{20}', pos = 2 },
    { type = T.char_class_close,   value = ']',       pos = 8 },
  })
end)

test('charclass escape: octal', function()
  deep_eq(tokenise('[\\0]'), {
    { type = T.char_class_open,  value = '[',   pos = 1, negated = false },
    { type = CC.cc_escape_octal, value = '\\0', pos = 2 },
    { type = T.char_class_close, value = ']',   pos = 4 },
  })
end)

test('charclass escape: property', function()
  deep_eq(tokenise('[\\p{L}]'), {
    { type = T.char_class_open,     value = '[',      pos = 1, negated = false },
    { type = CC.cc_escape_property, value = '\\p{L}', pos = 2, negated = false },
    { type = T.char_class_close,    value = ']',      pos = 7 },
  })
end)

--------------------------------------------------------------------------------
-- Character classes: POSIX ----------------------------------------------------
--------------------------------------------------------------------------------

test('charclass POSIX: alpha', function()
  deep_eq(tokenise('[[:alpha:]]'), {
    { type = T.char_class_open,  value = '[',         pos = 1, negated = false },
    { type = CC.cc_posix,        value = '[:alpha:]', pos = 2, class_name = 'alpha', negated = false },
    { type = T.char_class_close, value = ']',         pos = 11 },
  })
end)

test('charclass POSIX: negated', function()
  deep_eq(tokenise('[[:^alpha:]]'), {
    { type = T.char_class_open,  value = '[',          pos = 1, negated = false },
    { type = CC.cc_posix,        value = '[:^alpha:]', pos = 2, class_name = 'alpha', negated = true },
    { type = T.char_class_close, value = ']',          pos = 12 },
  })
end)

test('charclass POSIX: digit', function()
  deep_eq(tokenise('[[:digit:]]'), {
    { type = T.char_class_open,  value = '[',         pos = 1, negated = false },
    { type = CC.cc_posix,        value = '[:digit:]', pos = 2, class_name = 'digit', negated = false },
    { type = T.char_class_close, value = ']',         pos = 11 },
  })
end)

test('charclass POSIX: multiple', function()
  deep_eq(tokenise('[[:alpha:][:digit:]]'), {
    { type = T.char_class_open,  value = '[',         pos = 1,  negated = false },
    { type = CC.cc_posix,        value = '[:alpha:]', pos = 2,  class_name = 'alpha', negated = false },
    { type = CC.cc_posix,        value = '[:digit:]', pos = 11, class_name = 'digit', negated = false },
    { type = T.char_class_close, value = ']',         pos = 20 },
  })
end)

test('charclass POSIX: with other elements', function()
  deep_eq(tokenise('[[:alpha:]_]'), {
    { type = T.char_class_open,  value = '[',         pos = 1, negated = false },
    { type = CC.cc_posix,        value = '[:alpha:]', pos = 2, class_name = 'alpha', negated = false },
    { type = CC.cc_literal,      value = '_',         pos = 11 },
    { type = T.char_class_close, value = ']',         pos = 12 },
  })
end)

-- TODO: all standard posix classes
-- 'alnum', 'alpha', 'ascii', 'blank', 'cntrl', 'digit',
-- 'graph', 'lower', 'print', 'punct', 'space', 'upper',
-- 'word', 'xdigit',

--------------------------------------------------------------------------------
-- Character classes: set operations -------------------------------------------
--------------------------------------------------------------------------------

test('charclass set: intersection', function()
  deep_eq(tokenise('[a-z&&[\\d]]'), {
    { type = T.char_class_open,  value = '[',   pos = 1, negated = false },
    { type = CC.cc_range,        value = 'a-z', pos = 2, from = 'a',     to = 'z' },
    { type = CC.cc_intersection, value = '&&',  pos = 5 },
    { type = CC.cc_nested_open,  value = '[',   pos = 7, negated = false },
    { type = CC.cc_escape_class, value = '\\d', pos = 8 },
    { type = CC.cc_nested_close, value = ']',   pos = 10 },
    { type = T.char_class_close, value = ']',   pos = 11 },
  })
end)

test('charclass set: nested', function()
  deep_eq(tokenise('[[a-z]]'), {
    { type = T.char_class_open,  value = '[',   pos = 1, negated = false },
    { type = CC.cc_nested_open,  value = '[',   pos = 2, negated = false },
    { type = CC.cc_range,        value = 'a-z', pos = 3, from = 'a',     to = 'z' },
    { type = CC.cc_nested_close, value = ']',   pos = 6 },
    { type = T.char_class_close, value = ']',   pos = 7 },
  })
end)

test('charclass set: negated nested', function()
  deep_eq(tokenise('[a-z&&[^xyz]]'), {
    { type = T.char_class_open,  value = '[',   pos = 1, negated = false },
    { type = CC.cc_range,        value = 'a-z', pos = 2, from = 'a',     to = 'z' },
    { type = CC.cc_intersection, value = '&&',  pos = 5 },
    { type = CC.cc_nested_open,  value = '[^',  pos = 7, negated = true },
    { type = CC.cc_literal,      value = 'x',   pos = 9 },
    { type = CC.cc_literal,      value = 'y',   pos = 10 },
    { type = CC.cc_literal,      value = 'z',   pos = 11 },
    { type = CC.cc_nested_close, value = ']',   pos = 12 },
    { type = T.char_class_close, value = ']',   pos = 13 },
  })
end)

--------------------------------------------------------------------------------
-- Character classes: metacharacters are literal inside ------------------------
--------------------------------------------------------------------------------

test('charclass meta: dot as literal', function()
  deep_eq(tokenise('[.]'), {
    { type = T.char_class_open,  value = '[', pos = 1, negated = false },
    { type = CC.cc_literal,      value = '.', pos = 2 },
    { type = T.char_class_close, value = ']', pos = 3 },
  })
end)

test('charclass meta: star as literal', function()
  deep_eq(tokenise('[*]'), {
    { type = T.char_class_open,  value = '[', pos = 1, negated = false },
    { type = CC.cc_literal,      value = '*', pos = 2 },
    { type = T.char_class_close, value = ']', pos = 3 },
  })
end)

test('charclass meta: plus as literal', function()
  deep_eq(tokenise('[+]'), {
    { type = T.char_class_open,  value = '[', pos = 1, negated = false },
    { type = CC.cc_literal,      value = '+', pos = 2 },
    { type = T.char_class_close, value = ']', pos = 3 },
  })
end)

test('charclass meta: question as literal', function()
  deep_eq(tokenise('[?]'), {
    { type = T.char_class_open,  value = '[', pos = 1, negated = false },
    { type = CC.cc_literal,      value = '?', pos = 2 },
    { type = T.char_class_close, value = ']', pos = 3 },
  })
end)

test('charclass meta: caret in middle as literal', function()
  deep_eq(tokenise('[a^b]'), {
    { type = T.char_class_open,  value = '[', pos = 1, negated = false },
    { type = CC.cc_literal,      value = 'a', pos = 2 },
    { type = CC.cc_literal,      value = '^', pos = 3 },
    { type = CC.cc_literal,      value = 'b', pos = 4 },
    { type = T.char_class_close, value = ']', pos = 5 },
  })
end)

test('charclass meta: pipe as literal', function()
  deep_eq(tokenise('[|]'), {
    { type = T.char_class_open,  value = '[', pos = 1, negated = false },
    { type = CC.cc_literal,      value = '|', pos = 2 },
    { type = T.char_class_close, value = ']', pos = 3 },
  })
end)

test('charclass meta: parens as literal', function()
  deep_eq(tokenise('[()]'), {
    { type = T.char_class_open,  value = '[', pos = 1, negated = false },
    { type = CC.cc_literal,      value = '(', pos = 2 },
    { type = CC.cc_literal,      value = ')', pos = 3 },
    { type = T.char_class_close, value = ']', pos = 4 },
  })
end)

--------------------------------------------------------------------------------
-- Summary ---------------------------------------------------------------------
--------------------------------------------------------------------------------

h.summary()
