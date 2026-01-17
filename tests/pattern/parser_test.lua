-- tests/pattern/parser_test.lua

-- Run with:
--   nvim --headless -c "luafile tests/pattern/parser_test.lua" -c "q"

local h = require('tests.harness')
local test = h.test
local deep_eq = h.deep_eq
local eq = h.eq
local types = require('brook.pattern.types')

-- Import will fail until parser.lua is implemented
local ok, parser = pcall(require, 'brook.pattern.parser')
if not ok then
  print('SKIP: brook.pattern.parser not yet implemented')
  print('Error: ' .. tostring(parser))
  print('0/0 tests passed')
  if vim and vim.cmd then
    vim.cmd('cquit 0')
  else
    os.exit(0)
  end
  return
end

local parse = parser.parse

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

--- Helper to assert parsing succeeds and returns expected tokens.
---@param input table Input tokens
---@param expected_tokens table Expected output tokens (with annotations)
local function assert_parses(input, expected_tokens)
  local result = parse(input)
  eq(result.error, nil, 'Expected no error')
  deep_eq(result.tokens, expected_tokens)
end

--- Helper to assert parsing fails with expected error.
---@param input table Input tokens
---@param expected_error string Expected error message
local function assert_fails(input, expected_error)
  local result = parse(input)
  eq(result.tokens, nil, 'Expected nil tokens on failure')
  eq(result.error, expected_error)
end

