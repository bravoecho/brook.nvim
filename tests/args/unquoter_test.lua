-- Run with:
--   nvim --headless -c "set rtp+=." -c "luafile tests/args/unquoter_test.lua" -c "q"

local h = require('tests.harness')
local test = h.test
local eq = h.eq
local deep_eq = h.deep_eq
local unquoter = require('brook.args.unquoter')
local tokenise = require('brook.args.tokeniser').tokenise
local Types = require('brook.args.types')

-- quoting defaults to literal mode when omitted, so most tests below don't
-- need to care about it; tests exercising strict_posix pass it explicitly.
local function unquote(token, quoting)
  return unquoter.unquote(token, quoting or Types.quoting.literal)
end
local function unquote_all(tokens, quoting)
  return unquoter.unquote_all(tokens, quoting or Types.quoting.literal)
end

--------------------------------------------------------------------------------
--- Unquoted input -------------------------------------------------------------
--------------------------------------------------------------------------------

test('unquoted: simple word', function()
  eq(unquote('hello'), 'hello')
end)

test('unquoted: empty string', function()
  eq(unquote(''), '')
end)

test('unquoted: with hyphens', function()
  eq(unquote('--word-regexp'), '--word-regexp')
end)

test('unquoted: path-like', function()
  eq(unquote('src/lib/foo.lua'), 'src/lib/foo.lua')
end)

--------------------------------------------------------------------------------
--- Single quotes --------------------------------------------------------------
--------------------------------------------------------------------------------

test('single: basic', function()
  eq(unquote("'hello world'"), 'hello world')
end)

test('single: empty', function()
  eq(unquote("''"), '')
end)

test('single: preserves double quotes inside', function()
  eq(unquote("'say \"hello\"'"), 'say "hello"')
end)

test('single: escaped single quote', function()
  eq(unquote("'it\\'s'"), "it's")
end)

test('single: unrecognised escape passes through', function()
  eq(unquote("'foo\\nbar'"), 'foo\\nbar')
end)

test('single: backslash-backslash preserved (not collapsed)', function()
  eq(unquote("'foo\\\\bar'"), 'foo\\\\bar')
end)

test('single: preserves dollar signs', function()
  eq(unquote("'$HOME'"), '$HOME')
end)

--------------------------------------------------------------------------------
--- Double quotes --------------------------------------------------------------
--------------------------------------------------------------------------------

test('double: basic', function()
  eq(unquote('"hello world"'), 'hello world')
end)

test('double: empty', function()
  eq(unquote('""'), '')
end)

test('double: preserves single quotes inside', function()
  eq(unquote('"it\'s"'), "it's")
end)

test('double: escaped double quote', function()
  eq(unquote('"say \\"hello\\""'), 'say "hello"')
end)

test('double: backslash-backslash preserved (not collapsed)', function()
  eq(unquote('"foo\\\\bar"'), 'foo\\\\bar')
end)

test('double: unrecognised escape passes through', function()
  -- In POSIX shells, \n inside double quotes is just \n (backslash + n)
  eq(unquote('"foo\\nbar"'), 'foo\\nbar')
end)

--------------------------------------------------------------------------------
--- Backslash escapes outside quotes -------------------------------------------
--------------------------------------------------------------------------------

test('backslash: escaped space', function()
  eq(unquote('foo\\ bar'), 'foo bar')
end)

test('backslash: escaped backslash', function()
  eq(unquote('foo\\\\bar'), 'foo\\bar')
end)

test('backslash: escaped single quote', function()
  eq(unquote("\\'hello"), "'hello")
end)

test('backslash: escaped double quote', function()
  eq(unquote('\\"hello'), '"hello')
end)

test('backslash: lone escaped single quote', function()
  eq(unquote("\\'"), "'")
end)

test('backslash: lone escaped double quote', function()
  eq(unquote('\\"'), '"')
end)

--------------------------------------------------------------------------------
--- POSIX single quote escape idiom --------------------------------------------
--------------------------------------------------------------------------------
--- This idiom (closing, escaping a quote outside the quotes, then reopening)
--- still works in the default mode, though \' inside the quotes achieves the
--- same result more directly. It remains the only way to embed a literal
--- single quote in `quoting_mode = 'posix'`, see below.

