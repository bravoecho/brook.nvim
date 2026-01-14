-- This file: tests/pattern/tokenise_test.lua

-- Run with:
--   nvim --headless -c "luafile tests/pattern/tokeniser_test.lua" -c "q"

local h = require('tests.harness')
local test = h.test
local deep_eq = h.deep_eq
local types = require('brook.pattern.types')

-- Import will fail until tokeniser.lua is implemented
local ok, tokeniser = pcall(require, 'brook.pattern.tokeniser')
if not ok then
  print('SKIP: brook.pattern.tokenise not yet implemented')
  print('0/0 tests passed')
  vim.cmd('cquit 0')
  return
end

local tokenise = tokeniser.tokenise

-- Shorthand for token types
local T = types.token_type
local CC = types.cc_token_type
local GK = types.group_kind

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
--- Empty and simple input -----------------------------------------------------
--------------------------------------------------------------------------------

test('empty: empty string', function()
  deep_eq(tokenise(''), {})
end)

test('simple: single letter', function()
  deep_eq(tokenise('a'), {
    tok(T.literal, 'a', 1),
  })
end)

test('simple: multiple letters', function()
  deep_eq(tokenise('abc'), {
    tok(T.literal, 'a', 1),
    tok(T.literal, 'b', 2),
    tok(T.literal, 'c', 3),
  })
end)

test('simple: word', function()
  deep_eq(tokenise('hello'), {
    tok(T.literal, 'h', 1),
    tok(T.literal, 'e', 2),
    tok(T.literal, 'l', 3),
    tok(T.literal, 'l', 4),
    tok(T.literal, 'o', 5),
  })
end)

test('simple: digits', function()
  deep_eq(tokenise('123'), {
    tok(T.literal, '1', 1),
    tok(T.literal, '2', 2),
    tok(T.literal, '3', 3),
  })
end)

test('simple: underscore', function()
  deep_eq(tokenise('_'), {
    tok(T.literal, '_', 1),
  })
end)

--------------------------------------------------------------------------------
--- Literal special characters (Vim-special, not regex metacharacters) ---------
--------------------------------------------------------------------------------

test('literal: equals sign', function()
  deep_eq(tokenise('='), {
    tok(T.literal, '=', 1),
  })
end)

test('literal: tilde', function()
  deep_eq(tokenise('~'), {
    tok(T.literal, '~', 1),
  })
end)

test('literal: at sign', function()
  deep_eq(tokenise('@'), {
    tok(T.literal, '@', 1),
  })
end)

test('literal: ampersand', function()
  deep_eq(tokenise('&'), {
    tok(T.literal, '&', 1),
  })
end)

test('literal: less than', function()
  deep_eq(tokenise('<'), {
    tok(T.literal, '<', 1),
  })
end)

test('literal: greater than', function()
  deep_eq(tokenise('>'), {
    tok(T.literal, '>', 1),
  })
end)

test('literal: mixed vim-special chars', function()
  deep_eq(tokenise('=~@&<>'), {
    tok(T.literal, '=', 1),
    tok(T.literal, '~', 2),
    tok(T.literal, '@', 3),
    tok(T.literal, '&', 4),
    tok(T.literal, '<', 5),
    tok(T.literal, '>', 6),
  })
end)

--------------------------------------------------------------------------------
--- Forward slash (search delimiter) -------------------------------------------
--------------------------------------------------------------------------------

test('slash: single', function()
  deep_eq(tokenise('/'), {
    tok(T.slash, '/', 1),
  })
end)

test('slash: in path', function()
  deep_eq(tokenise('a/b'), {
    tok(T.literal, 'a', 1),
    tok(T.slash, '/', 2),
    tok(T.literal, 'b', 3),
  })
end)

test('slash: multiple', function()
  deep_eq(tokenise('/api/v1'), {
    tok(T.slash, '/', 1),
    tok(T.literal, 'a', 2),
    tok(T.literal, 'p', 3),
    tok(T.literal, 'i', 4),
    tok(T.slash, '/', 5),
    tok(T.literal, 'v', 6),
    tok(T.literal, '1', 7),
  })
end)

--------------------------------------------------------------------------------
--- Anchors (^ and $) ----------------------------------------------------------
--------------------------------------------------------------------------------

test('anchor: caret at start', function()
  deep_eq(tokenise('^a'), {
    tok(T.anchor, '^', 1),
    tok(T.literal, 'a', 2),
  })
end)

test('anchor: dollar at end', function()
  deep_eq(tokenise('a$'), {
    tok(T.literal, 'a', 1),
    tok(T.anchor, '$', 2),
  })
end)

test('anchor: both', function()
  deep_eq(tokenise('^a$'), {
    tok(T.anchor, '^', 1),
    tok(T.literal, 'a', 2),
    tok(T.anchor, '$', 3),
  })
end)

test('anchor: caret in middle (still anchor token)', function()
  -- Tokeniser doesn't validate semantics; parser will handle
  deep_eq(tokenise('a^b'), {
    tok(T.literal, 'a', 1),
    tok(T.anchor, '^', 2),
    tok(T.literal, 'b', 3),
  })
end)

--------------------------------------------------------------------------------
--- Dot (any character) --------------------------------------------------------
--------------------------------------------------------------------------------

test('dot: single', function()
  deep_eq(tokenise('.'), {
    tok(T.literal, '.', 1),
  })
end)