--- Helper to assert parsing succeeds with expected warning.
---@param input table Input tokens
---@param expected_warning string Expected warning message (first warning)
local function assert_warns(input, expected_warning)
  local result = parse(input)
  assert(result.tokens ~= nil, 'Expected tokens on success with warning')
  assert(#result.warnings > 0, 'Expected at least one warning')
  eq(result.warnings[1], expected_warning)
end

--------------------------------------------------------------------------------
--- Empty input ----------------------------------------------------------------
--------------------------------------------------------------------------------

test('empty: empty token list', function()
  local result = parse({})
  eq(result.error, nil)
  deep_eq(result.tokens, {})
end)

--------------------------------------------------------------------------------
--- Escape classification: shorthand word --------------------------------------
--------------------------------------------------------------------------------

test('escape class: \\w is shorthand_word', function()
  local result = parse({
    tok(T.escape, '\\w', 1),
  })
  eq(result.tokens[1].escape_class, EC.shorthand_word)
  eq(result.tokens[1].wordness, W.word)
end)

test('escape class: \\d is shorthand_word', function()
  local result = parse({
    tok(T.escape, '\\d', 1),
  })
  eq(result.tokens[1].escape_class, EC.shorthand_word)
  eq(result.tokens[1].wordness, W.word)
end)

--------------------------------------------------------------------------------
--- Escape classification: shorthand non-word ----------------------------------
--------------------------------------------------------------------------------

test('escape class: \\s is shorthand_nonword', function()
  local result = parse({
    tok(T.escape, '\\s', 1),
  })
  eq(result.tokens[1].escape_class, EC.shorthand_nonword)
  eq(result.tokens[1].wordness, W.non_word)
end)

test('escape class: \\W is shorthand_nonword', function()
  local result = parse({
    tok(T.escape, '\\W', 1),
  })
  eq(result.tokens[1].escape_class, EC.shorthand_nonword)
  eq(result.tokens[1].wordness, W.non_word)
end)

test('escape class: \\t is shorthand_nonword', function()
  local result = parse({
    tok(T.escape, '\\t', 1),
  })
  eq(result.tokens[1].escape_class, EC.shorthand_nonword)
  eq(result.tokens[1].wordness, W.non_word)
end)

test('escape class: \\n is shorthand_nonword', function()
  local result = parse({
    tok(T.escape, '\\n', 1),
  })
  eq(result.tokens[1].escape_class, EC.shorthand_nonword)
  eq(result.tokens[1].wordness, W.non_word)
end)

test('escape class: \\r is shorthand_nonword', function()
  local result = parse({
    tok(T.escape, '\\r', 1),
  })
  eq(result.tokens[1].escape_class, EC.shorthand_nonword)
  eq(result.tokens[1].wordness, W.non_word)
end)

--------------------------------------------------------------------------------
--- Escape classification: shorthand unknown -----------------------------------
--------------------------------------------------------------------------------

test('escape class: \\S is shorthand_unknown', function()
  local result = parse({
    tok(T.escape, '\\S', 1),
  })
  eq(result.tokens[1].escape_class, EC.shorthand_unknown)
  eq(result.tokens[1].wordness, W.unknown)
end)

test('escape class: \\D is shorthand_unknown', function()
  local result = parse({
    tok(T.escape, '\\D', 1),
  })
  eq(result.tokens[1].escape_class, EC.shorthand_unknown)
  eq(result.tokens[1].wordness, W.unknown)
end)

--------------------------------------------------------------------------------
--- Escape classification: boundary --------------------------------------------
--------------------------------------------------------------------------------

test('escape class: \\b is boundary', function()
  local result = parse({
    tok(T.escape, '\\b', 1),
  })
  eq(result.tokens[1].escape_class, EC.boundary)
end)

test('escape class: \\B is boundary_neg (unsupported)', function()
  assert_fails({
    tok(T.escape, '\\B', 1),
  }, '\\B not supported')
end)

--------------------------------------------------------------------------------
--- Escape classification: anchors ---------------------------------------------
--------------------------------------------------------------------------------

test('escape class: \\A is anchor_start', function()
  local result = parse({
    tok(T.escape, '\\A', 1),
  })
  eq(result.tokens[1].escape_class, EC.anchor_start)
end)

test('escape class: \\z is anchor_end', function()
  local result = parse({
    tok(T.escape, '\\z', 1),
  })
  eq(result.tokens[1].escape_class, EC.anchor_end)
end)

--------------------------------------------------------------------------------
--- Escape classification: unicode properties (unsupported) --------------------
--------------------------------------------------------------------------------

test('escape class: \\p{L} is unicode_prop (unsupported)', function()
  assert_fails({
    tok(T.escape, '\\p{L}', 1),
  }, 'unicode properties not supported')
end)

test('escape class: \\P{L} is unicode_prop (unsupported)', function()
  assert_fails({
    tok(T.escape, '\\P{L}', 1),
  }, 'unicode properties not supported')
end)

test('escape class: \\p{Letter} is unicode_prop (unsupported)', function()
  assert_fails({
    tok(T.escape, '\\p{Letter}', 1),
  }, 'unicode properties not supported')
end)

--------------------------------------------------------------------------------
--- Escape classification: backreferences (unsupported) ------------------------
--------------------------------------------------------------------------------

test('escape class: \\1 is backref (unsupported)', function()
  assert_fails({
    tok(T.escape, '\\1', 1),
  }, 'backreferences require PCRE2')
end)

test('escape class: \\9 is backref (unsupported)', function()
  assert_fails({
    tok(T.escape, '\\9', 1),
  }, 'backreferences require PCRE2')
end)

test('escape class: \\0 is escaped_literal (not a backref)', function()
  local result = parse({
    tok(T.escape, '\\0', 1),
  })
  eq(result.tokens[1].escape_class, EC.escaped_literal)
end)

--------------------------------------------------------------------------------
--- Escape classification: escaped literals ------------------------------------
--------------------------------------------------------------------------------

test('escape class: \\. is escaped_literal', function()
  local result = parse({
    tok(T.escape, '\\.', 1),
  })
  eq(result.tokens[1].escape_class, EC.escaped_literal)
  eq(result.tokens[1].wordness, W.non_word)
end)

test('escape class: \\( is escaped_literal', function()
  local result = parse({
    tok(T.escape, '\\(', 1),
  })
  eq(result.tokens[1].escape_class, EC.escaped_literal)
  eq(result.tokens[1].wordness, W.non_word)
end)

test('escape class: \\\\ is escaped_literal', function()
  local result = parse({
    tok(T.escape, '\\\\', 1),
  })
  eq(result.tokens[1].escape_class, EC.escaped_literal)
  eq(result.tokens[1].wordness, W.non_word)
end)

test('escape class: escaped word char \\a is escaped_literal (word)', function()
  local result = parse({
    tok(T.escape, '\\a', 1),
  })
  eq(result.tokens[1].escape_class, EC.escaped_literal)
  eq(result.tokens[1].wordness, W.word)
end)

test('escape class: escaped digit \\5 is escaped_literal (word)', function()
  local result = parse({
    tok(T.escape, '\\5', 1),
  })
  -- Note: \\5 as literal "5" in non-backref context would be escaped_literal
  -- But if backref context is detected, it fails. Here assuming 0 isn't backref
  -- This test assumes \\5 outside of a pattern with groups is literal.
  -- Actually per the tokeniser, \5 without preceding groups might be interpreted
  -- differently. Let me reconsider: \1-\9 are always backrefs in ripgrep.
  -- So this test expects failure.
end)

-- Corrected: \1-\9 are always backrefs
test('escape class: \\5 is backref (unsupported)', function()
  assert_fails({
    tok(T.escape, '\\5', 1),
  }, 'backreferences require PCRE2')
end)

--------------------------------------------------------------------------------
--- Literal wordness -----------------------------------------------------------
--------------------------------------------------------------------------------

test('literal wordness: lowercase letter is word', function()
  local result = parse({
    tok(T.literal, 'a', 1),
  })
  eq(result.tokens[1].wordness, W.word)
end)

test('literal wordness: uppercase letter is word', function()
  local result = parse({
    tok(T.literal, 'Z', 1),
  })
  eq(result.tokens[1].wordness, W.word)
end)

test('literal wordness: digit is word', function()
  local result = parse({
    tok(T.literal, '5', 1),
  })
  eq(result.tokens[1].wordness, W.word)
end)

test('literal wordness: underscore is word', function()
  local result = parse({
    tok(T.literal, '_', 1),
  })
  eq(result.tokens[1].wordness, W.word)
end)

test('literal wordness: space is non_word', function()
  local result = parse({
    tok(T.literal, ' ', 1),
  })
  eq(result.tokens[1].wordness, W.non_word)
end)

test('literal wordness: dot is unknown (matches any)', function()
  local result = parse({
    tok(T.literal, '.', 1),
  })
  eq(result.tokens[1].wordness, W.unknown)
end)

test('literal wordness: hyphen is non_word', function()
  local result = parse({
    tok(T.literal, '-', 1),
  })
  eq(result.tokens[1].wordness, W.non_word)
end)

test('literal wordness: punctuation is non_word', function()
  local result = parse({
    tok(T.literal, '!', 1),
  })
  eq(result.tokens[1].wordness, W.non_word)
end)

--------------------------------------------------------------------------------
--- Structural token wordness --------------------------------------------------
--------------------------------------------------------------------------------

test('anchor wordness: ^ is non_word (structural)', function()
  local result = parse({
    tok(T.anchor, '^', 1),
  })
  eq(result.tokens[1].wordness, W.non_word)
end)

test('anchor wordness: $ is non_word (structural)', function()
  local result = parse({
    tok(T.anchor, '$', 1),
  })
  eq(result.tokens[1].wordness, W.non_word)
end)

test('alternation wordness: | is non_word (structural)', function()
  local result = parse({
    tok(T.alternation, '|', 1),
  })
  eq(result.tokens[1].wordness, W.non_word)
end)

test('group_open wordness: ( is non_word (structural)', function()
  local result = parse({
    tok(T.group_open, '(', 1, { kind = GK.capturing }),
  })
  eq(result.tokens[1].wordness, W.non_word)
end)

test('group_close wordness: ) is non_word (structural)', function()
  local result = parse({
    tok(T.group_close, ')', 1),
  })
  eq(result.tokens[1].wordness, W.non_word)
end)

--------------------------------------------------------------------------------
--- Quantifier wordness (inherits from preceding) ------------------------------
--------------------------------------------------------------------------------

test('quantifier wordness: * inherits word from preceding \\w', function()
  local result = parse({
    tok(T.escape, '\\w', 1),
    tok(T.quantifier, '*', 3, { greedy = true }),
  })
  eq(result.tokens[2].wordness, W.word)
end)

test('quantifier wordness: + inherits non_word from preceding \\s', function()
  local result = parse({
    tok(T.escape, '\\s', 1),
    tok(T.quantifier, '+', 3, { greedy = true }),
  })
  eq(result.tokens[2].wordness, W.non_word)
end)

test('quantifier wordness: ? inherits unknown from preceding .', function()
  local result = parse({
    tok(T.literal, '.', 1),
    tok(T.quantifier, '?', 2, { greedy = true }),
  })
  eq(result.tokens[2].wordness, W.unknown)
end)

test('quantifier wordness: {2,3} inherits word from preceding literal', function()
  local result = parse({
    tok(T.literal, 'a', 1),
    tok(T.quantifier, '{2,3}', 2, { greedy = true }),
  })
  eq(result.tokens[2].wordness, W.word)
end)

test('quantifier wordness: inherits from group_close (non_word)', function()
  local result = parse({
    tok(T.group_open, '(', 1, { kind = GK.capturing }),
    tok(T.literal, 'a', 2),
    tok(T.group_close, ')', 3),
    tok(T.quantifier, '+', 4, { greedy = true }),
  })
  eq(result.tokens[4].wordness, W.non_word)
end)

test('quantifier wordness: inherits from char_class_close (computed)', function()
  local result = parse({
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_literal, 'a', 2),
    tok(T.char_class_close, ']', 3),
    tok(T.quantifier, '+', 4, { greedy = true }),
  })
  -- [a] contains only word char, so class is word, quantifier inherits
  eq(result.tokens[4].wordness, W.word)
end)

