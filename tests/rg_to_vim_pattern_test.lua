-- Run with:
--   nvim --headless -c "luafile tests/rg_to_vim_pattern_test.lua" -c "q"

local h = require('tests.harness')
local test = h.test
local eq = h.eq
local rg_to_vim_pattern = require('brook.rg_to_vim_pattern')._rg_to_vim_pattern

--------------------------------------------------------------------------------
--- Fixed string / literal searches (opts.fixed = true) ------------------------
--------------------------------------------------------------------------------

test('fixed: simple literal', function()
  eq(rg_to_vim_pattern('hello', { fixed = true }), '\\Vhello')
end)

test('fixed: escapes backslashes', function()
  eq(rg_to_vim_pattern('foo\\bar', { fixed = true }), '\\Vfoo\\\\bar')
end)

test('fixed: escapes forward slashes (search delimiter)', function()
  eq(rg_to_vim_pattern('foo/bar', { fixed = true }), '\\Vfoo\\/bar')
end)

test('fixed: preserves metacharacters literally', function()
  eq(rg_to_vim_pattern('[a+b].*', { fixed = true }), '\\V[a+b].*')
end)

test('fixed: complex path-like pattern', function()
  eq(rg_to_vim_pattern('path/to/file.txt', { fixed = true }), '\\Vpath\\/to\\/file.txt')
end)

--------------------------------------------------------------------------------
--- Special metacharacters -----------------------------------------------------
--------------------------------------------------------------------------------

test('fixed: complex path-like pattern', function()
  eq(rg_to_vim_pattern('[~=]= nil', {}), [[\v[~=]\= nil]])
end)

--------------------------------------------------------------------------------
--- Word boundary handling (opts.word = true) ----------------------------------
--------------------------------------------------------------------------------

test('word: wraps pattern with word boundaries', function()
  eq(rg_to_vim_pattern('hello', { word = true }), '\\v<hello>')
end)

test('word: combined with fixed', function()
  eq(rg_to_vim_pattern('hello', { fixed = true, word = true }), '\\V\\<hello\\>')
end)

--------------------------------------------------------------------------------
--- Very magic basics: metacharacters pass through -----------------------------
--------------------------------------------------------------------------------

test('verymagic: + passes through', function()
  eq(rg_to_vim_pattern('a+b', {}), '\\va+b')
end)

test('verymagic: ? passes through', function()
  eq(rg_to_vim_pattern('a?b', {}), '\\va?b')
end)

test('verymagic: () pass through', function()
  eq(rg_to_vim_pattern('(foo)', {}), '\\v(foo)')
end)

test('verymagic: {} pass through', function()
  eq(rg_to_vim_pattern('a{2,3}', {}), '\\va{2,3}')
end)

test('verymagic: | passes through', function()
  eq(rg_to_vim_pattern('foo|bar', {}), '\\vfoo|bar')
end)

test('verymagic: multiple metacharacters pass through', function()
  eq(rg_to_vim_pattern('(a+|b?)', {}), '\\v(a+|b?)')
end)

--------------------------------------------------------------------------------
--- Escaped metacharacters (literal in rg -> literal in Vim) -------------------
--------------------------------------------------------------------------------

test('escaped: \\( passes through (literal in both)', function()
  eq(rg_to_vim_pattern('\\(', {}), '\\v\\(')
end)

test('escaped: \\) passes through (literal in both)', function()
  eq(rg_to_vim_pattern('\\)', {}), '\\v\\)')
end)

test('escaped: \\+ passes through (literal in both)', function()
  eq(rg_to_vim_pattern('\\+', {}), '\\v\\+')
end)

test('escaped: \\? passes through (literal in both)', function()
  eq(rg_to_vim_pattern('\\?', {}), '\\v\\?')
end)

test('escaped: \\{ passes through (literal in both)', function()
  eq(rg_to_vim_pattern('\\{', {}), '\\v\\{')
end)

test('escaped: \\} passes through (literal in both)', function()
  eq(rg_to_vim_pattern('\\}', {}), '\\v\\}')
end)

