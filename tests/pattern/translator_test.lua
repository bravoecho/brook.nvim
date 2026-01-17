-- tests/pattern/translator_test.lua

-- Run with:
--   nvim --headless -c "luafile tests/pattern/translator_test.lua" -c "q"

local h = require('tests.harness')
local test = h.test
local deep_eq = h.deep_eq
local types = require('brook.pattern.types')

-- Import will fail until translator.lua is implemented
local ok, translator = pcall(require, 'brook.pattern.translator')
if not ok then
  print('SKIP: brook.pattern.translator not yet implemented')
  print('Error: ' .. tostring(translator))
  print('0/0 tests passed')
  if vim and vim.cmd then
    vim.cmd('cquit 0')
  else
    os.exit(0)
  end
  return
end

local translate = translator.translate

-- Shorthand for types
local T = types.token_type
local CC = types.cc_token_type
local GK = types.group_kind
local EC = types.escape_class
local W = types.wordness

--- Helper to create a token with common fields.
---@param token_type string
---@param value string
---@param pos integer
---@param extra? table
---@return table
local function tok(token_type, value, pos, extra)
  local t = { type = token_type, value = value, pos = pos }
  if extra then
    for k, v in pairs(extra) do
      t[k] = v
    end
  end
  return t
end

--------------------------------------------------------------------------------
--- Empty input ----------------------------------------------------------------
--------------------------------------------------------------------------------

test('empty: empty token list', function()
  deep_eq(translate({}, {}), {
    pattern = '\\v',
    warnings = {},
  })
end)

--------------------------------------------------------------------------------
--- Fixed string mode ----------------------------------------------------------
--------------------------------------------------------------------------------

test('fixed: simple literal', function()
  -- In fixed mode, tokens are literals; translator handles escaping
  deep_eq(translate({
    tok(T.literal, 'h', 1, { wordness = W.word }),
    tok(T.literal, 'e', 2, { wordness = W.word }),
    tok(T.literal, 'l', 3, { wordness = W.word }),
    tok(T.literal, 'l', 4, { wordness = W.word }),
    tok(T.literal, 'o', 5, { wordness = W.word }),
  }, { fixed = true }), {
    pattern = '\\Vhello',
    warnings = {},
  })
end)

test('fixed: escapes backslashes', function()
  deep_eq(translate({
    tok(T.literal, 'f', 1, { wordness = W.word }),
    tok(T.literal, 'o', 2, { wordness = W.word }),
    tok(T.literal, 'o', 3, { wordness = W.word }),
    tok(T.escape, '\\\\', 4, { escape_class = EC.escaped_literal, wordness = W.non_word }),
    tok(T.literal, 'b', 6, { wordness = W.word }),
    tok(T.literal, 'a', 7, { wordness = W.word }),
    tok(T.literal, 'r', 8, { wordness = W.word }),
  }, { fixed = true }), {
    pattern = '\\Vfoo\\\\bar',
    warnings = {},
  })
end)

test('fixed: escapes forward slashes', function()
  deep_eq(translate({
    tok(T.literal, 'f', 1, { wordness = W.word }),
    tok(T.literal, 'o', 2, { wordness = W.word }),
    tok(T.literal, 'o', 3, { wordness = W.word }),
    tok(T.slash, '/', 4, { wordness = W.non_word }),
    tok(T.literal, 'b', 5, { wordness = W.word }),
    tok(T.literal, 'a', 6, { wordness = W.word }),
    tok(T.literal, 'r', 7, { wordness = W.word }),
  }, { fixed = true }), {
    pattern = '\\Vfoo\\/bar',
    warnings = {},
  })
end)

test('fixed: with word boundary', function()
  deep_eq(translate({
    tok(T.literal, 'h', 1, { wordness = W.word }),
    tok(T.literal, 'e', 2, { wordness = W.word }),
    tok(T.literal, 'l', 3, { wordness = W.word }),
    tok(T.literal, 'l', 4, { wordness = W.word }),
    tok(T.literal, 'o', 5, { wordness = W.word }),
  }, { fixed = true, word = true }), {
    pattern = '\\V\\<hello\\>',
    warnings = {},
  })
end)

test('fixed: case sensitive', function()
  deep_eq(translate({
    tok(T.literal, 'h', 1, { wordness = W.word }),
    tok(T.literal, 'i', 2, { wordness = W.word }),
  }, { fixed = true, case = 'case-sensitive' }), {
    pattern = '\\C\\Vhi',
    warnings = {},
  })
end)

test('fixed: case insensitive', function()
  deep_eq(translate({
    tok(T.literal, 'h', 1, { wordness = W.word }),
    tok(T.literal, 'i', 2, { wordness = W.word }),
  }, { fixed = true, case = 'case-insensitive' }), {
    pattern = '\\c\\Vhi',
    warnings = {},
  })
end)

--------------------------------------------------------------------------------
--- Literals: pass through -----------------------------------------------------
--------------------------------------------------------------------------------

test('literal: single letter', function()
  deep_eq(translate({
    tok(T.literal, 'a', 1, { wordness = W.word }),
  }, {}), {
    pattern = '\\va',
    warnings = {},
  })
end)

test('literal: multiple letters', function()
  deep_eq(translate({
    tok(T.literal, 'a', 1, { wordness = W.word }),
    tok(T.literal, 'b', 2, { wordness = W.word }),
    tok(T.literal, 'c', 3, { wordness = W.word }),
  }, {}), {
    pattern = '\\vabc',
    warnings = {},
  })
end)

test('literal: dot passes through', function()
  deep_eq(translate({
    tok(T.literal, 'a', 1, { wordness = W.word }),
    tok(T.literal, '.', 2, { wordness = W.unknown }),
    tok(T.literal, 'b', 3, { wordness = W.word }),
  }, {}), {
    pattern = '\\va.b',
    warnings = {},
  })
end)

--------------------------------------------------------------------------------
--- Vim-special characters (need escaping outside char classes) ----------------
--------------------------------------------------------------------------------

test('vimspecial: equals sign', function()
  deep_eq(translate({
    tok(T.literal, 'f', 1, { wordness = W.word }),
    tok(T.literal, 'o', 2, { wordness = W.word }),
    tok(T.literal, 'o', 3, { wordness = W.word }),
    tok(T.literal, '=', 4, { wordness = W.non_word }),
    tok(T.literal, 'b', 5, { wordness = W.word }),
    tok(T.literal, 'a', 6, { wordness = W.word }),
    tok(T.literal, 'r', 7, { wordness = W.word }),
  }, {}), {
    pattern = '\\vfoo\\=bar',
    warnings = {},
  })
end)

test('vimspecial: tilde', function()
  deep_eq(translate({
    tok(T.literal, 'x', 1, { wordness = W.word }),
    tok(T.literal, '~', 2, { wordness = W.non_word }),
    tok(T.literal, 'y', 3, { wordness = W.word }),
  }, {}), {
    pattern = '\\vx\\~y',
    warnings = {},
  })
end)