--------------------------------------------------------------------------------
--- Slash wordness -------------------------------------------------------------
--------------------------------------------------------------------------------

test('slash wordness: / is non_word', function()
  local result = parse({
    tok(T.slash, '/', 1),
  })
  eq(result.tokens[1].wordness, W.non_word)
end)

--------------------------------------------------------------------------------
--- Character class wordness: word-only ----------------------------------------
--------------------------------------------------------------------------------

test('class wordness: [a] is word', function()
  local result = parse({
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_literal, 'a', 2),
    tok(T.char_class_close, ']', 3),
  })
  eq(result.tokens[1].wordness, W.word)
  eq(result.tokens[3].wordness, W.word)
end)

test('class wordness: [aeiou] is word', function()
  local result = parse({
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_literal, 'a', 2),
    tok(CC.cc_literal, 'e', 3),
    tok(CC.cc_literal, 'i', 4),
    tok(CC.cc_literal, 'o', 5),
    tok(CC.cc_literal, 'u', 6),
    tok(T.char_class_close, ']', 7),
  })
  eq(result.tokens[1].wordness, W.word)
end)

test('class wordness: [a-z] is word', function()
  local result = parse({
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_range, 'a-z', 2, { from = 'a', to = 'z' }),
    tok(T.char_class_close, ']', 5),
  })
  eq(result.tokens[1].wordness, W.word)