test('dot: in pattern', function()
  deep_eq(tokenise('a.b'), {
    tok(T.literal, 'a', 1),
    tok(T.literal, '.', 2),
    tok(T.literal, 'b', 3),
  })
end)

--------------------------------------------------------------------------------
--- Alternation ----------------------------------------------------------------
--------------------------------------------------------------------------------

test('alternation: simple', function()
  deep_eq(tokenise('a|b'), {
    tok(T.literal, 'a', 1),
    tok(T.alternation, '|', 2),
    tok(T.literal, 'b', 3),
  })
end)

test('alternation: multiple', function()
  deep_eq(tokenise('a|b|c'), {
    tok(T.literal, 'a', 1),
    tok(T.alternation, '|', 2),
    tok(T.literal, 'b', 3),
    tok(T.alternation, '|', 4),
    tok(T.literal, 'c', 5),
  })
end)

--------------------------------------------------------------------------------
--- Escape sequences (simple) --------------------------------------------------
--------------------------------------------------------------------------------

test('escape: word shorthand \\w', function()
  deep_eq(tokenise('\\w'), {
    tok(T.escape, '\\w', 1),
  })
end)

test('escape: digit shorthand \\d', function()
  deep_eq(tokenise('\\d'), {
    tok(T.escape, '\\d', 1),
  })
end)

test('escape: whitespace shorthand \\s', function()
  deep_eq(tokenise('\\s'), {
    tok(T.escape, '\\s', 1),
  })
end)

test('escape: non-word shorthand \\W', function()
  deep_eq(tokenise('\\W'), {
    tok(T.escape, '\\W', 1),
  })
end)

test('escape: non-digit shorthand \\D', function()
  deep_eq(tokenise('\\D'), {
    tok(T.escape, '\\D', 1),
  })
end)

test('escape: non-whitespace shorthand \\S', function()
  deep_eq(tokenise('\\S'), {
    tok(T.escape, '\\S', 1),
  })
end)

test('escape: tab \\t', function()
  deep_eq(tokenise('\\t'), {
    tok(T.escape, '\\t', 1),
  })
end)

test('escape: newline \\n', function()
  deep_eq(tokenise('\\n'), {
    tok(T.escape, '\\n', 1),
  })
end)

test('escape: carriage return \\r', function()
  deep_eq(tokenise('\\r'), {
    tok(T.escape, '\\r', 1),
  })
end)

test('escape: word boundary \\b', function()
  deep_eq(tokenise('\\b'), {
    tok(T.escape, '\\b', 1),
  })
end)

test('escape: non-word boundary \\B', function()
  deep_eq(tokenise('\\B'), {
    tok(T.escape, '\\B', 1),
  })
end)

test('escape: start anchor \\A', function()
  deep_eq(tokenise('\\A'), {
    tok(T.escape, '\\A', 1),
  })
end)

test('escape: end anchor \\z', function()
  deep_eq(tokenise('\\z'), {
    tok(T.escape, '\\z', 1),
  })
end)

--------------------------------------------------------------------------------
--- Escaped metacharacters (literal in both engines) ---------------------------
--------------------------------------------------------------------------------

test('escape: escaped dot', function()
  deep_eq(tokenise('\\.'), {
    tok(T.escape, '\\.', 1),
  })
end)

test('escape: escaped star', function()
  deep_eq(tokenise('\\*'), {
    tok(T.escape, '\\*', 1),
  })
end)

test('escape: escaped plus', function()
  deep_eq(tokenise('\\+'), {
    tok(T.escape, '\\+', 1),
  })
end)

test('escape: escaped question', function()
  deep_eq(tokenise('\\?'), {
    tok(T.escape, '\\?', 1),
  })
end)

test('escape: escaped open paren', function()
  deep_eq(tokenise('\\('), {
    tok(T.escape, '\\(', 1),
  })
end)

test('escape: escaped close paren', function()
  deep_eq(tokenise('\\)'), {
    tok(T.escape, '\\)', 1),
  })
end)

test('escape: escaped open bracket', function()
  deep_eq(tokenise('\\['), {
    tok(T.escape, '\\[', 1),
  })
end)

test('escape: escaped close bracket', function()
  deep_eq(tokenise('\\]'), {
    tok(T.escape, '\\]', 1),
  })
end)

test('escape: escaped open brace', function()
  deep_eq(tokenise('\\{'), {
    tok(T.escape, '\\{', 1),
  })
end)

test('escape: escaped close brace', function()
  deep_eq(tokenise('\\}'), {
    tok(T.escape, '\\}', 1),
  })
end)

test('escape: escaped pipe', function()
  deep_eq(tokenise('\\|'), {
    tok(T.escape, '\\|', 1),
  })
end)

test('escape: escaped caret', function()
  deep_eq(tokenise('\\^'), {
    tok(T.escape, '\\^', 1),
  })
end)

test('escape: escaped dollar', function()
  deep_eq(tokenise('\\$'), {
    tok(T.escape, '\\$', 1),
  })
end)

test('escape: escaped backslash', function()
  deep_eq(tokenise('\\\\'), {
    tok(T.escape, '\\\\', 1),
  })
end)

test('escape: escaped forward slash', function()
  deep_eq(tokenise('\\/'), {
    tok(T.escape, '\\/', 1),
  })
end)

--------------------------------------------------------------------------------
--- Escape sequences: backreferences -------------------------------------------
--------------------------------------------------------------------------------