test('posix idiom: basic', function()
  -- 'foo'\''bar' means: 'foo' + escaped single quote + 'bar'
  eq(unquote("'foo'\\''bar'"), "foo'bar")
end)

test('posix idiom: contraction', function()
  eq(unquote("'it'\\''s a test'"), "it's a test")
end)

test('posix idiom: multiple escapes', function()
  eq(unquote("'don'\\''t won'\\''t'"), "don't won't")
end)

--------------------------------------------------------------------------------
--- Mixed quoting --------------------------------------------------------------
--------------------------------------------------------------------------------

test('mixed: single then double', function()
  eq(unquote("'foo'\"bar\""), 'foobar')
end)

test('mixed: double then single', function()
  eq(unquote("\"foo\"'bar'"), 'foobar')
end)

test('mixed: unquoted and quoted', function()
  eq(unquote("foo'bar baz'qux"), 'foobar bazqux')
end)

test('mixed: complex', function()
  eq(unquote("hello' world '\"!\""), 'hello world !')
end)

--------------------------------------------------------------------------------
--- Real-world ripgrep patterns ------------------------------------------------
--------------------------------------------------------------------------------

test('rg: simple quoted pattern', function()
  eq(unquote("'hello world'"), 'hello world')
end)

test('rg: regex with special chars', function()
  eq(unquote("'foo.*bar'"), 'foo.*bar')
end)

test('rg: escaped parens (for literal search)', function()
  eq(unquote("'Fatal\\(err\\)'"), 'Fatal\\(err\\)')
end)

test('rg: glob pattern', function()
  eq(unquote("'*.lua'"), '*.lua')
end)

test('rg: pattern with pipe', function()
  eq(unquote("'foo|bar'"), 'foo|bar')
end)

