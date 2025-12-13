-- Run with:
--   nvim --headless -c "luafile tests/categorise_args_test.lua" -c "q"

local h = require('tests.harness')
local test = h.test
local deep_eq = h.deep_eq
local categorise_args = require('brook.categorise_args')._categorise_args

--------------------------------------------------------------------------------
--- Simple cases (no options, no paths) ----------------------------------------
--------------------------------------------------------------------------------

test('simple: single unquoted pattern', function()
  deep_eq(
    categorise_args({ 'hello' }),
    { patterns = { 'hello' }, word = false, fixed = false }
  )
end)

test('simple: single-quoted pattern', function()
  deep_eq(
    categorise_args({ "'hello world'" }),
    { patterns = { 'hello world' }, word = false, fixed = false }
  )
end)

test('simple: double-quoted pattern', function()
  deep_eq(categorise_args({ '"hello world"' }), {
    patterns = { 'hello world' },
    word = false,
    fixed = false,
  })
end)

test('simple: empty token list', function()
  deep_eq(categorise_args({}), nil)
end)

--------------------------------------------------------------------------------
--- Flags (boolean options) ----------------------------------------------------
--------------------------------------------------------------------------------

test('flag: pattern immediately after boolean flag', function()
  deep_eq(
    categorise_args({ '--hidden', 'pattern' }),
    { patterns = { 'pattern' }, word = false, fixed = false }
  )
end)

test('flag: pattern after multiple boolean flags', function()
  deep_eq(
    categorise_args({ '-i', '-H', 'pattern' }),
    { patterns = { 'pattern' }, word = false, fixed = false }
  )
end)

test('flag: pattern after combined short flags', function()
  -- rg allows -iw as shorthand for -i -H
  deep_eq(categorise_args({ '-iH', 'pattern' }), {
    patterns = { 'pattern' },
    word = false,
    fixed = false,
  })
end)

--------------------------------------------------------------------------------
--- Stacked short options (flags + options with attached values) ---------------
--------------------------------------------------------------------------------

test('stacked: flags then -e with attached value', function()
  deep_eq(
    categorise_args({ '-Hefoo' }),
    { patterns = { 'foo' }, word = false, fixed = false }
  )
end)

test('stacked: flags then -e with attached value, plus path', function()
  deep_eq(categorise_args({ '-Hefoo', 'src/' }), {
    patterns = { 'foo' },
    word = false,
    fixed = false,
  })
end)

test('stacked: multiple -e in separate stacks', function()
  deep_eq(
    categorise_args({ '-Hefoo', '-ebar' }),
    { patterns = { 'foo', 'bar' }, word = false, fixed = false }
  )
end)

test('stacked: option with attached value (not -e)', function()
  deep_eq(categorise_args({ '-g*.lua', 'pattern' }), {
    patterns = { 'pattern' },
    word = false,
    fixed = false,
  })
end)

test('stacked: flags then option with attached value', function()
  deep_eq(
    categorise_args({ '-Hg*.lua', 'pattern' }),
    { patterns = { 'pattern' }, word = false, fixed = false }
  )
end)

test('flag: single flag before pattern', function()
  deep_eq(
    categorise_args({ '--hidden', 'pattern' }),
    { patterns = { 'pattern' }, word = false, fixed = false }
  )
end)

test('flag: multiple flags before pattern', function()
  deep_eq(
    categorise_args({ '--hidden', '--smart-case', 'pattern' }),
    { patterns = { 'pattern' }, word = false, fixed = false }
  )
end)

test('flag: short flag before pattern', function()
  deep_eq(
    categorise_args({ '-H', 'pattern' }),
    { patterns = { 'pattern' }, word = false, fixed = false }
  )
end)

--------------------------------------------------------------------------------
--- Options (with values) ------------------------------------------------------
--------------------------------------------------------------------------------

test('option: flag with = value before pattern', function()
  deep_eq(
    categorise_args({ '--color=never', 'pattern' }),
    { patterns = { 'pattern' }, word = false, fixed = false }
  )
end)

test('option: flag with separate value before pattern', function()
  deep_eq(
    categorise_args({ '-g', '*.lua', '--hidden', 'pattern' }),
    { patterns = { 'pattern' }, word = false, fixed = false }
  )
end)

test('option: quoted option value before pattern', function()
  deep_eq(
    categorise_args({ '-g', "'*.lua'", '--hidden', "'my pattern'" }),
    { patterns = { 'my pattern' }, word = false, fixed = false }
  )
end)

test('option: --glob=quoted-value before pattern', function()
  deep_eq(
    categorise_args({ "--glob='*.lua'", 'pattern' }),
    { patterns = { 'pattern' }, word = false, fixed = false }
  )
end)