test('vimspecial: at sign', function()
  deep_eq(translate({
    tok(T.literal, 'a', 1, { wordness = W.word }),
    tok(T.literal, '@', 2, { wordness = W.non_word }),
    tok(T.literal, 'b', 3, { wordness = W.word }),
  }, {}), {
    pattern = '\\va\\@b',
    warnings = {},
  })
end)

test('vimspecial: ampersand', function()
  deep_eq(translate({
    tok(T.literal, 'a', 1, { wordness = W.word }),
    tok(T.literal, '&', 2, { wordness = W.non_word }),
    tok(T.literal, 'b', 3, { wordness = W.word }),
  }, {}), {
    pattern = '\\va\\&b',
    warnings = {},
  })
end)

test('vimspecial: less than', function()
  deep_eq(translate({
    tok(T.literal, 'a', 1, { wordness = W.word }),
    tok(T.literal, '<', 2, { wordness = W.non_word }),
    tok(T.literal, 'b', 3, { wordness = W.word }),
  }, {}), {
    pattern = '\\va\\<b',
    warnings = {},
  })
end)

test('vimspecial: greater than', function()
  deep_eq(translate({
    tok(T.literal, 'x', 1, { wordness = W.word }),
    tok(T.literal, ' ', 2, { wordness = W.non_word }),
    tok(T.literal, '>', 3, { wordness = W.non_word }),
    tok(T.literal, ' ', 4, { wordness = W.non_word }),
    tok(T.literal, '0', 5, { wordness = W.word }),
  }, {}), {
    pattern = '\\vx \\> 0',
    warnings = {},
  })
end)

--------------------------------------------------------------------------------
--- Forward slash (search delimiter) -------------------------------------------
--------------------------------------------------------------------------------

test('slash: simple path', function()
  deep_eq(translate({
    tok(T.literal, 'f', 1, { wordness = W.word }),
    tok(T.literal, 'o', 2, { wordness = W.word }),
    tok(T.literal, 'o', 3, { wordness = W.word }),
    tok(T.slash, '/', 4, { wordness = W.non_word }),
    tok(T.literal, 'b', 5, { wordness = W.word }),
    tok(T.literal, 'a', 6, { wordness = W.word }),
    tok(T.literal, 'r', 7, { wordness = W.word }),
  }, {}), {
    pattern = '\\vfoo\\/bar',
    warnings = {},
  })
end)

--------------------------------------------------------------------------------
--- Anchors (^ and $) ----------------------------------------------------------
--------------------------------------------------------------------------------

test('anchor: caret at start', function()
  deep_eq(translate({
    tok(T.anchor, '^', 1, { wordness = W.non_word }),
    tok(T.literal, 'a', 2, { wordness = W.word }),
  }, {}), {
    pattern = '\\v^a',
    warnings = {},
  })
end)

test('anchor: dollar at end', function()
  deep_eq(translate({
    tok(T.literal, 'a', 1, { wordness = W.word }),
    tok(T.anchor, '$', 2, { wordness = W.non_word }),
  }, {}), {
    pattern = '\\va$',
    warnings = {},
  })
end)

--------------------------------------------------------------------------------
--- Escape sequences: shorthands pass through ----------------------------------
--------------------------------------------------------------------------------

test('escape: \\w passes through', function()
  deep_eq(translate({
    tok(T.escape, '\\w', 1, { escape_class = EC.shorthand_word, wordness = W.word }),
  }, {}), {
    pattern = '\\v\\w',
    warnings = {},
  })
end)

test('escape: \\d passes through', function()
  deep_eq(translate({
    tok(T.escape, '\\d', 1, { escape_class = EC.shorthand_word, wordness = W.word }),
  }, {}), {
    pattern = '\\v\\d',
    warnings = {},
  })
end)

test('escape: \\s passes through', function()
  deep_eq(translate({
    tok(T.escape, '\\s', 1, { escape_class = EC.shorthand_nonword, wordness = W.non_word }),
  }, {}), {
    pattern = '\\v\\s',
    warnings = {},
  })
end)

test('escape: \\W passes through', function()
  deep_eq(translate({
    tok(T.escape, '\\W', 1, { escape_class = EC.shorthand_nonword, wordness = W.non_word }),
  }, {}), {
    pattern = '\\v\\W',
    warnings = {},
  })
end)

test('escape: \\S passes through', function()
  deep_eq(translate({
    tok(T.escape, '\\S', 1, { escape_class = EC.shorthand_unknown, wordness = W.unknown }),
  }, {}), {
    pattern = '\\v\\S',
    warnings = {},
  })
end)

test('escape: \\D passes through', function()
  deep_eq(translate({
    tok(T.escape, '\\D', 1, { escape_class = EC.shorthand_unknown, wordness = W.unknown }),
  }, {}), {
    pattern = '\\v\\D',
    warnings = {},
  })
end)

test('escape: \\t passes through', function()
  deep_eq(translate({
    tok(T.escape, '\\t', 1, { escape_class = EC.shorthand_nonword, wordness = W.non_word }),
  }, {}), {
    pattern = '\\v\\t',
    warnings = {},
  })
end)

test('escape: \\n passes through', function()
  deep_eq(translate({
    tok(T.escape, '\\n', 1, { escape_class = EC.shorthand_nonword, wordness = W.non_word }),
  }, {}), {
    pattern = '\\v\\n',
    warnings = {},
  })
end)

test('escape: \\r passes through', function()
  deep_eq(translate({
    tok(T.escape, '\\r', 1, { escape_class = EC.shorthand_nonword, wordness = W.non_word }),
  }, {}), {
    pattern = '\\v\\r',
    warnings = {},
  })
end)

--------------------------------------------------------------------------------
--- Escape sequences: escaped literals pass through ----------------------------
--------------------------------------------------------------------------------

test('escape: \\( passes through', function()
  deep_eq(translate({
    tok(T.escape, '\\(', 1, { escape_class = EC.escaped_literal, wordness = W.non_word }),
  }, {}), {
    pattern = '\\v\\(',
    warnings = {},
  })
end)

test('escape: \\. passes through', function()
  deep_eq(translate({
    tok(T.escape, '\\.', 1, { escape_class = EC.escaped_literal, wordness = W.non_word }),
  }, {}), {
    pattern = '\\v\\.',
    warnings = {},
  })
end)

test('escape: \\\\ passes through', function()
  deep_eq(translate({
    tok(T.escape, '\\\\', 1, { escape_class = EC.escaped_literal, wordness = W.non_word }),
  }, {}), {
    pattern = '\\v\\\\',
    warnings = {},
  })
end)

--------------------------------------------------------------------------------
--- Escape sequences: anchors --------------------------------------------------
--------------------------------------------------------------------------------

