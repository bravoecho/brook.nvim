-- tests/pattern/tokenise_basic_test.lua

-- Run with:
--   nvim --headless -c "luafile tests/pattern/tokeniser_basic_test.lua" -c "q"

local h = require('tests.harness')
local test = h.test
local deep_eq = h.deep_eq

local tokeniser = require('brook.pattern.tokeniser')

local types = require('brook.pattern.types')
local T = types.token_type

local tokenise = tokeniser.tokenise

--------------------------------------------------------------------------------
-- Literals --------------------------------------------------------------------
--------------------------------------------------------------------------------

test('literals: simple letters', function()
  deep_eq(tokenise('abc'), {
    { type = T.literal, value = 'a', pos = 1 },
    { type = T.literal, value = 'b', pos = 2 },
    { type = T.literal, value = 'c', pos = 3 },
  })
end)

test('literals: digits', function()
  deep_eq(tokenise('123'), {
    { type = T.literal, value = '1', pos = 1 },
    { type = T.literal, value = '2', pos = 2 },
    { type = T.literal, value = '3', pos = 3 },
  })
end)

test('literals: non-special punctuation', function()
  deep_eq(tokenise('=<>,'), {
    { type = T.literal, value = '=', pos = 1 },
    { type = T.literal, value = '<', pos = 2 },
    { type = T.literal, value = '>', pos = 3 },
    { type = T.literal, value = ',', pos = 4 },
  })
end)

--------------------------------------------------------------------------------
-- Dot -------------------------------------------------------------------------
--------------------------------------------------------------------------------

test('dot: standalone', function()
  deep_eq(tokenise('.'), {
    { type = T.dot, value = '.', pos = 1 },
  })
end)

test('dot: among literals', function()
  deep_eq(tokenise('a.b'), {
    { type = T.literal, value = 'a', pos = 1 },
    { type = T.dot,     value = '.', pos = 2 },
    { type = T.literal, value = 'b', pos = 3 },
  })
end)

test('dot: multiple', function()
  deep_eq(tokenise('...'), {
    { type = T.dot, value = '.', pos = 1 },
    { type = T.dot, value = '.', pos = 2 },
    { type = T.dot, value = '.', pos = 3 },
  })
end)

--------------------------------------------------------------------------------
-- Anchors ---------------------------------------------------------------------
--------------------------------------------------------------------------------

test('anchors: caret at start', function()
  deep_eq(tokenise('^a'), {
    { type = T.anchor,  value = '^', pos = 1 },
    { type = T.literal, value = 'a', pos = 2 },
  })
end)

test('anchors: dollar at end', function()
  deep_eq(tokenise('a$'), {
    { type = T.literal, value = 'a', pos = 1 },
    { type = T.anchor,  value = '$', pos = 2 },
  })
end)

test('anchors: caret in middle', function()
  -- tokeniser does not determine validity
  deep_eq(tokenise('a^b'), {
    { type = T.literal, value = 'a', pos = 1 },
    { type = T.anchor,  value = '^', pos = 2 },
    { type = T.literal, value = 'b', pos = 3 },
  })
end)

--------------------------------------------------------------------------------
-- Alternation -----------------------------------------------------------------
--------------------------------------------------------------------------------

test('alternation: pipe between literals', function()
  deep_eq(tokenise('a|b'), {
    { type = T.literal,     value = 'a', pos = 1 },
    { type = T.alternation, value = '|', pos = 2 },
    { type = T.literal,     value = 'b', pos = 3 },
  })
end)

test('alternation: at start', function()
  -- valid in ripgrep: matches empty or "a"
  deep_eq(tokenise('|a'), {
    { type = T.alternation, value = '|', pos = 1 },
    { type = T.literal,     value = 'a', pos = 2 },
  })
end)

--------------------------------------------------------------------------------
-- Quantifiers: basic ----------------------------------------------------------
--------------------------------------------------------------------------------

test('quantifiers: star', function()
  deep_eq(tokenise('a*'), {
    { type = T.literal,    value = 'a', pos = 1 },
    { type = T.quantifier, value = '*', pos = 2, greedy = true },
  })
end)

test('quantifiers: plus', function()
  deep_eq(tokenise('a+'), {
    { type = T.literal,    value = 'a', pos = 1 },
    { type = T.quantifier, value = '+', pos = 2, greedy = true },
  })
end)

test('quantifiers: question mark', function()
  deep_eq(tokenise('a?'), {
    { type = T.literal,    value = 'a', pos = 1 },
    { type = T.quantifier, value = '?', pos = 2, greedy = true },
  })
end)

--------------------------------------------------------------------------------
-- Quantifiers: non-greedy -----------------------------------------------------
--------------------------------------------------------------------------------

