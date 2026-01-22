-- tests/pattern/parser_escape_test.lua
-- Escape sequence classification tests for the parser.
--
-- The parser receives tokens from the tokeniser and adds semantic
-- classification via the `escape_class` field. These tests verify
-- correct classification of all escape sequence types.
--
-- Run with:
--   nvim --headless -u NONE -c "set rtp+=." -c "luafile tests/pattern/parser_escape_test.lua"

local h = require('tests.harness')
local test = h.test
local eq = h.eq
local deep_eq = h.deep_eq
local types = require('brook.pattern.types')

local parser = require('brook.pattern.parser')

local parse = parser.parse

local T = types.token_type
local EC = types.escape_class

--------------------------------------------------------------------------------
--- Shorthand word escapes -----------------------------------------------------
--------------------------------------------------------------------------------

test('escape class: \\w is shorthand_word', function()
  local result = parse({
    { type = T.escape_class, value = '\\w', pos = 1 },
  })
  eq(result.tokens[1].escape_class, EC.shorthand_word)
end)

test('escape class: \\d is shorthand_word', function()
  local result = parse({
    { type = T.escape_class, value = '\\d', pos = 1 },
  })
  eq(result.tokens[1].escape_class, EC.shorthand_word)
end)

--------------------------------------------------------------------------------
--- Shorthand non-word escapes -------------------------------------------------
--------------------------------------------------------------------------------

test('escape class: \\s is shorthand_nonword', function()
  local result = parse({
    { type = T.escape_class, value = '\\s', pos = 1 },
  })
  eq(result.tokens[1].escape_class, EC.shorthand_nonword)
end)

test('escape class: \\W is shorthand_nonword', function()
  local result = parse({
    { type = T.escape_class, value = '\\W', pos = 1 },
  })
  eq(result.tokens[1].escape_class, EC.shorthand_nonword)
end)

--------------------------------------------------------------------------------
--- Shorthand unknown escapes --------------------------------------------------
--------------------------------------------------------------------------------

test('escape class: \\S is shorthand_unknown', function()
  local result = parse({
    { type = T.escape_class, value = '\\S', pos = 1 },
  })
  eq(result.tokens[1].escape_class, EC.shorthand_unknown)
end)

test('escape class: \\D is shorthand_unknown', function()
  local result = parse({
    { type = T.escape_class, value = '\\D', pos = 1 },
  })
  eq(result.tokens[1].escape_class, EC.shorthand_unknown)
end)

--------------------------------------------------------------------------------
--- Escape literals ------------------------------------------------------------
--------------------------------------------------------------------------------

test('escape class: \\n is escaped_literal', function()
  local result = parse({
    { type = T.escape_literal, value = '\\n', pos = 1 },
  })
  eq(result.tokens[1].escape_class, EC.escaped_literal)
end)

test('escape class: \\t is escaped_literal', function()
  local result = parse({
    { type = T.escape_literal, value = '\\t', pos = 1 },
  })
  eq(result.tokens[1].escape_class, EC.escaped_literal)
end)

test('escape class: \\r is escaped_literal', function()
  local result = parse({
    { type = T.escape_literal, value = '\\r', pos = 1 },
  })
  eq(result.tokens[1].escape_class, EC.escaped_literal)
end)

test('escape class: \\\\ is escaped_literal', function()
  local result = parse({
    { type = T.escape_literal, value = '\\\\', pos = 1 },
  })
  eq(result.tokens[1].escape_class, EC.escaped_literal)
end)

test('escape class: \\. is escaped_literal', function()
  local result = parse({
    { type = T.escape_literal, value = '\\.', pos = 1 },
  })
  eq(result.tokens[1].escape_class, EC.escaped_literal)
end)

test('escape class: \\* is escaped_literal', function()
  local result = parse({
    { type = T.escape_literal, value = '\\*', pos = 1 },
  })
  eq(result.tokens[1].escape_class, EC.escaped_literal)
end)

test('escape class: \\+ is escaped_literal', function()
  local result = parse({
    { type = T.escape_literal, value = '\\+', pos = 1 },
  })
  eq(result.tokens[1].escape_class, EC.escaped_literal)
end)