test('escape: backreference \\1', function()
  deep_eq(tokenise('\\1'), {
    tok(T.escape, '\\1', 1),
  })
end)

test('escape: backreference \\9', function()
  deep_eq(tokenise('\\9'), {
    tok(T.escape, '\\9', 1),
  })
end)

test('escape: \\0 is not a backreference', function()
  -- \0 is typically NUL byte, not a backreference
  deep_eq(tokenise('\\0'), {
    tok(T.escape, '\\0', 1),
  })
end)

--------------------------------------------------------------------------------
--- Escape sequences: unicode properties ---------------------------------------
--------------------------------------------------------------------------------

test('escape: unicode property \\p{L}', function()
  deep_eq(tokenise('\\p{L}'), {
    tok(T.escape, '\\p{L}', 1),
  })
end)

test('escape: negated unicode property \\P{L}', function()
  deep_eq(tokenise('\\P{L}'), {
    tok(T.escape, '\\P{L}', 1),
  })
end)

test('escape: unicode property with long name', function()
  deep_eq(tokenise('\\p{Letter}'), {
    tok(T.escape, '\\p{Letter}', 1),
  })
end)

test('escape: unicode property with script', function()
  deep_eq(tokenise('\\p{Greek}'), {
    tok(T.escape, '\\p{Greek}', 1),
  })
end)

test('escape: unicode property in pattern', function()
  deep_eq(tokenise('a\\p{L}b'), {
    tok(T.literal, 'a', 1),
    tok(T.escape, '\\p{L}', 2),
    tok(T.literal, 'b', 7),
  })
end)

--------------------------------------------------------------------------------
--- Quantifiers: greedy --------------------------------------------------------
--------------------------------------------------------------------------------

test('quantifier: star (greedy)', function()
  deep_eq(tokenise('a*'), {
    tok(T.literal, 'a', 1),
    tok(T.quantifier, '*', 2, { greedy = true }),
  })
end)

test('quantifier: plus (greedy)', function()
  deep_eq(tokenise('a+'), {
    tok(T.literal, 'a', 1),
    tok(T.quantifier, '+', 2, { greedy = true }),
  })
end)

test('quantifier: question (greedy)', function()
  deep_eq(tokenise('a?'), {
    tok(T.literal, 'a', 1),
    tok(T.quantifier, '?', 2, { greedy = true }),
  })
end)

test('quantifier: brace exact {3}', function()
  deep_eq(tokenise('a{3}'), {
    tok(T.literal, 'a', 1),
    tok(T.quantifier, '{3}', 2, { greedy = true }),
  })
end)

test('quantifier: brace min {3,}', function()
  deep_eq(tokenise('a{3,}'), {
    tok(T.literal, 'a', 1),
    tok(T.quantifier, '{3,}', 2, { greedy = true }),
  })
end)

test('quantifier: brace range {3,5}', function()
  deep_eq(tokenise('a{3,5}'), {
    tok(T.literal, 'a', 1),
    tok(T.quantifier, '{3,5}', 2, { greedy = true }),
  })
end)

test('quantifier: brace {0,1} equivalent to ?', function()
  deep_eq(tokenise('a{0,1}'), {
    tok(T.literal, 'a', 1),
    tok(T.quantifier, '{0,1}', 2, { greedy = true }),
  })
end)

--------------------------------------------------------------------------------
--- Quantifiers: non-greedy ----------------------------------------------------
--------------------------------------------------------------------------------

test('quantifier: star non-greedy *?', function()
  deep_eq(tokenise('a*?'), {
    tok(T.literal, 'a', 1),
    tok(T.quantifier, '*?', 2, { greedy = false }),
  })
end)

test('quantifier: plus non-greedy +?', function()
  deep_eq(tokenise('a+?'), {
    tok(T.literal, 'a', 1),
    tok(T.quantifier, '+?', 2, { greedy = false }),
  })
end)

test('quantifier: question non-greedy ??', function()
  deep_eq(tokenise('a??'), {
    tok(T.literal, 'a', 1),
    tok(T.quantifier, '??', 2, { greedy = false }),
  })
end)

test('quantifier: brace exact non-greedy {3}?', function()
  deep_eq(tokenise('a{3}?'), {
    tok(T.literal, 'a', 1),
    tok(T.quantifier, '{3}?', 2, { greedy = false }),
  })
end)

test('quantifier: brace min non-greedy {3,}?', function()
  deep_eq(tokenise('a{3,}?'), {
    tok(T.literal, 'a', 1),
    tok(T.quantifier, '{3,}?', 2, { greedy = false }),
  })
end)

test('quantifier: brace range non-greedy {3,5}?', function()
  deep_eq(tokenise('a{3,5}?'), {
    tok(T.literal, 'a', 1),
    tok(T.quantifier, '{3,5}?', 2, { greedy = false }),
  })
end)

--------------------------------------------------------------------------------
--- Quantifiers: possessive (tokenised, parser will reject) --------------------
--------------------------------------------------------------------------------

test('quantifier: star possessive *+', function()
  deep_eq(tokenise('a*+'), {
    tok(T.literal, 'a', 1),
    tok(T.quantifier, '*+', 2, { greedy = true, possessive = true }),
  })
end)

test('quantifier: plus possessive ++', function()
  deep_eq(tokenise('a++'), {
    tok(T.literal, 'a', 1),
    tok(T.quantifier, '++', 2, { greedy = true, possessive = true }),
  })
end)

