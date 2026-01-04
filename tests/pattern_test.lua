-- Run with:
--   nvim --headless -c "luafile tests/pattern_test.lua" -c "q"

local h = require('tests.harness')
local test = h.test
local eq = h.eq
local rg_to_vim = require('brook.pattern').rg_to_vim

--------------------------------------------------------------------------------
--- Fixed string mode (opts.fixed = true) --------------------------------------
--------------------------------------------------------------------------------

test('fixed: simple literal', function()
  eq(rg_to_vim('hello', { fixed = true }), '\\Vhello')
end)

test('fixed: escapes backslashes', function()
  eq(rg_to_vim('foo\\bar', { fixed = true }), '\\Vfoo\\\\bar')
end)

test('fixed: escapes forward slashes (search delimiter)', function()
  eq(rg_to_vim('foo/bar', { fixed = true }), '\\Vfoo\\/bar')
end)

test('fixed: preserves metacharacters literally', function()
  eq(rg_to_vim('[a+b].*', { fixed = true }), '\\V[a+b].*')
end)

test('fixed: complex path-like pattern', function()
  eq(rg_to_vim('path/to/file.txt', { fixed = true }), '\\Vpath\\/to\\/file.txt')
end)

test('fixed: empty string', function()
  eq(rg_to_vim('', { fixed = true }), '\\V')
end)

test('fixed: special chars preserved', function()
  eq(rg_to_vim('foo=bar~baz', { fixed = true }), '\\Vfoo=bar~baz')
end)

test('fixed: with word boundary', function()
  eq(rg_to_vim('hello', { fixed = true, word = true }), '\\V\\<hello\\>')
end)

test('fixed: with word boundary and dot (literal)', function()
  eq(rg_to_vim('foo.bar', { fixed = true, word = true }), '\\V\\<foo.bar\\>')
end)

--------------------------------------------------------------------------------
--- Vim-special character escaping (literal in rg, special in \v) --------------
--------------------------------------------------------------------------------

test('vimspecial: equals sign', function()
  eq(rg_to_vim('foo=bar', {}), '\\vfoo\\=bar')
end)

test('vimspecial: multiple equals signs', function()
  eq(rg_to_vim('foo==bar', {}), '\\vfoo\\=\\=bar')
end)

test('vimspecial: tilde', function()
  eq(rg_to_vim('x~y', {}), '\\vx\\~y')
end)

test('vimspecial: at-sign', function()
  eq(rg_to_vim('a@b', {}), '\\va\\@b')
end)

test('vimspecial: ampersand', function()
  eq(rg_to_vim('a&b', {}), '\\va\\&b')
end)

test('vimspecial: double ampersand (logical AND)', function()
  eq(rg_to_vim('a && b', {}), '\\va \\&\\& b')
end)

test('vimspecial: less-than (comparison)', function()
  eq(rg_to_vim('a<b', {}), '\\va\\<b')
end)

test('vimspecial: greater-than (comparison)', function()
  eq(rg_to_vim('x > 0', {}), '\\vx \\> 0')
end)

test('vimspecial: generic type syntax', function()
  eq(rg_to_vim('Vec<T>', {}), '\\vVec\\<T\\>')
end)

test('vimspecial: HTML tag', function()
  eq(rg_to_vim('<div>', {}), '\\v\\<div\\>')
end)

test('vimspecial: Python decorator', function()
  eq(rg_to_vim('@decorator', {}), '\\v\\@decorator')
end)

test('vimspecial: inside class literal, outside escaped', function()
  eq(rg_to_vim('[~=]= nil', {}), '\\v[~=]\\= nil')
end)

test('vimspecial: angle brackets inside class (no escape needed)', function()
  eq(rg_to_vim('[<>]', {}), '\\v[<>]')
end)

test('vimspecial: at and ampersand inside class (no escape needed)', function()
  eq(rg_to_vim('[@&]', {}), '\\v[@&]')
end)

test('vimspecial: escaped equals in rg (literal)', function()
  eq(rg_to_vim('\\=', {}), '\\v\\=')
end)

