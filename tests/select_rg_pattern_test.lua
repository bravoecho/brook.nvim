-- Run with:
--   nvim --headless -c "luafile tests/select_rg_pattern_test.lua" -c "q"

local h = require('tests.harness')
local test = h.test
local eq_list = h.eq_list
local select_rg_pattern = require('brook.select_rg_pattern')._select_rg_pattern

--------------------------------------------------------------------------------
--- Simple cases (no options, no paths) ----------------------------------------
--------------------------------------------------------------------------------

test('simple: single unquoted pattern', function()
  eq_list(select_rg_pattern({ 'hello' }), { 'hello' })
end)

test('simple: single-quoted pattern', function()
  eq_list(select_rg_pattern({ "'hello world'" }), { 'hello world' })
end)

test('simple: double-quoted pattern', function()
  eq_list(select_rg_pattern({ '"hello world"' }), { 'hello world' })
end)

test('simple: empty token list', function()
  eq_list(select_rg_pattern({}), nil)
end)

--------------------------------------------------------------------------------
--- Flags (boolean options) ----------------------------------------------------
--------------------------------------------------------------------------------

test('flag: pattern immediately after boolean flag', function()
  eq_list(select_rg_pattern({ '--hidden', 'pattern' }), { 'pattern' })
end)

test('flag: pattern after multiple boolean flags', function()
  eq_list(select_rg_pattern({ '-i', '-w', 'pattern' }), { 'pattern' })
end)

test('flag: pattern after combined short flags', function()
  -- rg allows -iw as shorthand for -i -w
  eq_list(select_rg_pattern({ '-iw', 'pattern' }), { 'pattern' })
end)

--------------------------------------------------------------------------------
--- Stacked short options (flags + options with attached values) ---------------
--------------------------------------------------------------------------------

test('stacked: flags then -e with attached value', function()
  eq_list(select_rg_pattern({ '-wefoo' }), { 'foo' })
end)

test('stacked: flags then -e with attached value, plus path', function()
  eq_list(select_rg_pattern({ '-wefoo', 'src/' }), { 'foo' })
end)

test('stacked: multiple -e in separate stacks', function()
  eq_list(select_rg_pattern({ '-wefoo', '-ebar' }), { 'foo', 'bar' })
end)

test('stacked: option with attached value (not -e)', function()
  eq_list(select_rg_pattern({ '-g*.lua', 'pattern' }), { 'pattern' })
end)

test('stacked: flags then option with attached value', function()
  eq_list(select_rg_pattern({ '-wg*.lua', 'pattern' }), { 'pattern' })
end)

test('flag: single flag before pattern', function()
  eq_list(select_rg_pattern({ '--word-regexp', 'pattern' }), { 'pattern' })
end)

test('flag: multiple flags before pattern', function()
  eq_list(select_rg_pattern({ '--word-regexp', '--fixed-strings', 'pattern' }), { 'pattern' })
end)

test('flag: short flag before pattern', function()
  eq_list(select_rg_pattern({ '-w', 'pattern' }), { 'pattern' })
end)

--------------------------------------------------------------------------------
--- Options (with values) ------------------------------------------------------
--------------------------------------------------------------------------------

test('option: flag with = value before pattern', function()
  eq_list(select_rg_pattern({ '--color=never', 'pattern' }), { 'pattern' })
end)

test('option: flag with separate value before pattern', function()
  eq_list(select_rg_pattern({ '-g', '*.lua', '--word-regexp', 'pattern' }), { 'pattern' })
end)

test('option: quoted option value before pattern', function()
  eq_list(select_rg_pattern({ '-g', "'*.lua'", '--word-regexp', "'my pattern'" }), { 'my pattern' })
end)

test('option: --glob=quoted-value before pattern', function()
  eq_list(select_rg_pattern({ "--glob='*.lua'", 'pattern' }), { 'pattern' })
end)

test('option: -g=quoted-value before pattern', function()
  eq_list(select_rg_pattern({ "-g='*.lua'", 'pattern' }), { 'pattern' })
end)

test('option: multiple options with values', function()
  eq_list(select_rg_pattern({ '-t', 'go', '-g', '!vendor/', 'pattern' }), { 'pattern' })
end)

--------------------------------------------------------------------------------
--- Pattern with paths after it ------------------------------------------------
--------------------------------------------------------------------------------

test('path: unquoted pattern with path', function()
  eq_list(select_rg_pattern({ 'pattern', 'src/lib' }), { 'pattern' })
end)

