-- Run with:
--   nvim --headless -c "luafile tests/parse_args_test.lua" -c "q"

local h = require('tests.harness')
local test = h.test
local deep_eq = h.deep_eq
local parse_args = require('brook.parse_args').parse_args

-- NOTE: `parse_args` receives already-unquoted tokens. Shell unquoting
-- behaviour is tested separately in posix_unquote_test.lua.

-- Helper: default result with pattern set
local function result(pattern, overrides)
  local r = {
    pattern = pattern,
    word = false,
    fixed = false,
    case = nil,
    output_format = nil,
    multiline = false,
  }
  if overrides then
    for k, v in pairs(overrides) do
      r[k] = v
    end
  end
  return r
end

-- Helper: empty result (no pattern found)
local function empty_result(overrides)
  return result(nil, overrides)
end

--------------------------------------------------------------------------------
--- Simple cases (no options, no paths) ----------------------------------------
--------------------------------------------------------------------------------

test('simple: single pattern', function()
  deep_eq(parse_args({ 'hello' }), result('hello'))
end)

test('simple: pattern with spaces', function()
  deep_eq(parse_args({ 'hello world' }), result('hello world'))
end)

test('simple: empty token list', function()
  deep_eq(parse_args({}), empty_result())
end)

test('simple: nil token list', function()
  deep_eq(parse_args(nil), empty_result())
end)

--------------------------------------------------------------------------------
--- Flags (boolean options) ----------------------------------------------------
--------------------------------------------------------------------------------

test('flag: pattern immediately after boolean flag', function()
  deep_eq(parse_args({ '--hidden', 'pattern' }), result('pattern'))
end)

test('flag: pattern after multiple boolean flags', function()
  deep_eq(parse_args({ '-v', '-H', 'pattern' }), result('pattern'))
end)

test('flag: pattern after combined short flags', function()
  -- rg allows -iH as shorthand for -i -H
  deep_eq(parse_args({ '-vH', 'pattern' }), result('pattern'))
end)

--------------------------------------------------------------------------------
--- Stacked short options (flags + options with attached values) ---------------
--------------------------------------------------------------------------------

test('stacked: flags then -e with attached value', function()
  deep_eq(parse_args({ '-Hefoo' }), result('foo'))
end)

test('stacked: flags then -e with attached value, plus path', function()
  deep_eq(parse_args({ '-Hefoo', 'src/' }), result('foo'))
end)

test('stacked: multiple -e in separate stacks', function()
  -- Only first pattern is kept
  deep_eq(parse_args({ '-Hefoo', '-ebar' }), result('foo'))
end)

test('stacked: option with attached value (not -e)', function()
  deep_eq(parse_args({ '-g*.lua', 'pattern' }), result('pattern'))
end)

test('stacked: flags then option with attached value', function()
  deep_eq(parse_args({ '-Hg*.lua', 'pattern' }), result('pattern'))
end)

test('flag: single flag before pattern', function()
  deep_eq(parse_args({ '--hidden', 'pattern' }), result('pattern'))
end)

test('flag: multiple flags before pattern', function()
  deep_eq(parse_args({ '--hidden', '--smart-case', 'pattern' }), result('pattern'))
end)

test('flag: short flag before pattern', function()
  deep_eq(parse_args({ '-H', 'pattern' }), result('pattern'))
end)

--------------------------------------------------------------------------------
--- Options (with values) ------------------------------------------------------
--------------------------------------------------------------------------------

test('option: flag with = value before pattern', function()
  deep_eq(parse_args({ '--color=never', 'pattern' }), result('pattern'))
end)

test('option: flag with separate value before pattern', function()
  deep_eq(parse_args({ '-g', '*.lua', '--hidden', 'pattern' }), result('pattern'))
end)

test('option: option value with spaces before pattern', function()
  deep_eq(parse_args({ '-g', '*.lua', '--hidden', 'my pattern' }), result('my pattern'))
end)

test('option: --glob=value before pattern', function()
  deep_eq(parse_args({ '--glob=*.lua', 'pattern' }), result('pattern'))
end)

test('option: -g=value before pattern', function()
  deep_eq(parse_args({ '-g=*.lua', 'pattern' }), result('pattern'))
end)

test('option: multiple options with values', function()
  deep_eq(parse_args({ '-t', 'go', '-g', '!vendor/', 'pattern' }), result('pattern'))
end)

