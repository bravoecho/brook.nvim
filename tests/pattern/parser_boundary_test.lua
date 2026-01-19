-- tests/pattern/parser_boundary_test.lua
-- Word boundary (\b) annotation tests for the parser.
--
-- The parser annotates `\b` tokens with `prev_wordness` and `next_wordness`
-- fields, which the translator uses to emit the correct Vim regex.
--
-- Run with:
--   nvim --headless -u NONE -c "set rtp+=." -c "luafile tests/pattern/parser_boundary_test.lua"

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
local W = types.wordness

--------------------------------------------------------------------------------
--- Boundary at pattern edges --------------------------------------------------
--------------------------------------------------------------------------------

test('boundary: \\b at start has prev_wordness nil', function()
  local result = parse({
    { type = T.escape_boundary, value = '\\b', pos = 1, boundary_kind = 'word' },
    { type = T.literal, value = 'a', pos = 3 },
  })
  eq(result.tokens[1].prev_wordness, nil)
  eq(result.tokens[1].next_wordness, W.word)
end)

test('boundary: \\b at end has next_wordness nil', function()
  local result = parse({
    { type = T.literal, value = 'a', pos = 1 },
    { type = T.escape_boundary, value = '\\b', pos = 2, boundary_kind = 'word' },
  })
  eq(result.tokens[2].prev_wordness, W.word)
  eq(result.tokens[2].next_wordness, nil)
end)

test('boundary: \\b alone has both nil', function()
  local result = parse({
    { type = T.escape_boundary, value = '\\b', pos = 1, boundary_kind = 'word' },
  })
  eq(result.tokens[1].prev_wordness, nil)
  eq(result.tokens[1].next_wordness, nil)
end)

--------------------------------------------------------------------------------
--- Boundary between literals --------------------------------------------------
--------------------------------------------------------------------------------

test('boundary: \\b between word chars', function()
  local result = parse({
    { type = T.literal, value = 'a', pos = 1 },
    { type = T.escape_boundary, value = '\\b', pos = 2, boundary_kind = 'word' },
    { type = T.literal, value = 'b', pos = 4 },
  })
  eq(result.tokens[2].prev_wordness, W.word)
  eq(result.tokens[2].next_wordness, W.word)
end)

test('boundary: \\b between non-word chars', function()
  local result = parse({
    { type = T.literal, value = '.', pos = 1 },
    { type = T.escape_boundary, value = '\\b', pos = 2, boundary_kind = 'word' },
    { type = T.literal, value = '-', pos = 4 },
  })
  eq(result.tokens[2].prev_wordness, W.non_word)
  eq(result.tokens[2].next_wordness, W.non_word)
end)

test('boundary: \\b between word and non-word', function()
  local result = parse({
    { type = T.literal, value = 'a', pos = 1 },
    { type = T.escape_boundary, value = '\\b', pos = 2, boundary_kind = 'word' },
    { type = T.literal, value = '.', pos = 4 },
  })
  eq(result.tokens[2].prev_wordness, W.word)
  eq(result.tokens[2].next_wordness, W.non_word)
end)

test('boundary: \\b between non-word and word', function()
  local result = parse({
    { type = T.literal, value = '.', pos = 1 },
    { type = T.escape_boundary, value = '\\b', pos = 2, boundary_kind = 'word' },
    { type = T.literal, value = 'a', pos = 4 },
  })
  eq(result.tokens[2].prev_wordness, W.non_word)
  eq(result.tokens[2].next_wordness, W.word)
end)

--------------------------------------------------------------------------------
--- Boundary with escape classes -----------------------------------------------
--------------------------------------------------------------------------------

test('boundary: \\b after \\w, before \\s', function()
  local result = parse({
    { type = T.escape_class, value = '\\w', pos = 1 },
    { type = T.escape_boundary, value = '\\b', pos = 3, boundary_kind = 'word' },
    { type = T.escape_class, value = '\\s', pos = 5 },
  })
  eq(result.tokens[2].prev_wordness, W.word)
  eq(result.tokens[2].next_wordness, W.non_word)
end)

