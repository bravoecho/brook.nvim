-- Run with:
--   nvim --headless -c "luafile tests/tokenise_test.lua" -c "q"

local h = require('tests.harness')
local test = h.test
local eq_list = h.eq_list
local tokenise = require('brook.tokenise')._tokenise

--------------------------------------------------------------------------------
--- Empty input ----------------------------------------------------------------
--------------------------------------------------------------------------------

test('empty: empty string', function()
  eq_list(tokenise(''), {})
end)

test('empty: only spaces', function()
  eq_list(tokenise('   '), {})
end)

test('empty: only tabs', function()
  eq_list(tokenise('\t\t'), {})
end)

--------------------------------------------------------------------------------
--- Basic splitting ------------------------------------------------------------
--------------------------------------------------------------------------------

test('basic: simple words', function()
  eq_list(tokenise('foo bar baz'), { 'foo', 'bar', 'baz' })
end)

test('basic: leading and trailing spaces', function()
  eq_list(tokenise('  foo   bar  '), { 'foo', 'bar' })
end)

test('basic: tab separator', function()
  eq_list(tokenise('foo\tbar'), { 'foo', 'bar' })
end)

test('basic: mixed whitespace', function()
  eq_list(tokenise('foo \t  bar'), { 'foo', 'bar' })
end)

--------------------------------------------------------------------------------
--- Single quotes --------------------------------------------------------------
--------------------------------------------------------------------------------

test('single quotes: basic', function()
  eq_list(tokenise("'foo bar'"), { "'foo bar'" })
end)

test('single quotes: multiple', function()
  eq_list(tokenise("'foo' 'bar'"), { "'foo'", "'bar'" })
end)

test('single quotes: glued to unquoted', function()
  eq_list(tokenise("foo'bar baz'qux"), { "foo'bar baz'qux" })
end)

test('single quotes: empty string', function()
  eq_list(tokenise("''"), { "''" })
end)

test('single quotes: empty with following token', function()
  eq_list(tokenise("'' foo"), { "''", 'foo' })
end)

--------------------------------------------------------------------------------
--- Double quotes --------------------------------------------------------------
--------------------------------------------------------------------------------

test('double quotes: basic', function()
  eq_list(tokenise('"foo bar"'), { '"foo bar"' })
end)

test('double quotes: multiple', function()
  eq_list(tokenise('"foo" "bar"'), { '"foo"', '"bar"' })
end)

test('double quotes: glued to unquoted', function()
  eq_list(tokenise('foo"bar baz"qux'), { 'foo"bar baz"qux' })
end)

test('double quotes: empty string', function()
  eq_list(tokenise('""'), { '""' })
end)

test('double quotes: empty with following token', function()
  eq_list(tokenise('"" foo'), { '""', 'foo' })
end)

--------------------------------------------------------------------------------
--- Escapes inside double quotes -----------------------------------------------
--------------------------------------------------------------------------------

test('double quotes escape: escaped quote', function()
  eq_list(tokenise('"foo\\"bar"'), { '"foo\\"bar"' })
end)

test('double quotes escape: escaped backslash', function()
  eq_list(tokenise('"foo\\\\bar"'), { '"foo\\\\bar"' })
end)

test('double quotes escape: multiple escaped quotes', function()
  eq_list(tokenise('"foo\\"bar\\"baz"'), { '"foo\\"bar\\"baz"' })
end)

--------------------------------------------------------------------------------
--- Backslash outside quotes ---------------------------------------------------
--------------------------------------------------------------------------------

test('backslash: escaped space', function()
  eq_list(tokenise('foo\\ bar'), { 'foo\\ bar' })
end)

test('backslash: escaped backslash', function()
  eq_list(tokenise('foo\\\\bar'), { 'foo\\\\bar' })
end)

test('backslash: escaped quote', function()
  eq_list(tokenise('foo\\"bar'), { 'foo\\"bar' })
end)

test('backslash: escaped single quote at start', function()
  eq_list(tokenise("\\'foo"), { "\\'foo" })
end)

--------------------------------------------------------------------------------
--- POSIX single quote escape idiom --------------------------------------------
--------------------------------------------------------------------------------

test('posix escape: basic', function()
  eq_list(tokenise("'foo'\\''bar'"), { "'foo'\\''bar'" })
end)

test('posix escape: contraction', function()
  eq_list(tokenise("'it'\\''s a test'"), { "'it'\\''s a test'" })
end)

test('posix escape: multiple escapes', function()
  eq_list(tokenise("'foo'\\''bar'\\''baz'"), { "'foo'\\''bar'\\''baz'" })
end)

test('posix escape: with surrounding tokens', function()
  eq_list(tokenise("-e 'foo'\\''bar' path/"), { '-e', "'foo'\\''bar'", 'path/' })
end)

-- Mixed quotes

test('mixed: single and double', function()
  eq_list(tokenise([[foo 'bar baz' "qux quux"]]), { 'foo', "'bar baz'", '"qux quux"' })
end)

test('mixed: double inside single', function()
  eq_list(tokenise([[foo'"bar"']]), { [[foo'"bar"']] })
end)

test('mixed: single inside double', function()
  eq_list(tokenise([[foo"'bar'"]]), { [[foo"'bar'"]] })
end)

--------------------------------------------------------------------------------
--- Unterminated quotes --------------------------------------------------------
--------------------------------------------------------------------------------

test('unterminated: single quote', function()
  eq_list(tokenise("'foo bar"), { "'foo bar" })
end)

test('unterminated: double quote', function()
  eq_list(tokenise('"foo bar'), { '"foo bar' })
end)

test('unterminated: with preceding token', function()
  eq_list(tokenise("foo 'bar"), { 'foo', "'bar" })
end)

-- TODO: ???
-- test('edge: unterminated string', function()
--   -- Best effort: treat as pattern anyway
--   eq(select_rg_pattern({ "'hello", 'world' }), "'hello world")
-- end)

--------------------------------------------------------------------------------
--- Real-world ripgrep examples ------------------------------------------------
--------------------------------------------------------------------------------

test('rg: simple with flags', function()
  eq_list(tokenise("-i 'hello world' src/"), { '-i', "'hello world'", 'src/' })
end)

test('rg: glob with equals', function()
  eq_list(tokenise('--glob="*.lua" pattern'), { '--glob="*.lua"', 'pattern' })
end)

test('rg: multiple -e flags', function()
  eq_list(tokenise('-e "foo bar" -e baz'), { '-e', '"foo bar"', '-e', 'baz' })
end)

test('rg: complex command', function()
  eq_list(
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
  eq_list(
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
  eq_list(
    tokenise("-e 'foo' -e \"bar\" baz"),
    { '-e', "'foo'", '-e', '"bar"', 'baz' }
  )
end)

test('rg: regexp with equals', function()
  eq_list(tokenise('--regexp="foo.*bar" path/'), { '--regexp="foo.*bar"', 'path/' })
end)

test('rg: glued option value', function()
  eq_list(tokenise('-e"foo bar"'), { '-e"foo bar"' })
end)

test('rg: double-dash sentinel', function()
  eq_list(tokenise('-- -pattern-starting-with-dash'), { '--', '-pattern-starting-with-dash' })
end)

test('rg: option with double-quoted value containing spaces', function()
  eq_list(tokenise('--regexp="foo bar"'), { '--regexp="foo bar"' })
end)

test('rg: option with single-quoted value containing spaces', function()
  eq_list(tokenise("--color --regexp='foo bar'"), { '--color', "--regexp='foo bar'" })
end)

-- =============================================================================
-- Summary
-- =============================================================================

h.summary()
