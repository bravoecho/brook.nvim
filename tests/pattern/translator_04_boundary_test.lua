-- tests/pattern/translator_boundary_test.lua
-- Translator tests for word boundary (\b) translation.
--
-- The translator uses prev_wordness and next_wordness annotations to emit
-- the correct Vim boundary: < for word start, > for word end, or %(<|>) for
-- ambiguous cases.
--
-- Run with:
--   nvim --headless -u NONE -c "set rtp+=." -c "luafile tests/pattern/translator_boundary_test.lua"

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
--- Boundary at pattern edges: word start --------------------------------------
--------------------------------------------------------------------------------

test('boundary: \\b at start with word following becomes <', function()
  local result = translate({
    { type = T.escape_boundary, value = '\\b', pos = 1, escape_class = EC.boundary, prev_wordness = nil, next_wordness = W.word },
    { type = T.literal, value = 'f', pos = 3, wordness = W.word },
    { type = T.literal, value = 'o', pos = 4, wordness = W.word },
    { type = T.literal, value = 'o', pos = 5, wordness = W.word },
  }, {})
  eq(result.pattern, '\\v<foo')
end)

test('boundary: \\b after non-word with word following becomes <', function()
  local result = translate({
    { type = T.literal, value = ' ', pos = 1, wordness = W.non_word },
    { type = T.escape_boundary, value = '\\b', pos = 2, escape_class = EC.boundary, prev_wordness = W.non_word, next_wordness = W.word },
    { type = T.literal, value = 'a', pos = 4, wordness = W.word },
  }, {})
  eq(result.pattern, '\\v <a')
end)

--------------------------------------------------------------------------------
--- Boundary at pattern edges: word end ----------------------------------------
--------------------------------------------------------------------------------

test('boundary: \\b at end with word preceding becomes >', function()
  local result = translate({
    { type = T.literal, value = 'f', pos = 1, wordness = W.word },
    { type = T.literal, value = 'o', pos = 2, wordness = W.word },
    { type = T.literal, value = 'o', pos = 3, wordness = W.word },
    { type = T.escape_boundary, value = '\\b', pos = 4, escape_class = EC.boundary, prev_wordness = W.word, next_wordness = nil },
  }, {})
  eq(result.pattern, '\\vfoo>')
end)

test('boundary: \\b before non-word with word preceding becomes >', function()
  local result = translate({
    { type = T.literal, value = 'a', pos = 1, wordness = W.word },
    { type = T.escape_boundary, value = '\\b', pos = 2, escape_class = EC.boundary, prev_wordness = W.word, next_wordness = W.non_word },
    { type = T.literal, value = ' ', pos = 4, wordness = W.non_word },
  }, {})
  eq(result.pattern, '\\va> ')
end)

--------------------------------------------------------------------------------
--- Classic word boundary pattern ----------------------------------------------
--------------------------------------------------------------------------------

test('boundary: \\bfoo\\b becomes <foo>', function()
  local result = translate({
    { type = T.escape_boundary, value = '\\b', pos = 1, escape_class = EC.boundary, prev_wordness = nil, next_wordness = W.word },
    { type = T.literal, value = 'f', pos = 3, wordness = W.word },
    { type = T.literal, value = 'o', pos = 4, wordness = W.word },
    { type = T.literal, value = 'o', pos = 5, wordness = W.word },
    { type = T.escape_boundary, value = '\\b', pos = 6, escape_class = EC.boundary, prev_wordness = W.word, next_wordness = nil },
  }, {})
  eq(result.pattern, '\\v<foo>')
end)

--------------------------------------------------------------------------------
--- Ambiguous boundaries: fallback to %(<|>) -----------------------------------
--------------------------------------------------------------------------------

test('boundary: \\b alone becomes %(<|>)', function()
  local result = translate({
    { type = T.escape_boundary, value = '\\b', pos = 1, escape_class = EC.boundary, prev_wordness = nil, next_wordness = nil },
  }, {})
  eq(result.pattern, '\\v%(<|>)')
end)