test('boundary: \\b after \\d, before \\W', function()
  local result = parse({
    { type = T.escape_class, value = '\\d', pos = 1 },
    { type = T.escape_boundary, value = '\\b', pos = 3, boundary_kind = 'word' },
    { type = T.escape_class, value = '\\W', pos = 5 },
  })
  eq(result.tokens[2].prev_wordness, W.word)
  eq(result.tokens[2].next_wordness, W.non_word)
end)

test('boundary: \\b after \\S, before \\D', function()
  local result = parse({
    { type = T.escape_class, value = '\\S', pos = 1 },
    { type = T.escape_boundary, value = '\\b', pos = 3, boundary_kind = 'word' },
    { type = T.escape_class, value = '\\D', pos = 5 },
  })
  eq(result.tokens[2].prev_wordness, W.unknown)
  eq(result.tokens[2].next_wordness, W.unknown)
end)

--------------------------------------------------------------------------------
--- Boundary with dot ----------------------------------------------------------
--------------------------------------------------------------------------------

test('boundary: \\b after dot has prev unknown', function()
  local result = parse({
    { type = T.dot, value = '.', pos = 1 },
    { type = T.escape_boundary, value = '\\b', pos = 2, boundary_kind = 'word' },
    { type = T.literal, value = 'a', pos = 4 },
  })
  eq(result.tokens[2].prev_wordness, W.unknown)
  eq(result.tokens[2].next_wordness, W.word)
end)

test('boundary: \\b before dot has next unknown', function()
  local result = parse({
    { type = T.literal, value = 'a', pos = 1 },
    { type = T.escape_boundary, value = '\\b', pos = 2, boundary_kind = 'word' },
    { type = T.dot, value = '.', pos = 4 },
  })
  eq(result.tokens[2].prev_wordness, W.word)
  eq(result.tokens[2].next_wordness, W.unknown)
end)

--------------------------------------------------------------------------------
--- Boundary with quantifiers --------------------------------------------------
--------------------------------------------------------------------------------

test('boundary: \\b after quantified \\w inherits word', function()
  local result = parse({
    { type = T.escape_class, value = '\\w', pos = 1 },
    { type = T.quantifier, value = '+', pos = 3, greedy = true },
    { type = T.escape_boundary, value = '\\b', pos = 4, boundary_kind = 'word' },
  })
  eq(result.tokens[3].prev_wordness, W.word)
  eq(result.tokens[3].next_wordness, nil)
end)

test('boundary: \\b after quantified . inherits unknown', function()
  local result = parse({
    { type = T.dot, value = '.', pos = 1 },
    { type = T.quantifier, value = '*', pos = 2, greedy = true },
    { type = T.escape_boundary, value = '\\b', pos = 3, boundary_kind = 'word' },
  })
  eq(result.tokens[3].prev_wordness, W.unknown)
  eq(result.tokens[3].next_wordness, nil)
end)

test('boundary: \\b before quantified atom looks at atom not quantifier', function()
  local result = parse({
    { type = T.escape_boundary, value = '\\b', pos = 1, boundary_kind = 'word' },
    { type = T.escape_class, value = '\\w', pos = 3 },
    { type = T.quantifier, value = '+', pos = 5, greedy = true },
  })
  eq(result.tokens[1].prev_wordness, nil)
  eq(result.tokens[1].next_wordness, W.word)
end)

--------------------------------------------------------------------------------
--- Boundary with character classes --------------------------------------------
--------------------------------------------------------------------------------

test('boundary: \\b after word-only class has prev word', function()
  local result = parse({
    { type = T.char_class_open, value = '[', pos = 1, negated = false },
    { type = CC.cc_range, value = 'a-z', pos = 2, from = 'a', to = 'z' },
    { type = T.char_class_close, value = ']', pos = 5 },
    { type = T.escape_boundary, value = '\\b', pos = 6, boundary_kind = 'word' },
  })
  eq(result.tokens[4].prev_wordness, W.word)
  eq(result.tokens[4].next_wordness, nil)
end)

