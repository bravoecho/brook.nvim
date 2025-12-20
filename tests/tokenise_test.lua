-- Run with:
--   nvim --headless -c "luafile tests/tokenise_test.lua" -c "q"

local h = require('tests.harness')
local test = h.test
local deep_eq = h.deep_eq
local tokenise = require('brook.tokenise').tokenise

--------------------------------------------------------------------------------
--- Empty input ----------------------------------------------------------------
--------------------------------------------------------------------------------

test('empty: empty string', function()
  deep_eq(tokenise(''), {})
end)

test('empty: only spaces', function()
  deep_eq(tokenise('   '), {})
end)

test('empty: only tabs', function()
  deep_eq(tokenise('\t\t'), {})
end)

--------------------------------------------------------------------------------
--- Basic splitting ------------------------------------------------------------
--------------------------------------------------------------------------------

test('basic: simple words', function()
  deep_eq(tokenise('foo bar baz'), { 'foo', 'bar', 'baz' })
end)

test('basic: leading and trailing spaces', function()
  deep_eq(tokenise('  foo   bar  '), { 'foo', 'bar' })
end)

test('basic: tab separator', function()
  deep_eq(tokenise('foo\tbar'), { 'foo', 'bar' })
end)

test('basic: mixed whitespace', function()
  deep_eq(tokenise('foo \t  bar'), { 'foo', 'bar' })
end)

--------------------------------------------------------------------------------
--- Single quotes --------------------------------------------------------------
--------------------------------------------------------------------------------

test('single quotes: basic', function()
  deep_eq(tokenise("'foo bar'"), { "'foo bar'" })
end)

test('single quotes: multiple', function()
  deep_eq(tokenise("'foo' 'bar'"), { "'foo'", "'bar'" })
end)

test('single quotes: glued to unquoted', function()
  deep_eq(tokenise("foo'bar baz'qux"), { "foo'bar baz'qux" })
end)

test('single quotes: empty string', function()
  deep_eq(tokenise("''"), { "''" })
end)

test('single quotes: empty with following token', function()
  deep_eq(tokenise("'' foo"), { "''", 'foo' })
end)

--------------------------------------------------------------------------------
--- Double quotes --------------------------------------------------------------
--------------------------------------------------------------------------------

test('double quotes: basic', function()
  deep_eq(tokenise('"foo bar"'), { '"foo bar"' })
end)

test('double quotes: multiple', function()
  deep_eq(tokenise('"foo" "bar"'), { '"foo"', '"bar"' })
end)

test('double quotes: glued to unquoted', function()
  deep_eq(tokenise('foo"bar baz"qux'), { 'foo"bar baz"qux' })
end)

test('double quotes: empty string', function()
  deep_eq(tokenise('""'), { '""' })
end)

test('double quotes: empty with following token', function()
  deep_eq(tokenise('"" foo'), { '""', 'foo' })
end)

--------------------------------------------------------------------------------
--- Escapes inside double quotes -----------------------------------------------
--------------------------------------------------------------------------------

test('double quotes escape: escaped quote', function()
  deep_eq(tokenise('"foo\\"bar"'), { '"foo\\"bar"' })
end)

test('double quotes escape: escaped backslash', function()
  deep_eq(tokenise('"foo\\\\bar"'), { '"foo\\\\bar"' })
end)

test('double quotes escape: multiple escaped quotes', function()
  deep_eq(tokenise('"foo\\"bar\\"baz"'), { '"foo\\"bar\\"baz"' })
end)

--------------------------------------------------------------------------------
--- Backslash outside quotes ---------------------------------------------------
--------------------------------------------------------------------------------

test('backslash: escaped space', function()
  deep_eq(tokenise('foo\\ bar'), { 'foo\\ bar' })
end)

test('backslash: escaped backslash', function()
  deep_eq(tokenise('foo\\\\bar'), { 'foo\\\\bar' })
end)

test('backslash: escaped quote', function()
  deep_eq(tokenise('foo\\"bar'), { 'foo\\"bar' })
end)

test('backslash: escaped single quote at start', function()
  deep_eq(tokenise("\\'foo"), { "\\'foo" })
end)