test('escaped: \\\\ stays as \\\\', function()
  eq(rg_to_vim_pattern('\\\\', {}), '\\v\\\\')
end)

--------------------------------------------------------------------------------
--- Non-greedy quantifiers -----------------------------------------------------
--------------------------------------------------------------------------------

test('nongreedy: *? becomes {-}', function()
  eq(rg_to_vim_pattern('a*?b', {}), '\\va{-}b')
end)

test('nongreedy: +? becomes {-1,}', function()
  eq(rg_to_vim_pattern('a+?b', {}), '\\va{-1,}b')
end)

test('nongreedy: ?? becomes {-0,1}', function()
  eq(rg_to_vim_pattern('a??b', {}), '\\va{-0,1}b')
end)

test('nongreedy: complex pattern with +?', function()
  eq(rg_to_vim_pattern([[\.password-.+?("|')\)]], {}), [[\v\.password-.{-1,}("|')\)]])
end)

test('nongreedy: .+? shorthand', function()
  eq(rg_to_vim_pattern('.+?', {}), '\\v.{-1,}')
end)

test('nongreedy: .*? shorthand', function()
  eq(rg_to_vim_pattern('.*?', {}), '\\v.{-}')
end)

test('nongreedy: multiple non-greedy in pattern', function()
  eq(rg_to_vim_pattern('a+?b*?c??', {}), '\\va{-1,}b{-}c{-0,1}')
end)

--------------------------------------------------------------------------------
--- Pass-through escape sequences (same in both) -------------------------------
--------------------------------------------------------------------------------

test('passthrough: \\d stays as \\d', function()
  eq(rg_to_vim_pattern('\\d', {}), '\\v\\d')
end)

test('passthrough: \\w stays as \\w', function()
  eq(rg_to_vim_pattern('\\w', {}), '\\v\\w')
end)

test('passthrough: \\s stays as \\s', function()
  eq(rg_to_vim_pattern('\\s', {}), '\\v\\s')
end)

test('passthrough: \\n stays as \\n', function()
  eq(rg_to_vim_pattern('\\n', {}), '\\v\\n')
end)

test('passthrough: \\. stays as \\.', function()
  eq(rg_to_vim_pattern('\\.', {}), '\\v\\.')
end)

--------------------------------------------------------------------------------
--- Word boundary \b translation -----------------------------------------------
--------------------------------------------------------------------------------

test('boundary: \\b at start', function()
  eq(rg_to_vim_pattern('\\bword', {}), '\\v(<|>)word')
end)

test('boundary: \\b at end', function()
  eq(rg_to_vim_pattern('word\\b', {}), '\\vword(<|>)')
end)

test('boundary: \\b at both ends', function()
  eq(rg_to_vim_pattern('\\bword\\b', {}), '\\v(<|>)word(<|>)')
end)

test('boundary: \\b in middle', function()
  eq(rg_to_vim_pattern('foo\\bbar', {}), '\\vfoo(<|>)bar')
end)

--------------------------------------------------------------------------------
--- Angle bracket escaping (literal in rg, word boundary in very magic) --------
--------------------------------------------------------------------------------

test('angle: < becomes \\<', function()
  eq(rg_to_vim_pattern('<', {}), '\\v\\<')
end)

test('angle: > becomes \\>', function()
  eq(rg_to_vim_pattern('>', {}), '\\v\\>')
end)

test('angle: generic type pattern', function()
  eq(rg_to_vim_pattern('Vec<T>', {}), '\\vVec\\<T\\>')
end)

test('angle: HTML tag', function()
  eq(rg_to_vim_pattern('<div>', {}), '\\v\\<div\\>')
end)

test('angle: comparison operators', function()
  eq(rg_to_vim_pattern('x > 0', {}), '\\vx \\> 0')
end)

test('angle: escaped in rg stays escaped (literal)', function()
  -- In rg, \< is an escaped literal <, which in \v should also be \
  eq(rg_to_vim_pattern('\\<', {}), '\\v\\<')
end)

--------------------------------------------------------------------------------
--- Character classes (brackets) -----------------------------------------------
--------------------------------------------------------------------------------

test('bracket: simple class passes through', function()
  eq(rg_to_vim_pattern('[abc]', {}), '\\v[abc]')
end)

test('bracket: negated class passes through', function()
  eq(rg_to_vim_pattern('[^abc]', {}), '\\v[^abc]')
end)

test('bracket: metacharacters inside remain literal', function()
  eq(rg_to_vim_pattern('[a+b]', {}), '\\v[a+b]')
end)

test('bracket: all metacharacters inside remain literal', function()
  eq(rg_to_vim_pattern('[+?(){}|]', {}), '\\v[+?(){}|]')
end)

test('bracket: literal ] at start of class', function()
  eq(rg_to_vim_pattern('[]abc]', {}), '\\v[]abc]')
end)

test('bracket: literal ] at start of negated class', function()
  eq(rg_to_vim_pattern('[^]abc]', {}), '\\v[^]abc]')
end)

test('bracket: escapes inside brackets pass through', function()
  eq(rg_to_vim_pattern('[\\d\\w]', {}), '\\v[\\d\\w]')
end)

test('bracket: metachar outside, literal inside', function()
  eq(rg_to_vim_pattern('[a+]+', {}), '\\v[a+]+')
end)

test('bracket: multiple classes in pattern', function()
  eq(rg_to_vim_pattern('[a-z]+[0-9]+', {}), '\\v[a-z]+[0-9]+')
end)

--------------------------------------------------------------------------------
--- Forward slash escaping (search delimiter) ----------------------------------
--------------------------------------------------------------------------------

test('slash: escaped in pattern', function()
  eq(rg_to_vim_pattern('foo/bar', {}), '\\vfoo\\/bar')
end)

test('slash: escaped inside brackets too', function()
  eq(rg_to_vim_pattern('[/]', {}), '\\v[\\/]')
end)

--------------------------------------------------------------------------------
--- Complex / realistic patterns -----------------------------------------------
--------------------------------------------------------------------------------

test('complex: function call pattern', function()
  eq(rg_to_vim_pattern('\\w+(.*)', {}), '\\v\\w+(.*)')
end)

test('complex: email-like pattern', function()
  eq(rg_to_vim_pattern('[a-zA-Z0-9.]+@[a-zA-Z0-9.]+', {}), '\\v[a-zA-Z0-9.]+@[a-zA-Z0-9.]+')
end)

test('complex: URL path', function()
  eq(rg_to_vim_pattern('/api/v[0-9]+/users', {}), '\\v\\/api\\/v[0-9]+\\/users')
end)

test('complex: alternation with groups', function()
  eq(rg_to_vim_pattern('(foo|bar)(baz)?', {}), '\\v(foo|bar)(baz)?')
end)

test('complex: word with quantifier', function()
  eq(rg_to_vim_pattern('\\b\\w{3,5}\\b', {}), '\\v(<|>)\\w{3,5}(<|>)')
end)

test('complex: non-greedy HTML tag matching', function()
  eq(rg_to_vim_pattern('<div.*?>', {}), [[\v\<div.{-}\>]])
end)

test('complex: quoted string (non-greedy)', function()
  eq(rg_to_vim_pattern('"[^"]*?"', {}), '\\v"[^"]{-}"')
end)

--------------------------------------------------------------------------------
--- Edge cases -----------------------------------------------------------------
--------------------------------------------------------------------------------

test('edge: empty string', function()
  eq(rg_to_vim_pattern('', {}), '\\v')
end)

test('edge: single backslash at end (malformed)', function()
  eq(rg_to_vim_pattern('\\', {}), '\\v\\')
end)

test('edge: only metacharacters', function()
  eq(rg_to_vim_pattern('+?|', {}), '\\v+?|')
end)

--------------------------------------------------------------------------------
--- Summary --------------------------------------------------------------------
--------------------------------------------------------------------------------

h.summary()