test('escape: \\A becomes ^ with warning', function()
  deep_eq(translate({
    tok(T.escape, '\\A', 1, { escape_class = EC.anchor_start, wordness = W.non_word }),
    tok(T.literal, 'f', 3, { wordness = W.word }),
    tok(T.literal, 'o', 4, { wordness = W.word }),
    tok(T.literal, 'o', 5, { wordness = W.word }),
  }, {}), {
    pattern = '\\v^foo',
    warnings = { '\\A treated as ^' },
  })
end)

test('escape: \\z becomes $ with warning', function()
  deep_eq(translate({
    tok(T.literal, 'f', 1, { wordness = W.word }),
    tok(T.literal, 'o', 2, { wordness = W.word }),
    tok(T.literal, 'o', 3, { wordness = W.word }),
    tok(T.escape, '\\z', 4, { escape_class = EC.anchor_end, wordness = W.non_word }),
  }, {}), {
    pattern = '\\vfoo$',
    warnings = { '\\z treated as $' },
  })
end)

test('escape: \\A and \\z together', function()
  deep_eq(translate({
    tok(T.escape, '\\A', 1, { escape_class = EC.anchor_start, wordness = W.non_word }),
    tok(T.literal, 'f', 3, { wordness = W.word }),
    tok(T.literal, 'o', 4, { wordness = W.word }),
    tok(T.literal, 'o', 5, { wordness = W.word }),
    tok(T.escape, '\\z', 6, { escape_class = EC.anchor_end, wordness = W.non_word }),
  }, {}), {
    pattern = '\\v^foo$',
    warnings = { '\\A treated as ^', '\\z treated as $' },
  })
end)

--------------------------------------------------------------------------------
--- Word boundaries: basic translation -----------------------------------------
--------------------------------------------------------------------------------

test('boundary: \\b at start (before word) => <', function()
  deep_eq(translate({
    tok(T.escape, '\\b', 1, { escape_class = EC.boundary, prev_wordness = nil, next_wordness = W.word }),
    tok(T.literal, 'w', 3, { wordness = W.word }),
    tok(T.literal, 'o', 4, { wordness = W.word }),
    tok(T.literal, 'r', 5, { wordness = W.word }),
    tok(T.literal, 'd', 6, { wordness = W.word }),
  }, {}), {
    pattern = '\\v<word',
    warnings = {},
  })
end)

test('boundary: \\b at end (after word) => >', function()
  deep_eq(translate({
    tok(T.literal, 'w', 1, { wordness = W.word }),
    tok(T.literal, 'o', 2, { wordness = W.word }),
    tok(T.literal, 'r', 3, { wordness = W.word }),
    tok(T.literal, 'd', 4, { wordness = W.word }),
    tok(T.escape, '\\b', 5, { escape_class = EC.boundary, prev_wordness = W.word, next_wordness = nil }),
  }, {}), {
    pattern = '\\vword>',
    warnings = {},
  })
end)

test('boundary: \\b at both ends', function()
  deep_eq(translate({
    tok(T.escape, '\\b', 1, { escape_class = EC.boundary, prev_wordness = nil, next_wordness = W.word }),
    tok(T.literal, 'w', 3, { wordness = W.word }),
    tok(T.literal, 'o', 4, { wordness = W.word }),
    tok(T.literal, 'r', 5, { wordness = W.word }),
    tok(T.literal, 'd', 6, { wordness = W.word }),
    tok(T.escape, '\\b', 7, { escape_class = EC.boundary, prev_wordness = W.word, next_wordness = nil }),
  }, {}), {
    pattern = '\\v<word>',
    warnings = {},
  })
end)

test('boundary: \\b in middle (word-word) => fallback', function()
  -- Both sides are word chars, so boundary is ambiguous
  deep_eq(translate({
    tok(T.literal, 'f', 1, { wordness = W.word }),
    tok(T.literal, 'o', 2, { wordness = W.word }),
    tok(T.literal, 'o', 3, { wordness = W.word }),
    tok(T.escape, '\\b', 4, { escape_class = EC.boundary, prev_wordness = W.word, next_wordness = W.word }),
    tok(T.literal, 'b', 6, { wordness = W.word }),
    tok(T.literal, 'a', 7, { wordness = W.word }),
    tok(T.literal, 'r', 8, { wordness = W.word }),
  }, {}), {
    pattern = '\\vfoo%(<|>)bar',
    warnings = {},
  })
end)

test('boundary: \\b after space => <', function()
  deep_eq(translate({
    tok(T.literal, 'f', 1, { wordness = W.word }),
    tok(T.literal, 'o', 2, { wordness = W.word }),
    tok(T.literal, 'o', 3, { wordness = W.word }),
    tok(T.literal, ' ', 4, { wordness = W.non_word }),
    tok(T.escape, '\\b', 5, { escape_class = EC.boundary, prev_wordness = W.non_word, next_wordness = W.word }),
    tok(T.literal, 'b', 7, { wordness = W.word }),
    tok(T.literal, 'a', 8, { wordness = W.word }),
    tok(T.literal, 'r', 9, { wordness = W.word }),
  }, {}), {
    pattern = '\\vfoo <bar',
    warnings = {},
  })
end)

test('boundary: \\b before space => >', function()
  deep_eq(translate({
    tok(T.literal, 'f', 1, { wordness = W.word }),
    tok(T.literal, 'o', 2, { wordness = W.word }),
    tok(T.literal, 'o', 3, { wordness = W.word }),
    tok(T.escape, '\\b', 4, { escape_class = EC.boundary, prev_wordness = W.word, next_wordness = W.non_word }),
    tok(T.literal, ' ', 6, { wordness = W.non_word }),
    tok(T.literal, 'b', 7, { wordness = W.word }),
    tok(T.literal, 'a', 8, { wordness = W.word }),
    tok(T.literal, 'r', 9, { wordness = W.word }),
  }, {}), {
    pattern = '\\vfoo> bar',
    warnings = {},
  })
end)

--------------------------------------------------------------------------------
--- Word boundaries: with shorthands -------------------------------------------
--------------------------------------------------------------------------------

test('boundary: \\b with \\w+', function()
  deep_eq(translate({
    tok(T.escape, '\\b', 1, { escape_class = EC.boundary, prev_wordness = nil, next_wordness = W.word }),
    tok(T.escape, '\\w', 3, { escape_class = EC.shorthand_word, wordness = W.word }),
    tok(T.quantifier, '+', 5, { greedy = true, wordness = W.word }),
    tok(T.escape, '\\b', 6, { escape_class = EC.boundary, prev_wordness = W.word, next_wordness = nil }),
  }, {}), {
    pattern = '\\v<\\w+>',
    warnings = {},
  })
end)

test('boundary: \\b after \\W => <', function()
  deep_eq(translate({
    tok(T.escape, '\\W', 1, { escape_class = EC.shorthand_nonword, wordness = W.non_word }),
    tok(T.escape, '\\b', 3, { escape_class = EC.boundary, prev_wordness = W.non_word, next_wordness = W.word }),
    tok(T.literal, 'f', 5, { wordness = W.word }),
    tok(T.literal, 'o', 6, { wordness = W.word }),
    tok(T.literal, 'o', 7, { wordness = W.word }),
  }, {}), {
    pattern = '\\v\\W<foo',
    warnings = {},
  })
end)