test('quantifier: question possessive ?+', function()
  deep_eq(tokenise('a?+'), {
    tok(T.literal, 'a', 1),
    tok(T.quantifier, '?+', 2, { greedy = true, possessive = true }),
  })
end)

--------------------------------------------------------------------------------
--- Quantifiers: edge cases ----------------------------------------------------
--------------------------------------------------------------------------------

test('quantifier: ? at start is literal', function()
  -- A ? at the very start has nothing to quantify; treat as literal
  deep_eq(tokenise('?a'), {
    tok(T.literal, '?', 1),
    tok(T.literal, 'a', 2),
  })
end)

test('quantifier: * at start is literal', function()
  deep_eq(tokenise('*a'), {
    tok(T.literal, '*', 1),
    tok(T.literal, 'a', 2),
  })
end)

test('quantifier: + at start is literal', function()
  deep_eq(tokenise('+a'), {
    tok(T.literal, '+', 1),
    tok(T.literal, 'a', 2),
  })
end)

test('quantifier: consecutive quantifiers (first quantifies, rest literal)', function()
  -- a*+ should be star then possessive marker, already tested
  -- a** is star then literal star (nothing to quantify)
  deep_eq(tokenise('a**'), {
    tok(T.literal, 'a', 1),
    tok(T.quantifier, '*', 2, { greedy = true }),
    tok(T.literal, '*', 3),
  })
end)

test('quantifier: dot star', function()
  deep_eq(tokenise('.*'), {
    tok(T.literal, '.', 1),
    tok(T.quantifier, '*', 2, { greedy = true }),
  })
end)

test('quantifier: dot star non-greedy', function()
  deep_eq(tokenise('.*?'), {
    tok(T.literal, '.', 1),
    tok(T.quantifier, '*?', 2, { greedy = false }),
  })
end)

--------------------------------------------------------------------------------
--- Groups: capturing ----------------------------------------------------------
--------------------------------------------------------------------------------

test('group: simple capturing', function()
  deep_eq(tokenise('(a)'), {
    tok(T.group_open, '(', 1, { kind = GK.capturing }),
    tok(T.literal, 'a', 2),
    tok(T.group_close, ')', 3),
  })
end)

test('group: nested capturing', function()
  deep_eq(tokenise('((a))'), {
    tok(T.group_open, '(', 1, { kind = GK.capturing }),
    tok(T.group_open, '(', 2, { kind = GK.capturing }),
    tok(T.literal, 'a', 3),
    tok(T.group_close, ')', 4),
    tok(T.group_close, ')', 5),
  })
end)

test('group: with alternation', function()
  deep_eq(tokenise('(a|b)'), {
    tok(T.group_open, '(', 1, { kind = GK.capturing }),
    tok(T.literal, 'a', 2),
    tok(T.alternation, '|', 3),
    tok(T.literal, 'b', 4),
    tok(T.group_close, ')', 5),
  })
end)

test('group: with quantifier', function()
  deep_eq(tokenise('(ab)+'), {
    tok(T.group_open, '(', 1, { kind = GK.capturing }),
    tok(T.literal, 'a', 2),
    tok(T.literal, 'b', 3),
    tok(T.group_close, ')', 4),
    tok(T.quantifier, '+', 5, { greedy = true }),
  })
end)

--------------------------------------------------------------------------------
--- Groups: non-capturing ------------------------------------------------------
--------------------------------------------------------------------------------

test('group: non-capturing', function()
  deep_eq(tokenise('(?:a)'), {
    tok(T.group_open, '(?:', 1, { kind = GK.non_capturing }),
    tok(T.literal, 'a', 4),
    tok(T.group_close, ')', 5),
  })
end)

test('group: non-capturing with alternation', function()
  deep_eq(tokenise('(?:a|b)'), {
    tok(T.group_open, '(?:', 1, { kind = GK.non_capturing }),
    tok(T.literal, 'a', 4),
    tok(T.alternation, '|', 5),
    tok(T.literal, 'b', 6),
    tok(T.group_close, ')', 7),
  })
end)

test('group: non-capturing with quantifier', function()
  deep_eq(tokenise('(?:ab)+?'), {
    tok(T.group_open, '(?:', 1, { kind = GK.non_capturing }),
    tok(T.literal, 'a', 4),
    tok(T.literal, 'b', 5),
    tok(T.group_close, ')', 6),
    tok(T.quantifier, '+?', 7, { greedy = false }),
  })
end)

--------------------------------------------------------------------------------
--- Groups: named (Python style) -----------------------------------------------
--------------------------------------------------------------------------------

test('group: named Python style', function()
  deep_eq(tokenise('(?P<name>a)'), {
    tok(T.group_open, '(?P<name>', 1, { kind = GK.named_python, name = 'name' }),
    tok(T.literal, 'a', 10),
    tok(T.group_close, ')', 11),
  })
end)

test('group: named Python style with underscore', function()
  deep_eq(tokenise('(?P<user_id>a)'), {
    tok(T.group_open, '(?P<user_id>', 1, { kind = GK.named_python, name = 'user_id' }),
    tok(T.literal, 'a', 13),
    tok(T.group_close, ')', 14),
  })
end)

test('group: named Python style with digits', function()
  deep_eq(tokenise('(?P<item01>a)'), {
    tok(T.group_open, '(?P<item01>', 1, { kind = GK.named_python, name = 'item01' }),
    tok(T.literal, 'a', 12),
    tok(T.group_close, ')', 13),
  })
end)