test('escape class: \\? is escaped_literal', function()
  local result = parse({
    { type = T.escape_literal, value = '\\?', pos = 1 },
  })
  eq(result.tokens[1].escape_class, EC.escaped_literal)
end)

test('escape class: \\( is escaped_literal', function()
  local result = parse({
    { type = T.escape_literal, value = '\\(', pos = 1 },
  })
  eq(result.tokens[1].escape_class, EC.escaped_literal)
end)

test('escape class: \\) is escaped_literal', function()
  local result = parse({
    { type = T.escape_literal, value = '\\)', pos = 1 },
  })
  eq(result.tokens[1].escape_class, EC.escaped_literal)
end)

test('escape class: \\[ is escaped_literal', function()
  local result = parse({
    { type = T.escape_literal, value = '\\[', pos = 1 },
  })
  eq(result.tokens[1].escape_class, EC.escaped_literal)
end)

test('escape class: \\] is escaped_literal', function()
  local result = parse({
    { type = T.escape_literal, value = '\\]', pos = 1 },
  })
  eq(result.tokens[1].escape_class, EC.escaped_literal)
end)

test('escape class: \\{ is escaped_literal', function()
  local result = parse({
    { type = T.escape_literal, value = '\\{', pos = 1 },
  })
  eq(result.tokens[1].escape_class, EC.escaped_literal)
end)

test('escape class: \\} is escaped_literal', function()
  local result = parse({
    { type = T.escape_literal, value = '\\}', pos = 1 },
  })
  eq(result.tokens[1].escape_class, EC.escaped_literal)
end)

test('escape class: \\| is escaped_literal', function()
  local result = parse({
    { type = T.escape_literal, value = '\\|', pos = 1 },
  })
  eq(result.tokens[1].escape_class, EC.escaped_literal)
end)

test('escape class: \\^ is escaped_literal', function()
  local result = parse({
    { type = T.escape_literal, value = '\\^', pos = 1 },
  })
  eq(result.tokens[1].escape_class, EC.escaped_literal)
end)

test('escape class: \\$ is escaped_literal', function()
  local result = parse({
    { type = T.escape_literal, value = '\\$', pos = 1 },
  })
  eq(result.tokens[1].escape_class, EC.escaped_literal)
end)

--------------------------------------------------------------------------------
--- Boundary escapes -----------------------------------------------------------
--------------------------------------------------------------------------------

test('escape class: \\b is boundary', function()
  local result = parse({
    { type = T.escape_boundary, value = '\\b', pos = 1, boundary_kind = 'word' },
  })
  eq(result.tokens[1].escape_class, EC.boundary)
end)

test('escape class: \\B is boundary_neg (unsupported)', function()
  local result = parse({
    { type = T.escape_boundary, value = '\\B', pos = 1, boundary_kind = 'word_neg' },
  })
  eq(result.error, '\\B not supported')
end)

--------------------------------------------------------------------------------
--- Anchor escapes -------------------------------------------------------------
--------------------------------------------------------------------------------

test('escape class: \\A is anchor_start', function()
  local result = parse({
    { type = T.escape_boundary, value = '\\A', pos = 1, boundary_kind = 'start' },
  })
  eq(result.tokens[1].escape_class, EC.anchor_start)
end)

test('escape class: \\z is anchor_end', function()
  local result = parse({
    { type = T.escape_boundary, value = '\\z', pos = 1, boundary_kind = 'end' },
  })
  eq(result.tokens[1].escape_class, EC.anchor_end)
end)

--------------------------------------------------------------------------------
--- Hex escapes ----------------------------------------------------------------
--------------------------------------------------------------------------------

test('escape class: \\x7F is escaped_literal', function()
  local result = parse({
    { type = T.escape_hex, value = '\\x7F', pos = 1 },
  })
  eq(result.tokens[1].escape_class, EC.escaped_literal)
end)

test('escape class: \\x{0041} is escaped_literal', function()
  local result = parse({
    { type = T.escape_hex, value = '\\x{0041}', pos = 1 },
  })
  eq(result.tokens[1].escape_class, EC.escaped_literal)
end)

--------------------------------------------------------------------------------
--- Unicode escapes ------------------------------------------------------------
--------------------------------------------------------------------------------