test('vimspecial: escaped tilde in rg (literal)', function()
  eq(rg_to_vim('\\~', {}), '\\v\\~')
end)

test('vimspecial: escaped at in rg (literal)', function()
  eq(rg_to_vim('\\@', {}), '\\v\\@')
end)

test('vimspecial: escaped ampersand in rg (literal)', function()
  eq(rg_to_vim('\\&', {}), '\\v\\&')
end)

--------------------------------------------------------------------------------
--- Characters special in both engines (pass through) --------------------------
--------------------------------------------------------------------------------

test('metachar: dot passes through', function()
  eq(rg_to_vim('a.b', {}), '\\va.b')
end)

test('metachar: star passes through', function()
  eq(rg_to_vim('a*b', {}), '\\va*b')
end)

test('metachar: plus passes through', function()
  eq(rg_to_vim('a+b', {}), '\\va+b')
end)

test('metachar: question passes through', function()
  eq(rg_to_vim('a?b', {}), '\\va?b')
end)

test('metachar: parentheses pass through', function()
  eq(rg_to_vim('(foo)', {}), '\\v(foo)')
end)

test('metachar: pipe passes through', function()
  eq(rg_to_vim('foo|bar', {}), '\\vfoo|bar')
end)

test('metachar: caret passes through', function()
  eq(rg_to_vim('^start', {}), '\\v^start')
end)

test('metachar: dollar passes through', function()
  eq(rg_to_vim('end$', {}), '\\vend$')
end)

test('metachar: braces pass through', function()
  eq(rg_to_vim('a{2,3}', {}), '\\va{2,3}')
end)

test('metachar: combined', function()
  eq(rg_to_vim('(a+|b?)', {}), '\\v(a+|b?)')
end)

--------------------------------------------------------------------------------
--- Escaped metacharacters (literal in both) -----------------------------------
--------------------------------------------------------------------------------

test('escaped: \\( passes through', function()
  eq(rg_to_vim('\\(', {}), '\\v\\(')
end)

test('escaped: \\) passes through', function()
  eq(rg_to_vim('\\)', {}), '\\v\\)')
end)

test('escaped: \\+ passes through', function()
  eq(rg_to_vim('\\+', {}), '\\v\\+')
end)

test('escaped: \\? passes through', function()
  eq(rg_to_vim('\\?', {}), '\\v\\?')
end)

test('escaped: \\{ passes through', function()
  eq(rg_to_vim('\\{', {}), '\\v\\{')
end)

test('escaped: \\} passes through', function()
  eq(rg_to_vim('\\}', {}), '\\v\\}')
end)

test('escaped: \\[ passes through', function()
  eq(rg_to_vim('\\[', {}), '\\v\\[')
end)

test('escaped: \\] passes through', function()
  eq(rg_to_vim('\\]', {}), '\\v\\]')
end)

test('escaped: \\| passes through', function()
  eq(rg_to_vim('\\|', {}), '\\v\\|')
end)

test('escaped: \\. passes through', function()
  eq(rg_to_vim('\\.', {}), '\\v\\.')
end)

test('escaped: \\* passes through', function()
  eq(rg_to_vim('\\*', {}), '\\v\\*')
end)

test('escaped: \\\\ passes through', function()
  eq(rg_to_vim('\\\\', {}), '\\v\\\\')
end)

test('escaped: \\^ passes through', function()
  eq(rg_to_vim('\\^', {}), '\\v\\^')
end)

test('escaped: \\$ passes through', function()
  eq(rg_to_vim('\\$', {}), '\\v\\$')
end)

--------------------------------------------------------------------------------
--- Character class shorthands (pass through) ----------------------------------
--------------------------------------------------------------------------------

test('shorthand: \\d passes through', function()
  eq(rg_to_vim('\\d', {}), '\\v\\d')
end)

test('shorthand: \\D passes through', function()
  eq(rg_to_vim('\\D', {}), '\\v\\D')
end)

