-- tests/pattern/translator_test.lua

-- Run with:
--   nvim --headless -c "luafile tests/pattern/translator_test.lua" -c "q"

local h = require('tests.harness')
local test = h.test
local eq = h.eq
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

--- Helper to assert translation produces expected pattern.
---@param tokens table Parsed tokens
---@param expected_pattern string Expected Vim pattern
---@param opts? table Translation options
local function assert_translates(tokens, expected_pattern, opts)
  local result = translate(tokens, opts or {})
  eq(result.pattern, expected_pattern)
end

--- Helper to assert translation produces expected pattern and warning.
---@param tokens table Parsed tokens
---@param expected_pattern string Expected Vim pattern
---@param expected_warning string Expected warning
---@param opts? table Translation options
local function assert_translates_with_warning(tokens, expected_pattern, expected_warning, opts)
  local result = translate(tokens, opts or {})
  eq(result.pattern, expected_pattern)
  eq(result.warning, expected_warning)
end

--------------------------------------------------------------------------------
--- Empty input ----------------------------------------------------------------
--------------------------------------------------------------------------------

test('empty: empty token list', function()
  assert_translates({}, '\\v')
end)

--------------------------------------------------------------------------------
--- Fixed string mode ----------------------------------------------------------
--------------------------------------------------------------------------------

test('fixed: simple literal', function()
  -- In fixed mode, tokens are literals; translator handles escaping
  assert_translates({
    tok(T.literal, 'h', 1, { wordness = W.word }),
    tok(T.literal, 'e', 2, { wordness = W.word }),
    tok(T.literal, 'l', 3, { wordness = W.word }),
    tok(T.literal, 'l', 4, { wordness = W.word }),
    tok(T.literal, 'o', 5, { wordness = W.word }),
  }, '\\Vhello', { fixed = true })
end)

test('fixed: escapes backslashes', function()
  assert_translates({
    tok(T.literal, 'f', 1, { wordness = W.word }),
    tok(T.literal, 'o', 2, { wordness = W.word }),
    tok(T.literal, 'o', 3, { wordness = W.word }),
    tok(T.escape, '\\\\', 4, { escape_class = EC.escaped_literal, wordness = W.non_word }),
    tok(T.literal, 'b', 6, { wordness = W.word }),
    tok(T.literal, 'a', 7, { wordness = W.word }),
    tok(T.literal, 'r', 8, { wordness = W.word }),
  }, '\\Vfoo\\\\bar', { fixed = true })
end)

test('fixed: escapes forward slashes', function()
  assert_translates({
    tok(T.literal, 'f', 1, { wordness = W.word }),
    tok(T.literal, 'o', 2, { wordness = W.word }),
    tok(T.literal, 'o', 3, { wordness = W.word }),
    tok(T.slash, '/', 4, { wordness = W.non_word }),
    tok(T.literal, 'b', 5, { wordness = W.word }),
    tok(T.literal, 'a', 6, { wordness = W.word }),
    tok(T.literal, 'r', 7, { wordness = W.word }),
  }, '\\Vfoo\\/bar', { fixed = true })
end)

test('fixed: with word boundary', function()
  assert_translates({
    tok(T.literal, 'h', 1, { wordness = W.word }),
    tok(T.literal, 'e', 2, { wordness = W.word }),
    tok(T.literal, 'l', 3, { wordness = W.word }),
    tok(T.literal, 'l', 4, { wordness = W.word }),
    tok(T.literal, 'o', 5, { wordness = W.word }),
  }, '\\V\\<hello\\>', { fixed = true, word = true })
end)

test('fixed: case sensitive', function()
  assert_translates({
    tok(T.literal, 'h', 1, { wordness = W.word }),
    tok(T.literal, 'i', 2, { wordness = W.word }),
  }, '\\C\\Vhi', { fixed = true, case = 'case-sensitive' })
end)

test('fixed: case insensitive', function()
  assert_translates({
    tok(T.literal, 'h', 1, { wordness = W.word }),
    tok(T.literal, 'i', 2, { wordness = W.word }),
  }, '\\c\\Vhi', { fixed = true, case = 'case-insensitive' })
end)

--------------------------------------------------------------------------------
--- Literals: pass through -----------------------------------------------------
--------------------------------------------------------------------------------

test('literal: single letter', function()
  assert_translates({
    tok(T.literal, 'a', 1, { wordness = W.word }),
  }, '\\va')
end)

test('literal: multiple letters', function()
  assert_translates({
    tok(T.literal, 'a', 1, { wordness = W.word }),
    tok(T.literal, 'b', 2, { wordness = W.word }),
    tok(T.literal, 'c', 3, { wordness = W.word }),
  }, '\\vabc')
end)

test('literal: dot passes through', function()
  assert_translates({
    tok(T.literal, 'a', 1, { wordness = W.word }),
    tok(T.literal, '.', 2, { wordness = W.unknown }),
    tok(T.literal, 'b', 3, { wordness = W.word }),
  }, '\\va.b')
end)

--------------------------------------------------------------------------------
--- Vim-special characters (need escaping outside char classes) ----------------
--------------------------------------------------------------------------------

test('vimspecial: equals sign', function()
  assert_translates({
    tok(T.literal, 'f', 1, { wordness = W.word }),
    tok(T.literal, 'o', 2, { wordness = W.word }),
    tok(T.literal, 'o', 3, { wordness = W.word }),
    tok(T.literal, '=', 4, { wordness = W.non_word }),
    tok(T.literal, 'b', 5, { wordness = W.word }),
    tok(T.literal, 'a', 6, { wordness = W.word }),
    tok(T.literal, 'r', 7, { wordness = W.word }),
  }, '\\vfoo\\=bar')
end)