test('option: -g=quoted-value before pattern', function()
  deep_eq(
    categorise_args({ "-g='*.lua'", 'pattern' }),
    { patterns = { 'pattern' }, word = false, fixed = false }
  )
end)

test('option: multiple options with values', function()
  deep_eq(
    categorise_args({ '-t', 'go', '-g', '!vendor/', 'pattern' }),
    { patterns = { 'pattern' }, word = false, fixed = false }
  )
end)

--------------------------------------------------------------------------------
--- Pattern with paths after it ------------------------------------------------
--------------------------------------------------------------------------------

test('path: unquoted pattern with path', function()
  deep_eq(
    categorise_args({ 'pattern', 'src/lib' }),
    { patterns = { 'pattern' }, word = false, fixed = false }
  )
end)

test('path: quoted pattern with path', function()
  deep_eq(
    categorise_args({ "'my pattern'", 'src/lib' }),
    { patterns = { 'my pattern' }, word = false, fixed = false }
  )
end)

test('path: pattern with multiple paths', function()
  deep_eq(
    categorise_args({ 'pattern', 'src/', 'lib/', 'tests/' }),
    { patterns = { 'pattern' }, word = false, fixed = false }
  )
end)

test('path: pattern with path containing spaces', function()
  deep_eq(
    categorise_args({ 'pattern', 'a/path/in side/the/repo' }),
    { patterns = { 'pattern' }, word = false, fixed = false }
  )
end)

--------------------------------------------------------------------------------
--- Full command: options, pattern, and paths ----------------------------------
--------------------------------------------------------------------------------

test('full: options, pattern, path', function()
  deep_eq(
    categorise_args({ '--hidden', 'pattern', 'src/' }),
    { patterns = { 'pattern' }, word = false, fixed = false }
  )
end)

test('full: multiple named args, quoted pattern, path', function()
  deep_eq(
    categorise_args({ '-H', '--vimgrep', "'my pattern'", 'src/' }),
    { patterns = { 'my pattern' }, word = false, fixed = false }
  )
end)

test('full: complex command with quoted pattern', function()
  local tokens = {
    '-g', "'*.lua'", '--color=never', '--ignore-case', '--hidden',
    "'my-special (pattern|here)'", 'a/path/in side/the/repo'
  }
  deep_eq(
    categorise_args(tokens),
    { patterns = { 'my-special (pattern|here)' }, word = false, fixed = false }
  )
end)

test('full: option with value as last named arg before pattern', function()
  local tokens = { '-g', "'*.go'", "'flags\\(\\)'", './go/termcol/' }
  deep_eq(
    categorise_args(tokens),
    { patterns = { 'flags\\(\\)' }, word = false, fixed = false }
  )
end)

--------------------------------------------------------------------------------
--- Double-dash separator ------------------------------------------------------
--------------------------------------------------------------------------------

test('double-dash: separates options from positional args', function()
  local tokens = { '-g', "'*.go'", '--', "'flags\\(\\)'", './go/termcol/' }
  deep_eq(
    categorise_args(tokens),
    { patterns = { 'flags\\(\\)' }, word = false, fixed = false }
  )
end)

test('double-dash: pattern that looks like a flag', function()
  deep_eq(
    categorise_args({ '--', '--not-a-flag' }),
    { patterns = { '--not-a-flag' }, word = false, fixed = false }
  )
end)

test('double-dash: pattern that looks like short option', function()
  deep_eq(
    categorise_args({ '--', '-e' }),
    { patterns = { '-e' }, word = false, fixed = false }
  )
end)

test('double-dash: pattern that looks like option with value', function()
  deep_eq(
    categorise_args({ '--', '-g=*.lua' }),
    { patterns = { '-g=*.lua' }, word = false, fixed = false }
  )
end)

test('double-dash: options before, flag-like pattern after', function()
  deep_eq(
    categorise_args({ '-i', '--', '--word-regexp' }),
    { patterns = { '--word-regexp' }, word = false, fixed = false }
  )
end)

test('double-dash: path that looks like option', function()
  deep_eq(
    categorise_args({ 'pattern', '--', '-weird-dir/' }),
    { patterns = { 'pattern' }, word = false, fixed = false }
  )
end)

test('double-dash: empty after separator', function()
  deep_eq(categorise_args({ '-i', '--' }), nil)
end)

--------------------------------------------------------------------------------
--- Unknown named arguments ----------------------------------------------------
--------------------------------------------------------------------------------

test('unknown: lone unknown long option treated as pattern', function()
  deep_eq(categorise_args({ '--foobar' }), nil)
end)

