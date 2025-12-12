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
--- Word boundary handling (opts.word = true) ----------------------------------
--------------------------------------------------------------------------------

test('word: wraps pattern with word boundaries', function()
  eq(rg_to_vim_pattern('hello', { word = true }), '\\<hello\\>')
end)

test('word: combined with fixed', function()
  eq(rg_to_vim_pattern('hello', { fixed = true, word = true }), '\\<\\Vhello\\>')
end)

--------------------------------------------------------------------------------
--- Metacharacter translation (rg -> Vim) --------------------------------------
--------------------------------------------------------------------------------

test('metachar: + becomes \\+', function()
  eq(rg_to_vim_pattern('a+b', {}), 'a\\+b')
end)

test('metachar: ? becomes \\?', function()
  eq(rg_to_vim_pattern('a?b', {}), 'a\\?b')
end)

test('metachar: () become \\(\\)', function()
  eq(rg_to_vim_pattern('(foo)', {}), '\\(foo\\)')
end)

test('metachar: {} become \\{\\}', function()
  eq(rg_to_vim_pattern('a{2,3}', {}), 'a\\{2,3\\}')
end)

test('metachar: | becomes \\|', function()
  eq(rg_to_vim_pattern('foo|bar', {}), 'foo\\|bar')
end)

test('metachar: multiple metacharacters', function()
  eq(rg_to_vim_pattern('(a+|b?)', {}), '\\(a\\+\\|b\\?\\)')
end)

--------------------------------------------------------------------------------
--- Escaped metacharacters in rg (literal in rg -> literal in Vim) -------------
--------------------------------------------------------------------------------

test('escaped: \\( becomes literal (', function()
  eq(rg_to_vim_pattern('\\(', {}), '(')
end)

test('escaped: \\) becomes literal )', function()
  eq(rg_to_vim_pattern('\\)', {}), ')')
end)

test('escaped: \\+ becomes literal +', function()
  eq(rg_to_vim_pattern('\\+', {}), '+')
end)

test('escaped: \\? becomes literal ?', function()
  eq(rg_to_vim_pattern('\\?', {}), '?')
end)

test('escaped: \\{ becomes literal {', function()
  eq(rg_to_vim_pattern('\\{', {}), '{')
end)

test('escaped: \\} becomes literal }', function()
  eq(rg_to_vim_pattern('\\}', {}), '}')
end)

test('escaped: \\\\ stays as \\\\', function()
  eq(rg_to_vim_pattern('\\\\', {}), '\\\\')
end)

--------------------------------------------------------------------------------
--- Pass-through escape sequences (same in both) -------------------------------
--------------------------------------------------------------------------------

test('passthrough: \\d stays as \\d', function()
  eq(rg_to_vim_pattern('\\d', {}), '\\d')
end)

test('passthrough: \\w stays as \\w', function()
  eq(rg_to_vim_pattern('\\w', {}), '\\w')
end)

test('passthrough: \\s stays as \\s', function()
  eq(rg_to_vim_pattern('\\s', {}), '\\s')
end)

test('passthrough: \\n stays as \\n', function()
  eq(rg_to_vim_pattern('\\n', {}), '\\n')
end)

--------------------------------------------------------------------------------
--- Word boundary \b translation -----------------------------------------------
--------------------------------------------------------------------------------

test('boundary: \\b at start becomes \\<', function()
  eq(rg_to_vim_pattern('\\bword', {}), '\\<word')
end)

test('boundary: \\b at end becomes \\>', function()
  eq(rg_to_vim_pattern('word\\b', {}), 'word\\>')
end)

test('boundary: \\b at both ends', function()
  eq(rg_to_vim_pattern('\\bword\\b', {}), '\\<word\\>')
end)

test('boundary: \\b in middle becomes \\> (heuristic)', function()
  -- This is a best-effort heuristic; middle \b defaults to \>
  eq(rg_to_vim_pattern('foo\\bbar', {}), 'foo\\>bar')
end)

--------------------------------------------------------------------------------
--- Character classes (brackets) -----------------------------------------------
--------------------------------------------------------------------------------

test('bracket: simple class passes through', function()
  eq(rg_to_vim_pattern('[abc]', {}), '[abc]')
end)

test('bracket: negated class passes through', function()
  eq(rg_to_vim_pattern('[^abc]', {}), '[^abc]')
end)

test('bracket: metacharacters inside are NOT escaped', function()
  -- + inside [] is literal in both rg and Vim, should not become \+
  eq(rg_to_vim_pattern('[a+b]', {}), '[a+b]')
end)

test('bracket: all metacharacters inside remain literal', function()
  eq(rg_to_vim_pattern('[+?(){}|]', {}), '[+?(){}|]')
end)

test('bracket: literal ] at start of class', function()
  eq(rg_to_vim_pattern('[]abc]', {}), '[]abc]')
end)

test('bracket: literal ] at start of negated class', function()
  eq(rg_to_vim_pattern('[^]abc]', {}), '[^]abc]')
end)

test('bracket: escapes inside brackets pass through', function()
  eq(rg_to_vim_pattern('[\\d\\w]', {}), '[\\d\\w]')
end)

test('bracket: metachar outside, literal inside', function()
  -- The + outside should be escaped, the + inside should not
  eq(rg_to_vim_pattern('[a+]+', {}), '[a+]\\+')
end)

test('bracket: multiple classes in pattern', function()
  eq(rg_to_vim_pattern('[a-z]+[0-9]+', {}), '[a-z]\\+[0-9]\\+')
end)

--------------------------------------------------------------------------------
--- Forward slash escaping (search delimiter) ----------------------------------
--------------------------------------------------------------------------------

test('slash: escaped in normal mode', function()
  eq(rg_to_vim_pattern('foo/bar', {}), 'foo\\/bar')
end)

test('slash: escaped inside brackets too', function()
  eq(rg_to_vim_pattern('[/]', {}), '[\\/]')
end)

--------------------------------------------------------------------------------
--- Complex / realistic patterns -----------------------------------------------
--------------------------------------------------------------------------------

test('complex: function call pattern', function()
  eq(rg_to_vim_pattern('\\w+(.*)', {}), '\\w\\+\\(.*\\)')
end)

test('complex: email-like pattern', function()
  eq(rg_to_vim_pattern('[a-zA-Z0-9.]+@[a-zA-Z0-9.]+', {}), '[a-zA-Z0-9.]\\+@[a-zA-Z0-9.]\\+')
end)

test('complex: URL path', function()
  eq(rg_to_vim_pattern('/api/v[0-9]+/users', {}), '\\/api\\/v[0-9]\\+\\/users')
end)

test('complex: alternation with groups', function()
  eq(rg_to_vim_pattern('(foo|bar)(baz)?', {}), '\\(foo\\|bar\\)\\(baz\\)\\?')
end)

test('complex: word with quantifier', function()
  eq(rg_to_vim_pattern('\\b\\w{3,5}\\b', {}), '\\<\\w\\{3,5\\}\\>')
end)

--------------------------------------------------------------------------------
--- Edge cases -----------------------------------------------------------------
--------------------------------------------------------------------------------

test('edge: empty string', function()
  eq(rg_to_vim_pattern('', {}), '')
end)

test('edge: single backslash at end (malformed)', function()
  -- A trailing backslash with nothing after it - should pass through
  eq(rg_to_vim_pattern('\\', {}), '\\')
end)

test('edge: only metacharacters', function()
  eq(rg_to_vim_pattern('+?|', {}), '\\+\\?\\|')
end)

--------------------------------------------------------------------------------
--- Summary --------------------------------------------------------------------
--------------------------------------------------------------------------------

h.summary()