test('boundary: \\b before \\W => >', function()
  deep_eq(translate({
    tok(T.literal, 'f', 1, { wordness = W.word }),
    tok(T.literal, 'o', 2, { wordness = W.word }),
    tok(T.literal, 'o', 3, { wordness = W.word }),
    tok(T.escape, '\\b', 4, { escape_class = EC.boundary, prev_wordness = W.word, next_wordness = W.non_word }),
    tok(T.escape, '\\W', 6, { escape_class = EC.shorthand_nonword, wordness = W.non_word }),
  }, {}), {
    pattern = '\\vfoo>\\W',
    warnings = {},
  })
end)

--------------------------------------------------------------------------------
--- Word boundaries: with unknown atoms ----------------------------------------
--------------------------------------------------------------------------------

test('boundary: \\b after \\S (unknown) => fallback', function()
  deep_eq(translate({
    tok(T.escape, '\\S', 1, { escape_class = EC.shorthand_unknown, wordness = W.unknown }),
    tok(T.escape, '\\b', 3, { escape_class = EC.boundary, prev_wordness = W.unknown, next_wordness = W.word }),
    tok(T.literal, 'f', 5, { wordness = W.word }),
    tok(T.literal, 'o', 6, { wordness = W.word }),
    tok(T.literal, 'o', 7, { wordness = W.word }),
  }, {}), {
    pattern = '\\v\\S%(<|>)foo',
    warnings = {},
  })
end)

test('boundary: \\b before \\S (unknown) => fallback', function()
  deep_eq(translate({
    tok(T.literal, 'f', 1, { wordness = W.word }),
    tok(T.literal, 'o', 2, { wordness = W.word }),
    tok(T.literal, 'o', 3, { wordness = W.word }),
    tok(T.escape, '\\b', 4, { escape_class = EC.boundary, prev_wordness = W.word, next_wordness = W.unknown }),
    tok(T.escape, '\\S', 6, { escape_class = EC.shorthand_unknown, wordness = W.unknown }),
  }, {}), {
    pattern = '\\vfoo%(<|>)\\S',
    warnings = {},
  })
end)

test('boundary: \\b after . (unknown) => fallback', function()
  deep_eq(translate({
    tok(T.literal, '.', 1, { wordness = W.unknown }),
    tok(T.escape, '\\b', 2, { escape_class = EC.boundary, prev_wordness = W.unknown, next_wordness = W.word }),
    tok(T.literal, 'f', 4, { wordness = W.word }),
    tok(T.literal, 'o', 5, { wordness = W.word }),
    tok(T.literal, 'o', 6, { wordness = W.word }),
  }, {}), {
    pattern = '\\v.%(<|>)foo',
    warnings = {},
  })
end)

--------------------------------------------------------------------------------
--- Word boundaries: with alternation and groups -------------------------------
--------------------------------------------------------------------------------

test('boundary: \\b after alternation', function()
  deep_eq(translate({
    tok(T.group_open, '(', 1, { kind = GK.capturing, wordness = W.non_word }),
    tok(T.literal, 'f', 2, { wordness = W.word }),
    tok(T.literal, 'o', 3, { wordness = W.word }),
    tok(T.literal, 'o', 4, { wordness = W.word }),
    tok(T.alternation, '|', 5, { wordness = W.non_word }),
    tok(T.escape, '\\b', 6, { escape_class = EC.boundary, prev_wordness = W.non_word, next_wordness = W.word }),
    tok(T.literal, 'b', 8, { wordness = W.word }),
    tok(T.literal, 'a', 9, { wordness = W.word }),
    tok(T.literal, 'r', 10, { wordness = W.word }),
    tok(T.group_close, ')', 11, { wordness = W.non_word }),
  }, {}), {
    pattern = '\\v(foo|<bar)',
    warnings = {},
  })
end)

test('boundary: \\b before alternation', function()
  deep_eq(translate({
    tok(T.group_open, '(', 1, { kind = GK.capturing, wordness = W.non_word }),
    tok(T.literal, 'f', 2, { wordness = W.word }),
    tok(T.literal, 'o', 3, { wordness = W.word }),
    tok(T.literal, 'o', 4, { wordness = W.word }),
    tok(T.escape, '\\b', 5, { escape_class = EC.boundary, prev_wordness = W.word, next_wordness = W.non_word }),
    tok(T.alternation, '|', 7, { wordness = W.non_word }),
    tok(T.literal, 'b', 8, { wordness = W.word }),
    tok(T.literal, 'a', 9, { wordness = W.word }),
    tok(T.literal, 'r', 10, { wordness = W.word }),
    tok(T.group_close, ')', 11, { wordness = W.non_word }),
  }, {}), {
    pattern = '\\v(foo>|bar)',
    warnings = {},
  })
end)

test('boundary: \\b after group start', function()
  deep_eq(translate({
    tok(T.group_open, '(', 1, { kind = GK.capturing, wordness = W.non_word }),
    tok(T.escape, '\\b', 2, { escape_class = EC.boundary, prev_wordness = W.non_word, next_wordness = W.word }),
    tok(T.literal, 'f', 4, { wordness = W.word }),
    tok(T.literal, 'o', 5, { wordness = W.word }),
    tok(T.literal, 'o', 6, { wordness = W.word }),
    tok(T.group_close, ')', 7, { wordness = W.non_word }),
  }, {}), {
    pattern = '\\v(<foo)',
    warnings = {},
  })
end)

test('boundary: \\b before group end', function()
  deep_eq(translate({
    tok(T.group_open, '(', 1, { kind = GK.capturing, wordness = W.non_word }),
    tok(T.literal, 'f', 2, { wordness = W.word }),
    tok(T.literal, 'o', 3, { wordness = W.word }),
    tok(T.literal, 'o', 4, { wordness = W.word }),
    tok(T.escape, '\\b', 5, { escape_class = EC.boundary, prev_wordness = W.word, next_wordness = W.non_word }),
    tok(T.group_close, ')', 7, { wordness = W.non_word }),
  }, {}), {
    pattern = '\\v(foo>)',
    warnings = {},
  })
end)

--------------------------------------------------------------------------------
--- Word boundaries: with anchors ----------------------------------------------
--------------------------------------------------------------------------------

test('boundary: \\b after ^', function()
  deep_eq(translate({
    tok(T.anchor, '^', 1, { wordness = W.non_word }),
    tok(T.escape, '\\b', 2, { escape_class = EC.boundary, prev_wordness = W.non_word, next_wordness = W.word }),
    tok(T.literal, 'f', 4, { wordness = W.word }),
    tok(T.literal, 'o', 5, { wordness = W.word }),
    tok(T.literal, 'o', 6, { wordness = W.word }),
  }, {}), {
    pattern = '\\v^<foo',
    warnings = {},
  })
end)