--------------------------------------------------------------------------------
--- Pattern with paths after it ------------------------------------------------
--------------------------------------------------------------------------------

test('path: pattern with path', function()
  deep_eq(parse_args({ 'pattern', 'src/lib' }), result('pattern'))
end)

test('path: pattern with spaces and path', function()
  deep_eq(parse_args({ 'my pattern', 'src/lib' }), result('my pattern'))
end)

test('path: pattern with multiple paths', function()
  deep_eq(parse_args({ 'pattern', 'src/', 'lib/', 'tests/' }), result('pattern'))
end)

test('path: pattern with path containing spaces', function()
  deep_eq(parse_args({ 'pattern', 'a/path/in side/the/repo' }), result('pattern'))
end)

--------------------------------------------------------------------------------
--- Full command: options, pattern, and paths ----------------------------------
--------------------------------------------------------------------------------

test('full: options, pattern, path', function()
  deep_eq(parse_args({ '--hidden', 'pattern', 'src/' }), result('pattern'))
end)

test('full: multiple named args, pattern with spaces, path', function()
  deep_eq(parse_args({ '-H', '--vimgrep', 'my pattern', 'src/' }),
    result('my pattern', { output_format = 'one-line-per-match' }))
end)

test('full: complex command with pattern containing special chars', function()
  local tokens = {
    '-g', '*.lua', '--color=never', '--no-unicode', '--hidden',
    'my-special (pattern|here)', 'a/path/in side/the/repo'
  }
  deep_eq(parse_args(tokens), result('my-special (pattern|here)'))
end)

test('full: option with value as last named arg before pattern', function()
  local tokens = { '-g', '*.go', 'flags\\(\\)', './go/termcol/' }
  deep_eq(parse_args(tokens), result('flags\\(\\)'))
end)

--------------------------------------------------------------------------------
--- Double-dash separator ------------------------------------------------------
--------------------------------------------------------------------------------

test('double-dash: separates options from positional args', function()
  local tokens = { '-g', '*.go', '--', 'flags\\(\\)', './go/termcol/' }
  deep_eq(parse_args(tokens), result('flags\\(\\)'))
end)

test('double-dash: pattern that looks like a flag', function()
  deep_eq(parse_args({ '--', '--not-a-flag' }), result('--not-a-flag'))
end)

test('double-dash: pattern that looks like short option', function()
  deep_eq(parse_args({ '--', '-e' }), result('-e'))
end)

test('double-dash: pattern that looks like option with value', function()
  deep_eq(parse_args({ '--', '-g=*.lua' }), result('-g=*.lua'))
end)

test('double-dash: options before, flag-like pattern after', function()
  deep_eq(parse_args({ '-.', '--', '--word-regexp' }), result('--word-regexp'))
end)

test('double-dash: path that looks like option', function()
  deep_eq(parse_args({ 'pattern', '--', '-weird-dir/' }), result('pattern'))
end)

test('double-dash: empty after separator', function()
  -- No pattern after --, returns empty result
  deep_eq(parse_args({ '-i', '--' }), empty_result({ case = 'case-insensitive' }))
end)

--------------------------------------------------------------------------------
--- Unknown named arguments ----------------------------------------------------
--------------------------------------------------------------------------------

-- Unknown args are now ignored, not treated as errors

test('unknown: lone unknown long option ignored', function()
  deep_eq(parse_args({ '--foobar' }), empty_result())
end)

test('unknown: unknown option followed by path', function()
  -- --foobar is unknown and ignored, 'src/' becomes the pattern
  deep_eq(parse_args({ '--foobar', 'src/' }), result('src/'))
end)

test('unknown: known options before unknown, with path', function()
  deep_eq(parse_args({ '-i', '--foobar', 'src/' }), result('src/', { case = 'case-insensitive' }))
end)

test('unknown: unknown option not immediately before pattern is ignored', function()
  deep_eq(parse_args({ '--foobar', '-i', 'pattern' }), result('pattern', { case = 'case-insensitive' }))
end)

test('unknown: unknown option immediately before pattern is ignored', function()
  deep_eq(parse_args({ '-i', '--foobar', 'pattern' }), result('pattern', { case = 'case-insensitive' }))
end)