test('vimspecial: tilde', function()
  assert_translates({
    tok(T.literal, 'x', 1, { wordness = W.word }),
    tok(T.literal, '~', 2, { wordness = W.non_word }),
    tok(T.literal, 'y', 3, { wordness = W.word }),
  }, '\\vx\\~y')
end)

test('vimspecial: at sign', function()
  assert_translates({
    tok(T.literal, 'a', 1, { wordness = W.word }),
    tok(T.literal, '@', 2, { wordness = W.non_word }),
    tok(T.literal, 'b', 3, { wordness = W.word }),
  }, '\\va\\@b')
end)

test('vimspecial: ampersand', function()
  assert_translates({
    tok(T.literal, 'a', 1, { wordness = W.word }),
    tok(T.literal, '&', 2, { wordness = W.non_word }),
    tok(T.literal, 'b', 3, { wordness = W.word }),
  }, '\\va\\&b')
end)

test('vimspecial: less than', function()
  assert_translates({
    tok(T.literal, 'a', 1, { wordness = W.word }),
    tok(T.literal, '<', 2, { wordness = W.non_word }),
    tok(T.literal, 'b', 3, { wordness = W.word }),
  }, '\\va\\<b')
end)

test('vimspecial: greater than', function()
  assert_translates({
    tok(T.literal, 'x', 1, { wordness = W.word }),
    tok(T.literal, ' ', 2, { wordness = W.non_word }),
    tok(T.literal, '>', 3, { wordness = W.non_word }),
    tok(T.literal, ' ', 4, { wordness = W.non_word }),
    tok(T.literal, '0', 5, { wordness = W.word }),
  }, '\\vx \\> 0')
end)

--------------------------------------------------------------------------------
--- Forward slash (search delimiter) -------------------------------------------
--------------------------------------------------------------------------------

test('slash: simple path', function()
  assert_translates({
    tok(T.literal, 'f', 1, { wordness = W.word }),
    tok(T.literal, 'o', 2, { wordness = W.word }),
    tok(T.literal, 'o', 3, { wordness = W.word }),
    tok(T.slash, '/', 4, { wordness = W.non_word }),
    tok(T.literal, 'b', 5, { wordness = W.word }),
    tok(T.literal, 'a', 6, { wordness = W.word }),
    tok(T.literal, 'r', 7, { wordness = W.word }),
  }, '\\vfoo\\/bar')
end)

--------------------------------------------------------------------------------
--- Anchors (^ and $) ----------------------------------------------------------
--------------------------------------------------------------------------------

test('anchor: caret at start', function()
  assert_translates({
    tok(T.anchor, '^', 1, { wordness = W.non_word }),
    tok(T.literal, 'a', 2, { wordness = W.word }),
  }, '\\v^a')
end)

test('anchor: dollar at end', function()
  assert_translates({
    tok(T.literal, 'a', 1, { wordness = W.word }),
    tok(T.anchor, '$', 2, { wordness = W.non_word }),
  }, '\\va$')
end)

--------------------------------------------------------------------------------
--- Escape sequences: shorthands pass through ----------------------------------
--------------------------------------------------------------------------------

test('escape: \\w passes through', function()
  assert_translates({
    tok(T.escape, '\\w', 1, { escape_class = EC.shorthand_word, wordness = W.word }),
  }, '\\v\\w')
end)

test('escape: \\d passes through', function()
  assert_translates({
    tok(T.escape, '\\d', 1, { escape_class = EC.shorthand_word, wordness = W.word }),
  }, '\\v\\d')
end)

test('escape: \\s passes through', function()
  assert_translates({
    tok(T.escape, '\\s', 1, { escape_class = EC.shorthand_nonword, wordness = W.non_word }),
  }, '\\v\\s')
end)

test('escape: \\W passes through', function()
  assert_translates({
    tok(T.escape, '\\W', 1, { escape_class = EC.shorthand_nonword, wordness = W.non_word }),
  }, '\\v\\W')
end)

test('escape: \\S passes through', function()
  assert_translates({
    tok(T.escape, '\\S', 1, { escape_class = EC.shorthand_unknown, wordness = W.unknown }),
  }, '\\v\\S')
end)

test('escape: \\D passes through', function()
  assert_translates({
    tok(T.escape, '\\D', 1, { escape_class = EC.shorthand_unknown, wordness = W.unknown }),
  }, '\\v\\D')
end)

test('escape: \\t passes through', function()
  assert_translates({
    tok(T.escape, '\\t', 1, { escape_class = EC.shorthand_nonword, wordness = W.non_word }),
  }, '\\v\\t')
end)

test('escape: \\n passes through', function()
  assert_translates({
    tok(T.escape, '\\n', 1, { escape_class = EC.shorthand_nonword, wordness = W.non_word }),
  }, '\\v\\n')
end)

test('escape: \\r passes through', function()
  assert_translates({
    tok(T.escape, '\\r', 1, { escape_class = EC.shorthand_nonword, wordness = W.non_word }),
  }, '\\v\\r')
end)

--------------------------------------------------------------------------------
--- Escape sequences: escaped literals pass through ----------------------------
--------------------------------------------------------------------------------

test('escape: \\( passes through', function()
  assert_translates({
    tok(T.escape, '\\(', 1, { escape_class = EC.escaped_literal, wordness = W.non_word }),
  }, '\\v\\(')
end)

test('escape: \\. passes through', function()
  assert_translates({
    tok(T.escape, '\\.', 1, { escape_class = EC.escaped_literal, wordness = W.non_word }),
  }, '\\v\\.')
end)

test('escape: \\\\ passes through', function()
  assert_translates({
    tok(T.escape, '\\\\', 1, { escape_class = EC.escaped_literal, wordness = W.non_word }),
  }, '\\v\\\\')
end)

--------------------------------------------------------------------------------
--- Escape sequences: anchors --------------------------------------------------
--------------------------------------------------------------------------------