test('boundary: \\b before $', function()
  deep_eq(translate({
    tok(T.literal, 'f', 1, { wordness = W.word }),
    tok(T.literal, 'o', 2, { wordness = W.word }),
    tok(T.literal, 'o', 3, { wordness = W.word }),
    tok(T.escape, '\\b', 4, { escape_class = EC.boundary, prev_wordness = W.word, next_wordness = W.non_word }),
    tok(T.anchor, '$', 6, { wordness = W.non_word }),
  }, {}), {
    pattern = '\\vfoo>$',
    warnings = {},
  })
end)

--------------------------------------------------------------------------------
--- Word boundaries: with character classes ------------------------------------
--------------------------------------------------------------------------------

test('boundary: \\b before word class => <', function()
  deep_eq(translate({
    tok(T.escape, '\\b', 1, { escape_class = EC.boundary, prev_wordness = nil, next_wordness = W.word }),
    tok(T.char_class_open, '[', 3, { negated = false, wordness = W.word }),
    tok(CC.cc_range, 'a-z', 4, { from = 'a', to = 'z' }),
    tok(T.char_class_close, ']', 7, { wordness = W.word }),
    tok(T.quantifier, '+', 8, { greedy = true, wordness = W.word }),
  }, {}), {
    pattern = '\\v<[a-z]+',
    warnings = {},
  })
end)

test('boundary: word class before \\b => >', function()
  deep_eq(translate({
    tok(T.char_class_open, '[', 1, { negated = false, wordness = W.word }),
    tok(CC.cc_range, 'a-z', 2, { from = 'a', to = 'z' }),
    tok(T.char_class_close, ']', 5, { wordness = W.word }),
    tok(T.quantifier, '+', 6, { greedy = true, wordness = W.word }),
    tok(T.escape, '\\b', 7, { escape_class = EC.boundary, prev_wordness = W.word, next_wordness = nil }),
  }, {}), {
    pattern = '\\v[a-z]+>',
    warnings = {},
  })
end)

test('boundary: negated class => fallback (unknown)', function()
  deep_eq(translate({
    tok(T.char_class_open, '[^', 1, { negated = true, wordness = W.unknown }),
    tok(CC.cc_literal, 'a', 3),
    tok(T.char_class_close, ']', 4, { wordness = W.unknown }),
    tok(T.escape, '\\b', 5, { escape_class = EC.boundary, prev_wordness = W.unknown, next_wordness = W.word }),
    tok(T.literal, 'f', 7, { wordness = W.word }),
    tok(T.literal, 'o', 8, { wordness = W.word }),
    tok(T.literal, 'o', 9, { wordness = W.word }),
  }, {}), {
    pattern = '\\v[^a]%(<|>)foo',
    warnings = {},
  })
end)

--------------------------------------------------------------------------------
--- Word option (wraps in word boundaries) -------------------------------------
--------------------------------------------------------------------------------

test('word option: wraps pattern', function()
  deep_eq(translate({
    tok(T.literal, 'h', 1, { wordness = W.word }),
    tok(T.literal, 'e', 2, { wordness = W.word }),
    tok(T.literal, 'l', 3, { wordness = W.word }),
    tok(T.literal, 'l', 4, { wordness = W.word }),
    tok(T.literal, 'o', 5, { wordness = W.word }),
  }, { word = true }), {
    pattern = '\\v<hello>',
    warnings = {},
  })
end)

test('word option: with regex pattern', function()
  deep_eq(translate({
    tok(T.literal, 'f', 1, { wordness = W.word }),
    tok(T.literal, 'o', 2, { wordness = W.word }),
    tok(T.literal, 'o', 3, { wordness = W.word }),
    tok(T.literal, '.', 4, { wordness = W.unknown }),
    tok(T.quantifier, '*', 5, { greedy = true, wordness = W.unknown }),
    tok(T.literal, 'b', 6, { wordness = W.word }),
    tok(T.literal, 'a', 7, { wordness = W.word }),
    tok(T.literal, 'r', 8, { wordness = W.word }),
  }, { word = true }), {
    pattern = '\\v<foo.*bar>',
    warnings = {},
  })
end)

--------------------------------------------------------------------------------
--- Case sensitivity -----------------------------------------------------------
--------------------------------------------------------------------------------

test('case: sensitive adds \\C prefix', function()
  deep_eq(translate({
    tok(T.literal, 'h', 1, { wordness = W.word }),
    tok(T.literal, 'e', 2, { wordness = W.word }),
    tok(T.literal, 'l', 3, { wordness = W.word }),
    tok(T.literal, 'l', 4, { wordness = W.word }),
    tok(T.literal, 'o', 5, { wordness = W.word }),
  }, { case = 'case-sensitive' }), {
    pattern = '\\C\\vhello',
    warnings = {},
  })
end)

test('case: insensitive adds \\c prefix', function()
  deep_eq(translate({
    tok(T.literal, 'h', 1, { wordness = W.word }),
    tok(T.literal, 'e', 2, { wordness = W.word }),
    tok(T.literal, 'l', 3, { wordness = W.word }),
    tok(T.literal, 'l', 4, { wordness = W.word }),
    tok(T.literal, 'o', 5, { wordness = W.word }),
  }, { case = 'case-insensitive' }), {
    pattern = '\\c\\vhello',
    warnings = {},
  })
end)

test('case: sensitive with word boundary', function()
  deep_eq(translate({
    tok(T.literal, 'h', 1, { wordness = W.word }),
    tok(T.literal, 'e', 2, { wordness = W.word }),
    tok(T.literal, 'l', 3, { wordness = W.word }),
    tok(T.literal, 'l', 4, { wordness = W.word }),
    tok(T.literal, 'o', 5, { wordness = W.word }),
  }, { case = 'case-sensitive', word = true }), {
    pattern = '\\C\\v<hello>',
    warnings = {},
  })
end)

--------------------------------------------------------------------------------
--- Greedy quantifiers (pass through) ------------------------------------------
--------------------------------------------------------------------------------

test('greedy: * passes through', function()
  deep_eq(translate({
    tok(T.literal, 'a', 1, { wordness = W.word }),
    tok(T.quantifier, '*', 2, { greedy = true, wordness = W.word }),
  }, {}), {
    pattern = '\\va*',
    warnings = {},
  })
end)

test('greedy: + passes through', function()
  deep_eq(translate({
    tok(T.literal, 'a', 1, { wordness = W.word }),
    tok(T.quantifier, '+', 2, { greedy = true, wordness = W.word }),
  }, {}), {
    pattern = '\\va+',
    warnings = {},
  })
end)

test('greedy: ? passes through', function()
  deep_eq(translate({
    tok(T.literal, 'a', 1, { wordness = W.word }),
    tok(T.quantifier, '?', 2, { greedy = true, wordness = W.word }),
  }, {}), {
    pattern = '\\va?',
    warnings = {},
  })
end)

