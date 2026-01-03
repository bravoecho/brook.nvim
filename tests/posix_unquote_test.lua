-- Run with:
--   nvim --headless -c "luafile tests/posix_unquote_test.lua" -c "q"

local h = require('tests.harness')
local test = h.test
local eq = h.eq
local deep_eq = h.deep_eq
local posix_unquote = require('brook.posix_unquote').posix_unquote
local posix_unquote_all = require('brook.posix_unquote').posix_unquote_all

--------------------------------------------------------------------------------
--- Unquoted input -------------------------------------------------------------
--------------------------------------------------------------------------------

test('unquoted: simple word', function()
  eq(posix_unquote('hello'), 'hello')
end)

test('unquoted: empty string', function()
  eq(posix_unquote(''), '')
end)

test('unquoted: with hyphens', function()
  eq(posix_unquote('--word-regexp'), '--word-regexp')
end)

test('unquoted: path-like', function()
  eq(posix_unquote('src/lib/foo.lua'), 'src/lib/foo.lua')
end)

--------------------------------------------------------------------------------
--- Single quotes --------------------------------------------------------------
--------------------------------------------------------------------------------

test('single: basic', function()
  eq(posix_unquote("'hello world'"), 'hello world')
end)

test('single: empty', function()
  eq(posix_unquote("''"), '')
end)

test('single: preserves double quotes inside', function()
  eq(posix_unquote("'say \"hello\"'"), 'say "hello"')
end)

test('single: preserves backslashes (no escapes in single quotes)', function()
  eq(posix_unquote("'foo\\nbar'"), 'foo\\nbar')
end)

test('single: preserves dollar signs', function()
  eq(posix_unquote("'$HOME'"), '$HOME')
end)

--------------------------------------------------------------------------------
--- Double quotes --------------------------------------------------------------
--------------------------------------------------------------------------------

test('double: basic', function()
  eq(posix_unquote('"hello world"'), 'hello world')
end)

test('double: empty', function()
  eq(posix_unquote('""'), '')
end)

test('double: preserves single quotes inside', function()
  eq(posix_unquote('"it\'s"'), "it's")
end)

test('double: escaped double quote', function()
  eq(posix_unquote('"say \\"hello\\""'), 'say "hello"')
end)

test('double: escaped backslash', function()
  eq(posix_unquote('"foo\\\\bar"'), 'foo\\bar')
end)

test('double: unrecognised escape passes through', function()
  -- In POSIX shells, \n inside double quotes is just \n (backslash + n)
  eq(posix_unquote('"foo\\nbar"'), 'foo\\nbar')
end)

--------------------------------------------------------------------------------
--- Backslash escapes outside quotes -------------------------------------------
--------------------------------------------------------------------------------

test('backslash: escaped space', function()
  eq(posix_unquote('foo\\ bar'), 'foo bar')
end)

test('backslash: escaped backslash', function()
  eq(posix_unquote('foo\\\\bar'), 'foo\\bar')
end)

test('backslash: escaped single quote', function()
  eq(posix_unquote("\\'hello"), "'hello")
end)

test('backslash: escaped double quote', function()
  eq(posix_unquote('\\"hello'), '"hello')
end)

test('backslash: lone escaped single quote', function()
  eq(posix_unquote("\\'"), "'")
end)

test('backslash: lone escaped double quote', function()
  eq(posix_unquote('\\"'), '"')
end)

--------------------------------------------------------------------------------
--- POSIX single quote escape idiom --------------------------------------------
--------------------------------------------------------------------------------

test('posix idiom: basic', function()
  -- 'foo'\''bar' means: 'foo' + escaped single quote + 'bar'
  eq(posix_unquote("'foo'\\''bar'"), "foo'bar")
end)

test('posix idiom: contraction', function()
  eq(posix_unquote("'it'\\''s a test'"), "it's a test")
end)

test('posix idiom: multiple escapes', function()
  eq(posix_unquote("'don'\\''t won'\\''t'"), "don't won't")
end)