test('escape: \\A becomes ^ with warning', function()
  assert_translates_with_warning({
    tok(T.escape, '\\A', 1, { escape_class = EC.anchor_start, wordness = W.non_word }),
    tok(T.literal, 'f', 3, { wordness = W.word }),
    tok(T.literal, 'o', 4, { wordness = W.word }),
    tok(T.literal, 'o', 5, { wordness = W.word }),
  }, '\\v^foo', '\\A treated as ^')
end)

test('escape: \\z becomes $ with warning', function()
  assert_translates_with_warning({
    tok(T.literal, 'f', 1, { wordness = W.word }),
    tok(T.literal, 'o', 2, { wordness = W.word }),
    tok(T.literal, 'o', 3, { wordness = W.word }),
    tok(T.escape, '\\z', 4, { escape_class = EC.anchor_end, wordness = W.non_word }),
  }, '\\vfoo$', '\\z treated as $')
end)

test('escape: \\A and \\z together shows count', function()
  assert_translates_with_warning({
    tok(T.escape, '\\A', 1, { escape_class = EC.anchor_start, wordness = W.non_word }),
    tok(T.literal, 'f', 3, { wordness = W.word }),
    tok(T.literal, 'o', 4, { wordness = W.word }),
    tok(T.literal, 'o', 5, { wordness = W.word }),
    tok(T.escape, '\\z', 6, { escape_class = EC.anchor_end, wordness = W.non_word }),
  }, '\\v^foo$', '\\A treated as ^ (+1 more)')
end)

--------------------------------------------------------------------------------
--- Word boundaries: basic translation -----------------------------------------
--------------------------------------------------------------------------------

test('boundary: \\b at start (before word) => <', function()
  assert_translates({
    tok(T.escape, '\\b', 1, { escape_class = EC.boundary, prev_wordness = nil, next_wordness = W.word }),
    tok(T.literal, 'w', 3, { wordness = W.word }),
    tok(T.literal, 'o', 4, { wordness = W.word }),
    tok(T.literal, 'r', 5, { wordness = W.word }),
    tok(T.literal, 'd', 6, { wordness = W.word }),
  }, '\\v<word')
end)

test('boundary: \\b at end (after word) => >', function()
  assert_translates({
    tok(T.literal, 'w', 1, { wordness = W.word }),
    tok(T.literal, 'o', 2, { wordness = W.word }),
    tok(T.literal, 'r', 3, { wordness = W.word }),
    tok(T.literal, 'd', 4, { wordness = W.word }),
    tok(T.escape, '\\b', 5, { escape_class = EC.boundary, prev_wordness = W.word, next_wordness = nil }),
  }, '\\vword>')
end)

test('boundary: \\b at both ends', function()
  assert_translates({
    tok(T.escape, '\\b', 1, { escape_class = EC.boundary, prev_wordness = nil, next_wordness = W.word }),
    tok(T.literal, 'w', 3, { wordness = W.word }),
    tok(T.literal, 'o', 4, { wordness = W.word }),
    tok(T.literal, 'r', 5, { wordness = W.word }),
    tok(T.literal, 'd', 6, { wordness = W.word }),
    tok(T.escape, '\\b', 7, { escape_class = EC.boundary, prev_wordness = W.word, next_wordness = nil }),
  }, '\\v<word>')
end)

test('boundary: \\b in middle (word-word) => fallback', function()
  -- Both sides are word chars, so boundary is ambiguous
  assert_translates({
    tok(T.literal, 'f', 1, { wordness = W.word }),
    tok(T.literal, 'o', 2, { wordness = W.word }),
    tok(T.literal, 'o', 3, { wordness = W.word }),
    tok(T.escape, '\\b', 4, { escape_class = EC.boundary, prev_wordness = W.word, next_wordness = W.word }),
    tok(T.literal, 'b', 6, { wordness = W.word }),
    tok(T.literal, 'a', 7, { wordness = W.word }),
    tok(T.literal, 'r', 8, { wordness = W.word }),
  }, '\\vfoo%(<|>)bar')
end)

test('boundary: \\b after space => <', function()
  assert_translates({
    tok(T.literal, 'f', 1, { wordness = W.word }),
    tok(T.literal, 'o', 2, { wordness = W.word }),
    tok(T.literal, 'o', 3, { wordness = W.word }),
    tok(T.literal, ' ', 4, { wordness = W.non_word }),
    tok(T.escape, '\\b', 5, { escape_class = EC.boundary, prev_wordness = W.non_word, next_wordness = W.word }),
    tok(T.literal, 'b', 7, { wordness = W.word }),
    tok(T.literal, 'a', 8, { wordness = W.word }),
    tok(T.literal, 'r', 9, { wordness = W.word }),
  }, '\\vfoo <bar')
end)

test('boundary: \\b before space => >', function()
  assert_translates({
    tok(T.literal, 'f', 1, { wordness = W.word }),
    tok(T.literal, 'o', 2, { wordness = W.word }),
    tok(T.literal, 'o', 3, { wordness = W.word }),
    tok(T.escape, '\\b', 4, { escape_class = EC.boundary, prev_wordness = W.word, next_wordness = W.non_word }),
    tok(T.literal, ' ', 6, { wordness = W.non_word }),
    tok(T.literal, 'b', 7, { wordness = W.word }),
    tok(T.literal, 'a', 8, { wordness = W.word }),
    tok(T.literal, 'r', 9, { wordness = W.word }),
  }, '\\vfoo> bar')
end)

--------------------------------------------------------------------------------
--- Word boundaries: with shorthands -------------------------------------------
--------------------------------------------------------------------------------