test('unknown: unknown option followed by path', function()
  deep_eq(categorise_args({ '--foobar', 'src/' }), nil)
end)

test('unknown: known options before unknown, with path', function()
  deep_eq(categorise_args({ '-i', '--foobar', 'src/' }), nil)
end)

test('unknown: unknown option not immediately before pattern is ignored', function()
  -- --foobar is unknown but not adjacent to pattern, so ignored
  deep_eq(categorise_args({ '--foobar', '-i', 'pattern' }), nil)
end)

test('unknown: unknown option immediately before pattern acts as flag', function()
  -- --foobar is unknown but immediately before pattern candidate
  deep_eq(categorise_args({ '-i', '--foobar', 'pattern' }), nil)
end)

test('unknown: unknown short option treated as pattern', function()
  deep_eq(categorise_args({ '-Z' }), nil)
end)

--------------------------------------------------------------------------------
--- No identifiable pattern ----------------------------------------------------
--------------------------------------------------------------------------------

test('no-pattern: only flags', function()
  deep_eq(categorise_args({ '-i', '-H', '--hidden' }), nil)
end)

test('no-pattern: option expecting value at end', function()
  deep_eq(categorise_args({ '-i', '-g' }), nil)
end)

test('no-pattern: only options with values', function()
  deep_eq(categorise_args({ '-g', '*.lua', '-t', 'go' }), nil)
end)

--------------------------------------------------------------------------------
--- Late options (options after positional arguments) --------------------------
--------------------------------------------------------------------------------

test('late-option: flag after pattern', function()
  deep_eq(
    categorise_args({ 'pattern', '-i' }),
    { patterns = { 'pattern' }, word = false, fixed = false }
  )
end)

test('late-option: flag after pattern and path', function()
  deep_eq(
    categorise_args({ 'pattern', 'src/', '-H' }),
    { patterns = { 'pattern' }, word = false, fixed = false }
  )
end)

test('late-option: option with value after pattern', function()
  deep_eq(
    categorise_args({ 'pattern', '-g', '*.lua' }),
    { patterns = { 'pattern' }, word = false, fixed = false }
  )
end)

test('late-option: option with value after pattern and path', function()
  deep_eq(
    categorise_args({ 'pattern', 'src/', '-t', 'go' }),
    { patterns = { 'pattern' }, word = false, fixed = false }
  )
end)

test('late-option: multiple late options', function()
  deep_eq(
    categorise_args({ 'pattern', 'src/', '-i', '-H', '-t', 'lua' }),
    { patterns = { 'pattern' }, word = false, fixed = false }
  )
end)

--------------------------------------------------------------------------------
--- Special: -e / --regexp (explicit pattern specification) --------------------
--------------------------------------------------------------------------------

-- -e with separate value
test('regexp: -e with separate unquoted value', function()
  deep_eq(
    categorise_args({ '-e', 'pattern' }),
    { patterns = { 'pattern' }, word = false, fixed = false }
  )
end)

test('regexp: -e with separate quoted value', function()
  deep_eq(
    categorise_args({ '-e', "'my pattern'" }),
    { patterns = { 'my pattern' }, word = false, fixed = false }
  )
end)

test('regexp: -e with value and path', function()
  deep_eq(
    categorise_args({ '-e', 'pattern', 'src/' }),
    { patterns = { 'pattern' }, word = false, fixed = false }
  )
end)

test('regexp: -e with options before', function()
  deep_eq(
    categorise_args({ '-i', '-H', '-e', 'pattern' }),
    { patterns = { 'pattern' }, word = false, fixed = false }
  )
end)

test('regexp: -e with options before and after', function()
  deep_eq(
    categorise_args({ '-i', '-e', 'pattern', '-H' }),
    { patterns = { 'pattern' }, word = false, fixed = false }
  )
end)

test('regexp: -e=value syntax', function()
  deep_eq(
    categorise_args({ '-e=pattern' }),
    { patterns = { 'pattern' }, word = false, fixed = false }
  )
end)

test('regexp: -e=quoted-value syntax', function()
  deep_eq(
    categorise_args({ "-e='my pattern'" }),
    { patterns = { 'my pattern' }, word = false, fixed = false }
  )
end)

test('regexp: -e=value with other options', function()
  deep_eq(
    categorise_args({ '-i', '-e=pattern', 'src/' }),
    { patterns = { 'pattern' }, word = false, fixed = false }
  )
end)

-- -e with attached value (no separator)
test('regexp: -evalue syntax (attached)', function()
  deep_eq(
    categorise_args({ '-epattern' }),
    { patterns = { 'pattern' }, word = false, fixed = false }
  )
end)

