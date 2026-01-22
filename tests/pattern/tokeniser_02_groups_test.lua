-- tests/pattern/tokenise_groups_test.lua

-- Run with:
--   nvim --headless -c "luafile tests/pattern/tokeniser_groups_test.lua" -c "q"

local h = require('tests.harness')
local test = h.test
local deep_eq = h.deep_eq

local tokeniser = require('brook.pattern.tokeniser')

local types = require('brook.pattern.types')
local T = types.token_type
local GK = types.group_kind

--- Helper to extract tokens from tokenise result.
local function tokenise(input)
  return tokeniser.tokenise(input).tokens
end

--------------------------------------------------------------------------------
-- Groups: basic ---------------------------------------------------------------
--------------------------------------------------------------------------------

test('groups: capturing', function()
  deep_eq(tokenise('(a)'), {
    { type = T.group_open,  value = '(', pos = 1, kind = GK.capturing },
    { type = T.literal,     value = 'a', pos = 2 },
    { type = T.group_close, value = ')', pos = 3 },
  })
end)

test('groups: non-capturing', function()
  deep_eq(tokenise('(?:a)'), {
    { type = T.group_open,  value = '(?:', pos = 1, kind = GK.non_capturing },
    { type = T.literal,     value = 'a',   pos = 4 },
    { type = T.group_close, value = ')',   pos = 5 },
  })
end)

test('groups: nested', function()
  deep_eq(tokenise('((a))'), {
    { type = T.group_open,  value = '(', pos = 1, kind = GK.capturing },
    { type = T.group_open,  value = '(', pos = 2, kind = GK.capturing },
    { type = T.literal,     value = 'a', pos = 3 },
    { type = T.group_close, value = ')', pos = 4 },
    { type = T.group_close, value = ')', pos = 5 },
  })
end)

--------------------------------------------------------------------------------
-- Groups: named (Python style) ------------------------------------------------
--------------------------------------------------------------------------------

test('groups: named Python simple', function()
  deep_eq(tokenise('(?P<foo>a)'), {
    { type = T.group_open,  value = '(?P<foo>', pos = 1, kind = GK.named_python, name = 'foo' },
    { type = T.literal,     value = 'a',        pos = 9 },
    { type = T.group_close, value = ')',        pos = 10 },
  })
end)

test('groups: named Python with underscore', function()
  deep_eq(tokenise('(?P<foo_bar>x)'), {
    { type = T.group_open,  value = '(?P<foo_bar>', pos = 1, kind = GK.named_python, name = 'foo_bar' },
    { type = T.literal,     value = 'x',            pos = 13 },
    { type = T.group_close, value = ')',            pos = 14 },
  })
end)

test('groups: named Python starting with underscore', function()
  deep_eq(tokenise('(?P<_quux>z)'), {
    { type = T.group_open,  value = '(?P<_quux>', pos = 1, kind = GK.named_python, name = '_quux' },
    { type = T.literal,     value = 'z',          pos = 11 },
    { type = T.group_close, value = ')',          pos = 12 },
  })
end)

--------------------------------------------------------------------------------
-- Groups: named (PCRE style) --------------------------------------------------
--------------------------------------------------------------------------------

test('groups: named PCRE simple', function()
  deep_eq(tokenise('(?<bar>a)'), {
    { type = T.group_open,  value = '(?<bar>', pos = 1, kind = GK.named_pcre, name = 'bar' },
    { type = T.literal,     value = 'a',       pos = 8 },
    { type = T.group_close, value = ')',       pos = 9 },
  })
end)

test('groups: named PCRE with digits', function()
  deep_eq(tokenise('(?<baz123>y)'), {
    { type = T.group_open,  value = '(?<baz123>', pos = 1, kind = GK.named_pcre, name = 'baz123' },
    { type = T.literal,     value = 'y',          pos = 11 },
    { type = T.group_close, value = ')',          pos = 12 },
  })
end)

--------------------------------------------------------------------------------
--- Groups: named (mixed style) ------------------------------------------------
--------------------------------------------------------------------------------

test('groups: multiple named mixed styles', function()
  deep_eq(tokenise('(?<foo>a)(?P<bar>b)'), {
    { type = T.group_open,  value = '(?<foo>',  pos = 1,  kind = GK.named_pcre,   name = 'foo' },
    { type = T.literal,     value = 'a',        pos = 8 },
    { type = T.group_close, value = ')',        pos = 9 },
    { type = T.group_open,  value = '(?P<bar>', pos = 10, kind = GK.named_python, name = 'bar' },
    { type = T.literal,     value = 'b',        pos = 18 },
    { type = T.group_close, value = ')',        pos = 19 },
  })
end)

--------------------------------------------------------------------------------
-- Groups: lookarounds (PCRE2) -------------------------------------------------
--------------------------------------------------------------------------------