--------------------------------------------------------------------------------
--- Groups: named (PCRE style) -------------------------------------------------
--------------------------------------------------------------------------------

test('group: named PCRE style', function()
  deep_eq(tokenise('(?<name>a)'), {
    tok(T.group_open, '(?<name>', 1, { kind = GK.named_pcre, name = 'name' }),
    tok(T.literal, 'a', 9),
    tok(T.group_close, ')', 10),
  })
end)

test('group: named PCRE style with underscore', function()
  deep_eq(tokenise('(?<user_id>a)'), {
    tok(T.group_open, '(?<user_id>', 1, { kind = GK.named_pcre, name = 'user_id' }),
    tok(T.literal, 'a', 12),
    tok(T.group_close, ')', 13),
  })
end)

--------------------------------------------------------------------------------
--- Groups: lookarounds (tokenised, parser will reject) ------------------------
--------------------------------------------------------------------------------

test('group: positive lookahead', function()
  deep_eq(tokenise('(?=a)'), {
    tok(T.group_open, '(?=', 1, { kind = GK.lookahead_pos }),
    tok(T.literal, 'a', 4),
    tok(T.group_close, ')', 5),
  })
end)

test('group: negative lookahead', function()
  deep_eq(tokenise('(?!a)'), {
    tok(T.group_open, '(?!', 1, { kind = GK.lookahead_neg }),
    tok(T.literal, 'a', 4),
    tok(T.group_close, ')', 5),
  })
end)

test('group: positive lookbehind', function()
  deep_eq(tokenise('(?<=a)'), {
    tok(T.group_open, '(?<=', 1, { kind = GK.lookbehind_pos }),
    tok(T.literal, 'a', 5),
    tok(T.group_close, ')', 6),
  })
end)

test('group: negative lookbehind', function()
  deep_eq(tokenise('(?<!a)'), {
    tok(T.group_open, '(?<!', 1, { kind = GK.lookbehind_neg }),
    tok(T.literal, 'a', 5),
    tok(T.group_close, ')', 6),
  })
end)

--------------------------------------------------------------------------------
--- Groups: atomic (tokenised, parser will reject) -----------------------------
--------------------------------------------------------------------------------

test('group: atomic', function()
  deep_eq(tokenise('(?>a)'), {
    tok(T.group_open, '(?>', 1, { kind = GK.atomic }),
    tok(T.literal, 'a', 4),
    tok(T.group_close, ')', 5),
  })
end)

--------------------------------------------------------------------------------
--- Groups: edge cases ---------------------------------------------------------
--------------------------------------------------------------------------------

test('group: unclosed group (tokens up to end)', function()
  deep_eq(tokenise('(a'), {
    tok(T.group_open, '(', 1, { kind = GK.capturing }),
    tok(T.literal, 'a', 2),
  })
end)

test('group: unmatched close paren', function()
  deep_eq(tokenise('a)'), {
    tok(T.literal, 'a', 1),
    tok(T.group_close, ')', 2),
  })
end)

test('group: named with empty name (still tokenised)', function()
  -- Parser will validate and reject; tokeniser just captures what's there
  deep_eq(tokenise('(?P<>a)'), {
    tok(T.group_open, '(?P<>', 1, { kind = GK.named_python, name = '' }),
    tok(T.literal, 'a', 6),
    tok(T.group_close, ')', 7),
  })
end)

test('group: named without closing > (best effort)', function()
  -- Tokeniser should handle gracefully
  deep_eq(tokenise('(?P<namea)'), {
    tok(T.group_open, '(?P<namea)', 1, { kind = GK.named_python, name = 'namea)' }),
    -- Note: the tokeniser will consume until it finds > or end of string
    -- Exact behaviour may vary; test documents expected handling
  })
end)

--------------------------------------------------------------------------------
--- Character classes: basic ---------------------------------------------------
--------------------------------------------------------------------------------

test('class: simple', function()
  deep_eq(tokenise('[abc]'), {
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_literal, 'a', 2),
    tok(CC.cc_literal, 'b', 3),
    tok(CC.cc_literal, 'c', 4),
    tok(T.char_class_close, ']', 5),
  })
end)

test('class: negated', function()
  deep_eq(tokenise('[^abc]'), {
    tok(T.char_class_open, '[^', 1, { negated = true }),
    tok(CC.cc_literal, 'a', 3),
    tok(CC.cc_literal, 'b', 4),
    tok(CC.cc_literal, 'c', 5),
    tok(T.char_class_close, ']', 6),
  })
end)

test('class: single character', function()
  deep_eq(tokenise('[a]'), {
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_literal, 'a', 2),
    tok(T.char_class_close, ']', 3),
  })
end)

--------------------------------------------------------------------------------
--- Character classes: ranges --------------------------------------------------
--------------------------------------------------------------------------------

test('class: lowercase range', function()
  deep_eq(tokenise('[a-z]'), {
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_range, 'a-z', 2, { from = 'a', to = 'z' }),
    tok(T.char_class_close, ']', 5),
  })
end)

test('class: uppercase range', function()
  deep_eq(tokenise('[A-Z]'), {
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_range, 'A-Z', 2, { from = 'A', to = 'Z' }),
    tok(T.char_class_close, ']', 5),
  })
end)

test('class: digit range', function()
  deep_eq(tokenise('[0-9]'), {
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_range, '0-9', 2, { from = '0', to = '9' }),
    tok(T.char_class_close, ']', 5),
  })