test('boundary: \\b between word chars becomes %(<|>)', function()
  local result = translate({
    { type = T.literal, value = 'a', pos = 1, wordness = W.word },
    { type = T.escape_boundary, value = '\\b', pos = 2, escape_class = EC.boundary, prev_wordness = W.word, next_wordness = W.word },
    { type = T.literal, value = 'b', pos = 4, wordness = W.word },
  }, {})
  eq(result.pattern, '\\va%(<|>)b')
end)

test('boundary: \\b between non-word chars becomes %(<|>)', function()
  local result = translate({
    { type = T.literal, value = '.', pos = 1, wordness = W.non_word },
    { type = T.escape_boundary, value = '\\b', pos = 2, escape_class = EC.boundary, prev_wordness = W.non_word, next_wordness = W.non_word },
    { type = T.literal, value = '-', pos = 4, wordness = W.non_word },
  }, {})
  eq(result.pattern, '\\v.%(<|>)-')
end)

test('boundary: \\b with unknown prev becomes %(<|>)', function()
  local result = translate({
    { type = T.dot, value = '.', pos = 1, wordness = W.unknown },
    { type = T.escape_boundary, value = '\\b', pos = 2, escape_class = EC.boundary, prev_wordness = W.unknown, next_wordness = W.word },
    { type = T.literal, value = 'a', pos = 4, wordness = W.word },
  }, {})
  eq(result.pattern, '\\v.%(<|>)a')
end)

test('boundary: \\b with unknown next becomes %(<|>)', function()
  local result = translate({
    { type = T.literal, value = 'a', pos = 1, wordness = W.word },
    { type = T.escape_boundary, value = '\\b', pos = 2, escape_class = EC.boundary, prev_wordness = W.word, next_wordness = W.unknown },
    { type = T.dot, value = '.', pos = 4, wordness = W.unknown },
  }, {})
  eq(result.pattern, '\\va%(<|>).')
end)

--------------------------------------------------------------------------------
--- Anchor escapes: \A and \z --------------------------------------------------
--------------------------------------------------------------------------------

test('boundary: \\A becomes ^ with warning', function()
  local result = translate({
    { type = T.escape_boundary, value = '\\A', pos = 1, escape_class = EC.anchor_start, wordness = W.non_word },
    { type = T.literal, value = 'a', pos = 3, wordness = W.word },
  }, {})
  eq(result.pattern, '\\v^a')
  eq(#result.warnings, 1)
  eq(result.warnings[1], '\\A treated as ^')
end)

test('boundary: \\z becomes $ with warning', function()
  local result = translate({
    { type = T.literal, value = 'a', pos = 1, wordness = W.word },
    { type = T.escape_boundary, value = '\\z', pos = 2, escape_class = EC.anchor_end, wordness = W.non_word },
  }, {})
  eq(result.pattern, '\\va$')
  eq(#result.warnings, 1)
  eq(result.warnings[1], '\\z treated as $')
end)

test('boundary: \\A and \\z together', function()
  local result = translate({
    { type = T.escape_boundary, value = '\\A', pos = 1, escape_class = EC.anchor_start, wordness = W.non_word },
    { type = T.literal, value = 'f', pos = 3, wordness = W.word },
    { type = T.literal, value = 'o', pos = 4, wordness = W.word },
    { type = T.literal, value = 'o', pos = 5, wordness = W.word },
    { type = T.escape_boundary, value = '\\z', pos = 6, escape_class = EC.anchor_end, wordness = W.non_word },
  }, {})
  eq(result.pattern, '\\v^foo$')
  eq(#result.warnings, 2)
  eq(result.warnings[1], '\\A treated as ^')
  eq(result.warnings[2], '\\z treated as $')
end)

--------------------------------------------------------------------------------
--- Summary --------------------------------------------------------------------
--------------------------------------------------------------------------------

h.summary()