test('quantifiers: non-greedy star', function()
  deep_eq(tokenise('a*?'), {
    { type = T.literal,    value = 'a',  pos = 1 },
    { type = T.quantifier, value = '*?', pos = 2, greedy = false },
  })
end)

test('quantifiers: non-greedy plus', function()
  deep_eq(tokenise('a+?'), {
    { type = T.literal,    value = 'a',  pos = 1 },
    { type = T.quantifier, value = '+?', pos = 2, greedy = false },
  })
end)

test('quantifiers: non-greedy question', function()
  deep_eq(tokenise('a??'), {
    { type = T.literal,    value = 'a',  pos = 1 },
    { type = T.quantifier, value = '??', pos = 2, greedy = false },
  })
end)

--------------------------------------------------------------------------------
-- Quantifiers: possessive -----------------------------------------------------
--------------------------------------------------------------------------------

test('quantifiers: possessive star', function()
  deep_eq(tokenise('a*+'), {
    { type = T.literal,    value = 'a',  pos = 1 },
    { type = T.quantifier, value = '*+', pos = 2, greedy = true, possessive = true },
  })
end)

test('quantifiers: possessive plus', function()
  deep_eq(tokenise('a++'), {
    { type = T.literal,    value = 'a',  pos = 1 },
    { type = T.quantifier, value = '++', pos = 2, greedy = true, possessive = true },
  })
end)

test('quantifier: possessive ?+', function()
  deep_eq(tokenise('a?+'), {
    { type = T.literal,    value = 'a',  pos = 1 },
    { type = T.quantifier, value = '?+', pos = 2, greedy = true, possessive = true },
  })
end)

--------------------------------------------------------------------------------
-- Quantifiers: braces ---------------------------------------------------------
--------------------------------------------------------------------------------

test('quantifiers: exact count', function()
  deep_eq(tokenise('a{3}'), {
    { type = T.literal,    value = 'a',   pos = 1 },
    { type = T.quantifier, value = '{3}', pos = 2, greedy = true },
  })
end)

test('quantifiers: range', function()
  deep_eq(tokenise('a{2,5}'), {
    { type = T.literal,    value = 'a',     pos = 1 },
    { type = T.quantifier, value = '{2,5}', pos = 2, greedy = true },
  })
end)

test('quantifiers: open range', function()
  deep_eq(tokenise('a{2,}'), {
    { type = T.literal,    value = 'a',    pos = 1 },
    { type = T.quantifier, value = '{2,}', pos = 2, greedy = true },
  })
end)

test('quantifiers: non-greedy brace', function()
  deep_eq(tokenise('a{2,5}?'), {
    { type = T.literal,    value = 'a',      pos = 1 },
    { type = T.quantifier, value = '{2,5}?', pos = 2, greedy = false },
  })
end)

--------------------------------------------------------------------------------
-- Quantifiers: edge cases -----------------------------------------------------
--------------------------------------------------------------------------------

test('quantifiers: at pattern start', function()
  -- lexically still a quantifier; parser handles validity
  deep_eq(tokenise('*a'), {
    { type = T.quantifier, value = '*', pos = 1, greedy = true },
    { type = T.literal,    value = 'a', pos = 2 },
  })
end)

test('quantifiers: consecutive', function()
  -- both are lexically quantifiers
  deep_eq(tokenise('a+*'), {
    { type = T.literal,    value = 'a', pos = 1 },
    { type = T.quantifier, value = '+', pos = 2, greedy = true },
    { type = T.quantifier, value = '*', pos = 3, greedy = true },
  })
end)

test('quantifiers: invalid brace as literals', function()
  -- {abc} is not a valid quantifier
  deep_eq(tokenise('a{b}'), {
    { type = T.literal, value = 'a', pos = 1 },
    { type = T.literal, value = '{', pos = 2 },
    { type = T.literal, value = 'b', pos = 3 },
    { type = T.literal, value = '}', pos = 4 },
  })
end)

test('quantifiers: empty brace as literals', function()
  deep_eq(tokenise('a{}'), {
    { type = T.literal, value = 'a', pos = 1 },
    { type = T.literal, value = '{', pos = 2 },
    { type = T.literal, value = '}', pos = 3 },
  })
end)

test('quantifiers: brace starting with comma as literals', function()
  deep_eq(tokenise('a{,3}'), {
    { type = T.literal, value = 'a', pos = 1 },
    { type = T.literal, value = '{', pos = 2 },
    { type = T.literal, value = ',', pos = 3 },
    { type = T.literal, value = '3', pos = 4 },
    { type = T.literal, value = '}', pos = 5 },
  })
end)

--------------------------------------------------------------------------------
-- Summary ---------------------------------------------------------------------
--------------------------------------------------------------------------------

h.summary()