test('regexp: -e with attached quoted value', function()
  deep_eq(
    categorise_args({ "-e'my pattern'" }),
    { patterns = { 'my pattern' }, word = false, fixed = false }
  )
end)

test('regexp: -evalue with other options and path', function()
  deep_eq(
    categorise_args({ '-i', '-epattern', 'src/' }),
    { patterns = { 'pattern' }, word = false, fixed = false }
  )
end)

-- --regexp variants
test('regexp: --regexp with separate value', function()
  deep_eq(
    categorise_args({ '--regexp', 'pattern' }),
    { patterns = { 'pattern' }, word = false, fixed = false }
  )
end)

test('regexp: --regexp=value syntax', function()
  deep_eq(
    categorise_args({ '--regexp=pattern' }),
    { patterns = { 'pattern' }, word = false, fixed = false }
  )
end)

test('regexp: --regexp with quoted value', function()
  deep_eq(
    categorise_args({ '--regexp', "'foo bar'" }),
    { patterns = { 'foo bar' }, word = false, fixed = false }
  )
end)

test('regexp: --regexp=quoted-value syntax', function()
  deep_eq(
    categorise_args({ "--regexp='foo bar'" }),
    { patterns = { 'foo bar' }, word = false, fixed = false }
  )
end)

-- Multiple -e patterns (OR semantics in ripgrep)
test('regexp: multiple -e returns array of patterns', function()
  deep_eq(
    categorise_args({ '-e', 'foo', '-e', 'bar' }),
    { patterns = { 'foo', 'bar' }, word = false, fixed = false }
  )
end)

test('regexp: multiple -e with various syntaxes', function()
  deep_eq(
    categorise_args({ '-efoo', '-e=bar', '-e', 'baz' }),
    { patterns = { 'foo', 'bar', 'baz' }, word = false, fixed = false }
  )
end)

test('regexp: multiple --regexp patterns', function()
  deep_eq(
    categorise_args({ '--regexp=foo', '--regexp', 'bar' }),
    { patterns = { 'foo', 'bar' }, word = false, fixed = false }
  )
end)

test('regexp: mixed -e and --regexp', function()
  deep_eq(
    categorise_args({ '-e', 'foo', '--regexp=bar' }),
    { patterns = { 'foo', 'bar' }, word = false, fixed = false }
  )
end)

test('regexp: -e with other options interspersed', function()
  deep_eq(
    categorise_args({ '-e', 'foo', '-i', '-e', 'bar', '-H' }),
    { patterns = { 'foo', 'bar' }, word = false, fixed = false }
  )
end)

-- -e takes precedence over positional pattern
test('regexp: -e pattern ignores positional pattern-like args', function()
  -- When -e is used, positional args are paths, not patterns
  deep_eq(
    categorise_args({ '-e', 'foo', 'bar', 'src/' }),
    { patterns = { 'foo' }, word = false, fixed = false }
  )
end)

--------------------------------------------------------------------------------
--- Literal search -------------------------------------------------------------
--------------------------------------------------------------------------------

test('literal: args include --fixed-strings', function()
  deep_eq(
    categorise_args({ 'someFunction()', '--fixed-strings' }),
    { patterns = { 'someFunction()' }, word = false, fixed = true }
  )
end)

test('literal: args include -F', function()
  deep_eq(
    categorise_args({ '-F', 'someFunction()' }),
    { patterns = { 'someFunction()' }, word = false, fixed = true }
  )
end)

test('literal: args include a stacked F', function()
  deep_eq(
    categorise_args({ '-LF.', 'someFunction()' }),
    { patterns = { 'someFunction()' }, word = false, fixed = true }
  )
end)

--------------------------------------------------------------------------------
--- Whole-word search ----------------------------------------------------------
--------------------------------------------------------------------------------

test('word: args include --word-regexp', function()
  deep_eq(
    categorise_args({ 'someFunction()', '--word-regexp' }),
    { patterns = { 'someFunction()' }, word = true, fixed = false }
  )
end)

test('word: args include -w', function()
  deep_eq(
    categorise_args({ '-w', 'someFunction()' }),
    { patterns = { 'someFunction()' }, word = true, fixed = false }
  )
end)

test('word: args include a stacked F', function()
  deep_eq(
    categorise_args({ '-Lw.', 'someFunction()' }),
    { patterns = { 'someFunction()' }, word = true, fixed = false }
  )
end)

--------------------------------------------------------------------------------
--- Quoted patterns: edge cases ------------------------------------------------
--------------------------------------------------------------------------------

