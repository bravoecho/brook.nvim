-- Run with:
--   nvim --headless -c "luafile tests/shell_unquote_test.lua" -c "q"

local h = require('tests.harness')
local test = h.test
local eq = h.eq
local shell_unquote = require('brook.shell_unquote')._shell_unquote

--------------------------------------------------------------------------------
--- Unquoted input -------------------------------------------------------------
--------------------------------------------------------------------------------

test('unquoted: simple word', function()
  eq(shell_unquote('hello'), 'hello')
end)

test('unquoted: empty string', function()
  eq(shell_unquote(''), '')
end)

test('unquoted: with hyphens', function()
  eq(shell_unquote('--word-regexp'), '--word-regexp')
end)

test('unquoted: path-like', function()
  eq(shell_unquote('src/lib/foo.lua'), 'src/lib/foo.lua')
end)

--------------------------------------------------------------------------------
--- Single quotes --------------------------------------------------------------
--------------------------------------------------------------------------------

test('single: basic', function()
  eq(shell_unquote("'hello world'"), 'hello world')
end)

test('single: empty', function()
  eq(shell_unquote("''"), '')
end)

test('single: preserves double quotes inside', function()
  eq(shell_unquote("'say \"hello\"'"), 'say "hello"')
end)

test('single: preserves backslashes (no escapes in single quotes)', function()
  eq(shell_unquote("'foo\\nbar'"), 'foo\\nbar')
end)

test('single: preserves dollar signs', function()
  eq(shell_unquote("'$HOME'"), '$HOME')
end)

--------------------------------------------------------------------------------
--- Double quotes --------------------------------------------------------------
--------------------------------------------------------------------------------

test('double: basic', function()
  eq(shell_unquote('"hello world"'), 'hello world')
end)

test('double: empty', function()
  eq(shell_unquote('""'), '')
end)

test('double: preserves single quotes inside', function()
  eq(shell_unquote('"it\'s"'), "it's")
end)

test('double: escaped double quote', function()
  eq(shell_unquote('"say \\"hello\\""'), 'say "hello"')
end)

test('double: escaped backslash', function()
  eq(shell_unquote('"foo\\\\bar"'), 'foo\\bar')
end)

test('double: unrecognised escape passes through', function()
  -- In POSIX shells, \n inside double quotes is just \n (backslash + n)
  eq(shell_unquote('"foo\\nbar"'), 'foo\\nbar')
end)

--------------------------------------------------------------------------------
--- Backslash escapes outside quotes -------------------------------------------
--------------------------------------------------------------------------------

test('backslash: escaped space', function()
  eq(shell_unquote('foo\\ bar'), 'foo bar')
end)

test('backslash: escaped backslash', function()
  eq(shell_unquote('foo\\\\bar'), 'foo\\bar')
end)

test('backslash: escaped single quote', function()
  eq(shell_unquote("\\'hello"), "'hello")
end)

test('backslash: escaped double quote', function()
  eq(shell_unquote('\\"hello'), '"hello')
end)

test('backslash: lone escaped single quote', function()
  eq(shell_unquote("\\'"), "'")
end)

test('backslash: lone escaped double quote', function()
  eq(shell_unquote('\\"'), '"')
end)

--------------------------------------------------------------------------------
--- POSIX single quote escape idiom --------------------------------------------
--------------------------------------------------------------------------------

test('posix idiom: basic', function()
  -- 'foo'\''bar' means: 'foo' + escaped single quote + 'bar'
  eq(shell_unquote("'foo'\\''bar'"), "foo'bar")
end)

test('posix idiom: contraction', function()
  eq(shell_unquote("'it'\\''s a test'"), "it's a test")
end)

test('posix idiom: multiple escapes', function()
  eq(shell_unquote("'don'\\''t won'\\''t'"), "don't won't")
end)

--------------------------------------------------------------------------------
--- Mixed quoting --------------------------------------------------------------
--------------------------------------------------------------------------------

test('mixed: single then double', function()
  eq(shell_unquote("'foo'\"bar\""), 'foobar')
end)

test('mixed: double then single', function()
  eq(shell_unquote("\"foo\"'bar'"), 'foobar')
end)

test('mixed: unquoted and quoted', function()
  eq(shell_unquote("foo'bar baz'qux"), 'foobar bazqux')
end)

test('mixed: complex', function()
  eq(shell_unquote("hello' world '\"!\""), 'hello world !')
end)

--------------------------------------------------------------------------------
--- Real-world ripgrep patterns ------------------------------------------------
--------------------------------------------------------------------------------

test('rg: simple quoted pattern', function()
  eq(shell_unquote("'hello world'"), 'hello world')
end)

test('rg: regex with special chars', function()
  eq(shell_unquote("'foo.*bar'"), 'foo.*bar')
end)

test('rg: escaped parens (for literal search)', function()
  eq(shell_unquote("'Fatal\\(err\\)'"), 'Fatal\\(err\\)')
end)

test('rg: glob pattern', function()
  eq(shell_unquote("'*.lua'"), '*.lua')
end)

test('rg: pattern with pipe', function()
  eq(shell_unquote("'foo|bar'"), 'foo|bar')
end)

test('rg: escaped double quotes', function()
  eq(shell_unquote([["\.password-.+?(\"|')\)"]]), [[\.password-.+?("|')\)]])
end)

--------------------------------------------------------------------------------
--- POSIX double-quote escapes ($ and `) --------------------------------------
--------------------------------------------------------------------------------

test('double: escaped dollar sign', function()
  eq(shell_unquote('"foo\\$bar"'), 'foo$bar')
end)

test('double: escaped backtick', function()
  eq(shell_unquote('"foo\\`bar"'), 'foo`bar')
end)

test('double: unescaped dollar sign preserved', function()
  eq(shell_unquote('"foo$bar"'), 'foo$bar')
end)

test('double: unescaped backtick preserved', function()
  eq(shell_unquote('"foo`bar"'), 'foo`bar')
end)

--------------------------------------------------------------------------------
--- Edge cases -----------------------------------------------------------------
--------------------------------------------------------------------------------

test('edge: unterminated single quote returns nil', function()
  eq(shell_unquote("'hello"), nil)
end)

test('edge: unterminated double quote returns nil', function()
  eq(shell_unquote('"hello'), nil)
end)

test('edge: trailing backslash returns nil', function()
  eq(shell_unquote('foo\\'), nil)
end)

test('edge: only quotes', function()
  eq(shell_unquote("''\"\""), '')
end)

test('edge: lone single quote returns nil', function()
  eq(shell_unquote("'"), nil)
end)

test('edge: lone double quote returns nil', function()
  eq(shell_unquote('"'), nil)
end)

test('edge: lone backslash returns nil', function()
  eq(shell_unquote('\\'), nil)
end)

--------------------------------------------------------------------------------
--- Summary --------------------------------------------------------------------
--------------------------------------------------------------------------------

h.summary()
