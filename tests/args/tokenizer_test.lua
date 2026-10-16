-- Run with:
--   nvim --headless -c "set rtp+=." -c "luafile tests/args/tokenizer_test.lua" -c "q"

local h = require('tests.harness')
local test = h.test
local deep_eq = h.deep_eq
local raw_tokenize = require('brook.args.tokenizer').tokenize
local Types = require('brook.args.types')

-- quoting defaults to literal mode when omitted, so most tests below don't
-- need to care about it; tests exercising strict_posix pass it explicitly.
local function tokenize(qargs, quoting)
  return raw_tokenize(qargs, quoting or Types.quoting.literal)
end

--------------------------------------------------------------------------------
--- Empty input ----------------------------------------------------------------
--------------------------------------------------------------------------------

test('empty: empty string', function()
  deep_eq(tokenize(''), {})
end)

test('empty: only spaces', function()
  deep_eq(tokenize('   '), {})
end)

test('empty: only tabs', function()
  deep_eq(tokenize('\t\t'), {})
end)

--------------------------------------------------------------------------------
--- Basic splitting ------------------------------------------------------------
--------------------------------------------------------------------------------

test('basic: simple words', function()
  deep_eq(tokenize('foo bar baz'), { 'foo', 'bar', 'baz' })
end)

test('basic: leading and trailing spaces', function()
  deep_eq(tokenize('  foo   bar  '), { 'foo', 'bar' })
end)

test('basic: tab separator', function()
  deep_eq(tokenize('foo\tbar'), { 'foo', 'bar' })
end)

test('basic: mixed whitespace', function()
  deep_eq(tokenize('foo \t  bar'), { 'foo', 'bar' })
end)

--------------------------------------------------------------------------------
--- Single quotes --------------------------------------------------------------
--------------------------------------------------------------------------------

test('single quotes: basic', function()
  deep_eq(tokenize("'foo bar'"), { "'foo bar'" })
end)

test('single quotes: multiple', function()
  deep_eq(tokenize("'foo' 'bar'"), { "'foo'", "'bar'" })
end)

test('single quotes: glued to unquoted', function()
  deep_eq(tokenize("foo'bar baz'qux"), { "foo'bar baz'qux" })
end)

test('single quotes: empty string', function()
  deep_eq(tokenize("''"), { "''" })
end)

test('single quotes: empty with following token', function()
  deep_eq(tokenize("'' foo"), { "''", 'foo' })
end)

--------------------------------------------------------------------------------
--- Escapes inside single quotes ------------------------------------------------
--------------------------------------------------------------------------------

test('single quotes escape: escaped quote does not close the token', function()
  deep_eq(tokenize("'it\\'s a test'"), { "'it\\'s a test'" })
end)

test('single quotes escape: escaped backslash', function()
  deep_eq(tokenize("'foo\\\\bar'"), { "'foo\\\\bar'" })
end)

test('single quotes escape: multiple escaped quotes', function()
  deep_eq(tokenize("'foo\\'bar\\'baz'"), { "'foo\\'bar\\'baz'" })
end)

test('single quotes escape: strict mode closes the quote early, unlike default mode', function()
  -- The tokenizer only finds *word* boundaries (splits on unquoted
  -- whitespace) and never rejects input -- it has no notion of "malformed".
  -- In strict mode the backslash isn't an escape inside single quotes, so
  -- the quote here closes right after "it\", "s" glues onto that same word
  -- (no whitespace separates them, same rule as the "glued to unquoted"
  -- tests above), then "a" and "test'" are their own words. The final
  -- token, "test'", opens an unmatched quote and is still emitted as-is --
  -- the tokenizer doesn't notice or care.
  --
  -- It's unquote (in unquoter.lua), not the tokenizer, that walks
  -- these tokens afterwards and detects the unterminated quote, returning
  -- nil for the whole command. See "strict: full pipeline rejects the
  -- default-mode idiom, like a real shell" in unquoter_test.lua for that
  -- end-to-end behaviour.
  deep_eq(tokenize("'it\\'s a test'", Types.quoting.strict_posix), { "'it\\'s", 'a', "test'" })
end)

--------------------------------------------------------------------------------
--- Double quotes --------------------------------------------------------------
--------------------------------------------------------------------------------

test('double quotes: basic', function()
  deep_eq(tokenize('"foo bar"'), { '"foo bar"' })
end)

test('double quotes: multiple', function()
  deep_eq(tokenize('"foo" "bar"'), { '"foo"', '"bar"' })
end)

test('double quotes: glued to unquoted', function()
  deep_eq(tokenize('foo"bar baz"qux'), { 'foo"bar baz"qux' })
end)

test('double quotes: empty string', function()
  deep_eq(tokenize('""'), { '""' })
end)

test('double quotes: empty with following token', function()
  deep_eq(tokenize('"" foo'), { '""', 'foo' })
end)

--------------------------------------------------------------------------------
--- Escapes inside double quotes -----------------------------------------------
--------------------------------------------------------------------------------