test('greedy: {3} passes through', function()
  deep_eq(translate({
    tok(T.literal, 'a', 1, { wordness = W.word }),
    tok(T.quantifier, '{3}', 2, { greedy = true, wordness = W.word }),
  }, {}), {
    pattern = '\\va{3}',
    warnings = {},
  })
end)

test('greedy: {3,} passes through', function()
  deep_eq(translate({
    tok(T.literal, 'a', 1, { wordness = W.word }),
    tok(T.quantifier, '{3,}', 2, { greedy = true, wordness = W.word }),
  }, {}), {
    pattern = '\\va{3,}',
    warnings = {},
  })
end)

test('greedy: {3,5} passes through', function()
  deep_eq(translate({
    tok(T.literal, 'a', 1, { wordness = W.word }),
    tok(T.quantifier, '{3,5}', 2, { greedy = true, wordness = W.word }),
  }, {}), {
    pattern = '\\va{3,5}',
    warnings = {},
  })
end)

--------------------------------------------------------------------------------
--- Non-greedy quantifiers (translation required) ------------------------------
--------------------------------------------------------------------------------

test('nongreedy: *? becomes {-}', function()
  deep_eq(translate({
    tok(T.literal, 'a', 1, { wordness = W.word }),
    tok(T.quantifier, '*?', 2, { greedy = false, wordness = W.word }),
  }, {}), {
    pattern = '\\va{-}',
    warnings = {},
  })
end)

test('nongreedy: +? becomes {-1,}', function()
  deep_eq(translate({
    tok(T.literal, 'a', 1, { wordness = W.word }),
    tok(T.quantifier, '+?', 2, { greedy = false, wordness = W.word }),
  }, {}), {
    pattern = '\\va{-1,}',
    warnings = {},
  })
end)

test('nongreedy: ?? becomes {-0,1}', function()
  deep_eq(translate({
    tok(T.literal, 'a', 1, { wordness = W.word }),
    tok(T.quantifier, '??', 2, { greedy = false, wordness = W.word }),
  }, {}), {
    pattern = '\\va{-0,1}',
    warnings = {},
  })
end)

test('nongreedy: {3}? becomes {-3}', function()
  deep_eq(translate({
    tok(T.literal, 'a', 1, { wordness = W.word }),
    tok(T.quantifier, '{3}?', 2, { greedy = false, wordness = W.word }),
  }, {}), {
    pattern = '\\va{-3}',
    warnings = {},
  })
end)

test('nongreedy: {3,}? becomes {-3,}', function()
  deep_eq(translate({
    tok(T.literal, 'a', 1, { wordness = W.word }),
    tok(T.quantifier, '{3,}?', 2, { greedy = false, wordness = W.word }),
  }, {}), {
    pattern = '\\va{-3,}',
    warnings = {},
  })
end)

test('nongreedy: {3,5}? becomes {-3,5}', function()
  deep_eq(translate({
    tok(T.literal, 'a', 1, { wordness = W.word }),
    tok(T.quantifier, '{3,5}?', 2, { greedy = false, wordness = W.word }),
  }, {}), {
    pattern = '\\va{-3,5}',
    warnings = {},
  })
end)

test('nongreedy: .*? common pattern', function()
  deep_eq(translate({
    tok(T.literal, '.', 1, { wordness = W.unknown }),
    tok(T.quantifier, '*?', 2, { greedy = false, wordness = W.unknown }),
  }, {}), {
    pattern = '\\v.{-}',
    warnings = {},
  })
end)

test('nongreedy: HTML tag pattern', function()
  deep_eq(translate({
    tok(T.literal, '<', 1, { wordness = W.non_word }),
    tok(T.literal, '.', 2, { wordness = W.unknown }),
    tok(T.quantifier, '*?', 3, { greedy = false, wordness = W.unknown }),
    tok(T.literal, '>', 5, { wordness = W.non_word }),
  }, {}), {
    pattern = '\\v\\<.{-}\\>',
    warnings = {},
  })
end)

--------------------------------------------------------------------------------
--- Groups: capturing ----------------------------------------------------------
--------------------------------------------------------------------------------

test('group: capturing passes through', function()
  deep_eq(translate({
    tok(T.group_open, '(', 1, { kind = GK.capturing, wordness = W.non_word }),
    tok(T.literal, 'f', 2, { wordness = W.word }),
    tok(T.literal, 'o', 3, { wordness = W.word }),
    tok(T.literal, 'o', 4, { wordness = W.word }),
    tok(T.group_close, ')', 5, { wordness = W.non_word }),
  }, {}), {
    pattern = '\\v(foo)',
    warnings = {},
  })
end)

--------------------------------------------------------------------------------
--- Groups: non-capturing ------------------------------------------------------
--------------------------------------------------------------------------------

test('group: non-capturing becomes %()', function()
  deep_eq(translate({
    tok(T.group_open, '(?:', 1, { kind = GK.non_capturing, wordness = W.non_word }),
    tok(T.literal, 'f', 4, { wordness = W.word }),
    tok(T.literal, 'o', 5, { wordness = W.word }),
    tok(T.literal, 'o', 6, { wordness = W.word }),
    tok(T.group_close, ')', 7, { wordness = W.non_word }),
  }, {}), {
    pattern = '\\v%(foo)',
    warnings = {},
  })
end)

--------------------------------------------------------------------------------
--- Groups: named (become numbered with warning) -------------------------------
--------------------------------------------------------------------------------

test('group: named Python style becomes numbered', function()
  deep_eq(translate({
    tok(T.group_open, '(?P<n>', 1, { kind = GK.named_python, name = 'name', wordness = W.non_word }),
    tok(T.literal, 'f', 10, { wordness = W.word }),
    tok(T.literal, 'o', 11, { wordness = W.word }),
    tok(T.literal, 'o', 12, { wordness = W.word }),
    tok(T.group_close, ')', 13, { wordness = W.non_word }),
  }, {}), {
    pattern = '\\v(foo)',
    warnings = { 'named groups become numbered' },
  })
end)

test('group: named PCRE style becomes numbered', function()
  deep_eq(translate({
    tok(T.group_open, '(?<n>', 1, { kind = GK.named_pcre, name = 'name', wordness = W.non_word }),
    tok(T.literal, 'f', 9, { wordness = W.word }),
    tok(T.literal, 'o', 10, { wordness = W.word }),
    tok(T.literal, 'o', 11, { wordness = W.word }),
    tok(T.group_close, ')', 12, { wordness = W.non_word }),
  }, {}), {
    pattern = '\\v(foo)',
    warnings = { 'named groups become numbered' },
  })
end)