test('boundary: \\b with \\w+', function()
  assert_translates({
    tok(T.escape, '\\b', 1, { escape_class = EC.boundary, prev_wordness = nil, next_wordness = W.word }),
    tok(T.escape, '\\w', 3, { escape_class = EC.shorthand_word, wordness = W.word }),
    tok(T.quantifier, '+', 5, { greedy = true, wordness = W.word }),
    tok(T.escape, '\\b', 6, { escape_class = EC.boundary, prev_wordness = W.word, next_wordness = nil }),
  }, '\\v<\\w+>')
end)

test('boundary: \\b after \\W => <', function()
  assert_translates({
    tok(T.escape, '\\W', 1, { escape_class = EC.shorthand_nonword, wordness = W.non_word }),
    tok(T.escape, '\\b', 3, { escape_class = EC.boundary, prev_wordness = W.non_word, next_wordness = W.word }),
    tok(T.literal, 'f', 5, { wordness = W.word }),
    tok(T.literal, 'o', 6, { wordness = W.word }),
    tok(T.literal, 'o', 7, { wordness = W.word }),
  }, '\\v\\W<foo')
end)

test('boundary: \\b before \\W => >', function()
  assert_translates({
    tok(T.literal, 'f', 1, { wordness = W.word }),
    tok(T.literal, 'o', 2, { wordness = W.word }),
    tok(T.literal, 'o', 3, { wordness = W.word }),
    tok(T.escape, '\\b', 4, { escape_class = EC.boundary, prev_wordness = W.word, next_wordness = W.non_word }),
    tok(T.escape, '\\W', 6, { escape_class = EC.shorthand_nonword, wordness = W.non_word }),
  }, '\\vfoo>\\W')
end)

--------------------------------------------------------------------------------
--- Word boundaries: with unknown atoms ----------------------------------------
--------------------------------------------------------------------------------

test('boundary: \\b after \\S (unknown) => fallback', function()
  assert_translates({
    tok(T.escape, '\\S', 1, { escape_class = EC.shorthand_unknown, wordness = W.unknown }),
    tok(T.escape, '\\b', 3, { escape_class = EC.boundary, prev_wordness = W.unknown, next_wordness = W.word }),
    tok(T.literal, 'f', 5, { wordness = W.word }),
    tok(T.literal, 'o', 6, { wordness = W.word }),
    tok(T.literal, 'o', 7, { wordness = W.word }),
  }, '\\v\\S%(<|>)foo')
end)

test('boundary: \\b before \\S (unknown) => fallback', function()
  assert_translates({
    tok(T.literal, 'f', 1, { wordness = W.word }),
    tok(T.literal, 'o', 2, { wordness = W.word }),
    tok(T.literal, 'o', 3, { wordness = W.word }),
    tok(T.escape, '\\b', 4, { escape_class = EC.boundary, prev_wordness = W.word, next_wordness = W.unknown }),
    tok(T.escape, '\\S', 6, { escape_class = EC.shorthand_unknown, wordness = W.unknown }),
  }, '\\vfoo%(<|>)\\S')
end)

test('boundary: \\b after . (unknown) => fallback', function()
  assert_translates({
    tok(T.literal, '.', 1, { wordness = W.unknown }),
    tok(T.escape, '\\b', 2, { escape_class = EC.boundary, prev_wordness = W.unknown, next_wordness = W.word }),
    tok(T.literal, 'f', 4, { wordness = W.word }),
    tok(T.literal, 'o', 5, { wordness = W.word }),
    tok(T.literal, 'o', 6, { wordness = W.word }),
  }, '\\v.%(<|>)foo')
end)

--------------------------------------------------------------------------------
--- Word boundaries: with alternation and groups -------------------------------
--------------------------------------------------------------------------------

test('boundary: \\b after alternation', function()
  assert_translates({
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
  }, '\\v(foo|<bar)')
end)

test('boundary: \\b before alternation', function()
  assert_translates({
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
  }, '\\v(foo>|bar)')
end)

test('boundary: \\b after group start', function()
  assert_translates({
    tok(T.group_open, '(', 1, { kind = GK.capturing, wordness = W.non_word }),
    tok(T.escape, '\\b', 2, { escape_class = EC.boundary, prev_wordness = W.non_word, next_wordness = W.word }),
    tok(T.literal, 'f', 4, { wordness = W.word }),
    tok(T.literal, 'o', 5, { wordness = W.word }),
    tok(T.literal, 'o', 6, { wordness = W.word }),
    tok(T.group_close, ')', 7, { wordness = W.non_word }),
  }, '\\v(<foo)')
end)

test('boundary: \\b before group end', function()
  assert_translates({
    tok(T.group_open, '(', 1, { kind = GK.capturing, wordness = W.non_word }),
    tok(T.literal, 'f', 2, { wordness = W.word }),
    tok(T.literal, 'o', 3, { wordness = W.word }),
    tok(T.literal, 'o', 4, { wordness = W.word }),
    tok(T.escape, '\\b', 5, { escape_class = EC.boundary, prev_wordness = W.word, next_wordness = W.non_word }),
    tok(T.group_close, ')', 7, { wordness = W.non_word }),
  }, '\\v(foo>)')
end)

--------------------------------------------------------------------------------
--- Word boundaries: with anchors ----------------------------------------------
--------------------------------------------------------------------------------

test('boundary: \\b after ^', function()
  assert_translates({
    tok(T.anchor, '^', 1, { wordness = W.non_word }),
    tok(T.escape, '\\b', 2, { escape_class = EC.boundary, prev_wordness = W.non_word, next_wordness = W.word }),
    tok(T.literal, 'f', 4, { wordness = W.word }),
    tok(T.literal, 'o', 5, { wordness = W.word }),
    tok(T.literal, 'o', 6, { wordness = W.word }),
  }, '\\v^<foo')
end)