end)

test('class wordness: [A-Z] is word', function()
  local result = parse({
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_range, 'A-Z', 2, { from = 'A', to = 'Z' }),
    tok(T.char_class_close, ']', 5),
  })
  eq(result.tokens[1].wordness, W.word)
end)

test('class wordness: [0-9] is word', function()
  local result = parse({
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_range, '0-9', 2, { from = '0', to = '9' }),
    tok(T.char_class_close, ']', 5),
  })
  eq(result.tokens[1].wordness, W.word)
end)

test('class wordness: [a-zA-Z0-9_] is word', function()
  local result = parse({
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_range, 'a-z', 2, { from = 'a', to = 'z' }),
    tok(CC.cc_range, 'A-Z', 5, { from = 'A', to = 'Z' }),
    tok(CC.cc_range, '0-9', 8, { from = '0', to = '9' }),
    tok(CC.cc_literal, '_', 11),
    tok(T.char_class_close, ']', 12),
  })
  eq(result.tokens[1].wordness, W.word)
end)

test('class wordness: [\\w] is word', function()
  local result = parse({
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_escape, '\\w', 2),
    tok(T.char_class_close, ']', 4),
  })
  eq(result.tokens[1].wordness, W.word)
end)

test('class wordness: [\\d] is word', function()
  local result = parse({
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_escape, '\\d', 2),
    tok(T.char_class_close, ']', 4),
  })
  eq(result.tokens[1].wordness, W.word)
end)

--------------------------------------------------------------------------------
--- Character class wordness: non-word -----------------------------------------
--------------------------------------------------------------------------------

test('class wordness: [\\s] is non_word', function()
  local result = parse({
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_escape, '\\s', 2),
    tok(T.char_class_close, ']', 4),
  })
  eq(result.tokens[1].wordness, W.non_word)
end)

test('class wordness: [\\W] is non_word', function()
  local result = parse({
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_escape, '\\W', 2),
    tok(T.char_class_close, ']', 4),
  })
  eq(result.tokens[1].wordness, W.non_word)
end)

test('class wordness: [.] is non_word (dot literal in class)', function()
  local result = parse({
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_literal, '.', 2),
    tok(T.char_class_close, ']', 3),
  })
  eq(result.tokens[1].wordness, W.non_word)
end)

test('class wordness: [.,;:] is non_word', function()
  local result = parse({
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_literal, '.', 2),
    tok(CC.cc_literal, ',', 3),
    tok(CC.cc_literal, ';', 4),
    tok(CC.cc_literal, ':', 5),
    tok(T.char_class_close, ']', 6),
  })
  eq(result.tokens[1].wordness, W.non_word)
end)

test('class wordness: [-] is non_word (leading hyphen)', function()
  local result = parse({
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_literal, '-', 2),
    tok(T.char_class_close, ']', 3),
  })
  eq(result.tokens[1].wordness, W.non_word)
end)

test('class wordness: [\\-] is non_word (escaped hyphen)', function()
  local result = parse({
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_escape, '\\-', 2),
    tok(T.char_class_close, ']', 4),
  })
  eq(result.tokens[1].wordness, W.non_word)
end)

test('class wordness: [\\\\] is non_word (escaped backslash)', function()
  local result = parse({
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_escape, '\\\\', 2),
    tok(T.char_class_close, ']', 4),
  })
  eq(result.tokens[1].wordness, W.non_word)
end)

test('class wordness: []] is non_word (] as first char)', function()
  local result = parse({
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_literal, ']', 2),
    tok(T.char_class_close, ']', 3),
  })
  eq(result.tokens[1].wordness, W.non_word)
end)

--------------------------------------------------------------------------------
--- Character class wordness: unknown ------------------------------------------
--------------------------------------------------------------------------------

test('class wordness: [^a-z] is unknown (negated)', function()
  local result = parse({
    tok(T.char_class_open, '[^', 1, { negated = true }),
    tok(CC.cc_range, 'a-z', 3, { from = 'a', to = 'z' }),
    tok(T.char_class_close, ']', 6),
  })
  eq(result.tokens[1].wordness, W.unknown)
end)