test('shorthand: \\w passes through', function()
  eq(rg_to_vim('\\w', {}), '\\v\\w')
end)

test('shorthand: \\W passes through', function()
  eq(rg_to_vim('\\W', {}), '\\v\\W')
end)

test('shorthand: \\s passes through', function()
  eq(rg_to_vim('\\s', {}), '\\v\\s')
end)

test('shorthand: \\S passes through', function()
  eq(rg_to_vim('\\S', {}), '\\v\\S')
end)

test('shorthand: \\t passes through', function()
  eq(rg_to_vim('\\t', {}), '\\v\\t')
end)

test('shorthand: \\n passes through', function()
  eq(rg_to_vim('\\n', {}), '\\v\\n')
end)

test('shorthand: \\r passes through', function()
  eq(rg_to_vim('\\r', {}), '\\v\\r')
end)

test('shorthand: combined with quantifier', function()
  eq(rg_to_vim('\\d+', {}), '\\v\\d+')
end)

test('shorthand: inside character class', function()
  eq(rg_to_vim('[\\d\\w]', {}), '\\v[\\d\\w]')
end)

--------------------------------------------------------------------------------
--- Word boundaries ------------------------------------------------------------
--------------------------------------------------------------------------------

test('boundary: \\b at start', function()
  eq(rg_to_vim('\\bword', {}), '\\v(<|>)word')
end)

test('boundary: \\b at end', function()
  eq(rg_to_vim('word\\b', {}), '\\vword(<|>)')
end)

test('boundary: \\b at both ends', function()
  eq(rg_to_vim('\\bword\\b', {}), '\\v(<|>)word(<|>)')
end)

test('boundary: \\b in middle', function()
  eq(rg_to_vim('foo\\bbar', {}), '\\vfoo(<|>)bar')
end)

test('boundary: \\b with shorthand', function()
  eq(rg_to_vim('\\b\\w+\\b', {}), '\\v(<|>)\\w+(<|>)')
end)

test('boundary: -w flag wraps with word boundaries', function()
  eq(rg_to_vim('hello', { word = true }), '\\v<hello>')
end)

test('boundary: -w flag with regex pattern', function()
  eq(rg_to_vim('foo.*bar', { word = true }), '\\v<foo.*bar>')
end)

test('boundary: \\B unsupported (returns nil)', function()
  eq(rg_to_vim('\\B', {}), nil)
end)

test('boundary: \\B in pattern unsupported (returns nil)', function()
  eq(rg_to_vim('foo\\Bbar', {}), nil)
end)

--------------------------------------------------------------------------------
--- Case sensitivity -----------------------------------------------------------
--------------------------------------------------------------------------------

test('case: sensitive adds \\C prefix', function()
  eq(rg_to_vim('hello', { case = 'case-sensitive' }), '\\C\\vhello')
end)

test('case: insensitive adds \\c prefix', function()
  eq(rg_to_vim('hello', { case = 'case-insensitive' }), '\\c\\vhello')
end)

test('case: unset adds no prefix', function()
  eq(rg_to_vim('hello', { case = nil }), '\\vhello')
end)

test('case: nil adds no prefix', function()
  eq(rg_to_vim('hello', {}), '\\vhello')
end)

test('case: sensitive with word boundary', function()
  eq(rg_to_vim('hello', { case = 'case-sensitive', word = true }), '\\C\\v<hello>')
end)

test('case: insensitive with word boundary', function()
  eq(rg_to_vim('hello', { case = 'case-insensitive', word = true }), '\\c\\v<hello>')
end)

test('case: sensitive with complex pattern', function()
  eq(rg_to_vim('foo.*bar', { case = 'case-sensitive' }), '\\C\\vfoo.*bar')
end)

test('case: insensitive with special chars', function()
  eq(rg_to_vim('foo=bar', { case = 'case-insensitive' }), '\\c\\vfoo\\=bar')
end)

--------------------------------------------------------------------------------
--- Case sensitivity with fixed strings ----------------------------------------
--------------------------------------------------------------------------------