end)

test('class: multiple ranges', function()
  deep_eq(tokenise('[a-zA-Z0-9]'), {
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_range, 'a-z', 2, { from = 'a', to = 'z' }),
    tok(CC.cc_range, 'A-Z', 5, { from = 'A', to = 'Z' }),
    tok(CC.cc_range, '0-9', 8, { from = '0', to = '9' }),
    tok(T.char_class_close, ']', 11),
  })
end)

test('class: range with underscore', function()
  deep_eq(tokenise('[a-z_]'), {
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_range, 'a-z', 2, { from = 'a', to = 'z' }),
    tok(CC.cc_literal, '_', 5),
    tok(T.char_class_close, ']', 6),
  })
end)

--------------------------------------------------------------------------------
--- Character classes: literal ] at start -------------------------------------
--------------------------------------------------------------------------------

test('class: ] as first char is literal', function()
  deep_eq(tokenise('[]a]'), {
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_literal, ']', 2),
    tok(CC.cc_literal, 'a', 3),
    tok(T.char_class_close, ']', 4),
  })
end)

test('class: ] as first char in negated class', function()
  deep_eq(tokenise('[^]a]'), {
    tok(T.char_class_open, '[^', 1, { negated = true }),
    tok(CC.cc_literal, ']', 3),
    tok(CC.cc_literal, 'a', 4),
    tok(T.char_class_close, ']', 5),
  })
end)

test('class: ] only', function()
  deep_eq(tokenise('[]]'), {
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_literal, ']', 2),
    tok(T.char_class_close, ']', 3),
  })
end)

--------------------------------------------------------------------------------
--- Character classes: literal - positioning -----------------------------------
--------------------------------------------------------------------------------

test('class: - at start is literal', function()
  deep_eq(tokenise('[-a]'), {
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_literal, '-', 2),
    tok(CC.cc_literal, 'a', 3),
    tok(T.char_class_close, ']', 4),
  })
end)

test('class: - at end is literal', function()
  deep_eq(tokenise('[a-]'), {
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_literal, 'a', 2),
    tok(CC.cc_literal, '-', 3),
    tok(T.char_class_close, ']', 4),
  })
end)

test('class: range then literal -', function()
  deep_eq(tokenise('[a-z-]'), {
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_range, 'a-z', 2, { from = 'a', to = 'z' }),
    tok(CC.cc_literal, '-', 5),
    tok(T.char_class_close, ']', 6),
  })
end)

test('class: - at start of negated', function()
  deep_eq(tokenise('[^-a]'), {
    tok(T.char_class_open, '[^', 1, { negated = true }),
    tok(CC.cc_literal, '-', 3),
    tok(CC.cc_literal, 'a', 4),
    tok(T.char_class_close, ']', 5),
  })
end)

--------------------------------------------------------------------------------
--- Character classes: escapes inside ------------------------------------------
--------------------------------------------------------------------------------

test('class: escaped ]', function()
  deep_eq(tokenise('[\\]]'), {
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_escape, '\\]', 2),
    tok(T.char_class_close, ']', 4),
  })
end)

test('class: escaped backslash', function()
  deep_eq(tokenise('[\\\\]'), {
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_escape, '\\\\', 2),
    tok(T.char_class_close, ']', 4),
  })
end)

test('class: escaped caret', function()
  deep_eq(tokenise('[\\^]'), {
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_escape, '\\^', 2),
    tok(T.char_class_close, ']', 4),
  })
end)

test('class: escaped hyphen', function()
  deep_eq(tokenise('[\\-]'), {
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_escape, '\\-', 2),
    tok(T.char_class_close, ']', 4),
  })
end)

test('class: shorthand \\w inside', function()
  deep_eq(tokenise('[\\w]'), {
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_escape, '\\w', 2),
    tok(T.char_class_close, ']', 4),
  })
end)

test('class: shorthand \\d inside', function()
  deep_eq(tokenise('[\\d]'), {
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_escape, '\\d', 2),
    tok(T.char_class_close, ']', 4),
  })
end)

test('class: shorthand \\s inside', function()
  deep_eq(tokenise('[\\s]'), {
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_escape, '\\s', 2),
    tok(T.char_class_close, ']', 4),
  })
end)

test('class: multiple shorthands', function()
  deep_eq(tokenise('[\\d\\w]'), {
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_escape, '\\d', 2),
    tok(CC.cc_escape, '\\w', 4),
    tok(T.char_class_close, ']', 6),
  })
end)

--------------------------------------------------------------------------------
--- Character classes: metacharacters literal inside ---------------------------
--------------------------------------------------------------------------------

test('class: quantifiers literal inside', function()
  deep_eq(tokenise('[+*?]'), {
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_literal, '+', 2),
    tok(CC.cc_literal, '*', 3),
    tok(CC.cc_literal, '?', 4),
    tok(T.char_class_close, ']', 5),
  })
end)

test('class: parens literal inside', function()
  deep_eq(tokenise('[()]'), {
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_literal, '(', 2),
    tok(CC.cc_literal, ')', 3),
    tok(T.char_class_close, ']', 4),
  })
end)

test('class: braces literal inside', function()
  deep_eq(tokenise('[{}]'), {
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_literal, '{', 2),
    tok(CC.cc_literal, '}', 3),
    tok(T.char_class_close, ']', 4),
  })
end)