test('boundary: \\b after non-word class has prev non_word', function()
  local result = parse({
    { type = T.char_class_open, value = '[', pos = 1, negated = false },
    { type = CC.cc_escape_class, value = '\\s', pos = 2 },
    { type = T.char_class_close, value = ']', pos = 4 },
    { type = T.escape_boundary, value = '\\b', pos = 5, boundary_kind = 'word' },
  })
  eq(result.tokens[4].prev_wordness, W.non_word)
  eq(result.tokens[4].next_wordness, nil)
end)

test('boundary: \\b after negated class has prev unknown', function()
  local result = parse({
    { type = T.char_class_open, value = '[^', pos = 1, negated = true },
    { type = CC.cc_range, value = 'a-z', pos = 3, from = 'a', to = 'z' },
    { type = T.char_class_close, value = ']', pos = 6 },
    { type = T.escape_boundary, value = '\\b', pos = 7, boundary_kind = 'word' },
  })
  eq(result.tokens[4].prev_wordness, W.unknown)
  eq(result.tokens[4].next_wordness, nil)
end)

test('boundary: \\b before word-only class has next word', function()
  local result = parse({
    { type = T.escape_boundary, value = '\\b', pos = 1, boundary_kind = 'word' },
    { type = T.char_class_open, value = '[', pos = 3, negated = false },
    { type = CC.cc_range, value = '0-9', pos = 4, from = '0', to = '9' },
    { type = T.char_class_close, value = ']', pos = 7 },
  })
  eq(result.tokens[1].prev_wordness, nil)
  eq(result.tokens[1].next_wordness, W.word)
end)

--------------------------------------------------------------------------------
--- Boundary with groups (structural tokens have non_word wordness) ------------
--------------------------------------------------------------------------------

test('boundary: \\b before group_open sees non_word', function()
  local result = parse({
    { type = T.escape_boundary, value = '\\b', pos = 1, boundary_kind = 'word' },
    { type = T.group_open, value = '(', pos = 3, kind = GK.capturing },
    { type = T.literal, value = 'a', pos = 4 },
    { type = T.group_close, value = ')', pos = 5 },
  })
  eq(result.tokens[1].prev_wordness, nil)
  eq(result.tokens[1].next_wordness, W.non_word)
end)

test('boundary: \\b after group_close sees non_word', function()
  local result = parse({
    { type = T.group_open, value = '(', pos = 1, kind = GK.capturing },
    { type = T.literal, value = 'a', pos = 2 },
    { type = T.group_close, value = ')', pos = 3 },
    { type = T.escape_boundary, value = '\\b', pos = 4, boundary_kind = 'word' },
  })
  eq(result.tokens[4].prev_wordness, W.non_word)
  eq(result.tokens[4].next_wordness, nil)
end)

test('boundary: \\b between group_close and group_open', function()
  local result = parse({
    { type = T.group_open, value = '(', pos = 1, kind = GK.capturing },
    { type = T.literal, value = 'a', pos = 2 },
    { type = T.group_close, value = ')', pos = 3 },
    { type = T.escape_boundary, value = '\\b', pos = 4, boundary_kind = 'word' },
    { type = T.group_open, value = '(', pos = 6, kind = GK.capturing },
    { type = T.literal, value = 'b', pos = 7 },
    { type = T.group_close, value = ')', pos = 8 },
  })
  eq(result.tokens[4].prev_wordness, W.non_word)
  eq(result.tokens[4].next_wordness, W.non_word)
end)

--------------------------------------------------------------------------------
--- Boundary with alternation --------------------------------------------------
--------------------------------------------------------------------------------

test('boundary: \\b after alternation sees non_word', function()
  local result = parse({
    { type = T.literal, value = 'a', pos = 1 },
    { type = T.alternation, value = '|', pos = 2 },
    { type = T.escape_boundary, value = '\\b', pos = 3, boundary_kind = 'word' },
    { type = T.literal, value = 'x', pos = 5 },
  })
  eq(result.tokens[3].prev_wordness, W.non_word)
  eq(result.tokens[3].next_wordness, W.word)
end)