test('boundary: \\b before $', function()
  assert_translates({
    tok(T.literal, 'f', 1, { wordness = W.word }),
    tok(T.literal, 'o', 2, { wordness = W.word }),
    tok(T.literal, 'o', 3, { wordness = W.word }),
    tok(T.escape, '\\b', 4, { escape_class = EC.boundary, prev_wordness = W.word, next_wordness = W.non_word }),
    tok(T.anchor, '$', 6, { wordness = W.non_word }),
  }, '\\vfoo>$')
end)

--------------------------------------------------------------------------------
--- Word boundaries: with character classes ------------------------------------
--------------------------------------------------------------------------------

test('boundary: \\b before word class => <', function()
  assert_translates({
    tok(T.escape, '\\b', 1, { escape_class = EC.boundary, prev_wordness = nil, next_wordness = W.word }),
    tok(T.char_class_open, '[', 3, { negated = false, wordness = W.word }),
    tok(CC.cc_range, 'a-z', 4, { from = 'a', to = 'z' }),
    tok(T.char_class_close, ']', 7, { wordness = W.word }),
    tok(T.quantifier, '+', 8, { greedy = true, wordness = W.word }),
  }, '\\v<[a-z]+')
end)

test('boundary: word class before \\b => >', function()
  assert_translates({
    tok(T.char_class_open, '[', 1, { negated = false, wordness = W.word }),
    tok(CC.cc_range, 'a-z', 2, { from = 'a', to = 'z' }),
    tok(T.char_class_close, ']', 5, { wordness = W.word }),
    tok(T.quantifier, '+', 6, { greedy = true, wordness = W.word }),
    tok(T.escape, '\\b', 7, { escape_class = EC.boundary, prev_wordness = W.word, next_wordness = nil }),
  }, '\\v[a-z]+>')
end)

test('boundary: negated class => fallback (unknown)', function()
  assert_translates({
    tok(T.char_class_open, '[^', 1, { negated = true, wordness = W.unknown }),
    tok(CC.cc_literal, 'a', 3),
    tok(T.char_class_close, ']', 4, { wordness = W.unknown }),
    tok(T.escape, '\\b', 5, { escape_class = EC.boundary, prev_wordness = W.unknown, next_wordness = W.word }),
    tok(T.literal, 'f', 7, { wordness = W.word }),
    tok(T.literal, 'o', 8, { wordness = W.word }),
    tok(T.literal, 'o', 9, { wordness = W.word }),
  }, '\\v[^a]%(<|>)foo')
end)

--------------------------------------------------------------------------------
--- Word option (wraps in word boundaries) -------------------------------------
--------------------------------------------------------------------------------

test('word option: wraps pattern', function()
  assert_translates({
    tok(T.literal, 'h', 1, { wordness = W.word }),
    tok(T.literal, 'e', 2, { wordness = W.word }),
    tok(T.literal, 'l', 3, { wordness = W.word }),
    tok(T.literal, 'l', 4, { wordness = W.word }),
    tok(T.literal, 'o', 5, { wordness = W.word }),
  }, '\\v<hello>', { word = true })
end)

test('word option: with regex pattern', function()
  assert_translates({
    tok(T.literal, 'f', 1, { wordness = W.word }),
    tok(T.literal, 'o', 2, { wordness = W.word }),
    tok(T.literal, 'o', 3, { wordness = W.word }),
    tok(T.literal, '.', 4, { wordness = W.unknown }),
    tok(T.quantifier, '*', 5, { greedy = true, wordness = W.unknown }),
    tok(T.literal, 'b', 6, { wordness = W.word }),
    tok(T.literal, 'a', 7, { wordness = W.word }),
    tok(T.literal, 'r', 8, { wordness = W.word }),
  }, '\\v<foo.*bar>', { word = true })
end)

--------------------------------------------------------------------------------
--- Case sensitivity -----------------------------------------------------------
--------------------------------------------------------------------------------

test('case: sensitive adds \\C prefix', function()
  assert_translates({
    tok(T.literal, 'h', 1, { wordness = W.word }),
    tok(T.literal, 'e', 2, { wordness = W.word }),
    tok(T.literal, 'l', 3, { wordness = W.word }),
    tok(T.literal, 'l', 4, { wordness = W.word }),
    tok(T.literal, 'o', 5, { wordness = W.word }),
  }, '\\C\\vhello', { case = 'case-sensitive' })
end)

test('case: insensitive adds \\c prefix', function()
  assert_translates({
    tok(T.literal, 'h', 1, { wordness = W.word }),
    tok(T.literal, 'e', 2, { wordness = W.word }),
    tok(T.literal, 'l', 3, { wordness = W.word }),
    tok(T.literal, 'l', 4, { wordness = W.word }),
    tok(T.literal, 'o', 5, { wordness = W.word }),
  }, '\\c\\vhello', { case = 'case-insensitive' })
end)

test('case: sensitive with word boundary', function()
  assert_translates({
    tok(T.literal, 'h', 1, { wordness = W.word }),
    tok(T.literal, 'e', 2, { wordness = W.word }),
    tok(T.literal, 'l', 3, { wordness = W.word }),
    tok(T.literal, 'l', 4, { wordness = W.word }),
    tok(T.literal, 'o', 5, { wordness = W.word }),
  }, '\\C\\v<hello>', { case = 'case-sensitive', word = true })
end)

--------------------------------------------------------------------------------
--- Greedy quantifiers (pass through) ------------------------------------------
--------------------------------------------------------------------------------

test('greedy: * passes through', function()
  assert_translates({
    tok(T.literal, 'a', 1, { wordness = W.word }),
    tok(T.quantifier, '*', 2, { greedy = true, wordness = W.word }),
  }, '\\va*')
end)

test('greedy: + passes through', function()
  assert_translates({
    tok(T.literal, 'a', 1, { wordness = W.word }),
    tok(T.quantifier, '+', 2, { greedy = true, wordness = W.word }),
  }, '\\va+')
end)