test('rg: escaped double quotes', function()
  eq(unquote([["\.password-.+?(\"|')\)"]]), [[\.password-.+?("|')\)]])
end)

test('rg: double and single quotes agree on \\( \\$ (regression)', function()
  eq(unquote('"myPhpFunction\\(\\$"'), 'myPhpFunction\\(\\$')
  eq(unquote("'myPhpFunction\\(\\$'"), 'myPhpFunction\\(\\$')
end)

test('rg: quoted options and flags, double-quoted pattern option (outer)', function()
  deep_eq(
    unquote_all({ "'-e=\"more data\"'", "'-w'", '--vimgrep', '"--max-columns=300"', '--max-columns-preview', "'--color=never'" }),
    { '-e="more data"', '-w', '--vimgrep', '--max-columns=300', '--max-columns-preview', '--color=never' }
  )
end)

test('rg: quoted options and flags, double-quoted pattern option (inner)', function()
  deep_eq(
    unquote_all({ "-e='\"more data\"'", "'-w'", '--vimgrep', '"--max-columns=300"', '--max-columns-preview', "'--color=never'" }),
    { '-e="more data"', '-w', '--vimgrep', '--max-columns=300', '--max-columns-preview', '--color=never' }
  )
end)

test('rg: quoted options and flags, single-quoted pattern option', function()
  deep_eq(
    unquote_all({ "-e='more data'", "'-w'", '--vimgrep', '"--max-columns=300"', '--max-columns-preview', "'--color=never'" }),
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
  eq(unquote('"foo\\$bar"'), 'foo\\$bar')
end)

test('double: backslash-backtick passes through literally', function()
  eq(unquote('"foo\\`bar"'), 'foo\\`bar')
end)

test('double: unescaped dollar sign preserved', function()
  eq(unquote('"foo$bar"'), 'foo$bar')
end)

test('double: unescaped backtick preserved', function()
  eq(unquote('"foo`bar"'), 'foo`bar')
end)

--------------------------------------------------------------------------------
--- quoting_mode = 'posix' -------------------------------------------------------
--------------------------------------------------------------------------------
--- Opt-in mode that reproduces full POSIX shell semantics, so a command
--- copied from (or destined for) a real shell round-trips exactly -- at the
--- cost of reintroducing the \$/\`-swallowing surprise for regex patterns,
--- and losing the ability to escape a quote from inside single quotes.

test('strict: escaped dollar sign is swallowed, like a real shell', function()
  eq(unquote('"foo\\$bar"', Types.quoting.strict_posix), 'foo$bar')
end)

test('strict: escaped backtick is swallowed, like a real shell', function()
  eq(unquote('"foo\\`bar"', Types.quoting.strict_posix), 'foo`bar')
end)

test('strict: escaped backslash collapses, like a real shell', function()
  eq(unquote('"foo\\\\bar"', Types.quoting.strict_posix), 'foo\\bar')
end)

test('strict: escaped double quote still works', function()
  eq(unquote('"say \\"hello\\""', Types.quoting.strict_posix), 'say "hello"')
end)

test('strict: unrecognised escape still passes through', function()
  eq(unquote('"foo\\nbar"', Types.quoting.strict_posix), 'foo\\nbar')
end)

test('strict: single quotes with no quote characters are unaffected by the mode', function()
  eq(unquote("'myPhpFunction\\(\\$'", Types.quoting.strict_posix), 'myPhpFunction\\(\\$')
end)

test('strict: no escapes at all inside single quotes, unlike the default mode', function()
  eq(unquote("'foo\\$bar'", Types.quoting.strict_posix), 'foo\\$bar')
end)

test('strict: the default mode\'s \\\' escape idiom is malformed instead (unterminated quote)', function()
  eq(unquote("'it\\'s'", Types.quoting.strict_posix), nil)
end)

test('strict: full pipeline rejects the default-mode idiom, like a real shell', function()
  -- 'it\'s a test' relies on the default mode's \' escape to stay one word.
  -- tokenise() and unquote() have distinct jobs: the tokeniser only
  -- finds word boundaries and never rejects anything by itself -- see
  -- "single quotes escape: strict mode closes the quote early, unlike
  -- default mode" in tokeniser_test.lua, which shows it happily emits
  -- { "'it\'s", "a", "test'" } even though the last token's quote never
  -- closes. It's unquote, called here on each of those tokens, that
  -- notices the dangling quote and returns nil -- so the two stages
  -- cooperate to reject this input end-to-end, exactly as `rg 'it\'s a
  -- test'` would be rejected by an actual shell.
  local input = "'it\\'s a test'"
  eq(unquote_all(tokenise(input, Types.quoting.strict_posix), Types.quoting.strict_posix), nil)
  -- The same input parses fine in the default (non-strict) mode.
  eq(unquote_all(tokenise(input, Types.quoting.literal), Types.quoting.literal)[1], "it's a test")
end)

test('strict: reproduces the real-shell divergence between quote styles', function()
  -- This is the documented, intentional trade-off of strict mode: unlike
  -- the default literal mode, double and single quotes disagree here,
  -- exactly as bash/zsh would for `rg "myPhpFunction\(\$"` vs `rg 'myPhpFunction\(\$'`.
  eq(unquote('"myPhpFunction\\(\\$"', Types.quoting.strict_posix), 'myPhpFunction\\($')
  eq(unquote("'myPhpFunction\\(\\$'", Types.quoting.strict_posix), 'myPhpFunction\\(\\$')
end)

test('strict: unquote_all threads quoting through', function()
  deep_eq(
    unquote_all({ '"foo\\$bar"', "'baz\\$qux'" }, Types.quoting.strict_posix),
    { 'foo$bar', 'baz\\$qux' }
  )
end)

--------------------------------------------------------------------------------
--- Edge cases -----------------------------------------------------------------
--------------------------------------------------------------------------------

test('edge: unterminated single quote returns nil', function()
  eq(unquote("'hello"), nil)
end)

test('edge: unterminated double quote returns nil', function()
  eq(unquote('"hello'), nil)
end)

test('edge: trailing backslash returns nil', function()
  eq(unquote('foo\\'), nil)
end)

test('edge: only quotes', function()
  eq(unquote("''\"\""), '')
end)

test('edge: lone single quote returns nil', function()
  eq(unquote("'"), nil)
end)

test('edge: lone double quote returns nil', function()
  eq(unquote('"'), nil)
end)

test('edge: lone backslash returns nil', function()
  eq(unquote('\\'), nil)
end)

--------------------------------------------------------------------------------
--- Summary --------------------------------------------------------------------
--------------------------------------------------------------------------------

h.summary()