test('fixed+case: sensitive', function()
  eq(rg_to_vim('hello', { fixed = true, case = 'case-sensitive' }), '\\C\\Vhello')
end)

test('fixed+case: insensitive', function()
  eq(rg_to_vim('hello', { fixed = true, case = 'case-insensitive' }), '\\c\\Vhello')
end)

test('fixed+case: unset', function()
  eq(rg_to_vim('hello', { fixed = true, case = 'unset' }), '\\Vhello')
end)

test('fixed+case: sensitive with word boundary', function()
  eq(rg_to_vim('hello', { fixed = true, case = 'case-sensitive', word = true }), '\\C\\V\\<hello\\>')
end)

test('fixed+case: insensitive with word boundary', function()
  eq(rg_to_vim('hello', { fixed = true, case = 'case-insensitive', word = true }), '\\c\\V\\<hello\\>')
end)

test('fixed+case: sensitive with special chars preserved', function()
  eq(rg_to_vim('[a+b].*', { fixed = true, case = 'case-sensitive' }), '\\C\\V[a+b].*')
end)

test('fixed+case: insensitive with path', function()
  eq(rg_to_vim('foo/bar', { fixed = true, case = 'case-insensitive' }), '\\c\\Vfoo\\/bar')
end)

--------------------------------------------------------------------------------
--- Greedy quantifiers (pass through) ------------------------------------------
--------------------------------------------------------------------------------

test('greedy: a* passes through', function()
  eq(rg_to_vim('a*', {}), '\\va*')
end)

test('greedy: a+ passes through', function()
  eq(rg_to_vim('a+', {}), '\\va+')
end)

test('greedy: a? passes through', function()
  eq(rg_to_vim('a?', {}), '\\va?')
end)

test('greedy: a{3} passes through', function()
  eq(rg_to_vim('a{3}', {}), '\\va{3}')
end)

test('greedy: a{3,} passes through', function()
  eq(rg_to_vim('a{3,}', {}), '\\va{3,}')
end)

test('greedy: a{3,5} passes through', function()
  eq(rg_to_vim('a{3,5}', {}), '\\va{3,5}')
end)

--------------------------------------------------------------------------------
--- Non-greedy quantifiers (translation required) ------------------------------
--------------------------------------------------------------------------------

test('nongreedy: *? becomes {-}', function()
  eq(rg_to_vim('a*?', {}), '\\va{-}')
end)

test('nongreedy: +? becomes {-1,}', function()
  eq(rg_to_vim('a+?', {}), '\\va{-1,}')
end)

test('nongreedy: ?? becomes {-0,1}', function()
  eq(rg_to_vim('a??', {}), '\\va{-0,1}')
end)

test('nongreedy: *? with preceding atom', function()
  eq(rg_to_vim('a*?b', {}), '\\va{-}b')
end)

test('nongreedy: +? with preceding atom', function()
  eq(rg_to_vim('a+?b', {}), '\\va{-1,}b')
end)

test('nongreedy: ?? with preceding atom', function()
  eq(rg_to_vim('a??b', {}), '\\va{-0,1}b')
end)

test('nongreedy: .*? common pattern', function()
  eq(rg_to_vim('.*?', {}), '\\v.{-}')
end)

test('nongreedy: .+? common pattern', function()
  eq(rg_to_vim('.+?', {}), '\\v.{-1,}')
end)

test('nongreedy: multiple in pattern', function()
  eq(rg_to_vim('a+?b*?c??', {}), '\\va{-1,}b{-}c{-0,1}')
end)

test('nongreedy: {n}? becomes {-n}', function()
  eq(rg_to_vim('a{3}?', {}), '\\va{-3}')
end)

test('nongreedy: {n,}? becomes {-n,}', function()
  eq(rg_to_vim('a{3,}?', {}), '\\va{-3,}')
end)

test('nongreedy: {n,m}? becomes {-n,m}', function()
  eq(rg_to_vim('a{3,5}?', {}), '\\va{-3,5}')
end)