test('greedy: ? passes through', function()
  assert_translates({
    tok(T.literal, 'a', 1, { wordness = W.word }),
    tok(T.quantifier, '?', 2, { greedy = true, wordness = W.word }),
  }, '\\va?')
end)

test('greedy: {3} passes through', function()
  assert_translates({
    tok(T.literal, 'a', 1, { wordness = W.word }),
    tok(T.quantifier, '{3}', 2, { greedy = true, wordness = W.word }),
  }, '\\va{3}')
end)

test('greedy: {3,} passes through', function()
  assert_translates({
    tok(T.literal, 'a', 1, { wordness = W.word }),
    tok(T.quantifier, '{3,}', 2, { greedy = true, wordness = W.word }),
  }, '\\va{3,}')
end)

test('greedy: {3,5} passes through', function()
  assert_translates({
    tok(T.literal, 'a', 1, { wordness = W.word }),
    tok(T.quantifier, '{3,5}', 2, { greedy = true, wordness = W.word }),
  }, '\\va{3,5}')
end)

--------------------------------------------------------------------------------
--- Non-greedy quantifiers (translation required) ------------------------------
--------------------------------------------------------------------------------

test('nongreedy: *? becomes {-}', function()
  assert_translates({
    tok(T.literal, 'a', 1, { wordness = W.word }),
    tok(T.quantifier, '*?', 2, { greedy = false, wordness = W.word }),
  }, '\\va{-}')
end)

test('nongreedy: +? becomes {-1,}', function()
  assert_translates({
    tok(T.literal, 'a', 1, { wordness = W.word }),
    tok(T.quantifier, '+?', 2, { greedy = false, wordness = W.word }),
  }, '\\va{-1,}')
end)

test('nongreedy: ?? becomes {-0,1}', function()
  assert_translates({
    tok(T.literal, 'a', 1, { wordness = W.word }),
    tok(T.quantifier, '??', 2, { greedy = false, wordness = W.word }),
  }, '\\va{-0,1}')
end)

test('nongreedy: {3}? becomes {-3}', function()
  assert_translates({
    tok(T.literal, 'a', 1, { wordness = W.word }),
    tok(T.quantifier, '{3}?', 2, { greedy = false, wordness = W.word }),
  }, '\\va{-3}')
end)

test('nongreedy: {3,}? becomes {-3,}', function()
  assert_translates({
    tok(T.literal, 'a', 1, { wordness = W.word }),
    tok(T.quantifier, '{3,}?', 2, { greedy = false, wordness = W.word }),
  }, '\\va{-3,}')
end)

test('nongreedy: {3,5}? becomes {-3,5}', function()
  assert_translates({
    tok(T.literal, 'a', 1, { wordness = W.word }),
    tok(T.quantifier, '{3,5}?', 2, { greedy = false, wordness = W.word }),
  }, '\\va{-3,5}')
end)

test('nongreedy: .*? common pattern', function()
  assert_translates({
    tok(T.literal, '.', 1, { wordness = W.unknown }),
    tok(T.quantifier, '*?', 2, { greedy = false, wordness = W.unknown }),
  }, '\\v.{-}')
end)

test('nongreedy: HTML tag pattern', function()
  assert_translates({
    tok(T.literal, '<', 1, { wordness = W.non_word }),
    tok(T.literal, '.', 2, { wordness = W.unknown }),
    tok(T.quantifier, '*?', 3, { greedy = false, wordness = W.unknown }),
    tok(T.literal, '>', 5, { wordness = W.non_word }),
  }, '\\v\\<.{-}\\>')
end)

--------------------------------------------------------------------------------
--- Groups: capturing ----------------------------------------------------------
--------------------------------------------------------------------------------

test('group: capturing passes through', function()
  assert_translates({
    tok(T.group_open, '(', 1, { kind = GK.capturing, wordness = W.non_word }),
    tok(T.literal, 'f', 2, { wordness = W.word }),
    tok(T.literal, 'o', 3, { wordness = W.word }),
    tok(T.literal, 'o', 4, { wordness = W.word }),
    tok(T.group_close, ')', 5, { wordness = W.non_word }),
  }, '\\v(foo)')
end)

--------------------------------------------------------------------------------
--- Groups: non-capturing ------------------------------------------------------
--------------------------------------------------------------------------------

test('group: non-capturing becomes %()', function()
  assert_translates({
    tok(T.group_open, '(?:', 1, { kind = GK.non_capturing, wordness = W.non_word }),
    tok(T.literal, 'f', 4, { wordness = W.word }),
    tok(T.literal, 'o', 5, { wordness = W.word }),
    tok(T.literal, 'o', 6, { wordness = W.word }),
    tok(T.group_close, ')', 7, { wordness = W.non_word }),
  }, '\\v%(foo)')
end)

--------------------------------------------------------------------------------
--- Groups: named (become numbered with warning) -------------------------------
--------------------------------------------------------------------------------

test('group: named Python style becomes numbered', function()
  assert_translates_with_warning({
    tok(T.group_open, '(?P<name>', 1, { kind = GK.named_python, name = 'name', wordness = W.non_word }),
    tok(T.literal, 'f', 10, { wordness = W.word }),
    tok(T.literal, 'o', 11, { wordness = W.word }),
    tok(T.literal, 'o', 12, { wordness = W.word }),
    tok(T.group_close, ')', 13, { wordness = W.non_word }),
  }, '\\v(foo)', 'named groups become numbered')
end)