test('quotes: pattern with escaped single quote inside double quotes', function()
  deep_eq(
    categorise_args({ '"it\'s"' }),
    { patterns = { "it's" }, word = false, fixed = false }
  )
end)

test('quotes: pattern with double quote inside single quotes', function()
  deep_eq(
    categorise_args({ "'say \"hello\"'" }),
    { patterns = { 'say "hello"' }, word = false, fixed = false }
  )
end)

test('quotes: empty quoted string', function()
  deep_eq(
    categorise_args({ "''" }),
    { patterns = { '' }, word = false, fixed = false }
  )
end)

test('quotes: empty double-quoted string', function()
  deep_eq(
    categorise_args({ '""' }),
    { patterns = { '' }, word = false, fixed = false }
  )
end)

--------------------------------------------------------------------------------
--- Edge cases -----------------------------------------------------------------
--------------------------------------------------------------------------------

test('edge: pattern that looks like a path', function()
  deep_eq(
    categorise_args({ 'src/lib/foo' }),
    { patterns = { 'src/lib/foo' }, word = false, fixed = false }
  )
end)

test('edge: pattern containing dashes but not an option', function()
  deep_eq(
    categorise_args({ 'my-pattern-here' }),
    { patterns = { 'my-pattern-here' }, word = false, fixed = false }
  )
end)

test('edge: pattern starting with dash needs -- separator', function()
  -- Without --, this is ambiguous - known limitation
  deep_eq(categorise_args({ '-pattern' }), nil)
end)

test('edge: pattern with special regex characters', function()
  deep_eq(
    categorise_args({ 'foo.*bar' }),
    { patterns = { 'foo.*bar' }, word = false, fixed = false }
  )
end)

test('edge: quoted pattern with special regex characters', function()
  deep_eq(
    categorise_args({ "'(foo|bar)+'" }),
    { patterns = { '(foo|bar)+' }, word = false, fixed = false }
  )
end)

test('edge: single quote character alone', function()
  -- Malformed input: unterminated quote
  deep_eq(categorise_args({ "'" }), nil)
end)

test('edge: single dash alone', function()
  -- Single dash typically means stdin in Unix tools
  deep_eq(
    categorise_args({ '-' }),
    { patterns = { '-' }, word = false, fixed = false }
  )
end)

test('edge: pattern is a number', function()
  deep_eq(
    categorise_args({ '42' }),
    { patterns = { '42' }, word = false, fixed = false }
  )
end)

test('edge: pattern is a dot', function()
  deep_eq(
    categorise_args({ '.' }),
    { patterns = { '.' }, word = false, fixed = false }
  )
end)

--------------------------------------------------------------------------------
--- Real-world usage patterns --------------------------------------------------
--------------------------------------------------------------------------------

test('real-world: typical code search with type filter', function()
  deep_eq(
    categorise_args({ '-t', 'go', '-H', 'func', './cmd/' }),
    { patterns = { 'func' }, word = false, fixed = false }
  )
end)

test('real-world: case-insensitive fixed string', function()
  deep_eq(
    categorise_args({ '-iF', 'TODO:', 'src/' }),
    { patterns = { 'TODO:' }, word = false, fixed = true }
  )
end)

test('real-world: hidden files with type filter', function()
  deep_eq(
    categorise_args({ '--hidden', '-t', 'lua', 'require' }),
    { patterns = { 'require' }, word = false, fixed = false }
  )
end)

test('real-world: word boundary search', function()
  deep_eq(
    categorise_args({ '-w', 'error', 'src/', 'lib/' }),
    { patterns = { 'error' }, word = true, fixed = false }
  )
end)

test('real-world: glob exclusion with pattern', function()
  deep_eq(
    categorise_args({ '-g', '!*.test.js', 'describe', 'src/' }),
    { patterns = { 'describe' }, word = false, fixed = false }
  )
end)

test('real-world: multiline search', function()
  deep_eq(
    categorise_args({ '-U', "'func.*\\n.*return'" }),
    { patterns = { 'func.*\\n.*return' }, word = false, fixed = false }
  )
end)

test('real-world: context lines with pattern', function()
  deep_eq(categorise_args({ '-C', '3', 'TODO', 'src/' }), {
    patterns = { 'TODO' },
    word = false,
    fixed = false,
  })
end)

test('real-world: pcre2 regex', function()
  deep_eq(
    categorise_args({ '-P', "'(?<=func )\\w+'" }),
    { patterns = { '(?<=func )\\w+' }, word = false, fixed = false }
  )
end)

--------------------------------------------------------------------------------
--- Summary --------------------------------------------------------------------
--------------------------------------------------------------------------------

h.summary()