test('boundary: \\b before alternation sees non_word', function()
  local result = parse({
    { type = T.literal, value = 'a', pos = 1 },
    { type = T.escape_boundary, value = '\\b', pos = 2, boundary_kind = 'word' },
    { type = T.alternation, value = '|', pos = 4 },
    { type = T.literal, value = 'x', pos = 5 },
  })
  eq(result.tokens[2].prev_wordness, W.word)
  eq(result.tokens[2].next_wordness, W.non_word)
end)

--------------------------------------------------------------------------------
--- Boundary with anchors ------------------------------------------------------
--------------------------------------------------------------------------------

test('boundary: \\b after ^ has prev non_word', function()
  local result = parse({
    { type = T.anchor, value = '^', pos = 1 },
    { type = T.escape_boundary, value = '\\b', pos = 2, boundary_kind = 'word' },
    { type = T.literal, value = 'a', pos = 4 },
  })
  eq(result.tokens[2].prev_wordness, W.non_word)
  eq(result.tokens[2].next_wordness, W.word)
end)

test('boundary: \\b before $ has next non_word', function()
  local result = parse({
    { type = T.literal, value = 'a', pos = 1 },
    { type = T.escape_boundary, value = '\\b', pos = 2, boundary_kind = 'word' },
    { type = T.anchor, value = '$', pos = 4 },
  })
  eq(result.tokens[2].prev_wordness, W.word)
  eq(result.tokens[2].next_wordness, W.non_word)
end)

--------------------------------------------------------------------------------
--- Multiple boundaries --------------------------------------------------------
--------------------------------------------------------------------------------

test('boundary: multiple \\b in pattern', function()
  local result = parse({
    { type = T.escape_boundary, value = '\\b', pos = 1, boundary_kind = 'word' },
    { type = T.literal, value = 'a', pos = 3 },
    { type = T.escape_boundary, value = '\\b', pos = 4, boundary_kind = 'word' },
  })
  eq(result.tokens[1].prev_wordness, nil)
  eq(result.tokens[1].next_wordness, W.word)
  eq(result.tokens[3].prev_wordness, W.word)
  eq(result.tokens[3].next_wordness, nil)
end)

test('boundary: adjacent \\b\\b', function()
  local result = parse({
    { type = T.escape_boundary, value = '\\b', pos = 1, boundary_kind = 'word' },
    { type = T.escape_boundary, value = '\\b', pos = 3, boundary_kind = 'word' },
  })
  -- First \b: prev=nil, next looks past second \b to end
  -- Second \b: prev looks past first \b to start, next=nil
  -- Both boundaries are non_word for adjacency purposes
  eq(result.tokens[1].prev_wordness, nil)
  eq(result.tokens[1].next_wordness, nil)
  eq(result.tokens[2].prev_wordness, nil)
  eq(result.tokens[2].next_wordness, nil)
end)

--------------------------------------------------------------------------------
--- Other boundary kinds (not \b) ----------------------------------------------
--------------------------------------------------------------------------------

test('boundary: \\A does not get prev/next wordness', function()
  local result = parse({
    { type = T.literal, value = 'a', pos = 1 },
    { type = T.escape_boundary, value = '\\A', pos = 2, boundary_kind = 'start' },
    { type = T.literal, value = 'b', pos = 4 },
  })
  eq(result.tokens[2].prev_wordness, nil)
  eq(result.tokens[2].next_wordness, nil)
end)

test('boundary: \\z does not get prev/next wordness', function()
  local result = parse({
    { type = T.literal, value = 'a', pos = 1 },
    { type = T.escape_boundary, value = '\\z', pos = 2, boundary_kind = 'end' },
    { type = T.literal, value = 'b', pos = 4 },
  })
  eq(result.tokens[2].prev_wordness, nil)
  eq(result.tokens[2].next_wordness, nil)
end)

--------------------------------------------------------------------------------
--- Summary --------------------------------------------------------------------
--------------------------------------------------------------------------------

h.summary()