test('escape class: \\u0041 is escaped_literal', function()
  local result = parse({
    { type = T.escape_unicode, value = '\\u0041', pos = 1 },
  })
  eq(result.tokens[1].escape_class, EC.escaped_literal)
end)

test('escape class: \\u{41} is escaped_literal', function()
  local result = parse({
    { type = T.escape_unicode, value = '\\u{41}', pos = 1 },
  })
  eq(result.tokens[1].escape_class, EC.escaped_literal)
end)

--------------------------------------------------------------------------------
--- Octal escapes --------------------------------------------------------------
--------------------------------------------------------------------------------

test('escape class: \\0 is escaped_literal', function()
  local result = parse({
    { type = T.escape_octal, value = '\\0', pos = 1 },
  })
  eq(result.tokens[1].escape_class, EC.escaped_literal)
end)

test('escape class: \\123 is escaped_literal', function()
  local result = parse({
    { type = T.escape_octal, value = '\\123', pos = 1 },
  })
  eq(result.tokens[1].escape_class, EC.escaped_literal)
end)

--------------------------------------------------------------------------------
--- Unicode property escapes (unsupported) -------------------------------------
--------------------------------------------------------------------------------

test('escape class: \\p{L} errors (unsupported)', function()
  local result = parse({
    { type = T.escape_property, value = '\\p{L}', pos = 1, negated = false },
  })
  eq(result.error, 'unicode properties not supported')
end)

test('escape class: \\P{L} errors (unsupported)', function()
  local result = parse({
    { type = T.escape_property, value = '\\P{L}', pos = 1, negated = true },
  })
  eq(result.error, 'unicode properties not supported')
end)

--------------------------------------------------------------------------------
--- Backreference escapes (unsupported) ----------------------------------------
--------------------------------------------------------------------------------

test('escape class: \\1 errors (unsupported)', function()
  local result = parse({
    { type = T.escape_backref, value = '\\1', pos = 1 },
  })
  eq(result.error, 'backreferences require PCRE2')
end)

test('escape class: \\9 errors (unsupported)', function()
  local result = parse({
    { type = T.escape_backref, value = '\\9', pos = 1 },
  })
  eq(result.error, 'backreferences require PCRE2')
end)

--------------------------------------------------------------------------------
--- Error and warning forwarding -----------------------------------------------
--------------------------------------------------------------------------------

test('forward: incoming warnings are preserved', function()
  local result = parse({
    { type = T.literal, value = 'a', pos = 1 },
  }, { 'tokeniser warning' })
  eq(result.error, nil)
  eq(#result.warnings, 1)
  eq(result.warnings[1], 'tokeniser warning')
end)

test('forward: incoming warnings combined with parser warnings', function()
  local result = parse({
    { type = T.escape_boundary, value = '\\A', pos = 1, boundary_kind = 'start' },
  }, { 'tokeniser warning' })
  eq(result.error, nil)
  eq(#result.warnings, 2)
  eq(result.warnings[1], 'tokeniser warning')
  eq(result.warnings[2], '\\A treated as ^')
end)

test('forward: incoming error returns early', function()
  local result = parse({
    { type = T.literal, value = 'a', pos = 1 },
  }, {}, 'tokeniser error')
  eq(result.error, 'tokeniser error')
  eq(result.tokens, nil)
end)

test('forward: incoming error preserves warnings', function()
  local result = parse({
    { type = T.literal, value = 'a', pos = 1 },
  }, { 'warning before error' }, 'tokeniser error')
  eq(result.error, 'tokeniser error')
  eq(#result.warnings, 1)
  eq(result.warnings[1], 'warning before error')
end)

test('forward: nil incoming warnings treated as empty', function()
  local result = parse({
    { type = T.literal, value = 'a', pos = 1 },
  }, nil, nil)
  eq(result.error, nil)
  deep_eq(result.warnings, {})
end)

test('forward: parser error still includes incoming warnings', function()
  local result = parse({
    { type = T.escape_property, value = '\\p{L}', pos = 1, negated = false },
  }, { 'tokeniser warning' })
  eq(result.error, 'unicode properties not supported')
  eq(#result.warnings, 1)
  eq(result.warnings[1], 'tokeniser warning')
end)

--------------------------------------------------------------------------------
--- Summary --------------------------------------------------------------------
--------------------------------------------------------------------------------

h.summary()
