-- Run with:
--   nvim --headless -c "set rtp+=." -c "luafile tests/args/unquoter_test.lua" -c "q"

local h = require('tests.harness')
local test = h.test
local eq = h.eq
local deep_eq = h.deep_eq
local unquoter = require('brook.args.unquoter')
local posix_unquote = unquoter.posix_unquote
local posix_unquote_all = unquoter.posix_unquote_all

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

test('double: backslash-backslash preserved (not collapsed)', function()
  eq(posix_unquote('"foo\\\\bar"'), 'foo\\\\bar')
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

test('rg: double and single quotes agree on \\( \\$ (regression)', function()
  eq(posix_unquote('"myPhpFunction\\(\\$"'), 'myPhpFunction\\(\\$')
  eq(posix_unquote("'myPhpFunction\\(\\$'"), 'myPhpFunction\\(\\$')
end)

test('rg: quoted options and flags, double-quoted pattern option (outer)', function()
  deep_eq(
    posix_unquote_all({ "'-e=\"more data\"'", "'-w'", '--vimgrep', '"--max-columns=300"', '--max-columns-preview', "'--color=never'" }),
    { '-e="more data"', '-w', '--vimgrep', '--max-columns=300', '--max-columns-preview', '--color=never' }
  )
end)

test('rg: quoted options and flags, double-quoted pattern option (inner)', function()
  deep_eq(
    posix_unquote_all({ "-e='\"more data\"'", "'-w'", '--vimgrep', '"--max-columns=300"', '--max-columns-preview', "'--color=never'" }),
    { '-e="more data"', '-w', '--vimgrep', '--max-columns=300', '--max-columns-preview', '--color=never' }
  )
end)

test('rg: quoted options and flags, single-quoted pattern option', function()
  deep_eq(
    posix_unquote_all({ "-e='more data'", "'-w'", '--vimgrep', '"--max-columns=300"', '--max-columns-preview', "'--color=never'" }),
    { '-e=more data', '-w', '--vimgrep', '--max-columns=300', '--max-columns-preview', '--color=never' }
  )
end)

--------------------------------------------------------------------------------
--- Double quotes (default/literal mode): $ and ` are never shell escapes ------
--------------------------------------------------------------------------------
--- Brook never spawns a shell, so \$ and \` have no interpolation to guard
--- against. Unlike POSIX, a backslash before them is preserved literally
--- (same as \( or \n), so ripgrep sees exactly what the user typed.

test('double: backslash-dollar passes through literally', function()
  eq(posix_unquote('"foo\\$bar"'), 'foo\\$bar')
end)

test('double: backslash-backtick passes through literally', function()
  eq(posix_unquote('"foo\\`bar"'), 'foo\\`bar')
end)

test('double: unescaped dollar sign preserved', function()
  eq(posix_unquote('"foo$bar"'), 'foo$bar')
end)

test('double: unescaped backtick preserved', function()
  eq(posix_unquote('"foo`bar"'), 'foo`bar')
end)

--------------------------------------------------------------------------------
--- strict_posix_quoting mode ---------------------------------------------------
--------------------------------------------------------------------------------
--- Opt-in mode that reproduces full POSIX shell semantics, so a command
--- copied from (or destined for) a real shell round-trips exactly -- at the
--- cost of reintroducing the \$/\`-swallowing surprise for regex patterns.

test('strict: escaped dollar sign is swallowed, like a real shell', function()
  eq(posix_unquote('"foo\\$bar"', true), 'foo$bar')
end)

test('strict: escaped backtick is swallowed, like a real shell', function()
  eq(posix_unquote('"foo\\`bar"', true), 'foo`bar')
end)

test('strict: escaped backslash collapses, like a real shell', function()
  eq(posix_unquote('"foo\\\\bar"', true), 'foo\\bar')
end)

test('strict: escaped double quote still works', function()
  eq(posix_unquote('"say \\"hello\\""', true), 'say "hello"')
end)

test('strict: unrecognised escape still passes through', function()
  eq(posix_unquote('"foo\\nbar"', true), 'foo\\nbar')
end)

test('strict: single quotes are unaffected by the flag', function()
  eq(posix_unquote("'myPhpFunction\\(\\$'", true), 'myPhpFunction\\(\\$')
end)

test('strict: reproduces the real-shell divergence between quote styles', function()
  -- This is the documented, intentional trade-off of strict mode: unlike
  -- the default literal mode, double and single quotes disagree here,
  -- exactly as bash/zsh would for `rg "myPhpFunction\(\$"` vs `rg 'myPhpFunction\(\$'`.
  eq(posix_unquote('"myPhpFunction\\(\\$"', true), 'myPhpFunction\\($')
  eq(posix_unquote("'myPhpFunction\\(\\$'", true), 'myPhpFunction\\(\\$')
end)

test('strict: posix_unquote_all threads the flag through', function()
  deep_eq(
    posix_unquote_all({ '"foo\\$bar"', "'baz\\$qux'" }, true),
    { 'foo$bar', 'baz\\$qux' }
  )
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
