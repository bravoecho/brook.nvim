-- Run with:
--   nvim --headless -c "set rtp+=." -c "luafile tests/args/parser_test.lua" -c "q"

local h = require('tests.harness')
local test = h.test
local deep_eq = h.deep_eq
local parse_args = require('brook.args.parser').parse_args

-- NOTE: `parse_args` receives already-unquoted tokens. Shell unquoting
-- behaviour is tested separately in unquoter_test.lua.

--- Original user command, we only need to check that it's forwarded correctly.
local raw = '<original command>'

-- Helper: default result with pattern set
local function result(patterns, overrides)
  local r = {
    patterns = patterns,
    word = false,
    fixed = false,
    case = nil,
    output_format = nil,
    multiline = false,
    pcre2 = false,
    raw = raw,
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
  return result({}, overrides)
end

--------------------------------------------------------------------------------
--- Simple cases (no options, no paths) ----------------------------------------
--------------------------------------------------------------------------------

test('simple: single pattern', function()
  deep_eq(parse_args({ 'hello' }, raw), result({ 'hello' }))
end)

test('simple: pattern with spaces', function()
  deep_eq(parse_args({ 'hello world' }, raw), result({ 'hello world' }))
end)

test('simple: empty token list', function()
  deep_eq(parse_args({}, raw), empty_result())
end)

test('simple: nil token list', function()
  deep_eq(parse_args(nil, raw), empty_result())
end)

--------------------------------------------------------------------------------
--- Flags (boolean options) ----------------------------------------------------
--------------------------------------------------------------------------------

test('flag: pattern immediately after boolean flag', function()
  deep_eq(parse_args({ '--hidden', 'pattern' }, raw), result({ 'pattern' }))
end)

test('flag: pattern after multiple boolean flags', function()
  deep_eq(parse_args({ '-v', '-H', 'pattern' }, raw), result({ 'pattern' }))
end)

test('flag: pattern after combined short flags', function()
  -- rg allows -iH as shorthand for -i -H
  deep_eq(parse_args({ '-vH', 'pattern' }, raw), result({ 'pattern' }))
end)

--------------------------------------------------------------------------------
--- Stacked short options (flags + options with attached values) ---------------
--------------------------------------------------------------------------------

test('stacked: flags then -e with attached value', function()
  deep_eq(parse_args({ '-Hefoo' }, raw), result({ 'foo' }))
end)

test('stacked: flags then -e with attached value, plus path', function()
  deep_eq(parse_args({ '-Hefoo', 'src/' }, raw), result({ 'foo' }))
end)

test('stacked: multiple -e in separate stacks', function()
  -- Only first pattern is kept
  deep_eq(parse_args({ '-Hefoo', '-ebar' }, raw), result({ 'foo', 'bar' }))
end)

test('stacked: option with attached value (not -e)', function()
  deep_eq(parse_args({ '-g*.lua', 'pattern' }, raw), result({ 'pattern' }))
end)

test('stacked: flags then option with attached value', function()
  deep_eq(parse_args({ '-Hg*.lua', 'pattern' }, raw), result({ 'pattern' }))
end)

test('flag: single flag before pattern', function()
  deep_eq(parse_args({ '--hidden', 'pattern' }, raw), result({ 'pattern' }))
end)

test('flag: multiple flags before pattern', function()
  deep_eq(parse_args({ '--hidden', '--smart-case', 'pattern' }, raw), result({ 'pattern' }))
end)

test('flag: short flag before pattern', function()
  deep_eq(parse_args({ '-H', 'pattern' }, raw), result({ 'pattern' }))
end)

--------------------------------------------------------------------------------
--- Options (with values) ------------------------------------------------------
--------------------------------------------------------------------------------

test('option: flag with = value before pattern', function()
  deep_eq(parse_args({ '--color=never', 'pattern' }, raw), result({ 'pattern' }))
end)

test('option: flag with separate value before pattern', function()
  deep_eq(parse_args({ '-g', '*.lua', '--hidden', 'pattern' }, raw), result({ 'pattern' }))
end)

test('option: option value with spaces before pattern', function()
  deep_eq(parse_args({ '-g', '*.lua', '--hidden', 'my pattern' }, raw), result({ 'my pattern' }))
end)

test('option: --glob=value before pattern', function()
  deep_eq(parse_args({ '--glob=*.lua', 'pattern' }, raw), result({ 'pattern' }))
end)

test('option: -g=value before pattern', function()
  deep_eq(parse_args({ '-g=*.lua', 'pattern' }, raw), result({ 'pattern' }))
end)

test('option: multiple options with values', function()
  deep_eq(parse_args({ '-t', 'go', '-g', '!vendor/', 'pattern' }, raw), result({ 'pattern' }))
end)

--------------------------------------------------------------------------------
--- Pattern with paths after it ------------------------------------------------
--------------------------------------------------------------------------------

test('path: pattern with path', function()
  deep_eq(parse_args({ 'pattern', 'src/lib' }, raw), result({ 'pattern' }))
end)

test('path: pattern with spaces and path', function()
  deep_eq(parse_args({ 'my pattern', 'src/lib' }, raw), result({ 'my pattern' }))
end)

test('path: pattern with multiple paths', function()
  deep_eq(parse_args({ 'pattern', 'src/', 'lib/', 'tests/' }, raw), result({ 'pattern' }))
end)

test('path: pattern with path containing spaces', function()
  deep_eq(parse_args({ 'pattern', 'a/path/in side/the/repo' }, raw), result({ 'pattern' }))
end)

--------------------------------------------------------------------------------
--- Full command: options, pattern, and paths ----------------------------------
--------------------------------------------------------------------------------

test('full: options, pattern, path', function()
  deep_eq(parse_args({ '--hidden', 'pattern', 'src/' }, raw), result({ 'pattern' }))
end)

test('full: multiple named args, pattern with spaces, path', function()
  deep_eq(parse_args({ '-H', '--vimgrep', 'my pattern', 'src/' }, raw),
    result({ 'my pattern' }, { output_format = 'one-line-per-match' }))
end)

test('full: complex command with pattern containing special chars', function()
  local tokens = {
    '-g', '*.lua', '--color=never', '--no-unicode', '--hidden',
    'my-special (pattern|here)', 'a/path/in side/the/repo'
  }
  deep_eq(parse_args(tokens, raw), result({ 'my-special (pattern|here)' }))
end)

test('full: option with value as last named arg before pattern', function()
  local tokens = { '-g', '*.go', 'flags\\(\\)', './go/termcol/' }
  deep_eq(parse_args(tokens, raw), result({ 'flags\\(\\)' }))
end)

--------------------------------------------------------------------------------
--- Double-dash separator ------------------------------------------------------
--------------------------------------------------------------------------------

test('double-dash: separates options from positional args', function()
  local tokens = { '-g', '*.go', '--', 'flags\\(\\)', './go/termcol/' }
  deep_eq(parse_args(tokens, raw), result({ 'flags\\(\\)' }))
end)

test('double-dash: pattern that looks like a flag', function()
  deep_eq(parse_args({ '--', '--not-a-flag' }, raw), result({ '--not-a-flag' }))
end)

test('double-dash: pattern that looks like short option', function()
  deep_eq(parse_args({ '--', '-e' }, raw), result({ '-e' }))
end)

test('double-dash: pattern that looks like option with value', function()
  deep_eq(parse_args({ '--', '-g=*.lua' }, raw), result({ '-g=*.lua' }))
end)

test('double-dash: options before, flag-like pattern after', function()
  deep_eq(parse_args({ '-.', '--', '--word-regexp' }, raw), result({ '--word-regexp' }))
end)

test('double-dash: path that looks like option', function()
  deep_eq(parse_args({ 'pattern', '--', '-weird-dir/' }, raw), result({ 'pattern' }))
end)

test('double-dash: empty after separator', function()
  -- No pattern after --, returns empty result
  deep_eq(parse_args({ '-i', '--' }, raw), empty_result({ case = 'case-insensitive' }))
end)

--------------------------------------------------------------------------------
--- Unknown named arguments ----------------------------------------------------
--------------------------------------------------------------------------------

-- Unknown args are now ignored, not treated as errors

test('unknown: lone unknown long option ignored', function()
  deep_eq(parse_args({ '--foobar' }, raw), empty_result())
end)

test('unknown: unknown option followed by path', function()
  -- --foobar is unknown and ignored, 'src/' becomes the pattern
  deep_eq(parse_args({ '--foobar', 'src/' }, raw), result({ 'src/' }))
end)

test('unknown: known options before unknown, with path', function()
  deep_eq(parse_args({ '-i', '--foobar', 'src/' }, raw), result({ 'src/' }, { case = 'case-insensitive' }))
end)

test('unknown: unknown option not immediately before pattern is ignored', function()
  deep_eq(parse_args({ '--foobar', '-i', 'pattern' }, raw), result({ 'pattern' }, { case = 'case-insensitive' }))
end)

test('unknown: unknown option immediately before pattern is ignored', function()
  deep_eq(parse_args({ '-i', '--foobar', 'pattern' }, raw), result({ 'pattern' }, { case = 'case-insensitive' }))
end)

test('unknown: unknown short option ignored', function()
  -- -Z is unknown, returned as empty (can't expand unknown stacked args)
  deep_eq(parse_args({ '-Z' }, raw), empty_result())
end)

--------------------------------------------------------------------------------
--- No identifiable pattern ----------------------------------------------------
--------------------------------------------------------------------------------

test('no-pattern: only flags', function()
  deep_eq(parse_args({ '-i', '-H', '--hidden' }, raw), empty_result({ case = 'case-insensitive' }))
end)

test('no-pattern: option expecting value at end', function()
  deep_eq(parse_args({ '-i', '-g' }, raw), empty_result({ case = 'case-insensitive' }))
end)

test('no-pattern: only options with values', function()
  deep_eq(parse_args({ '-g', '*.lua', '-t', 'go' }, raw), empty_result())
end)

--------------------------------------------------------------------------------
--- Late options (options after positional arguments) --------------------------
--------------------------------------------------------------------------------

test('late-option: flag after pattern', function()
  deep_eq(parse_args({ 'pattern', '-L' }, raw), result({ 'pattern' }))
end)

test('late-option: flag after pattern and path', function()
  deep_eq(parse_args({ 'pattern', 'src/', '-H' }, raw), result({ 'pattern' }))
end)

test('late-option: option with value after pattern', function()
  deep_eq(parse_args({ 'pattern', '-g', '*.lua' }, raw), result({ 'pattern' }))
end)

test('late-option: option with value after pattern and path', function()
  deep_eq(parse_args({ 'pattern', 'src/', '-t', 'go' }, raw), result({ 'pattern' }))
end)

test('late-option: multiple late options', function()
  deep_eq(parse_args({ 'pattern', 'src/', '-a', '-H', '-t', 'lua' }, raw), result({ 'pattern' }))
end)

--------------------------------------------------------------------------------
--- Special: -e / --regexp (explicit pattern specification) --------------------
--------------------------------------------------------------------------------

-- -e with separate value
test('regexp: -e with separate value', function()
  deep_eq(parse_args({ '-e', 'pattern' }, raw), result({ 'pattern' }))
end)

test('regexp: -e with value containing spaces', function()
  deep_eq(parse_args({ '-e', 'my pattern' }, raw), result({ 'my pattern' }))
end)

test('regexp: -e with value and path', function()
  deep_eq(parse_args({ '-e', 'pattern', 'src/' }, raw), result({ 'pattern' }))
end)

test('regexp: -e with options before', function()
  deep_eq(parse_args({ '-v', '-H', '-e', 'pattern' }, raw), result({ 'pattern' }))
end)

test('regexp: -e with options before and after', function()
  deep_eq(parse_args({ '-v', '-e', 'pattern', '-H' }, raw), result({ 'pattern' }))
end)

test('regexp: -e=value syntax', function()
  deep_eq(parse_args({ '-e=pattern' }, raw), result({ 'pattern' }))
end)

test('regexp: -e=value with spaces', function()
  deep_eq(parse_args({ '-e=my pattern' }, raw), result({ 'my pattern' }))
end)

test('regexp: -e=value with other options', function()
  deep_eq(parse_args({ '-v', '-e=pattern', 'src/' }, raw), result({ 'pattern' }))
end)

-- -e with attached value (no separator)
test('regexp: -evalue syntax (attached)', function()
  deep_eq(parse_args({ '-epattern' }, raw), result({ 'pattern' }))
end)

test('regexp: -evalue with other options and path', function()
  deep_eq(parse_args({ '-v', '-epattern', 'src/' }, raw), result({ 'pattern' }))
end)

-- --regexp variants
test('regexp: --regexp with separate value', function()
  deep_eq(parse_args({ '--regexp', 'pattern' }, raw), result({ 'pattern' }))
end)

test('regexp: --regexp=value syntax', function()
  deep_eq(parse_args({ '--regexp=pattern' }, raw), result({ 'pattern' }))
end)

test('regexp: --regexp with value containing spaces', function()
  deep_eq(parse_args({ '--regexp', 'foo bar' }, raw), result({ 'foo bar' }))
end)

test('regexp: --regexp=value with spaces', function()
  deep_eq(parse_args({ '--regexp=foo bar' }, raw), result({ 'foo bar' }))
end)

-- Multiple -e patterns (only first is kept)
test('regexp: multiple -e returns all patterns', function()
  deep_eq(parse_args({ '-e', 'foo', '-e', 'bar' }, raw), result({ 'foo', 'bar' }))
end)

test('regexp: multiple -e with various syntaxes returns all patterns', function()
  deep_eq(parse_args({ '-efoo', '-e=bar', '-e', 'baz' }, raw), result({ 'foo', 'bar', 'baz' }))
end)

test('regexp: multiple --regexp patterns returns all patterns', function()
  deep_eq(parse_args({ '--regexp=foo', '--regexp', 'bar' }, raw), result({ 'foo', 'bar' }))
end)

test('regexp: mixed -e and --regexp returns all patterns', function()
  deep_eq(parse_args({ '-e', 'foo', '--regexp=bar' }, raw), result({ 'foo', 'bar' }))
end)

test('regexp: -e with other options interspersed returns all patterns', function()
  deep_eq(parse_args({ '-e', 'foo', '-v', '-e', 'bar', '-H' }, raw), result({ 'foo', 'bar' }))
end)

-- -e takes precedence over positional pattern
test('regexp: -e pattern ignores positional pattern-like args', function()
  -- When -e is used, positional args are paths, not patterns
  deep_eq(parse_args({ '-e', 'foo', 'bar', 'src/' }, raw), result({ 'foo' }))
end)

-- -e without value is tolerated
test('regexp: -e at end without value', function()
  deep_eq(parse_args({ '-e' }, raw), empty_result())
end)

test('regexp: -e at end after options', function()
  deep_eq(parse_args({ '-i', '-e' }, raw), empty_result({ case = 'case-insensitive' }))
end)

--------------------------------------------------------------------------------
--- Literal search -------------------------------------------------------------
--------------------------------------------------------------------------------

test('literal: args include --fixed-strings', function()
  deep_eq(parse_args({ 'someFunction()', '--fixed-strings' }, raw), result({ 'someFunction()' }, { fixed = true }))
end)

test('literal: args include -F', function()
  deep_eq(parse_args({ '-F', 'someFunction()' }, raw), result({ 'someFunction()' }, { fixed = true }))
end)

test('literal: args include a stacked F', function()
  deep_eq(parse_args({ '-LF.', 'someFunction()' }, raw), result({ 'someFunction()' }, { fixed = true }))
end)

--------------------------------------------------------------------------------
--- Whole-word search ----------------------------------------------------------
--------------------------------------------------------------------------------

test('word: args include --word-regexp', function()
  deep_eq(parse_args({ 'someFunction()', '--word-regexp' }, raw), result({ 'someFunction()' }, { word = true }))
end)

test('word: args include -w', function()
  deep_eq(parse_args({ '-w', 'someFunction()' }, raw), result({ 'someFunction()' }, { word = true }))
end)

test('word: args include a stacked w', function()
  deep_eq(parse_args({ '-Lw.', 'someFunction()' }, raw), result({ 'someFunction()' }, { word = true }))
end)

--------------------------------------------------------------------------------
--- Case sensitivity -----------------------------------------------------------
--------------------------------------------------------------------------------

test('case: args include --case-sensitive', function()
  deep_eq(parse_args({ 'pattern', '--case-sensitive' }, raw), result({ 'pattern' }, { case = 'case-sensitive' }))
end)

test('case: args include -s', function()
  deep_eq(parse_args({ '-s', 'pattern' }, raw), result({ 'pattern' }, { case = 'case-sensitive' }))
end)

test('case: args include --ignore-case', function()
  deep_eq(parse_args({ 'pattern', '--ignore-case' }, raw), result({ 'pattern' }, { case = 'case-insensitive' }))
end)

test('case: args include -i', function()
  deep_eq(parse_args({ '-i', 'pattern' }, raw), result({ 'pattern' }, { case = 'case-insensitive' }))
end)

test('case: args include a stacked s', function()
  deep_eq(parse_args({ '-Hs', 'pattern' }, raw), result({ 'pattern' }, { case = 'case-sensitive' }))
end)

test('case: args include a stacked i', function()
  deep_eq(parse_args({ '-Hi', 'pattern' }, raw), result({ 'pattern' }, { case = 'case-insensitive' }))
end)

test('case: last flag wins (-i then -s)', function()
  deep_eq(parse_args({ '-i', '-s', 'pattern' }, raw), result({ 'pattern' }, { case = 'case-sensitive' }))
end)

test('case: last flag wins (-s then -i)', function()
  deep_eq(parse_args({ '-s', '-i', 'pattern' }, raw), result({ 'pattern' }, { case = 'case-insensitive' }))
end)

test('case: last flag wins (long form mixed)', function()
  deep_eq(parse_args({ '--ignore-case', '--case-sensitive', '-i', 'pattern' }, raw),
    result({ 'pattern' }, { case = 'case-insensitive' }))
end)

test('case: unset by default', function()
  deep_eq(parse_args({ 'pattern' }, raw), result({ 'pattern' }))
end)

test('case: combined with other flags', function()
  deep_eq(parse_args({ '-siF', 'pattern' }, raw), result({ 'pattern' }, { case = 'case-insensitive', fixed = true }))
end)

test('case: combined with word flag', function()
  deep_eq(parse_args({ '-ws', 'pattern' }, raw), result({ 'pattern' }, { word = true, case = 'case-sensitive' }))
end)

test('case: --smart-case resets to nil', function()
  deep_eq(parse_args({ '--smart-case', 'pattern' }, raw), result({ 'pattern' }))
end)

test('case: -S resets to nil', function()
  deep_eq(parse_args({ '-S', 'pattern' }, raw), result({ 'pattern' }))
end)

test('case: stacked S resets to nil', function()
  deep_eq(parse_args({ '-HS', 'pattern' }, raw), result({ 'pattern' }))
end)

test('case: -S overrides previous -s', function()
  deep_eq(parse_args({ '-s', '-S', 'pattern' }, raw), result({ 'pattern' }))
  deep_eq(parse_args({ '--case-sensitive', '-S', 'pattern' }, raw), result({ 'pattern' }))
end)

test('case: -S overrides previous -i', function()
  deep_eq(parse_args({ '-i', '-S', 'pattern' }, raw), result({ 'pattern' }))
  deep_eq(parse_args({ '--ignore-case', '-S', 'pattern' }, raw), result({ 'pattern' }))
end)

test('case: -s overrides previous -S', function()
  deep_eq(parse_args({ '-S', '-s', 'pattern' }, raw), result({ 'pattern' }, { case = 'case-sensitive' }))
  deep_eq(parse_args({ '--smart-case', '-s', 'pattern' }, raw), result({ 'pattern' }, { case = 'case-sensitive' }))
end)

test('case: -i overrides previous -S', function()
  deep_eq(parse_args({ '-S', '-i', 'pattern' }, raw), result({ 'pattern' }, { case = 'case-insensitive' }))
  deep_eq(parse_args({ '--smart-case', '-i', 'pattern' }, raw), result({ 'pattern' }, { case = 'case-insensitive' }))
end)

--------------------------------------------------------------------------------
--- Output format (--line-number vs --vimgrep) ---------------------------------
--------------------------------------------------------------------------------

test('output-format: -n sets unique-lines', function()
  deep_eq(parse_args({ '-n', 'pattern' }, raw), result({ 'pattern' }, { output_format = 'unique-lines' }))
end)

test('output-format: --line-number sets unique-lines', function()
  deep_eq(parse_args({ '--line-number', 'pattern' }, raw), result({ 'pattern' }, { output_format = 'unique-lines' }))
end)

test('output-format: --vimgrep sets one-line-per-match', function()
  deep_eq(parse_args({ '--vimgrep', 'pattern' }, raw), result({ 'pattern' }, { output_format = 'one-line-per-match' }))
end)

test('output-format: --vimgrep overrides -n', function()
  deep_eq(parse_args({ '-n', '--vimgrep', 'pattern' }, raw), result({ 'pattern' }, { output_format = 'one-line-per-match' }))
end)

test('output-format: -n overrides --vimgrep', function()
  deep_eq(parse_args({ '--vimgrep', '-n', 'pattern' }, raw), result({ 'pattern' }, { output_format = 'unique-lines' }))
end)

test('output-format: stacked -n with other flags', function()
  deep_eq(parse_args({ '-Hn', 'pattern' }, raw), result({ 'pattern' }, { output_format = 'unique-lines' }))
end)

test('output-format: nil by default', function()
  deep_eq(parse_args({ 'pattern' }, raw), result({ 'pattern' }, { output_format = nil }))
end)

--------------------------------------------------------------------------------
--- Multiline ------------------------------------------------------------------
--------------------------------------------------------------------------------

test('multiline: -U sets multiline true', function()
  deep_eq(parse_args({ '-U', 'pattern' }, raw), result({ 'pattern' }, { multiline = true }))
end)

test('multiline: --multiline sets multiline true', function()
  deep_eq(parse_args({ '--multiline', 'pattern' }, raw), result({ 'pattern' }, { multiline = true }))
end)

test('multiline: --multiline-dotall sets multiline true', function()
  deep_eq(parse_args({ '--multiline-dotall', 'pattern' }, raw), result({ 'pattern' }, { multiline = true }))
end)

test('multiline: --no-multiline sets multiline false', function()
  deep_eq(parse_args({ '--no-multiline', 'pattern' }, raw), result({ 'pattern' }, { multiline = false }))
end)

test('multiline: --no-multiline overrides -U', function()
  deep_eq(parse_args({ '-U', '--no-multiline', 'pattern' }, raw), result({ 'pattern' }, { multiline = false }))
end)

test('multiline: -U overrides --no-multiline', function()
  deep_eq(parse_args({ '--no-multiline', '-U', 'pattern' }, raw), result({ 'pattern' }, { multiline = true }))
end)

test('multiline: stacked -U with other flags', function()
  deep_eq(parse_args({ '-HU', 'pattern' }, raw), result({ 'pattern' }, { multiline = true }))
end)

test('multiline: false by default', function()
  deep_eq(parse_args({ 'pattern' }, raw), result({ 'pattern' }, { multiline = false }))
end)

--------------------------------------------------------------------------------
--- PCRE2 ----------------------------------------------------------------------
--------------------------------------------------------------------------------

test('pcre2: -P sets pcre2 true', function()
  deep_eq(parse_args({ '-P', 'pattern' }, raw), result({ 'pattern' }, { pcre2 = true }))
end)

test('pcre2: --pcre2 sets pcre2 true', function()
  deep_eq(parse_args({ '--pcre2', 'pattern' }, raw), result({ 'pattern' }, { pcre2 = true }))
end)

test('pcre2: --no-pcre2 sets pcre2 false', function()
  deep_eq(parse_args({ '--no-pcre2', 'pattern' }, raw), result({ 'pattern' }, { pcre2 = false }))
end)

test('pcre2: --no-pcre2 overrides -P', function()
  deep_eq(parse_args({ '-P', '--no-pcre2', 'pattern' }, raw), result({ 'pattern' }, { pcre2 = false }))
end)

test('pcre2: -P overrides --no-pcre2', function()
  deep_eq(parse_args({ '--no-pcre2', '-P', 'pattern' }, raw), result({ 'pattern' }, { pcre2 = true }))
end)

test('pcre2: --engine=pcre2 sets pcre2 true', function()
  deep_eq(parse_args({ '--engine=pcre2', 'pattern' }, raw), result({ 'pattern' }, { pcre2 = true }))
end)

test('pcre2: --engine pcre2 sets pcre2 true', function()
  deep_eq(parse_args({ '--engine', 'pcre2', 'pattern' }, raw), result({ 'pattern' }, { pcre2 = true }))
end)

test('pcre2: --engine=auto sets pcre2 true', function()
  deep_eq(parse_args({ '--engine=auto', 'pattern' }, raw), result({ 'pattern' }, { pcre2 = true }))
end)

test('pcre2: --engine auto sets pcre2 true', function()
  deep_eq(parse_args({ '--engine', 'auto', 'pattern' }, raw), result({ 'pattern' }, { pcre2 = true }))
end)

test('pcre2: --engine=default sets pcre2 false', function()
  deep_eq(parse_args({ '--engine=default', 'pattern' }, raw), result({ 'pattern' }, { pcre2 = false }))
end)

test('pcre2: --engine default sets pcre2 false', function()
  deep_eq(parse_args({ '--engine', 'default', 'pattern' }, raw), result({ 'pattern' }, { pcre2 = false }))
end)

test('pcre2: --engine=default overrides -P', function()
  deep_eq(parse_args({ '-P', '--engine=default', 'pattern' }, raw), result({ 'pattern' }, { pcre2 = false }))
end)

test('pcre2: --engine=pcre2 overrides --no-pcre2', function()
  deep_eq(parse_args({ '--no-pcre2', '--engine=pcre2', 'pattern' }, raw), result({ 'pattern' }, { pcre2 = true }))
end)

test('pcre2: stacked -P with other flags', function()
  deep_eq(parse_args({ '-HP', 'pattern' }, raw), result({ 'pattern' }, { pcre2 = true }))
end)

test('pcre2: false by default', function()
  deep_eq(parse_args({ 'pattern' }, raw), result({ 'pattern' }, { pcre2 = false }))
end)

--------------------------------------------------------------------------------
--- Patterns with embedded quotes (post-unquoting) -----------------------------
--------------------------------------------------------------------------------

-- After posix_unquote, the pattern itself may contain quote characters
test('pattern: contains single quote', function()
  deep_eq(parse_args({ "it's" }, raw), result({ "it's" }))
end)

test('pattern: contains double quote', function()
  deep_eq(parse_args({ 'say "hello"' }, raw), result({ 'say "hello"' }))
end)

test('pattern: empty string', function()
  deep_eq(parse_args({ '' }, raw), result({ '' }))
end)

--------------------------------------------------------------------------------
--- Edge cases -----------------------------------------------------------------
--------------------------------------------------------------------------------

test('edge: pattern that looks like a path', function()
  deep_eq(parse_args({ 'src/lib/foo' }, raw), result({ 'src/lib/foo' }))
end)

test('edge: pattern containing dashes but not an option', function()
  deep_eq(parse_args({ 'my-pattern-here' }, raw), result({ 'my-pattern-here' }))
end)

test('edge: pattern starting with dash needs -- separator', function()
  -- Without --, -pattern is an unknown stacked arg, can't be expanded
  deep_eq(parse_args({ '-pattern' }, raw), empty_result())
end)

test('edge: pattern with special regex characters', function()
  deep_eq(parse_args({ 'foo.*bar' }, raw), result({ 'foo.*bar' }))
end)

test('edge: pattern with complex regex', function()
  deep_eq(parse_args({ '(foo|bar)+' }, raw), result({ '(foo|bar)+' }))
end)

test('edge: single dash alone', function()
  -- Single dash typically means stdin in Unix tools
  deep_eq(parse_args({ '-' }, raw), result({ '-' }))
end)

test('edge: pattern is a number', function()
  deep_eq(parse_args({ '42' }, raw), result({ '42' }))
end)

test('edge: pattern is a dot', function()
  deep_eq(parse_args({ '.' }, raw), result({ '.' }))
end)

--------------------------------------------------------------------------------
--- Real-world usage patterns --------------------------------------------------
--------------------------------------------------------------------------------

test('real-world: typical code search with type filter', function()
  deep_eq(parse_args({ '-t', 'go', '-H', 'func', './cmd/' }, raw), result({ 'func' }))
end)

test('real-world: case-insensitive fixed string', function()
  deep_eq(parse_args({ '-iF', 'TODO:', 'src/' }, raw), result({ 'TODO:' }, { case = 'case-insensitive', fixed = true }))
end)

test('real-world: hidden files with type filter', function()
  deep_eq(parse_args({ '--hidden', '-t', 'lua', 'require' }, raw), result({ 'require' }))
end)

test('real-world: word boundary search', function()
  deep_eq(parse_args({ '-w', 'error', 'src/', 'lib/' }, raw), result({ 'error' }, { word = true }))
end)

test('real-world: glob exclusion with pattern', function()
  deep_eq(parse_args({ '-g', '!*.test.js', 'describe', 'src/' }, raw), result({ 'describe' }))
end)

test('real-world: multiline search', function()
  deep_eq(parse_args({ '-U', 'func.*\\n.*return' }, raw), result({ 'func.*\\n.*return' }, { multiline = true }))
end)

test('real-world: context lines with pattern', function()
  deep_eq(parse_args({ '-C', '3', 'TODO', 'src/' }, raw), result({ 'TODO' }))
end)

test('real-world: pcre2 regex', function()
  deep_eq(parse_args({ '-P', '(?<=func )\\w+' }, raw), result({ '(?<=func )\\w+' }, { pcre2 = true }))
end)

test('real-world: vimgrep mode explicit', function()
  deep_eq(parse_args({ '--vimgrep', '-i', 'pattern' }, raw),
    result({ 'pattern' }, { case = 'case-insensitive', output_format = 'one-line-per-match' }))
end)

test('real-world: line-number mode', function()
  deep_eq(parse_args({ '-n', '-w', 'TODO' }, raw), result({ 'TODO' }, { word = true, output_format = 'unique-lines' }))
end)

test('real-world: tokens are assumed to be already shell-unquoted (what ripgrep would see)', function()
  -- The result includes the double quotes because the parser assumes the tokens
  -- are pre-unquoted. See:
  --
  -- https://www.gnu.org/software/bash/manual/html_node/Quote-Removal.html
  -- https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html#tag_18_06_07
  deep_eq(parse_args({ '-e="more data"' }, raw), result({ '"more data"' }))
end)

--------------------------------------------------------------------------------
--- Combined flags -------------------------------------------------------------
--------------------------------------------------------------------------------

test('combined: word + fixed + case-insensitive', function()
  deep_eq(parse_args({ '-wFi', 'pattern' }, raw), result({ 'pattern' }, { word = true, fixed = true, case = 'case-insensitive' }))
end)

test('combined: multiline + output_format', function()
  deep_eq(parse_args({ '-Un', 'pattern' }, raw), result({ 'pattern' }, { multiline = true, output_format = 'unique-lines' }))
end)

test('combined: all boolean flags', function()
  deep_eq(parse_args({ '-wFsUn', 'pattern' }, raw), result({ 'pattern' }, {
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