test('path: quoted pattern with path', function()
  eq_list(select_rg_pattern({ "'my pattern'", 'src/lib' }), { 'my pattern' })
end)

test('path: pattern with multiple paths', function()
  eq_list(select_rg_pattern({ 'pattern', 'src/', 'lib/', 'tests/' }), { 'pattern' })
end)

test('path: pattern with path containing spaces', function()
  eq_list(select_rg_pattern({ 'pattern', 'a/path/in side/the/repo' }), { 'pattern' })
end)

--------------------------------------------------------------------------------
--- Full command: options, pattern, and paths ----------------------------------
--------------------------------------------------------------------------------

test('full: options, pattern, path', function()
  eq_list(select_rg_pattern({ '--word-regexp', 'pattern', 'src/' }), { 'pattern' })
end)

test('full: multiple options, quoted pattern, path', function()
  eq_list(select_rg_pattern({ '-w', '--fixed-strings', "'my pattern'", 'src/' }), { 'my pattern' })
end)

test('full: complex command with quoted pattern', function()
  local tokens = {
    '-g', "'*.lua'", '--color=never', '--word-regexp', '--fixed-strings',
    "'my-special (pattern|here)'", 'a/path/in side/the/repo'
  }
  eq_list(select_rg_pattern(tokens), { 'my-special (pattern|here)' })
end)

test('full: option with value as last named arg before pattern', function()
  local tokens = { '-g', "'*.go'", "'flags\\(\\)'", './go/termcol/' }
  eq_list(select_rg_pattern(tokens), { 'flags\\(\\)' })
end)

--------------------------------------------------------------------------------
--- Double-dash separator ------------------------------------------------------
--------------------------------------------------------------------------------

test('double-dash: separates options from positional args', function()
  local tokens = { '-g', "'*.go'", '--', "'flags\\(\\)'", './go/termcol/' }
  eq_list(select_rg_pattern(tokens), { 'flags\\(\\)' })
end)

test('double-dash: pattern that looks like a flag', function()
  eq_list(select_rg_pattern({ '--', '--not-a-flag' }), { '--not-a-flag' })
end)

test('double-dash: pattern that looks like short option', function()
  eq_list(select_rg_pattern({ '--', '-e' }), { '-e' })
end)

test('double-dash: pattern that looks like option with value', function()
  eq_list(select_rg_pattern({ '--', '-g=*.lua' }), { '-g=*.lua' })
end)

test('double-dash: options before, flag-like pattern after', function()
  eq_list(select_rg_pattern({ '-i', '--', '--word-regexp' }), { '--word-regexp' })
end)

test('double-dash: path that looks like option', function()
  eq_list(select_rg_pattern({ 'pattern', '--', '-weird-dir/' }), { 'pattern' })
end)

test('double-dash: empty after separator', function()
  eq_list(select_rg_pattern({ '-i', '--' }), nil)
end)

--------------------------------------------------------------------------------
--- Unknown named arguments ----------------------------------------------------
--------------------------------------------------------------------------------

test('unknown: lone unknown long option treated as pattern', function()
  eq_list(select_rg_pattern({ '--foobar' }), nil)
end)

test('unknown: unknown option followed by path', function()
  eq_list(select_rg_pattern({ '--foobar', 'src/' }), nil)
end)

test('unknown: known options before unknown, with path', function()
  eq_list(select_rg_pattern({ '-i', '--foobar', 'src/' }), nil)
end)

test('unknown: unknown option not immediately before pattern is ignored', function()
  -- --foobar is unknown but not adjacent to pattern, so ignored
  eq_list(select_rg_pattern({ '--foobar', '-i', 'pattern' }), nil)
end)

test('unknown: unknown option immediately before pattern acts as flag', function()
  -- --foobar is unknown but immediately before pattern candidate
  eq_list(select_rg_pattern({ '-i', '--foobar', 'pattern' }), nil)
end)

test('unknown: unknown short option treated as pattern', function()
  eq_list(select_rg_pattern({ '-Z' }), nil)
end)

--------------------------------------------------------------------------------
--- No pattern identifiable ----------------------------------------------------
--------------------------------------------------------------------------------

test('no-pattern: only flags', function()
  eq_list(select_rg_pattern({ '-i', '-w', '--hidden' }), nil)
end)

test('no-pattern: option expecting value at end', function()
  eq_list(select_rg_pattern({ '-i', '-g' }), nil)
end)