test('unknown: unknown short option ignored', function()
  -- -Z is unknown, returned as empty (can't expand unknown stacked args)
  deep_eq(parse_args({ '-Z' }), empty_result())
end)

--------------------------------------------------------------------------------
--- No identifiable pattern ----------------------------------------------------
--------------------------------------------------------------------------------

test('no-pattern: only flags', function()
  deep_eq(parse_args({ '-i', '-H', '--hidden' }), empty_result({ case = 'case-insensitive' }))
end)

test('no-pattern: option expecting value at end', function()
  deep_eq(parse_args({ '-i', '-g' }), empty_result({ case = 'case-insensitive' }))
end)

test('no-pattern: only options with values', function()
  deep_eq(parse_args({ '-g', '*.lua', '-t', 'go' }), empty_result())
end)

--------------------------------------------------------------------------------
--- Late options (options after positional arguments) --------------------------
--------------------------------------------------------------------------------

test('late-option: flag after pattern', function()
  deep_eq(parse_args({ 'pattern', '-L' }), result('pattern'))
end)

test('late-option: flag after pattern and path', function()
  deep_eq(parse_args({ 'pattern', 'src/', '-H' }), result('pattern'))
end)

test('late-option: option with value after pattern', function()
  deep_eq(parse_args({ 'pattern', '-g', '*.lua' }), result('pattern'))
end)

test('late-option: option with value after pattern and path', function()
  deep_eq(parse_args({ 'pattern', 'src/', '-t', 'go' }), result('pattern'))
end)

test('late-option: multiple late options', function()
  deep_eq(parse_args({ 'pattern', 'src/', '-a', '-H', '-t', 'lua' }), result('pattern'))
end)

--------------------------------------------------------------------------------
--- Special: -e / --regexp (explicit pattern specification) --------------------
--------------------------------------------------------------------------------

-- -e with separate value
test('regexp: -e with separate value', function()
  deep_eq(parse_args({ '-e', 'pattern' }), result('pattern'))
end)

test('regexp: -e with value containing spaces', function()
  deep_eq(parse_args({ '-e', 'my pattern' }), result('my pattern'))
end)

test('regexp: -e with value and path', function()
  deep_eq(parse_args({ '-e', 'pattern', 'src/' }), result('pattern'))
end)

test('regexp: -e with options before', function()
  deep_eq(parse_args({ '-v', '-H', '-e', 'pattern' }), result('pattern'))
end)

test('regexp: -e with options before and after', function()
  deep_eq(parse_args({ '-v', '-e', 'pattern', '-H' }), result('pattern'))
end)

test('regexp: -e=value syntax', function()
  deep_eq(parse_args({ '-e=pattern' }), result('pattern'))
end)

test('regexp: -e=value with spaces', function()
  deep_eq(parse_args({ '-e=my pattern' }), result('my pattern'))
end)

test('regexp: -e=value with other options', function()
  deep_eq(parse_args({ '-v', '-e=pattern', 'src/' }), result('pattern'))
end)

-- -e with attached value (no separator)
test('regexp: -evalue syntax (attached)', function()
  deep_eq(parse_args({ '-epattern' }), result('pattern'))
end)

test('regexp: -evalue with other options and path', function()
  deep_eq(parse_args({ '-v', '-epattern', 'src/' }), result('pattern'))
end)

-- --regexp variants
test('regexp: --regexp with separate value', function()
  deep_eq(parse_args({ '--regexp', 'pattern' }), result('pattern'))
end)

test('regexp: --regexp=value syntax', function()
  deep_eq(parse_args({ '--regexp=pattern' }), result('pattern'))
end)

test('regexp: --regexp with value containing spaces', function()
  deep_eq(parse_args({ '--regexp', 'foo bar' }), result('foo bar'))
end)

test('regexp: --regexp=value with spaces', function()
  deep_eq(parse_args({ '--regexp=foo bar' }), result('foo bar'))
end)

-- Multiple -e patterns (only first is kept)
test('regexp: multiple -e returns first pattern only', function()
  deep_eq(parse_args({ '-e', 'foo', '-e', 'bar' }), result('foo'))
end)

test('regexp: multiple -e with various syntaxes returns first', function()
  deep_eq(parse_args({ '-efoo', '-e=bar', '-e', 'baz' }), result('foo'))
end)

test('regexp: multiple --regexp patterns returns first', function()
  deep_eq(parse_args({ '--regexp=foo', '--regexp', 'bar' }), result('foo'))
end)

test('regexp: mixed -e and --regexp returns first', function()
  deep_eq(parse_args({ '-e', 'foo', '--regexp=bar' }), result('foo'))
end)

test('regexp: -e with other options interspersed returns first pattern', function()
  deep_eq(parse_args({ '-e', 'foo', '-v', '-e', 'bar', '-H' }), result('foo'))
end)

-- -e takes precedence over positional pattern
test('regexp: -e pattern ignores positional pattern-like args', function()
  -- When -e is used, positional args are paths, not patterns
  deep_eq(parse_args({ '-e', 'foo', 'bar', 'src/' }), result('foo'))
end)

-- -e without value is tolerated
test('regexp: -e at end without value', function()
  deep_eq(parse_args({ '-e' }), empty_result())
end)

test('regexp: -e at end after options', function()
  deep_eq(parse_args({ '-i', '-e' }), empty_result({ case = 'case-insensitive' }))
end)

--------------------------------------------------------------------------------
--- Literal search -------------------------------------------------------------
--------------------------------------------------------------------------------

test('literal: args include --fixed-strings', function()
  deep_eq(parse_args({ 'someFunction()', '--fixed-strings' }), result('someFunction()', { fixed = true }))
end)

test('literal: args include -F', function()
  deep_eq(parse_args({ '-F', 'someFunction()' }), result('someFunction()', { fixed = true }))
end)

test('literal: args include a stacked F', function()
  deep_eq(parse_args({ '-LF.', 'someFunction()' }), result('someFunction()', { fixed = true }))
end)

--------------------------------------------------------------------------------
--- Whole-word search ----------------------------------------------------------
--------------------------------------------------------------------------------

test('word: args include --word-regexp', function()
  deep_eq(parse_args({ 'someFunction()', '--word-regexp' }), result('someFunction()', { word = true }))
end)

test('word: args include -w', function()
  deep_eq(parse_args({ '-w', 'someFunction()' }), result('someFunction()', { word = true }))
end)

test('word: args include a stacked w', function()
  deep_eq(parse_args({ '-Lw.', 'someFunction()' }), result('someFunction()', { word = true }))
end)

--------------------------------------------------------------------------------
--- Case sensitivity -----------------------------------------------------------
--------------------------------------------------------------------------------

test('case: args include --case-sensitive', function()
  deep_eq(parse_args({ 'pattern', '--case-sensitive' }), result('pattern', { case = 'case-sensitive' }))
end)

test('case: args include -s', function()
  deep_eq(parse_args({ '-s', 'pattern' }), result('pattern', { case = 'case-sensitive' }))
end)

test('case: args include --ignore-case', function()
  deep_eq(parse_args({ 'pattern', '--ignore-case' }), result('pattern', { case = 'case-insensitive' }))
end)

test('case: args include -i', function()
  deep_eq(parse_args({ '-i', 'pattern' }), result('pattern', { case = 'case-insensitive' }))
end)

test('case: args include a stacked s', function()
  deep_eq(parse_args({ '-Hs', 'pattern' }), result('pattern', { case = 'case-sensitive' }))
end)

test('case: args include a stacked i', function()
  deep_eq(parse_args({ '-Hi', 'pattern' }), result('pattern', { case = 'case-insensitive' }))
end)

test('case: last flag wins (-i then -s)', function()
  deep_eq(parse_args({ '-i', '-s', 'pattern' }), result('pattern', { case = 'case-sensitive' }))
end)

test('case: last flag wins (-s then -i)', function()
  deep_eq(parse_args({ '-s', '-i', 'pattern' }), result('pattern', { case = 'case-insensitive' }))
end)

test('case: last flag wins (long form mixed)', function()
  deep_eq(parse_args({ '--ignore-case', '--case-sensitive', '-i', 'pattern' }),
    result('pattern', { case = 'case-insensitive' }))
end)

test('case: unset by default', function()
  deep_eq(parse_args({ 'pattern' }), result('pattern'))
end)

test('case: combined with other flags', function()
  deep_eq(parse_args({ '-siF', 'pattern' }), result('pattern', { case = 'case-insensitive', fixed = true }))
end)

test('case: combined with word flag', function()
  deep_eq(parse_args({ '-ws', 'pattern' }), result('pattern', { word = true, case = 'case-sensitive' }))
end)

test('case: --smart-case resets to nil', function()
  deep_eq(parse_args({ '--smart-case', 'pattern' }), result('pattern'))
end)

test('case: -S resets to nil', function()
  deep_eq(parse_args({ '-S', 'pattern' }), result('pattern'))
end)

test('case: stacked S resets to nil', function()
  deep_eq(parse_args({ '-HS', 'pattern' }), result('pattern'))
end)

test('case: -S overrides previous -s', function()
  deep_eq(parse_args({ '-s', '-S', 'pattern' }), result('pattern'))
  deep_eq(parse_args({ '--case-sensitive', '-S', 'pattern' }), result('pattern'))
end)

test('case: -S overrides previous -i', function()
  deep_eq(parse_args({ '-i', '-S', 'pattern' }), result('pattern'))
  deep_eq(parse_args({ '--ignore-case', '-S', 'pattern' }), result('pattern'))
end)

test('case: -s overrides previous -S', function()
  deep_eq(parse_args({ '-S', '-s', 'pattern' }), result('pattern', { case = 'case-sensitive' }))
  deep_eq(parse_args({ '--smart-case', '-s', 'pattern' }), result('pattern', { case = 'case-sensitive' }))
end)

test('case: -i overrides previous -S', function()
  deep_eq(parse_args({ '-S', '-i', 'pattern' }), result('pattern', { case = 'case-insensitive' }))
  deep_eq(parse_args({ '--smart-case', '-i', 'pattern' }), result('pattern', { case = 'case-insensitive' }))
end)

--------------------------------------------------------------------------------
--- Output format (--line-number vs --vimgrep) ---------------------------------
--------------------------------------------------------------------------------

test('output-format: -n sets unique-lines', function()
  deep_eq(parse_args({ '-n', 'pattern' }), result('pattern', { output_format = 'unique-lines' }))
end)

test('output-format: --line-number sets unique-lines', function()
  deep_eq(parse_args({ '--line-number', 'pattern' }), result('pattern', { output_format = 'unique-lines' }))
end)

test('output-format: --vimgrep sets one-line-per-match', function()
  deep_eq(parse_args({ '--vimgrep', 'pattern' }), result('pattern', { output_format = 'one-line-per-match' }))
end)

test('output-format: --vimgrep overrides -n', function()
  deep_eq(parse_args({ '-n', '--vimgrep', 'pattern' }), result('pattern', { output_format = 'one-line-per-match' }))
end)

test('output-format: -n overrides --vimgrep', function()
  deep_eq(parse_args({ '--vimgrep', '-n', 'pattern' }), result('pattern', { output_format = 'unique-lines' }))
end)

test('output-format: stacked -n with other flags', function()
  deep_eq(parse_args({ '-Hn', 'pattern' }), result('pattern', { output_format = 'unique-lines' }))
end)

test('output-format: nil by default', function()
  deep_eq(parse_args({ 'pattern' }), result('pattern', { output_format = nil }))
end)

--------------------------------------------------------------------------------
--- Multiline ------------------------------------------------------------------
--------------------------------------------------------------------------------

test('multiline: -U sets multiline true', function()
  deep_eq(parse_args({ '-U', 'pattern' }), result('pattern', { multiline = true }))
end)

test('multiline: --multiline sets multiline true', function()
  deep_eq(parse_args({ '--multiline', 'pattern' }), result('pattern', { multiline = true }))
end)

test('multiline: --multiline-dotall sets multiline true', function()
  deep_eq(parse_args({ '--multiline-dotall', 'pattern' }), result('pattern', { multiline = true }))
end)

test('multiline: --no-multiline sets multiline false', function()
  deep_eq(parse_args({ '--no-multiline', 'pattern' }), result('pattern', { multiline = false }))
end)

test('multiline: --no-multiline overrides -U', function()
  deep_eq(parse_args({ '-U', '--no-multiline', 'pattern' }), result('pattern', { multiline = false }))
end)

test('multiline: -U overrides --no-multiline', function()
  deep_eq(parse_args({ '--no-multiline', '-U', 'pattern' }), result('pattern', { multiline = true }))
end)

test('multiline: stacked -U with other flags', function()
  deep_eq(parse_args({ '-HU', 'pattern' }), result('pattern', { multiline = true }))
end)

test('multiline: false by default', function()
  deep_eq(parse_args({ 'pattern' }), result('pattern', { multiline = false }))
end)

--------------------------------------------------------------------------------
--- Patterns with embedded quotes (post-unquoting) -----------------------------
--------------------------------------------------------------------------------

-- After posix_unquote, the pattern itself may contain quote characters
test('pattern: contains single quote', function()
  deep_eq(parse_args({ "it's" }), result("it's"))
end)

test('pattern: contains double quote', function()
  deep_eq(parse_args({ 'say "hello"' }), result('say "hello"'))
end)

test('pattern: empty string', function()
  deep_eq(parse_args({ '' }), result(''))
end)

--------------------------------------------------------------------------------
--- Edge cases -----------------------------------------------------------------
--------------------------------------------------------------------------------

test('edge: pattern that looks like a path', function()
  deep_eq(parse_args({ 'src/lib/foo' }), result('src/lib/foo'))
end)

test('edge: pattern containing dashes but not an option', function()
  deep_eq(parse_args({ 'my-pattern-here' }), result('my-pattern-here'))
end)

test('edge: pattern starting with dash needs -- separator', function()
  -- Without --, -pattern is an unknown stacked arg, can't be expanded
  deep_eq(parse_args({ '-pattern' }), empty_result())
end)

test('edge: pattern with special regex characters', function()
  deep_eq(parse_args({ 'foo.*bar' }), result('foo.*bar'))
end)

test('edge: pattern with complex regex', function()
  deep_eq(parse_args({ '(foo|bar)+' }), result('(foo|bar)+'))
end)

test('edge: single dash alone', function()
  -- Single dash typically means stdin in Unix tools
  deep_eq(parse_args({ '-' }), result('-'))
end)

test('edge: pattern is a number', function()
  deep_eq(parse_args({ '42' }), result('42'))
end)

test('edge: pattern is a dot', function()
  deep_eq(parse_args({ '.' }), result('.'))
end)

--------------------------------------------------------------------------------
--- Real-world usage patterns --------------------------------------------------
--------------------------------------------------------------------------------

test('real-world: typical code search with type filter', function()
  deep_eq(parse_args({ '-t', 'go', '-H', 'func', './cmd/' }), result('func'))
end)

test('real-world: case-insensitive fixed string', function()
  deep_eq(parse_args({ '-iF', 'TODO:', 'src/' }), result('TODO:', { case = 'case-insensitive', fixed = true }))
end)

test('real-world: hidden files with type filter', function()
  deep_eq(parse_args({ '--hidden', '-t', 'lua', 'require' }), result('require'))
end)

test('real-world: word boundary search', function()
  deep_eq(parse_args({ '-w', 'error', 'src/', 'lib/' }), result('error', { word = true }))
end)

test('real-world: glob exclusion with pattern', function()
  deep_eq(parse_args({ '-g', '!*.test.js', 'describe', 'src/' }), result('describe'))
end)

test('real-world: multiline search', function()
  deep_eq(parse_args({ '-U', 'func.*\\n.*return' }), result('func.*\\n.*return', { multiline = true }))
end)

test('real-world: context lines with pattern', function()
  deep_eq(parse_args({ '-C', '3', 'TODO', 'src/' }), result('TODO'))
end)

test('real-world: pcre2 regex', function()
  deep_eq(parse_args({ '-P', '(?<=func )\\w+' }), result('(?<=func )\\w+'))
end)

test('real-world: vimgrep mode explicit', function()
  deep_eq(parse_args({ '--vimgrep', '-i', 'pattern' }),
    result('pattern', { case = 'case-insensitive', output_format = 'one-line-per-match' }))
end)

test('real-world: line-number mode', function()
  deep_eq(parse_args({ '-n', '-w', 'TODO' }), result('TODO', { word = true, output_format = 'unique-lines' }))
end)

--------------------------------------------------------------------------------
--- Combined flags -------------------------------------------------------------
--------------------------------------------------------------------------------

test('combined: word + fixed + case-insensitive', function()
  deep_eq(parse_args({ '-wFi', 'pattern' }), result('pattern', { word = true, fixed = true, case = 'case-insensitive' }))
end)

test('combined: multiline + output_format', function()
  deep_eq(parse_args({ '-Un', 'pattern' }), result('pattern', { multiline = true, output_format = 'unique-lines' }))
end)

test('combined: all boolean flags', function()
  deep_eq(parse_args({ '-wFsUn', 'pattern' }), result('pattern', {
    word = true,
    fixed = true,
    case = 'case-sensitive',
    multiline = true,
    output_format = 'unique-lines',
  }))
end)

--------------------------------------------------------------------------------
--- Summary --------------------------------------------------------------------
--------------------------------------------------------------------------------

h.summary()