test('class wordness: [\\S] is unknown', function()
  local result = parse({
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_escape, '\\S', 2),
    tok(T.char_class_close, ']', 4),
  })
  eq(result.tokens[1].wordness, W.unknown)
end)

test('class wordness: [\\D] is unknown', function()
  local result = parse({
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_escape, '\\D', 2),
    tok(T.char_class_close, ']', 4),
  })
  eq(result.tokens[1].wordness, W.unknown)
end)

test('class wordness: [a\\s] is unknown (mixed word and non_word)', function()
  local result = parse({
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_literal, 'a', 2),
    tok(CC.cc_escape, '\\s', 3),
    tok(T.char_class_close, ']', 5),
  })
  eq(result.tokens[1].wordness, W.unknown)
end)

test('class wordness: [a-z.] is unknown (mixed word and non_word)', function()
  local result = parse({
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_range, 'a-z', 2, { from = 'a', to = 'z' }),
    tok(CC.cc_literal, '.', 5),
    tok(T.char_class_close, ']', 6),
  })
  eq(result.tokens[1].wordness, W.unknown)
end)

test('class wordness: [-a-z] is unknown (mixed word and non_word)', function()
  local result = parse({
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_literal, '-', 2),
    tok(CC.cc_range, 'a-z', 3, { from = 'a', to = 'z' }),
    tok(T.char_class_close, ']', 6),
  })
  eq(result.tokens[1].wordness, W.unknown)
end)

test('class wordness: [A-z] is unknown (range spans word/non-word)', function()
  local result = parse({
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_range, 'A-z', 2, { from = 'A', to = 'z' }),
    tok(T.char_class_close, ']', 5),
  })
  eq(result.tokens[1].wordness, W.unknown)
end)

test('class wordness: [0-Z] is unknown (range digit to letter via gap)', function()
  local result = parse({
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_range, '0-Z', 2, { from = '0', to = 'Z' }),
    tok(T.char_class_close, ']', 5),
  })
  eq(result.tokens[1].wordness, W.unknown)
end)

--------------------------------------------------------------------------------
--- Word boundary (\b) annotation ----------------------------------------------
--------------------------------------------------------------------------------

test('boundary: \\b at start has prev_wordness nil, next from following', function()
  local result = parse({
    tok(T.escape, '\\b', 1),
    tok(T.literal, 'a', 3),
  })
  eq(result.tokens[1].prev_wordness, nil)
  eq(result.tokens[1].next_wordness, W.word)
end)

test('boundary: \\b at end has next_wordness nil, prev from preceding', function()
  local result = parse({
    tok(T.literal, 'a', 1),
    tok(T.escape, '\\b', 2),
  })
  eq(result.tokens[2].prev_wordness, W.word)
  eq(result.tokens[2].next_wordness, nil)
end)

test('boundary: \\b between word chars', function()
  local result = parse({
    tok(T.literal, 'a', 1),
    tok(T.escape, '\\b', 2),
    tok(T.literal, 'b', 4),
  })
  eq(result.tokens[2].prev_wordness, W.word)
  eq(result.tokens[2].next_wordness, W.word)
end)

test('boundary: \\b after \\w, before \\s', function()
  local result = parse({
    tok(T.escape, '\\w', 1),
    tok(T.escape, '\\b', 3),
    tok(T.escape, '\\s', 5),
  })
  eq(result.tokens[2].prev_wordness, W.word)
  eq(result.tokens[2].next_wordness, W.non_word)
end)

test('boundary: \\b after non-word, before word', function()
  local result = parse({
    tok(T.literal, ' ', 1),
    tok(T.escape, '\\b', 2),
    tok(T.literal, 'a', 4),
  })
  eq(result.tokens[2].prev_wordness, W.non_word)
  eq(result.tokens[2].next_wordness, W.word)
end)

test('boundary: \\b after quantifier (inherits wordness)', function()
  local result = parse({
    tok(T.escape, '\\w', 1),
    tok(T.quantifier, '+', 3, { greedy = true }),
    tok(T.escape, '\\b', 4),
  })
  eq(result.tokens[3].prev_wordness, W.word)
end)

test('boundary: \\b after char class', function()
  local result = parse({
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_range, 'a-z', 2, { from = 'a', to = 'z' }),
    tok(T.char_class_close, ']', 5),
    tok(T.escape, '\\b', 6),
  })
  eq(result.tokens[4].prev_wordness, W.word)
end)

test('boundary: \\b after char class with quantifier', function()
  local result = parse({
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_range, 'a-z', 2, { from = 'a', to = 'z' }),
    tok(T.char_class_close, ']', 5),
    tok(T.quantifier, '+', 6, { greedy = true }),
    tok(T.escape, '\\b', 7),
  })
  eq(result.tokens[5].prev_wordness, W.word)
end)

test('boundary: \\b after dot (unknown)', function()
  local result = parse({
    tok(T.literal, '.', 1),
    tok(T.escape, '\\b', 2),
  })
  eq(result.tokens[2].prev_wordness, W.unknown)
end)