test('class: pipe literal inside', function()
  deep_eq(tokenise('[|]'), {
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_literal, '|', 2),
    tok(T.char_class_close, ']', 3),
  })
end)

test('class: dot literal inside', function()
  deep_eq(tokenise('[.]'), {
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_literal, '.', 2),
    tok(T.char_class_close, ']', 3),
  })
end)

test('class: caret not at start is literal', function()
  deep_eq(tokenise('[a^]'), {
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_literal, 'a', 2),
    tok(CC.cc_literal, '^', 3),
    tok(T.char_class_close, ']', 4),
  })
end)

test('class: dollar literal inside', function()
  deep_eq(tokenise('[$]'), {
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_literal, '$', 2),
    tok(T.char_class_close, ']', 3),
  })
end)

--------------------------------------------------------------------------------
--- Character classes: Vim-special chars inside (no escape needed) -------------
--------------------------------------------------------------------------------

test('class: tilde and equals inside', function()
  deep_eq(tokenise('[~=]'), {
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_literal, '~', 2),
    tok(CC.cc_literal, '=', 3),
    tok(T.char_class_close, ']', 4),
  })
end)

test('class: angle brackets inside', function()
  deep_eq(tokenise('[<>]'), {
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_literal, '<', 2),
    tok(CC.cc_literal, '>', 3),
    tok(T.char_class_close, ']', 4),
  })
end)

test('class: at and ampersand inside', function()
  deep_eq(tokenise('[@&]'), {
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_literal, '@', 2),
    tok(CC.cc_literal, '&', 3),
    tok(T.char_class_close, ']', 4),
  })
end)

--------------------------------------------------------------------------------
--- Character classes: slash inside --------------------------------------------
--------------------------------------------------------------------------------

test('class: slash inside', function()
  deep_eq(tokenise('[/]'), {
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_literal, '/', 2),
    tok(T.char_class_close, ']', 3),
  })
end)

--------------------------------------------------------------------------------
--- Character classes: edge cases ----------------------------------------------
--------------------------------------------------------------------------------

test('class: unclosed bracket', function()
  deep_eq(tokenise('[abc'), {
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_literal, 'a', 2),
    tok(CC.cc_literal, 'b', 3),
    tok(CC.cc_literal, 'c', 4),
    -- No close token; tokeniser handles gracefully
  })
end)

test('class: empty class []', function()
  -- This is actually ] as first char making it literal
  deep_eq(tokenise('[]'), {
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_literal, ']', 2),
    -- Unclosed
  })
end)

test('class: \\] followed by actual closer', function()
  -- [\\]] is [ then \\ then ] (closer)
  deep_eq(tokenise('[\\\\]'), {
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_escape, '\\\\', 2),
    tok(T.char_class_close, ']', 4),
  })
end)

test('class: with quantifier after', function()
  deep_eq(tokenise('[a-z]+'), {
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_range, 'a-z', 2, { from = 'a', to = 'z' }),
    tok(T.char_class_close, ']', 5),
    tok(T.quantifier, '+', 6, { greedy = true }),
  })
end)

test('class: multiple classes in pattern', function()
  deep_eq(tokenise('[a][b]'), {
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_literal, 'a', 2),
    tok(T.char_class_close, ']', 3),
    tok(T.char_class_open, '[', 4, { negated = false }),
    tok(CC.cc_literal, 'b', 5),
    tok(T.char_class_close, ']', 6),
  })
end)

--------------------------------------------------------------------------------
--- Complex patterns -----------------------------------------------------------
--------------------------------------------------------------------------------

test('complex: function call pattern', function()
  deep_eq(tokenise('\\w+(.*)'), {
    tok(T.escape, '\\w', 1),
    tok(T.quantifier, '+', 3, { greedy = true }),
    tok(T.group_open, '(', 4, { kind = GK.capturing }),
    tok(T.literal, '.', 5),
    tok(T.quantifier, '*', 6, { greedy = true }),
    tok(T.group_close, ')', 7),
  })
end)

test('complex: email-like pattern', function()
  deep_eq(tokenise('[a-z]+@[a-z]+'), {
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_range, 'a-z', 2, { from = 'a', to = 'z' }),
    tok(T.char_class_close, ']', 5),
    tok(T.quantifier, '+', 6, { greedy = true }),
    tok(T.literal, '@', 7),
    tok(T.char_class_open, '[', 8, { negated = false }),
    tok(CC.cc_range, 'a-z', 9, { from = 'a', to = 'z' }),
    tok(T.char_class_close, ']', 12),
    tok(T.quantifier, '+', 13, { greedy = true }),
  })
end)

test('complex: URL path', function()
  deep_eq(tokenise('/api/v[0-9]+'), {
    tok(T.slash, '/', 1),
    tok(T.literal, 'a', 2),
    tok(T.literal, 'p', 3),
    tok(T.literal, 'i', 4),
    tok(T.slash, '/', 5),
    tok(T.literal, 'v', 6),
    tok(T.char_class_open, '[', 7, { negated = false }),
    tok(CC.cc_range, '0-9', 8, { from = '0', to = '9' }),
    tok(T.char_class_close, ']', 11),
    tok(T.quantifier, '+', 12, { greedy = true }),
  })
end)

test('complex: word boundary pattern', function()
  deep_eq(tokenise('\\bword\\b'), {
    tok(T.escape, '\\b', 1),
    tok(T.literal, 'w', 3),
    tok(T.literal, 'o', 4),
    tok(T.literal, 'r', 5),
    tok(T.literal, 'd', 6),
    tok(T.escape, '\\b', 7),
  })
end)