--------------------------------------------------------------------------------
--- POSIX single quote escape idiom --------------------------------------------
--------------------------------------------------------------------------------

test('posix escape: basic', function()
  deep_eq(tokenise("'foo'\\''bar'"), { "'foo'\\''bar'" })
end)

test('posix escape: contraction', function()
  deep_eq(tokenise("'it'\\''s a test'"), { "'it'\\''s a test'" })
end)

test('posix escape: multiple escapes', function()
  deep_eq(tokenise("'foo'\\''bar'\\''baz'"), { "'foo'\\''bar'\\''baz'" })
end)

test('posix escape: with surrounding tokens', function()
  deep_eq(tokenise("-e 'foo'\\''bar' path/"), { '-e', "'foo'\\''bar'", 'path/' })
end)

-- Mixed quotes

test('mixed: single and double', function()
  deep_eq(tokenise([[foo 'bar baz' "qux quux"]]), { 'foo', "'bar baz'", '"qux quux"' })
end)

test('mixed: double inside single', function()
  deep_eq(tokenise([[foo'"bar"']]), { [[foo'"bar"']] })
end)

test('mixed: single inside double', function()
  deep_eq(tokenise([[foo"'bar'"]]), { [[foo"'bar'"]] })
end)

--------------------------------------------------------------------------------
--- Unterminated quotes --------------------------------------------------------
--------------------------------------------------------------------------------

test('unterminated: single quote', function()
  deep_eq(tokenise("'foo bar"), { "'foo bar" })
end)

test('unterminated: double quote', function()
  deep_eq(tokenise('"foo bar'), { '"foo bar' })
end)

test('unterminated: with preceding token', function()
  deep_eq(tokenise("foo 'bar"), { 'foo', "'bar" })
end)

-- TODO: ???
-- test('edge: unterminated string', function()
--   -- Best effort: treat as pattern anyway
--   eq(parse_args({ "'hello", 'world' }), "'hello world")
-- end)

--------------------------------------------------------------------------------
--- Real-world ripgrep examples ------------------------------------------------
--------------------------------------------------------------------------------

test('rg: simple with flags', function()
  deep_eq(tokenise("-i 'hello world' src/"), { '-i', "'hello world'", 'src/' })
end)

test('rg: glob with equals', function()
  deep_eq(tokenise('--glob="*.lua" pattern'), { '--glob="*.lua"', 'pattern' })
end)

test('rg: multiple -e flags', function()
  deep_eq(tokenise('-e "foo bar" -e baz'), { '-e', '"foo bar"', '-e', 'baz' })
end)

test('rg: complex command', function()
  deep_eq(
    tokenise("rg -i 'foo bar' --glob '*.txt' src/"),
    {
      'rg',
      '-i',
      "'foo bar'",
      '--glob',
      "'*.txt'",
      'src/',
    }
  )
end)

test('rg: complex command with token containing space', function()
  deep_eq(
    tokenise("rg -i 'foo bar' --glob '*.txt' src/ second\\ src"),
    {
      'rg',
      '-i',
      "'foo bar'",
      '--glob',
      "'*.txt'",
      'src/',
      'second\\ src',
    }
  )
end)

test('rg: mixed quote styles', function()
  deep_eq(
    tokenise("-e 'foo' -e \"bar\" baz"),
    { '-e', "'foo'", '-e', '"bar"', 'baz' }
  )
end)

test('rg: regexp with equals', function()
  deep_eq(tokenise('--regexp="foo.*bar" path/'), { '--regexp="foo.*bar"', 'path/' })
end)

test('rg: glued option value', function()
  deep_eq(tokenise('-e"foo bar"'), { '-e"foo bar"' })
end)

test('rg: double-dash sentinel', function()
  deep_eq(tokenise('-- -pattern-starting-with-dash'), { '--', '-pattern-starting-with-dash' })
end)

test('rg: option with double-quoted value containing spaces', function()
  deep_eq(tokenise('--regexp="foo bar"'), { '--regexp="foo bar"' })
end)

test('rg: option with single-quoted value containing spaces', function()
  deep_eq(tokenise("--color --regexp='foo bar'"), { '--color', "--regexp='foo bar'" })
end)

-- =============================================================================
-- Summary
-- =============================================================================

h.summary()