test('group: named PCRE style becomes numbered', function()
  assert_translates_with_warning({
    tok(T.group_open, '(?<name>', 1, { kind = GK.named_pcre, name = 'name', wordness = W.non_word }),
    tok(T.literal, 'f', 9, { wordness = W.word }),
    tok(T.literal, 'o', 10, { wordness = W.word }),
    tok(T.literal, 'o', 11, { wordness = W.word }),
    tok(T.group_close, ')', 12, { wordness = W.non_word }),
  }, '\\v(foo)', 'named groups become numbered')
end)

test('group: multiple named groups show count', function()
  assert_translates_with_warning({
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
  }, '\\v(foo)(bar)', 'named groups become numbered (+1 more)')
end)

--------------------------------------------------------------------------------
--- Alternation ----------------------------------------------------------------
--------------------------------------------------------------------------------

test('alternation: simple', function()
  assert_translates({
    tok(T.literal, 'f', 1, { wordness = W.word }),
    tok(T.literal, 'o', 2, { wordness = W.word }),
    tok(T.literal, 'o', 3, { wordness = W.word }),
    tok(T.alternation, '|', 4, { wordness = W.non_word }),
    tok(T.literal, 'b', 5, { wordness = W.word }),
    tok(T.literal, 'a', 6, { wordness = W.word }),
    tok(T.literal, 'r', 7, { wordness = W.word }),
  }, '\\vfoo|bar')
end)

test('alternation: in group', function()
  assert_translates({
    tok(T.group_open, '(', 1, { kind = GK.capturing, wordness = W.non_word }),
    tok(T.literal, 'f', 2, { wordness = W.word }),
    tok(T.literal, 'o', 3, { wordness = W.word }),
    tok(T.literal, 'o', 4, { wordness = W.word }),
    tok(T.alternation, '|', 5, { wordness = W.non_word }),
    tok(T.literal, 'b', 6, { wordness = W.word }),
    tok(T.literal, 'a', 7, { wordness = W.word }),
    tok(T.literal, 'r', 8, { wordness = W.word }),
    tok(T.group_close, ')', 9, { wordness = W.non_word }),
  }, '\\v(foo|bar)')
end)

--------------------------------------------------------------------------------
--- Character classes ----------------------------------------------------------
--------------------------------------------------------------------------------

test('class: simple', function()
  assert_translates({
    tok(T.char_class_open, '[', 1, { negated = false, wordness = W.word }),
    tok(CC.cc_literal, 'a', 2),
    tok(CC.cc_literal, 'b', 3),
    tok(CC.cc_literal, 'c', 4),
    tok(T.char_class_close, ']', 5, { wordness = W.word }),
  }, '\\v[abc]')
end)

test('class: range', function()
  assert_translates({
    tok(T.char_class_open, '[', 1, { negated = false, wordness = W.word }),
    tok(CC.cc_range, 'a-z', 2, { from = 'a', to = 'z' }),
    tok(T.char_class_close, ']', 5, { wordness = W.word }),
  }, '\\v[a-z]')
end)

test('class: negated', function()
  assert_translates({
    tok(T.char_class_open, '[^', 1, { negated = true, wordness = W.unknown }),
    tok(CC.cc_literal, 'a', 3),
    tok(CC.cc_literal, 'b', 4),
    tok(CC.cc_literal, 'c', 5),
    tok(T.char_class_close, ']', 6, { wordness = W.unknown }),
  }, '\\v[^abc]')
end)

test('class: ] at start literal', function()
  assert_translates({
    tok(T.char_class_open, '[', 1, { negated = false, wordness = W.non_word }),
    tok(CC.cc_literal, ']', 2),
    tok(CC.cc_literal, 'a', 3),
    tok(CC.cc_literal, 'b', 4),
    tok(CC.cc_literal, 'c', 5),
    tok(T.char_class_close, ']', 6, { wordness = W.non_word }),
  }, '\\v[]abc]')
end)

test('class: shorthands inside', function()
  assert_translates({
    tok(T.char_class_open, '[', 1, { negated = false, wordness = W.word }),
    tok(CC.cc_escape, '\\d', 2),
    tok(CC.cc_escape, '\\w', 4),
    tok(T.char_class_close, ']', 6, { wordness = W.word }),
  }, '\\v[\\d\\w]')
end)

test('class: vim-special chars inside (no escape)', function()
  assert_translates({
    tok(T.char_class_open, '[', 1, { negated = false, wordness = W.non_word }),
    tok(CC.cc_literal, '~', 2),
    tok(CC.cc_literal, '=', 3),
    tok(T.char_class_close, ']', 4, { wordness = W.non_word }),
  }, '\\v[~=]')
end)

test('class: forward slash inside needs escaping', function()
  assert_translates({
    tok(T.char_class_open, '[', 1, { negated = false, wordness = W.non_word }),
    tok(CC.cc_literal, '/', 2),
    tok(T.char_class_close, ']', 3, { wordness = W.non_word }),
  }, '\\v[\\/]')
end)

--------------------------------------------------------------------------------
--- Complex patterns -----------------------------------------------------------
--------------------------------------------------------------------------------

test('complex: function call pattern', function()
  assert_translates({
    tok(T.escape, '\\w', 1, { escape_class = EC.shorthand_word, wordness = W.word }),
    tok(T.quantifier, '+', 3, { greedy = true, wordness = W.word }),
    tok(T.group_open, '(', 4, { kind = GK.capturing, wordness = W.non_word }),
    tok(T.literal, '.', 5, { wordness = W.unknown }),
    tok(T.quantifier, '*', 6, { greedy = true, wordness = W.unknown }),
    tok(T.group_close, ')', 7, { wordness = W.non_word }),
  }, '\\v\\w+(.*)')
end)