test('no-pattern: only options with values', function()
  eq_list(select_rg_pattern({ '-g', '*.lua', '-t', 'go' }), nil)
end)

--------------------------------------------------------------------------------
--- Late options (options after positional arguments) --------------------------
--------------------------------------------------------------------------------

test('late-option: flag after pattern', function()
  eq_list(select_rg_pattern({ 'pattern', '-i' }), { 'pattern' })
end)

test('late-option: flag after pattern and path', function()
  eq_list(select_rg_pattern({ 'pattern', 'src/', '-w' }), { 'pattern' })
end)

test('late-option: option with value after pattern', function()
  eq_list(select_rg_pattern({ 'pattern', '-g', '*.lua' }), { 'pattern' })
end)

test('late-option: option with value after pattern and path', function()
  eq_list(select_rg_pattern({ 'pattern', 'src/', '-t', 'go' }), { 'pattern' })
end)

test('late-option: multiple late options', function()
  eq_list(select_rg_pattern({ 'pattern', 'src/', '-i', '-w', '-t', 'lua' }), { 'pattern' })
end)

--------------------------------------------------------------------------------
--- Special: -e / --regexp (explicit pattern specification) --------------------
--------------------------------------------------------------------------------

-- -e with separate value
test('regexp: -e with separate unquoted value', function()
  eq_list(select_rg_pattern({ '-e', 'pattern' }), { 'pattern' })
end)

test('regexp: -e with separate quoted value', function()
  eq_list(select_rg_pattern({ '-e', "'my pattern'" }), { 'my pattern' })
end)

test('regexp: -e with value and path', function()
  eq_list(select_rg_pattern({ '-e', 'pattern', 'src/' }), { 'pattern' })
end)

test('regexp: -e with options before', function()
  eq_list(select_rg_pattern({ '-i', '-w', '-e', 'pattern' }), { 'pattern' })
end)

test('regexp: -e with options before and after', function()
  eq_list(select_rg_pattern({ '-i', '-e', 'pattern', '-w' }), { 'pattern' })
end)

-- -e with = syntax
test('regexp: -e=value syntax', function()
  eq_list(select_rg_pattern({ '-e=pattern' }), { 'pattern' })
end)

test('regexp: -e=quoted-value syntax', function()
  eq_list(select_rg_pattern({ "-e='my pattern'" }), { 'my pattern' })
end)

test('regexp: -e=value with other options', function()
  eq_list(select_rg_pattern({ '-i', '-e=pattern', 'src/' }), { 'pattern' })
end)

-- -e with attached value (no separator)
test('regexp: -evalue syntax (attached)', function()
  eq_list(select_rg_pattern({ '-epattern' }), { 'pattern' })
end)

test('regexp: -e with attached quoted value', function()
  eq_list(select_rg_pattern({ "-e'my pattern'" }), { 'my pattern' })
end)

test('regexp: -evalue with other options and path', function()
  eq_list(select_rg_pattern({ '-i', '-epattern', 'src/' }), { 'pattern' })
end)

-- --regexp variants
test('regexp: --regexp with separate value', function()
  eq_list(select_rg_pattern({ '--regexp', 'pattern' }), { 'pattern' })
end)

test('regexp: --regexp=value syntax', function()
  eq_list(select_rg_pattern({ '--regexp=pattern' }), { 'pattern' })
end)

test('regexp: --regexp with quoted value', function()
  eq_list(select_rg_pattern({ '--regexp', "'foo bar'" }), { 'foo bar' })
end)

test('regexp: --regexp=quoted-value syntax', function()
  eq_list(select_rg_pattern({ "--regexp='foo bar'" }), { 'foo bar' })
end)

-- Multiple -e patterns (OR semantics in ripgrep)
test('regexp: multiple -e returns array of patterns', function()
  eq_list(select_rg_pattern({ '-e', 'foo', '-e', 'bar' }), { 'foo', 'bar' })
end)

test('regexp: multiple -e with various syntaxes', function()
  eq_list(select_rg_pattern({ '-efoo', '-e=bar', '-e', 'baz' }), { 'foo', 'bar', 'baz' })
end)

test('regexp: multiple --regexp patterns', function()
  eq_list(select_rg_pattern({ '--regexp=foo', '--regexp', 'bar' }), { 'foo', 'bar' })
end)