--------------------------------------------------------------------------------
--- Mixed quoting --------------------------------------------------------------
--------------------------------------------------------------------------------

test('mixed: single then double', function()
  eq(posix_unquote("'foo'\"bar\""), 'foobar')
end)

test('mixed: double then single', function()
  eq(posix_unquote("\"foo\"'bar'"), 'foobar')
end)

test('mixed: unquoted and quoted', function()
  eq(posix_unquote("foo'bar baz'qux"), 'foobar bazqux')
end)

test('mixed: complex', function()
  eq(posix_unquote("hello' world '\"!\""), 'hello world !')
end)

--------------------------------------------------------------------------------
--- Real-world ripgrep patterns ------------------------------------------------
--------------------------------------------------------------------------------

test('rg: simple quoted pattern', function()
  eq(posix_unquote("'hello world'"), 'hello world')
end)

test('rg: regex with special chars', function()
  eq(posix_unquote("'foo.*bar'"), 'foo.*bar')
end)

test('rg: escaped parens (for literal search)', function()
  eq(posix_unquote("'Fatal\\(err\\)'"), 'Fatal\\(err\\)')
end)

test('rg: glob pattern', function()
  eq(posix_unquote("'*.lua'"), '*.lua')
end)

test('rg: pattern with pipe', function()
  eq(posix_unquote("'foo|bar'"), 'foo|bar')
end)

test('rg: escaped double quotes', function()
  eq(posix_unquote([["\.password-.+?(\"|')\)"]]), [[\.password-.+?("|')\)]])
end)

test('rg: quoted options and flags, double-quoted pattern option', function()
  deep_eq(
    posix_unquote_all({ "'-e=\"more data\"'", "'-w'", '--vimgrep', '"--max-columns=300"', '--max-columns-preview', "'--color=never'" }),
    { '-e="more data"', '-w', '--vimgrep', '--max-columns=300', '--max-columns-preview', '--color=never' }
  )
end)

test('rg: quoted options and flags, single-quoted pattern option', function()
  deep_eq(
    posix_unquote_all({ "-e='more data'", "'-w'", '--vimgrep', '"--max-columns=300"', '--max-columns-preview', "'--color=never'" }),
    { "-e='more data'", '-w', '--vimgrep', '--max-columns=300', '--max-columns-preview', '--color=never' }
  )
end)

--------------------------------------------------------------------------------
--- POSIX double-quote escapes ($ and `) --------------------------------------
--------------------------------------------------------------------------------

test('double: escaped dollar sign', function()
  eq(posix_unquote('"foo\\$bar"'), 'foo$bar')
end)

test('double: escaped backtick', function()
  eq(posix_unquote('"foo\\`bar"'), 'foo`bar')
end)

test('double: unescaped dollar sign preserved', function()
  eq(posix_unquote('"foo$bar"'), 'foo$bar')
end)

test('double: unescaped backtick preserved', function()
  eq(posix_unquote('"foo`bar"'), 'foo`bar')
end)

--------------------------------------------------------------------------------
--- Edge cases -----------------------------------------------------------------
--------------------------------------------------------------------------------

test('edge: unterminated single quote returns nil', function()
  eq(posix_unquote("'hello"), nil)
end)

test('edge: unterminated double quote returns nil', function()
  eq(posix_unquote('"hello'), nil)
end)

test('edge: trailing backslash returns nil', function()
  eq(posix_unquote('foo\\'), nil)
end)

test('edge: only quotes', function()
  eq(posix_unquote("''\"\""), '')
end)

test('edge: lone single quote returns nil', function()
  eq(posix_unquote("'"), nil)
end)

test('edge: lone double quote returns nil', function()
  eq(posix_unquote('"'), nil)
end)

test('edge: lone backslash returns nil', function()
  eq(posix_unquote('\\'), nil)
end)

--------------------------------------------------------------------------------
--- Summary --------------------------------------------------------------------
--------------------------------------------------------------------------------

h.summary()