test('complex: email-like pattern', function()
  assert_translates({
    tok(T.char_class_open, '[', 1, { negated = false, wordness = W.word }),
    tok(CC.cc_range, 'a-z', 2, { from = 'a', to = 'z' }),
    tok(T.char_class_close, ']', 5, { wordness = W.word }),
    tok(T.quantifier, '+', 6, { greedy = true, wordness = W.word }),
    tok(T.literal, '@', 7, { wordness = W.non_word }),
    tok(T.char_class_open, '[', 8, { negated = false, wordness = W.word }),
    tok(CC.cc_range, 'a-z', 9, { from = 'a', to = 'z' }),
    tok(T.char_class_close, ']', 12, { wordness = W.word }),
    tok(T.quantifier, '+', 13, { greedy = true, wordness = W.word }),
  }, '\\v[a-z]+\\@[a-z]+')
end)

test('complex: URL path', function()
  assert_translates({
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
  }, '\\v\\/api\\/v[0-9]+')
end)

test('complex: word boundary pattern', function()
  assert_translates({
    tok(T.escape, '\\b', 1, { escape_class = EC.boundary, prev_wordness = nil, next_wordness = W.word }),
    tok(T.escape, '\\w', 3, { escape_class = EC.shorthand_word, wordness = W.word }),
    tok(T.quantifier, '{3,5}', 5, { greedy = true, wordness = W.word }),
    tok(T.escape, '\\b', 10, { escape_class = EC.boundary, prev_wordness = W.word, next_wordness = nil }),
  }, '\\v<\\w{3,5}>')
end)

test('complex: quoted string non-greedy', function()
  assert_translates({
    tok(T.literal, '"', 1, { wordness = W.non_word }),
    tok(T.char_class_open, '[^', 2, { negated = true, wordness = W.unknown }),
    tok(CC.cc_literal, '"', 4),
    tok(T.char_class_close, ']', 5, { wordness = W.unknown }),
    tok(T.quantifier, '*?', 6, { greedy = false, wordness = W.unknown }),
    tok(T.literal, '"', 8, { wordness = W.non_word }),
  }, '\\v"[^"]{-}"')
end)

--------------------------------------------------------------------------------
--- Edge cases -----------------------------------------------------------------
--------------------------------------------------------------------------------

test('edge: single backslash at end', function()
  assert_translates({
    tok(T.literal, 'a', 1, { wordness = W.word }),
    tok(T.escape, '\\', 2, { escape_class = EC.escaped_literal, wordness = W.non_word }),
  }, '\\va\\')
end)

test('edge: only metacharacters', function()
  -- When quantifier chars appear without preceding atom, they are literals
  assert_translates({
    tok(T.literal, '+', 1, { wordness = W.non_word }),
    tok(T.literal, '?', 2, { wordness = W.non_word }),
    tok(T.alternation, '|', 3, { wordness = W.non_word }),
  }, '\\v+?|')
end)

test('edge: unclosed bracket', function()
  -- Tokeniser passes through; translator handles gracefully
  assert_translates({
    tok(T.char_class_open, '[', 1, { negated = false, wordness = W.word }),
    tok(CC.cc_literal, 'a', 2),
    tok(CC.cc_literal, 'b', 3),
    tok(CC.cc_literal, 'c', 4),
  }, '\\v[abc')
end)

test('edge: unclosed group', function()
  assert_translates({
    tok(T.group_open, '(', 1, { kind = GK.capturing, wordness = W.non_word }),
    tok(T.literal, 'f', 2, { wordness = W.word }),
    tok(T.literal, 'o', 3, { wordness = W.word }),
    tok(T.literal, 'o', 4, { wordness = W.word }),
  }, '\\v(foo')
end)

test('edge: only special chars', function()
  assert_translates({
    tok(T.literal, '~', 1, { wordness = W.non_word }),
    tok(T.literal, '=', 2, { wordness = W.non_word }),
    tok(T.literal, '@', 3, { wordness = W.non_word }),
    tok(T.literal, '&', 4, { wordness = W.non_word }),
    tok(T.literal, '<', 5, { wordness = W.non_word }),
    tok(T.literal, '>', 6, { wordness = W.non_word }),
  }, '\\v\\~\\=\\@\\&\\<\\>')
end)

test('edge: consecutive escapes', function()
  assert_translates({
    tok(T.escape, '\\\\', 1, { escape_class = EC.escaped_literal, wordness = W.non_word }),
    tok(T.escape, '\\d', 3, { escape_class = EC.shorthand_word, wordness = W.word }),
  }, '\\v\\\\\\d')
end)

--------------------------------------------------------------------------------
--- Warning formatting ---------------------------------------------------------
--------------------------------------------------------------------------------

test('warnings: single warning', function()
  local result = translate({
    tok(T.escape, '\\A', 1, { escape_class = EC.anchor_start, wordness = W.non_word }),
  }, {})
  eq(result.warning, '\\A treated as ^')
end)

test('warnings: two warnings shows +1 more', function()
  local result = translate({
    tok(T.escape, '\\A', 1, { escape_class = EC.anchor_start, wordness = W.non_word }),
    tok(T.escape, '\\z', 3, { escape_class = EC.anchor_end, wordness = W.non_word }),
  }, {})
  eq(result.warning, '\\A treated as ^ (+1 more)')
end)

test('warnings: three warnings shows +2 more', function()
  local result = translate({
    tok(T.escape, '\\A', 1, { escape_class = EC.anchor_start, wordness = W.non_word }),
    tok(T.group_open, '(?P<n>', 3, { kind = GK.named_python, name = 'n', wordness = W.non_word }),
    tok(T.literal, 'x', 9, { wordness = W.word }),
    tok(T.group_close, ')', 10, { wordness = W.non_word }),
    tok(T.escape, '\\z', 11, { escape_class = EC.anchor_end, wordness = W.non_word }),
  }, {})
  eq(result.warning, '\\A treated as ^ (+2 more)')
end)

--------------------------------------------------------------------------------
--- Summary --------------------------------------------------------------------
--------------------------------------------------------------------------------

h.summary()