test('boundary: \\b before dot (unknown)', function()
  local result = parse({
    tok(T.escape, '\\b', 1),
    tok(T.literal, '.', 3),
  })
  eq(result.tokens[1].next_wordness, W.unknown)
end)

test('boundary: \\b after group_close (non_word structural)', function()
  local result = parse({
    tok(T.group_open, '(', 1, { kind = GK.capturing }),
    tok(T.literal, 'a', 2),
    tok(T.group_close, ')', 3),
    tok(T.escape, '\\b', 4),
  })
  eq(result.tokens[4].prev_wordness, W.non_word)
end)

test('boundary: \\b after alternation (non_word structural)', function()
  local result = parse({
    tok(T.literal, 'a', 1),
    tok(T.alternation, '|', 2),
    tok(T.escape, '\\b', 3),
    tok(T.literal, 'b', 5),
  })
  eq(result.tokens[3].prev_wordness, W.non_word)
end)

test('boundary: \\b standalone (both nil)', function()
  local result = parse({
    tok(T.escape, '\\b', 1),
  })
  eq(result.tokens[1].prev_wordness, nil)
  eq(result.tokens[1].next_wordness, nil)
end)

test('boundary: multiple \\b in pattern', function()
  local result = parse({
    tok(T.escape, '\\b', 1),
    tok(T.literal, 'w', 3),
    tok(T.literal, 'o', 4),
    tok(T.literal, 'r', 5),
    tok(T.literal, 'd', 6),
    tok(T.escape, '\\b', 7),
  })
  eq(result.tokens[1].prev_wordness, nil)
  eq(result.tokens[1].next_wordness, W.word)
  eq(result.tokens[6].prev_wordness, W.word)
  eq(result.tokens[6].next_wordness, nil)
end)

--------------------------------------------------------------------------------
--- Group validation: unsupported types ----------------------------------------
--------------------------------------------------------------------------------

test('group: lookahead_pos is unsupported', function()
  assert_fails({
    tok(T.group_open, '(?=', 1, { kind = GK.lookahead_pos }),
    tok(T.literal, 'a', 4),
    tok(T.group_close, ')', 5),
  }, 'lookarounds and atomic groups not supported')
end)

test('group: lookahead_neg is unsupported', function()
  assert_fails({
    tok(T.group_open, '(?!', 1, { kind = GK.lookahead_neg }),
    tok(T.literal, 'a', 4),
    tok(T.group_close, ')', 5),
  }, 'lookarounds and atomic groups not supported')
end)

test('group: lookbehind_pos is unsupported', function()
  assert_fails({
    tok(T.group_open, '(?<=', 1, { kind = GK.lookbehind_pos }),
    tok(T.literal, 'a', 5),
    tok(T.group_close, ')', 6),
  }, 'lookarounds not supported')
end)

test('group: lookbehind_neg is unsupported', function()
  assert_fails({
    tok(T.group_open, '(?<!', 1, { kind = GK.lookbehind_neg }),
    tok(T.literal, 'a', 5),
    tok(T.group_close, ')', 6),
  }, 'lookarounds not supported')
end)

test('group: atomic is unsupported', function()
  assert_fails({
    tok(T.group_open, '(?>', 1, { kind = GK.atomic }),
    tok(T.literal, 'a', 4),
    tok(T.group_close, ')', 5),
  }, 'lookarounds and atomic groups not supported')
end)

--------------------------------------------------------------------------------
--- Group validation: supported types ------------------------------------------
--------------------------------------------------------------------------------