test('nongreedy: {n,m}? realistic', function()
  eq(rg_to_vim('a{2,4}?', {}), '\\va{-2,4}')
end)

test('nongreedy: on group', function()
  eq(rg_to_vim('(ab)+?', {}), '\\v(ab){-1,}')
end)

test('nongreedy: HTML tag pattern', function()
  eq(rg_to_vim('<.*?>', {}), '\\v\\<.{-}\\>')
end)

test('nongreedy: quoted string', function()
  eq(rg_to_vim('".*?"', {}), '\\v".{-}"')
end)

test('nongreedy: with shorthand', function()
  eq(rg_to_vim('\\w+?', {}), '\\v\\w{-1,}')
end)

test('nongreedy: complex pattern', function()
  eq(rg_to_vim([[\.password-.+?("|')\)]], {}), [[\v\.password-.{-1,}("|')\)]])
end)

--------------------------------------------------------------------------------
--- Character classes ----------------------------------------------------------
--------------------------------------------------------------------------------

-- Basic syntax
test('class: simple', function()
  eq(rg_to_vim('[abc]', {}), '\\v[abc]')
end)

test('class: range', function()
  eq(rg_to_vim('[a-z]', {}), '\\v[a-z]')
end)

test('class: negated', function()
  eq(rg_to_vim('[^abc]', {}), '\\v[^abc]')
end)

test('class: multiple ranges', function()
  eq(rg_to_vim('[a-zA-Z0-9]', {}), '\\v[a-zA-Z0-9]')
end)

-- Special positions
test('class: literal ] at start', function()
  eq(rg_to_vim('[]abc]', {}), '\\v[]abc]')
end)

test('class: literal ] at start of negated', function()
  eq(rg_to_vim('[^]abc]', {}), '\\v[^]abc]')
end)

test('class: literal - at start', function()
  eq(rg_to_vim('[-abc]', {}), '\\v[-abc]')
end)

test('class: literal - at end', function()
  eq(rg_to_vim('[abc-]', {}), '\\v[abc-]')
end)

test('class: range then literal -', function()
  eq(rg_to_vim('[a-z-]', {}), '\\v[a-z-]')
end)

-- Vim-special chars inside (no escaping needed)
test('class: tilde and equals inside', function()
  eq(rg_to_vim('[~=]', {}), '\\v[~=]')
end)

test('class: angle brackets inside', function()
  eq(rg_to_vim('[<>]', {}), '\\v[<>]')
end)

test('class: at and ampersand inside', function()
  eq(rg_to_vim('[@&]', {}), '\\v[@&]')
end)

-- Escapes inside classes
test('class: shorthands inside', function()
  eq(rg_to_vim('[\\d\\w]', {}), '\\v[\\d\\w]')
end)

test('class: escaped ]', function()
  eq(rg_to_vim('[\\]]', {}), '\\v[\\]]')
end)

test('class: escaped backslash', function()
  eq(rg_to_vim('[\\\\]', {}), '\\v[\\\\]')
end)

test('class: escaped caret', function()
  eq(rg_to_vim('[\\^]', {}), '\\v[\\^]')
end)

test('class: escaped hyphen', function()
  eq(rg_to_vim('[\\-]', {}), '\\v[\\-]')
end)

-- Metacharacters literal inside
test('class: quantifiers literal inside', function()
  eq(rg_to_vim('[+*?]', {}), '\\v[+*?]')
end)

test('class: parens literal inside', function()
  eq(rg_to_vim('[()]', {}), '\\v[()]')
end)

test('class: braces literal inside', function()
  eq(rg_to_vim('[{}]', {}), '\\v[{}]')
end)

test('class: pipe literal inside', function()
  eq(rg_to_vim('[|]', {}), '\\v[|]')
end)

test('class: dot literal inside', function()
  eq(rg_to_vim('[.]', {}), '\\v[.]')
end)

test('class: all metacharacters inside', function()
  eq(rg_to_vim('[+?(){}|]', {}), '\\v[+?(){}|]')
end)

-- Mixed inside/outside
test('class: metachar outside, literal inside', function()
  eq(rg_to_vim('[a+]+', {}), '\\v[a+]+')
end)

test('class: multiple classes in pattern', function()
  eq(rg_to_vim('[a-z]+[0-9]+', {}), '\\v[a-z]+[0-9]+')
end)

--------------------------------------------------------------------------------
--- Groups ---------------------------------------------------------------------
--------------------------------------------------------------------------------

-- Capturing groups (pass through)
test('group: simple capturing', function()
  eq(rg_to_vim('(foo)', {}), '\\v(foo)')
end)

test('group: with alternation', function()
  eq(rg_to_vim('(a|b)', {}), '\\v(a|b)')
end)

test('group: multiple', function()
  eq(rg_to_vim('(foo)(bar)', {}), '\\v(foo)(bar)')
end)

test('group: nested', function()
  eq(rg_to_vim('((nested))', {}), '\\v((nested))')
end)

-- Non-capturing groups (translation required)
test('group: non-capturing simple', function()
  eq(rg_to_vim('(?:foo)', {}), '\\v%(foo)')
end)

test('group: non-capturing with alternation', function()
  eq(rg_to_vim('(?:a|b)', {}), '\\v%(a|b)')
end)

test('group: non-capturing with quantifier +', function()
  eq(rg_to_vim('(?:foo)+', {}), '\\v%(foo)+')
end)

test('group: non-capturing with quantifier ?', function()
  eq(rg_to_vim('(?:foo)?', {}), '\\v%(foo)?')
end)

test('group: non-capturing with quantifier *', function()
  eq(rg_to_vim('(?:foo)*', {}), '\\v%(foo)*')
end)

test('group: mixed capturing and non-capturing', function()
  eq(rg_to_vim('(a)(?:b)(c)', {}), '\\v(a)%(b)(c)')
end)

test('group: nested non-capturing', function()
  eq(rg_to_vim('(?:(?:inner))', {}), '\\v%(%(inner))')
end)

test('group: non-capturing with non-greedy', function()
  eq(rg_to_vim('(?:ab)+?', {}), '\\v%(ab){-1,}')
end)

--------------------------------------------------------------------------------
--- Named groups: translated to numbered groups --------------------------------
--------------------------------------------------------------------------------

test('group: named Python style: unsupported by Neovim, translated to numbered groups', function()
  eq(rg_to_vim('(?P<name>foo)', {}), '\\v(foo)')
end)

test('group: named PCRE style: unsupported by Neovim, translated to numbered groups', function()
  eq(rg_to_vim('(?<name>foo)', {}), '\\v(foo)')
end)

test('group: named capture preserves inner pattern', function()
  eq(rg_to_vim('(?P<id>ab|cd)+', {}), '\\v(ab|cd)+')
end)

-- Works when nested / combined with normal groups.
test('group: named capture nested inside capture', function()
  eq(rg_to_vim('a((?P<n>bc)d)e', {}), '\\va((bc)d)e')
end)

-- Name can include underscores/digits (we don’t validate charset; we just skip to '>').
test('group: named capture with underscore and digits', function()
  eq(rg_to_vim('(?P<user_01>foo)', {}), '\\v(foo)')
end)

-- Quantifiers / alternation should still apply to the resulting group.
test('group: named capture with quantifier', function()
  eq(rg_to_vim('(?P<id>ab|cd)+', {}), '\\v(ab|cd)+')
end)

-- Double check named groups are not detected in char classes by mistake.
test('group: named marker inside char class is literal', function()
  eq(rg_to_vim('[(?P<name>]', {}), '\\v[(?P<name>]')
end)

--------------------------------------------------------------------------------
--- Named capture rejection cases ----------------------------------------------
--------------------------------------------------------------------------------

-- Reject empty names.
test('group: reject empty Python name', function()
  eq(rg_to_vim('(?P<>foo)', {}), nil)
end)

test('group: reject empty PCRE name', function()
  eq(rg_to_vim('(?<>foo)', {}), nil)
end)

-- Reject missing closing ">" (we can’t safely skip forward).
test('group: reject unterminated Python name', function()
  eq(rg_to_vim('(?P<namefoo)', {}), nil)
end)

test('group: reject unterminated PCRE name', function()
  eq(rg_to_vim('(?<namefoo)', {}), nil)
end)

-- Confirm we still bail on lookbehinds (avoid confusing them with named groups).
test('group: lookbehind still unsupported (?<=...)', function()
  eq(rg_to_vim('(?<=foo)bar', {}), nil)
end)

test('group: negative lookbehind still unsupported (?<!...)', function()
  eq(rg_to_vim('(?<!foo)bar', {}), nil)
end)

-- Confirm other (?X...) forms still bail (atomic group etc).
test('group: atomic group still unsupported (?>...)', function()
  eq(rg_to_vim('(?>foo)bar', {}), nil)
end)

test('group: named capture alongside non-capturing group', function()
  eq(rg_to_vim('(?P<a>foo)(?:bar)', {}), '\\v(foo)%(bar)')
end)

--------------------------------------------------------------------------------
--- Anchors: \A and \z ----------------------------------------------------------
--------------------------------------------------------------------------------

test([[anchors: \A maps to ^ (line start under our constraints)]], function()
  eq(rg_to_vim([[\Afoo]]), [[\v^foo]])
end)

test([[anchors: \z maps to $ (line end under our constraints)]], function()
  eq(rg_to_vim([[foo\z]]), [[\vfoo$]])
end)

test([[anchors: \A...\z maps to ^...$]], function()
  eq(rg_to_vim([[\Afoo\z]]), [[\v^foo$]])
end)

--------------------------------------------------------------------------------
--- Backreferences -------------------------------------------------------------
--------------------------------------------------------------------------------

test('backref: simple repeat', function()
  eq(rg_to_vim('(\\w+) \\1', {}), '\\v(\\w+) \\1')
end)

test('backref: palindrome-ish', function()
  eq(rg_to_vim('(.).*\\1', {}), '\\v(.).*\\1')
end)

test('backref: multiple refs', function()
  eq(rg_to_vim('(a)(b)\\2\\1', {}), '\\v(a)(b)\\2\\1')
end)

--------------------------------------------------------------------------------
--- Forward slash escaping -----------------------------------------------------
--------------------------------------------------------------------------------

test('slash: simple path', function()
  eq(rg_to_vim('foo/bar', {}), '\\vfoo\\/bar')
end)

test('slash: URL path', function()
  eq(rg_to_vim('/api/v1', {}), '\\v\\/api\\/v1')
end)

test('slash: inside character class', function()
  eq(rg_to_vim('[/]', {}), '\\v[\\/]')
end)

test('slash: multiple', function()
  eq(rg_to_vim('a/b/c', {}), '\\va\\/b\\/c')
end)

--------------------------------------------------------------------------------
--- Unsupported features (should return nil) -----------------------------------
--------------------------------------------------------------------------------

-- Lookarounds
test('unsupported: positive lookahead', function()
  eq(rg_to_vim('foo(?=bar)', {}), nil)
end)

test('unsupported: negative lookahead', function()
  eq(rg_to_vim('foo(?!bar)', {}), nil)
end)

test('unsupported: positive lookbehind', function()
  eq(rg_to_vim('(?<=foo)bar', {}), nil)
end)

test('unsupported: negative lookbehind', function()
  eq(rg_to_vim('(?<!foo)bar', {}), nil)
end)

-- Atomic groups
test('unsupported: atomic group', function()
  eq(rg_to_vim('(?>foo)', {}), nil)
end)

-- Possessive quantifiers
test('unsupported: possessive *+', function()
  eq(rg_to_vim('a*+', {}), nil)
end)

test('unsupported: possessive ++', function()
  eq(rg_to_vim('a++', {}), nil)
end)

test('unsupported: possessive ?+', function()
  eq(rg_to_vim('a?+', {}), nil)
end)

-- Unicode categories
test('unsupported: unicode category', function()
  eq(rg_to_vim('\\p{L}', {}), nil)
end)

test('unsupported: negated unicode category', function()
  eq(rg_to_vim('\\P{L}', {}), nil)
end)

--------------------------------------------------------------------------------
--- Complex / realistic patterns -----------------------------------------------
--------------------------------------------------------------------------------

test('complex: function call pattern', function()
  eq(rg_to_vim('\\w+(.*)', {}), '\\v\\w+(.*)')
end)

test('complex: email-like pattern', function()
  eq(rg_to_vim('[a-zA-Z0-9.]+@[a-zA-Z0-9.]+', {}), '\\v[a-zA-Z0-9.]+\\@[a-zA-Z0-9.]+')
end)

test('complex: URL path with version', function()
  eq(rg_to_vim('/api/v[0-9]+/users', {}), '\\v\\/api\\/v[0-9]+\\/users')
end)

test('complex: alternation with groups', function()
  eq(rg_to_vim('(foo|bar)(baz)?', {}), '\\v(foo|bar)(baz)?')
end)

test('complex: word with quantifier range', function()
  eq(rg_to_vim('\\b\\w{3,5}\\b', {}), '\\v(<|>)\\w{3,5}(<|>)')
end)

test('complex: non-greedy HTML tag', function()
  eq(rg_to_vim('<div.*?>', {}), '\\v\\<div.{-}\\>')
end)

test('complex: quoted string non-greedy', function()
  eq(rg_to_vim('"[^"]*?"', {}), '\\v"[^"]{-}"')
end)

test('complex: Go generic type', function()
  eq(rg_to_vim('Map\\[string\\]', {}), '\\vMap\\[string\\]')
end)

test('complex: Lua nil check', function()
  eq(rg_to_vim('[~=]= nil', {}), '\\v[~=]\\= nil')
end)

test('complex: CSS selector', function()
  eq(rg_to_vim('\\.class-name', {}), '\\v\\.class-name')
end)

test('complex: method chaining', function()
  eq(rg_to_vim('\\.\\w+\\(.*?\\)', {}), '\\v\\.\\w+\\(.{-}\\)')
end)

test('complex: assignment operator', function()
  eq(rg_to_vim('\\w+ = ', {}), '\\v\\w+ \\= ')
end)

test('complex: shell variable', function()
  eq(rg_to_vim('\\$\\{?\\w+\\}?', {}), '\\v\\$\\{?\\w+\\}?')
end)

test('complex: markdown link', function()
  eq(rg_to_vim('\\[.*?\\]\\(.*?\\)', {}), '\\v\\[.{-}\\]\\(.{-}\\)')
end)

test('complex: SQL LIKE pattern', function()
  eq(rg_to_vim("LIKE '%.*?%'", {}), "\\vLIKE '%.{-}%'")
end)

--------------------------------------------------------------------------------
--- Edge cases -----------------------------------------------------------------
--------------------------------------------------------------------------------

test('edge: empty string', function()
  eq(rg_to_vim('', {}), '\\v')
end)

test('edge: single backslash at end (malformed)', function()
  eq(rg_to_vim('\\', {}), '\\v\\')
end)

test('edge: only metacharacters', function()
  eq(rg_to_vim('+?|', {}), '\\v+?|')
end)

test('edge: unclosed bracket', function()
  eq(rg_to_vim('[abc', {}), '\\v[abc')
end)

test('edge: unclosed group', function()
  eq(rg_to_vim('(foo', {}), '\\v(foo')
end)

test('edge: only special chars', function()
  eq(rg_to_vim('~=@&<>', {}), '\\v\\~\\=\\@\\&\\<\\>')
end)

test('edge: consecutive escapes', function()
  eq(rg_to_vim('\\\\\\d', {}), '\\v\\\\\\d')
end)

--------------------------------------------------------------------------------
--- Summary --------------------------------------------------------------------
--------------------------------------------------------------------------------

h.summary()