test('group: multiple named groups', function()
  deep_eq(translate({
    tok(T.group_open, '(?P<a>', 1, { kind = GK.named_python, name = 'a', wordness = W.non_word }),
    tok(T.literal, 'f', 7, { wordness = W.word }),
    tok(T.literal, 'o', 8, { wordness = W.word }),
    tok(T.literal, 'o', 9, { wordness = W.word }),
    tok(T.group_close, ')', 10, { wordness = W.non_word }),
    tok(T.group_open, '(?P<b>', 11, { kind = GK.named_python, name = 'b', wordness = W.non_word }),
    tok(T.literal, 'b', 17, { wordness = W.word }),
    tok(T.literal, 'a', 18, { wordness = W.word }),
    tok(T.literal, 'r', 19, { wordness = W.word }),
    tok(T.group_close, ')', 20, { wordness = W.non_word }),
  }, {}), {
    pattern = '\\v(foo)(bar)',
    warnings = { 'named groups become numbered', 'named groups become numbered' },
  })
end)

--------------------------------------------------------------------------------
--- Alternation ----------------------------------------------------------------
--------------------------------------------------------------------------------

test('alternation: simple', function()
  deep_eq(translate({
    tok(T.literal, 'f', 1, { wordness = W.word }),
    tok(T.literal, 'o', 2, { wordness = W.word }),
    tok(T.literal, 'o', 3, { wordness = W.word }),
    tok(T.alternation, '|', 4, { wordness = W.non_word }),
    tok(T.literal, 'b', 5, { wordness = W.word }),
    tok(T.literal, 'a', 6, { wordness = W.word }),
    tok(T.literal, 'r', 7, { wordness = W.word }),
  }, {}), {
    pattern = '\\vfoo|bar',
    warnings = {},
  })
end)

test('alternation: in group', function()
  deep_eq(translate({
    tok(T.group_open, '(', 1, { kind = GK.capturing, wordness = W.non_word }),
    tok(T.literal, 'f', 2, { wordness = W.word }),
    tok(T.literal, 'o', 3, { wordness = W.word }),
    tok(T.literal, 'o', 4, { wordness = W.word }),
    tok(T.alternation, '|', 5, { wordness = W.non_word }),
    tok(T.literal, 'b', 6, { wordness = W.word }),
    tok(T.literal, 'a', 7, { wordness = W.word }),
    tok(T.literal, 'r', 8, { wordness = W.word }),
    tok(T.group_close, ')', 9, { wordness = W.non_word }),
  }, {}), {
    pattern = '\\v(foo|bar)',
    warnings = {},
  })
end)

--------------------------------------------------------------------------------
--- Character classes ----------------------------------------------------------
--------------------------------------------------------------------------------

test('class: simple', function()
  deep_eq(translate({
    tok(T.char_class_open, '[', 1, { negated = false, wordness = W.word }),
    tok(CC.cc_literal, 'a', 2),
    tok(CC.cc_literal, 'b', 3),
    tok(CC.cc_literal, 'c', 4),
    tok(T.char_class_close, ']', 5, { wordness = W.word }),
  }, {}), {
    pattern = '\\v[abc]',
    warnings = {},
  })
end)

test('class: range', function()
  deep_eq(translate({
    tok(T.char_class_open, '[', 1, { negated = false, wordness = W.word }),
    tok(CC.cc_range, 'a-z', 2, { from = 'a', to = 'z' }),
    tok(T.char_class_close, ']', 5, { wordness = W.word }),
  }, {}), {
    pattern = '\\v[a-z]',
    warnings = {},
  })
end)

test('class: negated', function()
  deep_eq(translate({
    tok(T.char_class_open, '[^', 1, { negated = true, wordness = W.unknown }),
    tok(CC.cc_literal, 'a', 3),
    tok(CC.cc_literal, 'b', 4),
    tok(CC.cc_literal, 'c', 5),
    tok(T.char_class_close, ']', 6, { wordness = W.unknown }),
  }, {}), {
    pattern = '\\v[^abc]',
    warnings = {},
  })
end)

test('class: ] at start literal', function()
  deep_eq(translate({
    tok(T.char_class_open, '[', 1, { negated = false, wordness = W.non_word }),
    tok(CC.cc_literal, ']', 2),
    tok(CC.cc_literal, 'a', 3),
    tok(CC.cc_literal, 'b', 4),
    tok(CC.cc_literal, 'c', 5),
    tok(T.char_class_close, ']', 6, { wordness = W.non_word }),
  }, {}), {
    pattern = '\\v[]abc]',
    warnings = {},
  })
end)

test('class: shorthands inside', function()
  deep_eq(translate({
    tok(T.char_class_open, '[', 1, { negated = false, wordness = W.word }),
    tok(CC.cc_escape, '\\d', 2),
    tok(CC.cc_escape, '\\w', 4),
    tok(T.char_class_close, ']', 6, { wordness = W.word }),
  }, {}), {
    pattern = '\\v[\\d\\w]',
    warnings = {},
  })
end)

test('class: vim-special chars inside (no escape)', function()
  deep_eq(translate({
    tok(T.char_class_open, '[', 1, { negated = false, wordness = W.non_word }),
    tok(CC.cc_literal, '~', 2),
    tok(CC.cc_literal, '=', 3),
    tok(T.char_class_close, ']', 4, { wordness = W.non_word }),
  }, {}), {
    pattern = '\\v[~=]',
    warnings = {},
  })
end)

test('class: forward slash inside needs escaping', function()
  deep_eq(translate({
    tok(T.char_class_open, '[', 1, { negated = false, wordness = W.non_word }),
    tok(CC.cc_literal, '/', 2),
    tok(T.char_class_close, ']', 3, { wordness = W.non_word }),
  }, {}), {
    pattern = '\\v[\\/]',
    warnings = {},
  })
end)

--------------------------------------------------------------------------------
--- Complex patterns -----------------------------------------------------------
--------------------------------------------------------------------------------

test('complex: function call pattern', function()
  deep_eq(translate({
    tok(T.escape, '\\w', 1, { escape_class = EC.shorthand_word, wordness = W.word }),
    tok(T.quantifier, '+', 3, { greedy = true, wordness = W.word }),
    tok(T.group_open, '(', 4, { kind = GK.capturing, wordness = W.non_word }),
    tok(T.literal, '.', 5, { wordness = W.unknown }),
    tok(T.quantifier, '*', 6, { greedy = true, wordness = W.unknown }),
    tok(T.group_close, ')', 7, { wordness = W.non_word }),
  }, {}), {
    pattern = '\\v\\w+(.*)',
    warnings = {},
  })
end)

test('complex: email-like pattern', function()
  deep_eq(translate({
    tok(T.char_class_open, '[', 1, { negated = false, wordness = W.word }),
    tok(CC.cc_range, 'a-z', 2, { from = 'a', to = 'z' }),
    tok(T.char_class_close, ']', 5, { wordness = W.word }),
    tok(T.quantifier, '+', 6, { greedy = true, wordness = W.word }),
    tok(T.literal, '@', 7, { wordness = W.non_word }),
    tok(T.char_class_open, '[', 8, { negated = false, wordness = W.word }),
    tok(CC.cc_range, 'a-z', 9, { from = 'a', to = 'z' }),
    tok(T.char_class_close, ']', 12, { wordness = W.word }),
    tok(T.quantifier, '+', 13, { greedy = true, wordness = W.word }),
  }, {}), {
    pattern = '\\v[a-z]+\\@[a-z]+',
    warnings = {},
  })
end)