test('groups: positive lookahead', function()
  deep_eq(tokenise('(?=a)'), {
    { type = T.group_open,  value = '(?=', pos = 1, kind = GK.lookahead_pos },
    { type = T.literal,     value = 'a',   pos = 4 },
    { type = T.group_close, value = ')',   pos = 5 },
  })
end)

test('groups: negative lookahead', function()
  deep_eq(tokenise('(?!a)'), {
    { type = T.group_open,  value = '(?!', pos = 1, kind = GK.lookahead_neg },
    { type = T.literal,     value = 'a',   pos = 4 },
    { type = T.group_close, value = ')',   pos = 5 },
  })
end)

test('groups: positive lookbehind', function()
  deep_eq(tokenise('(?<=a)'), {
    { type = T.group_open,  value = '(?<=', pos = 1, kind = GK.lookbehind_pos },
    { type = T.literal,     value = 'a',    pos = 5 },
    { type = T.group_close, value = ')',    pos = 6 },
  })
end)

test('groups: negative lookbehind', function()
  deep_eq(tokenise('(?<!a)'), {
    { type = T.group_open,  value = '(?<!', pos = 1, kind = GK.lookbehind_neg },
    { type = T.literal,     value = 'a',    pos = 5 },
    { type = T.group_close, value = ')',    pos = 6 },
  })
end)

test('groups: atomic', function()
  deep_eq(tokenise('(?>a)'), {
    { type = T.group_open,  value = '(?>', pos = 1, kind = GK.atomic },
    { type = T.literal,     value = 'a',   pos = 4 },
    { type = T.group_close, value = ')',   pos = 5 },
  })
end)

--------------------------------------------------------------------------------
-- Groups: flags (standalone) --------------------------------------------------
--------------------------------------------------------------------------------

test('groups: standalone flag single', function()
  deep_eq(tokenise('(?i)a'), {
    { type = T.group_open, value = '(?i)', pos = 1, kind = GK.flags, flags = 'i', scoped = false },
    { type = T.literal,    value = 'a',    pos = 5 },
  })
end)

test('groups: standalone flag multiple', function()
  deep_eq(tokenise('(?is)a'), {
    { type = T.group_open, value = '(?is)', pos = 1, kind = GK.flags, flags = 'is', scoped = false },
    { type = T.literal,    value = 'a',     pos = 6 },
  })
end)

test('groups: standalone flag negation', function()
  deep_eq(tokenise('(?-i)a'), {
    { type = T.group_open, value = '(?-i)', pos = 1, kind = GK.flags, flags = '-i', scoped = false },
    { type = T.literal,    value = 'a',     pos = 6 },
  })
end)

test('groups: standalone flag mixed', function()
  deep_eq(tokenise('(?im-s)a'), {
    { type = T.group_open, value = '(?im-s)', pos = 1, kind = GK.flags, flags = 'im-s', scoped = false },
    { type = T.literal,    value = 'a',       pos = 8 },
  })
end)

test('groups: all standard flags', function()
  -- i: case insensitive, m: multiline, s: dotall, U: swap greediness,
  -- u: unicode, x: extended/verbose, R: CRLF mode
  deep_eq(tokenise('(?imsUuxR)'), {
    { type = T.group_open, value = '(?imsUuxR)', pos = 1, kind = GK.flags, flags = 'imsUuxR', scoped = false },
  })
end)

--------------------------------------------------------------------------------
-- Groups: flags (scoped) ------------------------------------------------------
--------------------------------------------------------------------------------

test('groups: scoped flag single', function()
  deep_eq(tokenise('(?i:a)'), {
    { type = T.group_open,  value = '(?i:', pos = 1, kind = GK.flags, flags = 'i', scoped = true },
    { type = T.literal,     value = 'a',    pos = 5 },
    { type = T.group_close, value = ')',    pos = 6 },
  })
end)

test('groups: scoped flag multiple', function()
  deep_eq(tokenise('(?ims:a)'), {
    { type = T.group_open,  value = '(?ims:', pos = 1, kind = GK.flags, flags = 'ims', scoped = true },
    { type = T.literal,     value = 'a',      pos = 7 },
    { type = T.group_close, value = ')',      pos = 8 },
  })
end)

test('groups: scoped flag negation', function()
  deep_eq(tokenise('(?-i:a)'), {
    { type = T.group_open,  value = '(?-i:', pos = 1, kind = GK.flags, flags = '-i', scoped = true },
    { type = T.literal,     value = 'a',     pos = 6 },
    { type = T.group_close, value = ')',     pos = 7 },
  })
end)

test('groups: scoped flag mixed', function()
  deep_eq(tokenise('(?i-ms:a)'), {
    { type = T.group_open,  value = '(?i-ms:', pos = 1, kind = GK.flags, flags = 'i-ms', scoped = true },
    { type = T.literal,     value = 'a',       pos = 8 },
    { type = T.group_close, value = ')',       pos = 9 },
  })
end)

--------------------------------------------------------------------------------
-- Summary
--------------------------------------------------------------------------------

h.summary()
