-- tests/pattern/tokenise_complex_test.lua

-- Run with:
--   nvim --headless -c "set rtp+=." -c "luafile tests/pattern/tokeniser_complex_test.lua" -c "q"

local h = require('tests.harness')
local test = h.test
local deep_eq = h.deep_eq
local eq = h.eq

local tokeniser = require('brook.pattern.tokeniser')

local types = require('brook.pattern.types')
local T = types.token_type
local CC = types.cc_token_type
local GK = types.group_kind

local tokenise = tokeniser.tokenise

--------------------------------------------------------------------------------
-- Complex patterns ------------------------------------------------------------
--------------------------------------------------------------------------------

test('complex: email-like pattern structure', function()
  local result = tokenise('[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}')
  -- verify key structural elements
  eq(result[1].type, T.char_class_open)
  eq(result[1].negated, false)
  -- find the + quantifier after first class
  local found_plus = false
  for i, tok in ipairs(result) do
    if tok.type == T.quantifier and tok.value == '+' then
      found_plus = true
      -- previous token should be char_class_close
      eq(result[i - 1].type, T.char_class_close)
      break
    end
  end
  eq(found_plus, true)
end)

test('complex: multiple features', function()
  deep_eq(tokenise('^(?:\\d+)\\b'), {
    { type = T.anchor,          value = '^',   pos = 1 },
    { type = T.group_open,      value = '(?:', pos = 2, kind = GK.non_capturing },
    { type = T.escape_class,    value = '\\d', pos = 5 },
    { type = T.quantifier,      value = '+',   pos = 7, greedy = true },
    { type = T.group_close,     value = ')',   pos = 8 },
    { type = T.escape_boundary, value = '\\b', pos = 9, boundary_kind = 'word' },
  })
end)

test('complex: URL-like pattern structure', function()
  local result = tokenise('https?://[^/]+/.*')
  eq(result[1].type, T.literal)
  eq(result[1].value, 'h')
  -- verify the ? is a quantifier after s
  local found_quantifier = false
  for i, tok in ipairs(result) do
    if tok.type == T.quantifier and tok.value == '?' then
      found_quantifier = true
      eq(result[i - 1].type, T.literal)
      eq(result[i - 1].value, 's')
      break
    end
  end
  eq(found_quantifier, true)
end)

--------------------------------------------------------------------------------
-- Edge cases ------------------------------------------------------------------
--------------------------------------------------------------------------------

test('edge: empty pattern', function()
  deep_eq(tokenise(''), {})
end)

test('edge: trailing backslash', function()
  -- trailing backslash is incomplete escape, emitted as escape_literal
  deep_eq(tokenise('a\\'), {
    { type = T.literal,        value = 'a',  pos = 1 },
    { type = T.escape_literal, value = '\\', pos = 2 },
  })
end)

test('edge: unclosed character class', function()
  -- should still produce tokens; parser handles the error
  local result = tokenise('[abc')
  eq(result[1].type, T.char_class_open)
  eq(result[2].type, CC.cc_literal)
  eq(result[2].value, 'a')
end)

test('edge: unclosed group', function()
  local result = tokenise('(abc')
  eq(result[1].type, T.group_open)
  eq(result[1].kind, GK.capturing)
  eq(result[2].type, T.literal)
  eq(result[2].value, 'a')
end)

test('edge: unmatched close paren', function()
  deep_eq(tokenise('a)'), {
    { type = T.literal,     value = 'a', pos = 1 },
    { type = T.group_close, value = ')', pos = 2 },
  })
end)

test('edge: multiple quantifiers after literal', function()
  -- a+*? should be: literal, quantifier +, non-greedy quantifier *?
  -- parser decides validity
  deep_eq(tokenise('a+*?'), {
    { type = T.literal,    value = 'a',  pos = 1 },
    { type = T.quantifier, value = '+',  pos = 2, greedy = true },
    { type = T.quantifier, value = '*?', pos = 3, greedy = false },
  })
end)

--------------------------------------------------------------------------------
-- Position tracking -----------------------------------------------------------
--------------------------------------------------------------------------------

test('position: simple pattern', function()
  local tokens = tokenise('a.b')
  eq(tokens[1].pos, 1)
  eq(tokens[2].pos, 2)
  eq(tokens[3].pos, 3)
end)

test('position: multi-char tokens', function()
  local tokens = tokenise('(?:a)')
  eq(tokens[1].pos, 1) -- (?:
  eq(tokens[2].pos, 4) -- a
  eq(tokens[3].pos, 5) -- )
end)

test('position: escape sequences', function()
  local tokens = tokenise('\\d\\w')
  eq(tokens[1].pos, 1) -- \\d
  eq(tokens[2].pos, 3) -- \\w
end)

test('position: named groups', function()
  local tokens = tokenise('(?P<foo>a)')
  eq(tokens[1].pos, 1)  -- (?P<foo>
  eq(tokens[2].pos, 9)  -- a
  eq(tokens[3].pos, 10) -- )
end)

--------------------------------------------------------------------------------
-- Summary ---------------------------------------------------------------------
--------------------------------------------------------------------------------

h.summary()