test('complex: non-greedy HTML tag', function()
  deep_eq(tokenise('<.*?>'), {
    tok(T.literal, '<', 1),
    tok(T.literal, '.', 2),
    tok(T.quantifier, '*?', 3, { greedy = false }),
    tok(T.literal, '>', 5),
  })
end)

test('complex: quoted string non-greedy', function()
  deep_eq(tokenise('".*?"'), {
    tok(T.literal, '"', 1),
    tok(T.literal, '.', 2),
    tok(T.quantifier, '*?', 3, { greedy = false }),
    tok(T.literal, '"', 5),
  })
end)

test('complex: alternation with groups', function()
  deep_eq(tokenise('(foo|bar)'), {
    tok(T.group_open, '(', 1, { kind = GK.capturing }),
    tok(T.literal, 'f', 2),
    tok(T.literal, 'o', 3),
    tok(T.literal, 'o', 4),
    tok(T.alternation, '|', 5),
    tok(T.literal, 'b', 6),
    tok(T.literal, 'a', 7),
    tok(T.literal, 'r', 8),
    tok(T.group_close, ')', 9),
  })
end)

test('complex: Lua nil check', function()
  deep_eq(tokenise('[~=]= nil'), {
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_literal, '~', 2),
    tok(CC.cc_literal, '=', 3),
    tok(T.char_class_close, ']', 4),
    tok(T.literal, '=', 5),
    tok(T.literal, ' ', 6),
    tok(T.literal, 'n', 7),
    tok(T.literal, 'i', 8),
    tok(T.literal, 'l', 9),
  })
end)

test('complex: password pattern', function()
  deep_eq(tokenise([[\.password-.+?("|')\)]]), {
    tok(T.escape, '\\.', 1),
    tok(T.literal, 'p', 3),
    tok(T.literal, 'a', 4),
    tok(T.literal, 's', 5),
    tok(T.literal, 's', 6),
    tok(T.literal, 'w', 7),
    tok(T.literal, 'o', 8),
    tok(T.literal, 'r', 9),
    tok(T.literal, 'd', 10),
    tok(T.literal, '-', 11),
    tok(T.literal, '.', 12),
    tok(T.quantifier, '+?', 13, { greedy = false }),
    tok(T.group_open, '(', 15, { kind = GK.capturing }),
    tok(T.literal, '"', 16),
    tok(T.alternation, '|', 17),
    tok(T.literal, "'", 18),
    tok(T.group_close, ')', 19),
    tok(T.escape, '\\)', 20),
  })
end)

--------------------------------------------------------------------------------
--- Edge cases -----------------------------------------------------------------
--------------------------------------------------------------------------------

test('edge: single backslash at end', function()
  -- Malformed but should handle gracefully
  deep_eq(tokenise('a\\'), {
    tok(T.literal, 'a', 1),
    tok(T.escape, '\\', 2), -- or could be literal; document behaviour
  })
end)

test('edge: only metacharacters', function()
  deep_eq(tokenise('+?|'), {
    tok(T.literal, '+', 1),
    tok(T.literal, '?', 2),
    tok(T.alternation, '|', 3),
  })
end)

test('edge: consecutive escapes', function()
  deep_eq(tokenise('\\\\\\d'), {
    tok(T.escape, '\\\\', 1),
    tok(T.escape, '\\d', 3),
  })
end)

test('edge: space characters', function()
  deep_eq(tokenise('a b'), {
    tok(T.literal, 'a', 1),
    tok(T.literal, ' ', 2),
    tok(T.literal, 'b', 3),
  })
end)

test('edge: tab character', function()
  deep_eq(tokenise('a\tb'), {
    tok(T.literal, 'a', 1),
    tok(T.literal, '\t', 2),
    tok(T.literal, 'b', 3),
  })
end)

--------------------------------------------------------------------------------
--- Position tracking ----------------------------------------------------------
--------------------------------------------------------------------------------

test('position: simple pattern', function()
  local tokens = tokenise('abc')
  h.eq(tokens[1].pos, 1)
  h.eq(tokens[2].pos, 2)
  h.eq(tokens[3].pos, 3)
end)

test('position: escape sequence', function()
  local tokens = tokenise('a\\wb')
  h.eq(tokens[1].pos, 1) -- a
  h.eq(tokens[2].pos, 2) -- \w
  h.eq(tokens[3].pos, 4) -- b
end)

test('position: character class', function()
  local tokens = tokenise('[a-z]b')
  h.eq(tokens[1].pos, 1) -- [
  h.eq(tokens[2].pos, 2) -- a-z
  h.eq(tokens[3].pos, 5) -- ]
  h.eq(tokens[4].pos, 6) -- b
end)

test('position: group', function()
  local tokens = tokenise('(?:a)')
  h.eq(tokens[1].pos, 1) -- (?:
  h.eq(tokens[2].pos, 4) -- a
  h.eq(tokens[3].pos, 5) -- )
end)

test('position: unicode property', function()
  local tokens = tokenise('a\\p{L}b')
  h.eq(tokens[1].pos, 1) -- a
  h.eq(tokens[2].pos, 2) -- \p{L}
  h.eq(tokens[3].pos, 7) -- b
end)

--------------------------------------------------------------------------------
--- Summary --------------------------------------------------------------------
--------------------------------------------------------------------------------

h.summary()
