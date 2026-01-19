-- tests/pattern/parser_validation_test.lua
-- Validation, error, and warning tests for the parser.
--
-- The parser detects unsupported constructs and emits errors or warnings.
-- Errors prevent translation; warnings allow translation with caveats.
--
-- Run with:
--   nvim --headless -u NONE -c "set rtp+=." -c "luafile tests/pattern/parser_validation_test.lua"

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

--------------------------------------------------------------------------------
--- Successful parse (no errors, no warnings) ----------------------------------
--------------------------------------------------------------------------------

test('valid: empty input succeeds', function()
  local result = parse({})
  eq(result.error, nil)
  deep_eq(result.warnings, {})
  deep_eq(result.tokens, {})
end)

test('valid: simple literal pattern succeeds', function()
  local result = parse({
    { type = T.literal, value = 'a', pos = 1 },
    { type = T.literal, value = 'b', pos = 2 },
    { type = T.literal, value = 'c', pos = 3 },
  })
  eq(result.error, nil)
  deep_eq(result.warnings, {})
  eq(#result.tokens, 3)
end)

test('valid: pattern with balanced groups succeeds', function()
  local result = parse({
    { type = T.group_open, value = '(', pos = 1, kind = GK.capturing },
    { type = T.literal, value = 'a', pos = 2 },
    { type = T.group_close, value = ')', pos = 3 },
  })
  eq(result.error, nil)
  deep_eq(result.warnings, {})
end)

test('valid: nested groups succeed', function()
  local result = parse({
    { type = T.group_open, value = '(', pos = 1, kind = GK.capturing },
    { type = T.group_open, value = '(?:', pos = 2, kind = GK.non_capturing },
    { type = T.literal, value = 'a', pos = 5 },
    { type = T.group_close, value = ')', pos = 6 },
    { type = T.group_close, value = ')', pos = 7 },
  })
  eq(result.error, nil)
  deep_eq(result.warnings, {})
end)

--------------------------------------------------------------------------------
--- Unsupported constructs: lookarounds ----------------------------------------
--------------------------------------------------------------------------------

test('error: positive lookahead (?=', function()
  local result = parse({
    { type = T.group_open, value = '(?=', pos = 1, kind = GK.lookahead_pos },
    { type = T.literal, value = 'a', pos = 4 },
    { type = T.group_close, value = ')', pos = 5 },
  })
  eq(result.error ~= nil, true)
end)

test('error: negative lookahead (?!', function()
  local result = parse({
    { type = T.group_open, value = '(?!', pos = 1, kind = GK.lookahead_neg },
    { type = T.literal, value = 'a', pos = 4 },
    { type = T.group_close, value = ')', pos = 5 },
  })
  eq(result.error ~= nil, true)
end)

test('error: positive lookbehind (?<=', function()
  local result = parse({
    { type = T.group_open, value = '(?<=', pos = 1, kind = GK.lookbehind_pos },
    { type = T.literal, value = 'a', pos = 5 },
    { type = T.group_close, value = ')', pos = 6 },
  })
  eq(result.error ~= nil, true)
end)

test('error: negative lookbehind (?<!', function()
  local result = parse({
    { type = T.group_open, value = '(?<!', pos = 1, kind = GK.lookbehind_neg },
    { type = T.literal, value = 'a', pos = 5 },
    { type = T.group_close, value = ')', pos = 6 },
  })
  eq(result.error ~= nil, true)
end)

--------------------------------------------------------------------------------
--- Unsupported constructs: atomic groups --------------------------------------
--------------------------------------------------------------------------------

test('error: atomic group (?>', function()
  local result = parse({
    { type = T.group_open, value = '(?>', pos = 1, kind = GK.atomic },
    { type = T.literal, value = 'a', pos = 4 },
    { type = T.group_close, value = ')', pos = 5 },
  })
  eq(result.error ~= nil, true)
end)

--------------------------------------------------------------------------------
--- Unsupported constructs: possessive quantifiers -----------------------------
--------------------------------------------------------------------------------

test('error: possessive quantifier *+', function()
  local result = parse({
    { type = T.literal, value = 'a', pos = 1 },
    { type = T.quantifier, value = '*+', pos = 2, greedy = true, possessive = true },
  })
  eq(result.error ~= nil, true)
end)

test('error: possessive quantifier ++', function()
  local result = parse({
    { type = T.literal, value = 'a', pos = 1 },
    { type = T.quantifier, value = '++', pos = 2, greedy = true, possessive = true },
  })
  eq(result.error ~= nil, true)
end)

test('error: possessive quantifier ?+', function()
  local result = parse({
    { type = T.literal, value = 'a', pos = 1 },
    { type = T.quantifier, value = '?+', pos = 2, greedy = true, possessive = true },
  })
  eq(result.error ~= nil, true)
end)

test('error: possessive quantifier {n}+', function()
  local result = parse({
    { type = T.literal, value = 'a', pos = 1 },
    { type = T.quantifier, value = '{2,3}+', pos = 2, greedy = true, possessive = true },
  })
  eq(result.error ~= nil, true)
end)

--------------------------------------------------------------------------------
--- Unsupported constructs: negative word boundary -----------------------------
--------------------------------------------------------------------------------

test('error: \\B negative word boundary', function()
  local result = parse({
    { type = T.escape_boundary, value = '\\B', pos = 1, boundary_kind = 'word_neg' },
  })
  eq(result.error ~= nil, true)
end)

--------------------------------------------------------------------------------
--- Unsupported constructs: unicode properties ---------------------------------
--------------------------------------------------------------------------------

test('error: \\p{L} unicode property', function()
  local result = parse({
    { type = T.escape_property, value = '\\p{L}', pos = 1, negated = false },
  })
  eq(result.error ~= nil, true)
end)

test('error: \\P{L} negated unicode property', function()
  local result = parse({
    { type = T.escape_property, value = '\\P{L}', pos = 1, negated = true },
  })
  eq(result.error ~= nil, true)
end)

test('error: \\p{Greek} named unicode property', function()
  local result = parse({
    { type = T.escape_property, value = '\\p{Greek}', pos = 1, negated = false },
  })
  eq(result.error ~= nil, true)
end)

--------------------------------------------------------------------------------
--- Unsupported constructs: backreferences -------------------------------------
--------------------------------------------------------------------------------

test('error: \\1 backreference', function()
  local result = parse({
    { type = T.escape_backref, value = '\\1', pos = 1 },
  })
  eq(result.error ~= nil, true)
end)

test('error: \\9 backreference', function()
  local result = parse({
    { type = T.escape_backref, value = '\\9', pos = 1 },
  })
  eq(result.error ~= nil, true)
end)

--------------------------------------------------------------------------------
--- Warnings: named groups -----------------------------------------------------
--------------------------------------------------------------------------------

test('warning: single named group (Python syntax)', function()
  local result = parse({
    { type = T.group_open, value = '(?P<name>', pos = 1, kind = GK.named_python, name = 'name' },
    { type = T.literal, value = 'a', pos = 10 },
    { type = T.group_close, value = ')', pos = 11 },
  })
  eq(result.error, nil)
  eq(#result.warnings, 1)
end)

test('warning: single named group (PCRE syntax)', function()
  local result = parse({
    { type = T.group_open, value = '(?<name>', pos = 1, kind = GK.named_pcre, name = 'name' },
    { type = T.literal, value = 'a', pos = 9 },
    { type = T.group_close, value = ')', pos = 10 },
  })
  eq(result.error, nil)
  eq(#result.warnings, 1)
end)

test('warning: multiple named groups', function()
  local result = parse({
    { type = T.group_open, value = '(?P<first>', pos = 1, kind = GK.named_python, name = 'first' },
    { type = T.literal, value = 'a', pos = 11 },
    { type = T.group_close, value = ')', pos = 12 },
    { type = T.group_open, value = '(?P<second>', pos = 13, kind = GK.named_python, name = 'second' },
    { type = T.literal, value = 'b', pos = 24 },
    { type = T.group_close, value = ')', pos = 25 },
  })
  eq(result.error, nil)
  eq(#result.warnings, 1)
end)

--------------------------------------------------------------------------------
--- Warnings: anchors \A and \z ------------------------------------------------
--------------------------------------------------------------------------------

test('warning: \\A anchor', function()
  local result = parse({
    { type = T.escape_boundary, value = '\\A', pos = 1, boundary_kind = 'start' },
    { type = T.literal, value = 'a', pos = 3 },
  })
  eq(result.error, nil)
  eq(#result.warnings, 1)
end)

test('warning: \\z anchor', function()
  local result = parse({
    { type = T.literal, value = 'a', pos = 1 },
    { type = T.escape_boundary, value = '\\z', pos = 2, boundary_kind = 'end' },
  })
  eq(result.error, nil)
  eq(#result.warnings, 1)
end)

test('warning: both \\A and \\z', function()
  local result = parse({
    { type = T.escape_boundary, value = '\\A', pos = 1, boundary_kind = 'start' },
    { type = T.literal, value = 'a', pos = 3 },
    { type = T.escape_boundary, value = '\\z', pos = 4, boundary_kind = 'end' },
  })
  eq(result.error, nil)
  eq(#result.warnings, 2)
end)

--------------------------------------------------------------------------------
--- Multiple warnings ----------------------------------------------------------
--------------------------------------------------------------------------------

test('warning: named group and \\A', function()
  local result = parse({
    { type = T.escape_boundary, value = '\\A', pos = 1, boundary_kind = 'start' },
    { type = T.group_open, value = '(?P<name>', pos = 3, kind = GK.named_python, name = 'name' },
    { type = T.literal, value = 'a', pos = 12 },
    { type = T.group_close, value = ')', pos = 13 },
  })
  eq(result.error, nil)
  eq(#result.warnings, 2)
end)

--------------------------------------------------------------------------------
--- Flag groups ----------------------------------------------------------------
--------------------------------------------------------------------------------

test('valid: flag group (?i) succeeds', function()
  local result = parse({
    { type = T.group_open, value = '(?i)', pos = 1, kind = GK.flags, flags = 'i', scoped = false },
    { type = T.literal, value = 'a', pos = 5 },
  })
  eq(result.error, nil)
end)

test('valid: scoped flag group (?i:...) succeeds', function()
  local result = parse({
    { type = T.group_open, value = '(?i:', pos = 1, kind = GK.flags, flags = 'i', scoped = true },
    { type = T.literal, value = 'a', pos = 5 },
    { type = T.group_close, value = ')', pos = 6 },
  })
  eq(result.error, nil)
end)

--------------------------------------------------------------------------------
--- Character class validation -------------------------------------------------
--------------------------------------------------------------------------------

test('valid: character class with intersection', function()
  local result = parse({
    { type = T.char_class_open, value = '[', pos = 1, negated = false },
    { type = CC.cc_range, value = 'a-z', pos = 2, from = 'a', to = 'z' },
    { type = CC.cc_intersection, value = '&&', pos = 5 },
    { type = CC.cc_nested_open, value = '[', pos = 7, negated = false },
    { type = CC.cc_range, value = 'A-Z', pos = 8, from = 'A', to = 'Z' },
    { type = CC.cc_nested_close, value = ']', pos = 11 },
    { type = T.char_class_close, value = ']', pos = 12 },
  })
  -- Intersection is valid syntax, may or may not be translatable
  eq(result.error, nil)
end)

test('valid: POSIX class in character class', function()
  local result = parse({
    { type = T.char_class_open, value = '[', pos = 1, negated = false },
    { type = CC.cc_posix, value = '[:alpha:]', pos = 2, class_name = 'alpha', negated = false },
    { type = T.char_class_close, value = ']', pos = 11 },
  })
  eq(result.error, nil)
end)

test('valid: negated POSIX class', function()
  local result = parse({
    { type = T.char_class_open, value = '[', pos = 1, negated = false },
    { type = CC.cc_posix, value = '[:^digit:]', pos = 2, class_name = 'digit', negated = true },
    { type = T.char_class_close, value = ']', pos = 12 },
  })
  eq(result.error, nil)
end)

--------------------------------------------------------------------------------
--- Edge cases -----------------------------------------------------------------
--------------------------------------------------------------------------------

test('valid: pattern with only anchors', function()
  local result = parse({
    { type = T.anchor, value = '^', pos = 1 },
    { type = T.anchor, value = '$', pos = 2 },
  })
  eq(result.error, nil)
  deep_eq(result.warnings, {})
end)

test('valid: pattern with only dot', function()
  local result = parse({
    { type = T.dot, value = '.', pos = 1 },
  })
  eq(result.error, nil)
  deep_eq(result.warnings, {})
end)

test('valid: alternation at top level', function()
  local result = parse({
    { type = T.literal, value = 'a', pos = 1 },
    { type = T.alternation, value = '|', pos = 2 },
    { type = T.literal, value = 'b', pos = 3 },
  })
  eq(result.error, nil)
  deep_eq(result.warnings, {})
end)

test('valid: quantifier after group', function()
  local result = parse({
    { type = T.group_open, value = '(', pos = 1, kind = GK.capturing },
    { type = T.literal, value = 'a', pos = 2 },
    { type = T.group_close, value = ')', pos = 3 },
    { type = T.quantifier, value = '+', pos = 4, greedy = true },
  })
  eq(result.error, nil)
  deep_eq(result.warnings, {})
end)

test('valid: quantifier after character class', function()
  local result = parse({
    { type = T.char_class_open, value = '[', pos = 1, negated = false },
    { type = CC.cc_range, value = 'a-z', pos = 2, from = 'a', to = 'z' },
    { type = T.char_class_close, value = ']', pos = 5 },
    { type = T.quantifier, value = '*', pos = 6, greedy = true },
  })
  eq(result.error, nil)
  deep_eq(result.warnings, {})
end)

--------------------------------------------------------------------------------
--- Summary --------------------------------------------------------------------
--------------------------------------------------------------------------------

h.summary()