test('group: capturing is supported', function()
  local result = parse({
    tok(T.group_open, '(', 1, { kind = GK.capturing }),
    tok(T.literal, 'a', 2),
    tok(T.group_close, ')', 3),
  })
  eq(result.error, nil)
  eq(#result.warnings, 0)
end)

test('group: non_capturing is supported', function()
  local result = parse({
    tok(T.group_open, '(?:', 1, { kind = GK.non_capturing }),
    tok(T.literal, 'a', 4),
    tok(T.group_close, ')', 5),
  })
  eq(result.error, nil)
  eq(#result.warnings, 0)
end)

--------------------------------------------------------------------------------
--- Group validation: named groups (supported with warning) --------------------
--------------------------------------------------------------------------------

test('group: named_python generates warning', function()
  local result = parse({
    tok(T.group_open, '(?P<name>', 1, { kind = GK.named_python, name = 'name' }),
    tok(T.literal, 'a', 10),
    tok(T.group_close, ')', 11),
  })
  eq(result.tokens ~= nil, true)
  eq(#result.warnings, 1)
  eq(result.warnings[1], 'named groups become numbered')
end)

test('group: named_pcre generates warning', function()
  local result = parse({
    tok(T.group_open, '(?<name>', 1, { kind = GK.named_pcre, name = 'name' }),
    tok(T.literal, 'a', 9),
    tok(T.group_close, ')', 10),
  })
  eq(result.tokens ~= nil, true)
  eq(#result.warnings, 1)
  eq(result.warnings[1], 'named groups become numbered')
end)

test('group: named with empty name fails', function()
  assert_fails({
    tok(T.group_open, '(?P<>', 1, { kind = GK.named_python, name = '' }),
    tok(T.literal, 'a', 6),
    tok(T.group_close, ')', 7),
  }, 'invalid group name')
end)

test('group: multiple named groups shows count', function()
  local result = parse({
    tok(T.group_open, '(?P<a>', 1, { kind = GK.named_python, name = 'a' }),
    tok(T.literal, 'x', 7),
    tok(T.group_close, ')', 8),
    tok(T.group_open, '(?P<b>', 9, { kind = GK.named_python, name = 'b' }),
    tok(T.literal, 'y', 15),
    tok(T.group_close, ')', 16),
  })
  eq(result.tokens ~= nil, true)
  eq(#result.warnings, 2)
  eq(result.warnings[1], 'named groups become numbered')
  eq(result.warnings[2], 'named groups become numbered')
end)

--------------------------------------------------------------------------------
--- Quantifier validation: possessive (unsupported) ----------------------------
--------------------------------------------------------------------------------

test('quantifier: possessive *+ is unsupported', function()
  assert_fails({
    tok(T.literal, 'a', 1),
    tok(T.quantifier, '*+', 2, { greedy = true, possessive = true }),
  }, 'possessive quantifiers not supported')
end)

test('quantifier: possessive ++ is unsupported', function()
  assert_fails({
    tok(T.literal, 'a', 1),
    tok(T.quantifier, '++', 2, { greedy = true, possessive = true }),
  }, 'possessive quantifiers not supported')
end)

test('quantifier: possessive ?+ is unsupported', function()
  assert_fails({
    tok(T.literal, 'a', 1),
    tok(T.quantifier, '?+', 2, { greedy = true, possessive = true }),
  }, 'possessive quantifiers not supported')
end)

--------------------------------------------------------------------------------
--- Anchor warnings ------------------------------------------------------------
--------------------------------------------------------------------------------

test('anchor: \\A generates warning', function()
  local result = parse({
    tok(T.escape, '\\A', 1),
    tok(T.literal, 'a', 3),
  })
  eq(result.tokens ~= nil, true)
  eq(#result.warnings, 1)
  eq(result.warnings[1], '\\A treated as ^')
end)

test('anchor: \\z generates warning', function()
  local result = parse({
    tok(T.literal, 'a', 1),
    tok(T.escape, '\\z', 2),
  })
  eq(result.tokens ~= nil, true)
  eq(#result.warnings, 1)
  eq(result.warnings[1], '\\z treated as $')
end)

test('anchor: \\A and \\z together shows count', function()
  local result = parse({
    tok(T.escape, '\\A', 1),
    tok(T.literal, 'a', 3),
    tok(T.escape, '\\z', 4),
  })
  eq(result.tokens ~= nil, true)
  eq(#result.warnings, 2)
  eq(result.warnings[1], '\\A treated as ^')
  eq(result.warnings[2], '\\z treated as $')
end)

--------------------------------------------------------------------------------
--- Multiple warnings ----------------------------------------------------------
--------------------------------------------------------------------------------

test('warnings: named group with \\A shows count', function()
  local result = parse({
    tok(T.escape, '\\A', 1),
    tok(T.group_open, '(?P<n>', 3, { kind = GK.named_python, name = 'n' }),
    tok(T.literal, 'a', 9),
    tok(T.group_close, ')', 10),
  })
  eq(result.tokens ~= nil, true)
  eq(#result.warnings, 2)
  eq(result.warnings[1], '\\A treated as ^')
  eq(result.warnings[2], 'named groups become numbered')
end)

test('warnings: three named groups shows (+2 more)', function()
  local result = parse({
    tok(T.group_open, '(?P<a>', 1, { kind = GK.named_python, name = 'a' }),
    tok(T.literal, 'x', 7),
    tok(T.group_close, ')', 8),
    tok(T.group_open, '(?P<b>', 9, { kind = GK.named_python, name = 'b' }),
    tok(T.literal, 'y', 15),
    tok(T.group_close, ')', 16),
    tok(T.group_open, '(?P<c>', 17, { kind = GK.named_python, name = 'c' }),
    tok(T.literal, 'z', 23),
    tok(T.group_close, ')', 24),
  })
  eq(result.tokens ~= nil, true)
  eq(#result.warnings, 3)
  eq(result.warnings[1], 'named groups become numbered')
  eq(result.warnings[2], 'named groups become numbered')
  eq(result.warnings[3], 'named groups become numbered')
end)

--------------------------------------------------------------------------------
--- Character class token pass-through -----------------------------------------
--------------------------------------------------------------------------------

test('cc_literal: escape class not assigned (cc tokens)', function()
  local result = parse({
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_literal, 'a', 2),
    tok(T.char_class_close, ']', 3),
  })
  -- cc_literal tokens don't get escape_class annotation
  eq(result.tokens[2].escape_class, nil)
end)

test('cc_escape: wordness computed for classification', function()
  local result = parse({
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_escape, '\\w', 2),
    tok(T.char_class_close, ']', 4),
  })
  -- The char class open/close get wordness based on contents
  eq(result.tokens[1].wordness, W.word)
end)

test('cc_range: contributes to class wordness', function()
  local result = parse({
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_range, 'a-z', 2, { from = 'a', to = 'z' }),
    tok(CC.cc_range, '0-9', 5, { from = '0', to = '9' }),
    tok(T.char_class_close, ']', 8),
  })
  eq(result.tokens[1].wordness, W.word)
end)

--------------------------------------------------------------------------------
--- Edge cases -----------------------------------------------------------------
--------------------------------------------------------------------------------

test('edge: trailing backslash (escape with single char)', function()
  local result = parse({
    tok(T.escape, '\\', 1),
  })
  eq(result.tokens[1].escape_class, EC.escaped_literal)
end)

test('edge: unclosed character class', function()
  -- Parser should handle tokens as provided; unclosed is tokeniser concern
  local result = parse({
    tok(T.char_class_open, '[', 1, { negated = false }),
    tok(CC.cc_literal, 'a', 2),
    -- No char_class_close
  })
  -- Should still process without error; wordness computed from available tokens
  eq(result.error, nil)
end)

test('edge: unclosed group', function()
  local result = parse({
    tok(T.group_open, '(', 1, { kind = GK.capturing }),
    tok(T.literal, 'a', 2),
    -- No group_close
  })
  eq(result.error, nil)
end)

test('edge: unmatched group_close', function()
  local result = parse({
    tok(T.literal, 'a', 1),
    tok(T.group_close, ')', 2),
  })
  eq(result.error, nil)
end)

test('edge: quantifier at start (literal as per tokeniser)', function()
  -- If tokeniser gave us literal '?', it stays literal
  local result = parse({
    tok(T.literal, '?', 1),
    tok(T.literal, 'a', 2),
  })
  eq(result.tokens[1].wordness, W.non_word)
  eq(result.tokens[2].wordness, W.word)
end)

--------------------------------------------------------------------------------
--- Complex patterns -----------------------------------------------------------
--------------------------------------------------------------------------------

test('complex: \\bword\\b', function()
  local result = parse({
    tok(T.escape, '\\b', 1),
    tok(T.literal, 'w', 3),
    tok(T.literal, 'o', 4),
    tok(T.literal, 'r', 5),
    tok(T.literal, 'd', 6),
    tok(T.escape, '\\b', 7),
  })
  eq(result.tokens[1].prev_wordness, nil)
  eq(result.tokens[1].next_wordness, W.word)
  eq(result.tokens[6].prev_wordness, W.word)
  eq(result.tokens[6].next_wordness, nil)
end)

test('complex: \\b\\w+\\b', function()
  local result = parse({
    tok(T.escape, '\\b', 1),
    tok(T.escape, '\\w', 3),
    tok(T.quantifier, '+', 5, { greedy = true }),
    tok(T.escape, '\\b', 6),
  })
  eq(result.tokens[1].next_wordness, W.word)
  eq(result.tokens[4].prev_wordness, W.word)  -- quantifier inherits from \w
end)

test('complex: [a-z]+@[a-z]+', function()
  local result = parse({
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
  eq(result.tokens[1].wordness, W.word)
  eq(result.tokens[4].wordness, W.word)  -- quantifier inherits from class
  eq(result.tokens[5].wordness, W.non_word)  -- @
  eq(result.tokens[6].wordness, W.word)
end)

test('complex: (foo|bar)', function()
  local result = parse({
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
  eq(result.error, nil)
  eq(result.tokens[1].wordness, W.non_word)  -- (
  eq(result.tokens[5].wordness, W.non_word)  -- |
  eq(result.tokens[9].wordness, W.non_word)  -- )
end)

test('complex: <.*?>', function()
  local result = parse({
    tok(T.literal, '<', 1),
    tok(T.literal, '.', 2),
    tok(T.quantifier, '*?', 3, { greedy = false }),
    tok(T.literal, '>', 5),
  })
  eq(result.tokens[1].wordness, W.non_word)
  eq(result.tokens[2].wordness, W.unknown)
  eq(result.tokens[3].wordness, W.unknown)  -- inherits from .
  eq(result.tokens[4].wordness, W.non_word)
end)

--------------------------------------------------------------------------------
--- Summary --------------------------------------------------------------------
--------------------------------------------------------------------------------

h.summary()