test('regexp: mixed -e and --regexp', function()
  eq_list(select_rg_pattern({ '-e', 'foo', '--regexp=bar' }), { 'foo', 'bar' })
end)

test('regexp: -e with other options interspersed', function()
  eq_list(select_rg_pattern({ '-e', 'foo', '-i', '-e', 'bar', '-w' }), { 'foo', 'bar' })
end)

-- -e takes precedence over positional pattern
test('regexp: -e pattern ignores positional pattern-like args', function()
  -- When -e is used, positional args are paths, not patterns
  eq_list(select_rg_pattern({ '-e', 'foo', 'bar', 'src/' }), { 'foo' })
end)

--------------------------------------------------------------------------------
--- Quoted patterns: edge cases ------------------------------------------------
--------------------------------------------------------------------------------

test('quotes: pattern with escaped single quote inside double quotes', function()
  eq_list(select_rg_pattern({ '"it\'s"' }), { "it's" })
end)

test('quotes: pattern with double quote inside single quotes', function()
  eq_list(select_rg_pattern({ "'say \"hello\"'" }), { 'say "hello"' })
end)

test('quotes: empty quoted string', function()
  eq_list(select_rg_pattern({ "''" }), { '' })
end)

test('quotes: empty double-quoted string', function()
  eq_list(select_rg_pattern({ '""' }), { '' })
end)

--------------------------------------------------------------------------------
--- Edge cases -----------------------------------------------------------------
--------------------------------------------------------------------------------

test('edge: pattern that looks like a path', function()
  eq_list(select_rg_pattern({ 'src/lib/foo' }), { 'src/lib/foo' })
end)

test('edge: pattern containing dashes but not an option', function()
  eq_list(select_rg_pattern({ 'my-pattern-here' }), { 'my-pattern-here' })
end)

test('edge: pattern starting with dash needs -- separator', function()
  -- Without --, this is ambiguous - known limitation
  eq_list(select_rg_pattern({ '-pattern' }), nil)
end)

test('edge: pattern with special regex characters', function()
  eq_list(select_rg_pattern({ 'foo.*bar' }), { 'foo.*bar' })
end)

test('edge: quoted pattern with special regex characters', function()
  eq_list(select_rg_pattern({ "'(foo|bar)+'" }), { '(foo|bar)+' })
end)

test('edge: single quote character alone', function()
  -- Malformed input: unterminated quote
  eq_list(select_rg_pattern({ "'" }), nil)
end)

test('edge: single dash alone', function()
  -- Single dash typically means stdin in Unix tools
  eq_list(select_rg_pattern({ '-' }), { '-' })
end)

test('edge: pattern is a number', function()
  eq_list(select_rg_pattern({ '42' }), { '42' })
end)

test('edge: pattern is a dot', function()
  eq_list(select_rg_pattern({ '.' }), { '.' })
end)

--------------------------------------------------------------------------------
--- Real-world usage patterns --------------------------------------------------
--------------------------------------------------------------------------------

test('real-world: typical code search with type filter', function()
  eq_list(select_rg_pattern({ '-t', 'go', '-w', 'func', './cmd/' }), { 'func' })
end)

test('real-world: case-insensitive fixed string', function()
  eq_list(select_rg_pattern({ '-iF', 'TODO:', 'src/' }), { 'TODO:' })
end)

test('real-world: hidden files with type filter', function()
  eq_list(select_rg_pattern({ '--hidden', '-t', 'lua', 'require' }), { 'require' })
end)

test('real-world: word boundary search', function()
  eq_list(select_rg_pattern({ '-w', 'error', 'src/', 'lib/' }), { 'error' })
end)

test('real-world: glob exclusion with pattern', function()
  eq_list(select_rg_pattern({ '-g', '!*.test.js', 'describe', 'src/' }), { 'describe' })
end)

test('real-world: multiline search', function()
  eq_list(select_rg_pattern({ '-U', "'func.*\\n.*return'" }), { 'func.*\\n.*return' })
end)

test('real-world: context lines with pattern', function()
  eq_list(select_rg_pattern({ '-C', '3', 'TODO', 'src/' }), { 'TODO' })
end)

test('real-world: pcre2 regex', function()
  eq_list(select_rg_pattern({ '-P', "'(?<=func )\\w+'" }), { '(?<=func )\\w+' })
end)

--------------------------------------------------------------------------------
--- Summary --------------------------------------------------------------------
--------------------------------------------------------------------------------

h.summary()