test('double quotes escape: escaped quote', function()
  deep_eq(tokenize('"foo\\"bar"'), { '"foo\\"bar"' })
end)

test('double quotes escape: escaped backslash', function()
  deep_eq(tokenize('"foo\\\\bar"'), { '"foo\\\\bar"' })
end)

test('double quotes escape: multiple escaped quotes', function()
  deep_eq(tokenize('"foo\\"bar\\"baz"'), { '"foo\\"bar\\"baz"' })
end)

--------------------------------------------------------------------------------
--- Backslash outside quotes ---------------------------------------------------
--------------------------------------------------------------------------------

test('backslash: escaped space', function()
  deep_eq(tokenize('foo\\ bar'), { 'foo\\ bar' })
end)

test('backslash: escaped backslash', function()
  deep_eq(tokenize('foo\\\\bar'), { 'foo\\\\bar' })
end)

test('backslash: escaped quote', function()
  deep_eq(tokenize('foo\\"bar'), { 'foo\\"bar' })
end)

test('backslash: escaped single quote at start', function()
  deep_eq(tokenize("\\'foo"), { "\\'foo" })
end)

--------------------------------------------------------------------------------
--- POSIX single quote escape idiom --------------------------------------------
--------------------------------------------------------------------------------

test('posix escape: basic', function()
  deep_eq(tokenize("'foo'\\''bar'"), { "'foo'\\''bar'" })
end)

test('posix escape: contraction', function()
  deep_eq(tokenize("'it'\\''s a test'"), { "'it'\\''s a test'" })
end)

test('posix escape: multiple escapes', function()
  deep_eq(tokenize("'foo'\\''bar'\\''baz'"), { "'foo'\\''bar'\\''baz'" })
end)

test('posix escape: with surrounding tokens', function()
  deep_eq(tokenize("-e 'foo'\\''bar' path/"), { '-e', "'foo'\\''bar'", 'path/' })
end)

-- Mixed quotes

test('mixed: single and double', function()
  deep_eq(tokenize([[foo 'bar baz' "qux quux"]]), { 'foo', "'bar baz'", '"qux quux"' })
end)

test('mixed: double inside single', function()
  deep_eq(tokenize([[foo'"bar"']]), { [[foo'"bar"']] })
end)

test('mixed: single inside double', function()
  deep_eq(tokenize([[foo"'bar'"]]), { [[foo"'bar'"]] })
end)

--------------------------------------------------------------------------------
--- Unterminated quotes --------------------------------------------------------
--------------------------------------------------------------------------------

test('unterminated: single quote', function()
  deep_eq(tokenize("'foo bar"), { "'foo bar" })
end)

test('unterminated: double quote', function()
  deep_eq(tokenize('"foo bar'), { '"foo bar' })
end)

test('unterminated: with preceding token', function()
  deep_eq(tokenize("foo 'bar"), { 'foo', "'bar" })
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
  deep_eq(tokenize("-i 'hello world' src/"), { '-i', "'hello world'", 'src/' })
end)

test('rg: glob with equals', function()
  deep_eq(tokenize('--glob="*.lua" pattern'), { '--glob="*.lua"', 'pattern' })
end)

test('rg: multiple -e flags', function()
  deep_eq(tokenize('-e "foo bar" -e baz'), { '-e', '"foo bar"', '-e', 'baz' })
end)

test('rg: complex command', function()
  deep_eq(
    tokenize("rg -i 'foo bar' --glob '*.txt' src/"),
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
    tokenize("rg -i 'foo bar' --glob '*.txt' src/ second\\ src"),
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
    tokenize("-e 'foo' -e \"bar\" baz"),
    { '-e', "'foo'", '-e', '"bar"', 'baz' }
  )
end)

test('rg: regexp with equals', function()
  deep_eq(tokenize('--regexp="foo.*bar" path/'), { '--regexp="foo.*bar"', 'path/' })
end)

test('rg: glued option value', function()
  deep_eq(tokenize('-e"foo bar"'), { '-e"foo bar"' })
end)

test('rg: double-dash sentinel', function()
  deep_eq(tokenize('-- -pattern-starting-with-dash'), { '--', '-pattern-starting-with-dash' })
end)

test('rg: option with double-quoted value containing spaces', function()
  deep_eq(tokenize('--regexp="foo bar"'), { '--regexp="foo bar"' })
end)

test('rg: option with single-quoted value containing spaces', function()
  deep_eq(tokenize("--color --regexp='foo bar'"), { '--color', "--regexp='foo bar'" })
end)

test('rg: quoted options and flags', function()
  deep_eq(
    tokenize("'-e=\"more data\"' '-w' --vimgrep \"--max-columns=300\" --max-columns-preview '--color=never'"),
    { "'-e=\"more data\"'", "'-w'", '--vimgrep', '"--max-columns=300"', '--max-columns-preview', "'--color=never'" }
  )
end)

-- =============================================================================
-- Summary
-- =============================================================================

h.summary()