test('complex: URL path', function()
  deep_eq(translate({
    tok(T.slash, '/', 1, { wordness = W.non_word }),
    tok(T.literal, 'a', 2, { wordness = W.word }),
    tok(T.literal, 'p', 3, { wordness = W.word }),
    tok(T.literal, 'i', 4, { wordness = W.word }),
    tok(T.slash, '/', 5, { wordness = W.non_word }),
    tok(T.literal, 'v', 6, { wordness = W.word }),
    tok(T.char_class_open, '[', 7, { negated = false, wordness = W.word }),
    tok(CC.cc_range, '0-9', 8, { from = '0', to = '9' }),
    tok(T.char_class_close, ']', 11, { wordness = W.word }),
    tok(T.quantifier, '+', 12, { greedy = true, wordness = W.word }),
  }, {}), {
    pattern = '\\v\\/api\\/v[0-9]+',
    warnings = {},
  })
end)

test('complex: word boundary pattern', function()
  deep_eq(translate({
    tok(T.escape, '\\b', 1, { escape_class = EC.boundary, prev_wordness = nil, next_wordness = W.word }),
    tok(T.escape, '\\w', 3, { escape_class = EC.shorthand_word, wordness = W.word }),
    tok(T.quantifier, '{3,5}', 5, { greedy = true, wordness = W.word }),
    tok(T.escape, '\\b', 10, { escape_class = EC.boundary, prev_wordness = W.word, next_wordness = nil }),
  }, {}), {
    pattern = '\\v<\\w{3,5}>',
    warnings = {},
  })
end)

test('complex: quoted string non-greedy', function()
  deep_eq(translate({
    tok(T.literal, '"', 1, { wordness = W.non_word }),
    tok(T.char_class_open, '[^', 2, { negated = true, wordness = W.unknown }),
    tok(CC.cc_literal, '"', 4),
    tok(T.char_class_close, ']', 5, { wordness = W.unknown }),
    tok(T.quantifier, '*?', 6, { greedy = false, wordness = W.unknown }),
    tok(T.literal, '"', 8, { wordness = W.non_word }),
  }, {}), {
    pattern = '\\v"[^"]{-}"',
    warnings = {},
  })
end)

--------------------------------------------------------------------------------
--- Edge cases -----------------------------------------------------------------
--------------------------------------------------------------------------------

test('edge: single backslash at end', function()
  deep_eq(translate({
    tok(T.literal, 'a', 1, { wordness = W.word }),
    tok(T.escape, '\\', 2, { escape_class = EC.escaped_literal, wordness = W.non_word }),
  }, {}), {
    pattern = '\\va\\',
    warnings = {},
  })
end)

test('edge: only metacharacters', function()
  -- When quantifier chars appear without preceding atom, they are literals
  deep_eq(translate({
    tok(T.literal, '+', 1, { wordness = W.non_word }),
    tok(T.literal, '?', 2, { wordness = W.non_word }),
    tok(T.alternation, '|', 3, { wordness = W.non_word }),
  }, {}), {
    pattern = '\\v+?|',
    warnings = {},
  })
end)

test('edge: unclosed bracket', function()
  -- Tokeniser passes through; translator handles gracefully
  deep_eq(translate({
    tok(T.char_class_open, '[', 1, { negated = false, wordness = W.word }),
    tok(CC.cc_literal, 'a', 2),
    tok(CC.cc_literal, 'b', 3),
    tok(CC.cc_literal, 'c', 4),
  }, {}), {
    pattern = '\\v[abc',
    warnings = {},
  })
end)

test('edge: unclosed group', function()
  deep_eq(translate({
    tok(T.group_open, '(', 1, { kind = GK.capturing, wordness = W.non_word }),
    tok(T.literal, 'f', 2, { wordness = W.word }),
    tok(T.literal, 'o', 3, { wordness = W.word }),
    tok(T.literal, 'o', 4, { wordness = W.word }),
  }, {}), {
    pattern = '\\v(foo',
    warnings = {},
  })
end)

test('edge: only special chars', function()
  deep_eq(translate({
    tok(T.literal, '~', 1, { wordness = W.non_word }),
    tok(T.literal, '=', 2, { wordness = W.non_word }),
    tok(T.literal, '@', 3, { wordness = W.non_word }),
    tok(T.literal, '&', 4, { wordness = W.non_word }),
    tok(T.literal, '<', 5, { wordness = W.non_word }),
    tok(T.literal, '>', 6, { wordness = W.non_word }),
  }, {}), {
    pattern = '\\v\\~\\=\\@\\&\\<\\>',
    warnings = {},
  })
end)

test('edge: consecutive escapes', function()
  deep_eq(translate({
    tok(T.escape, '\\\\', 1, { escape_class = EC.escaped_literal, wordness = W.non_word }),
    tok(T.escape, '\\d', 3, { escape_class = EC.shorthand_word, wordness = W.word }),
  }, {}), {
    pattern = '\\v\\\\\\d',
    warnings = {},
  })
end)

--------------------------------------------------------------------------------
--- Warnings array -------------------------------------------------------------
--------------------------------------------------------------------------------

test('warnings: single warning', function()
  deep_eq(translate({
    tok(T.escape, '\\A', 1, { escape_class = EC.anchor_start, wordness = W.non_word }),
  }, {}), {
    pattern = '\\v^',
    warnings = { '\\A treated as ^' },
  })
end)

test('warnings: two warnings', function()
  deep_eq(translate({
    tok(T.escape, '\\A', 1, { escape_class = EC.anchor_start, wordness = W.non_word }),
    tok(T.escape, '\\z', 3, { escape_class = EC.anchor_end, wordness = W.non_word }),
  }, {}), {
    pattern = '\\v^$',
    warnings = { '\\A treated as ^', '\\z treated as $' },
  })
end)

test('warnings: three warnings', function()
  deep_eq(translate({
    tok(T.escape, '\\A', 1, { escape_class = EC.anchor_start, wordness = W.non_word }),
    tok(T.group_open, '(?P<n>', 3, { kind = GK.named_python, name = 'n', wordness = W.non_word }),
    tok(T.literal, 'x', 9, { wordness = W.word }),
    tok(T.group_close, ')', 10, { wordness = W.non_word }),
    tok(T.escape, '\\z', 11, { escape_class = EC.anchor_end, wordness = W.non_word }),
  }, {}), {
    pattern = '\\v^(x)$',
    warnings = { '\\A treated as ^', 'named groups become numbered', '\\z treated as $' },
  })
end)

--------------------------------------------------------------------------------
--- Summary --------------------------------------------------------------------
--------------------------------------------------------------------------------

h.summary()
