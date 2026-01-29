-- tests/pattern/pattern_merging_test.lua
--
-- Run with:
--   nvim --headless -u NONE -c "set rtp+=." -c "luafile tests/pattern/pattern_merging_test.lua" -c "q"

local h = require('tests.harness')
local test = h.test
local eq = h.deep_eq
local rg_to_vim = require('brook.pattern').rg_to_vim

---@param pattern string|nil
---@param other? table
---@return brook.pattern.Result
local function result(pattern, other)
  local res = { pattern = pattern, warning = nil }
  if other and other.warning then res.warning = other.warning end
  return res
end

--------------------------------------------------------------------------------
--- Single pattern (baseline) --------------------------------------------------
--------------------------------------------------------------------------------

test('single: behaves as before', function()
  eq(rg_to_vim({ 'foo' }, {}), result('\\vfoo'))
end)

test('single: with -e equivalent to positional', function()
  eq(rg_to_vim({ 'bar' }, {}), result('\\vbar'))
end)

--------------------------------------------------------------------------------
--- Multiple patterns (normal mode) --------------------------------------------
--------------------------------------------------------------------------------

test('merge: two simple patterns', function()
  eq(rg_to_vim({ 'foo', 'bar' }, {}), result('\\vfoo|bar'))
end)

test('merge: three patterns', function()
  eq(rg_to_vim({ 'foo', 'bar', 'baz' }, {}), result('\\vfoo|bar|baz'))
end)

test('merge: patterns with anchors', function()
  -- ^foo|^bar: anchors bind tighter than alternation
  eq(rg_to_vim({ '^foo', '^bar' }, {}), result('\\v^foo|^bar'))
end)

test('merge: patterns with end anchors', function()
  eq(rg_to_vim({ 'foo$', 'bar$' }, {}), result('\\vfoo$|bar$'))
end)

test('merge: pattern containing literal pipe', function()
  -- Escaped pipe in ripgrep: \|
  eq(rg_to_vim({ 'a\\|b', 'c' }, {}), result('\\va\\|b|c'))
end)

test('merge: pattern with alternation inside', function()
  -- foo|bar merged with baz becomes foo|bar|baz
  eq(rg_to_vim({ 'foo|bar', 'baz' }, {}), result('\\vfoo|bar|baz'))
end)

--------------------------------------------------------------------------------
--- Empty pattern filtering ----------------------------------------------------
--------------------------------------------------------------------------------

test('filter: empty string removed', function()
  eq(rg_to_vim({ '', 'foo' }, {}), result('\\vfoo'))
end)

test('filter: multiple empty strings removed', function()
  eq(rg_to_vim({ '', 'foo', '', 'bar', '' }, {}), result('\\vfoo|bar'))
end)

test('filter: all empty returns nil', function()
  eq(rg_to_vim({ '', '' }, {}), result(nil))
end)

test('filter: single empty returns nil', function()
  eq(rg_to_vim({ '' }, {}), result(nil))
end)

--------------------------------------------------------------------------------
--- Fixed mode (-F) ------------------------------------------------------------
--------------------------------------------------------------------------------

test('fixed: single pattern', function()
  eq(rg_to_vim({ 'foo' }, { fixed = true }), result('\\Vfoo'))
end)

test('fixed: two patterns joined with escaped bar', function()
  eq(rg_to_vim({ 'foo', 'bar' }, { fixed = true }), result('\\Vfoo\\|bar'))
end)

test('fixed: three patterns', function()
  eq(rg_to_vim({ 'foo', 'bar', 'baz' }, { fixed = true }), result('\\Vfoo\\|bar\\|baz'))
end)

test('fixed: pattern with regex metacharacters treated literally', function()
  -- ^foo and ^bar are literal strings in fixed mode
  eq(rg_to_vim({ '^foo', '^bar' }, { fixed = true }), result('\\V^foo\\|^bar'))
end)

test('fixed: pattern with backslash', function()
  eq(rg_to_vim({ 'foo\\bar', 'baz' }, { fixed = true }), result('\\Vfoo\\\\bar\\|baz'))
end)

test('fixed: pattern with forward slash', function()
  eq(rg_to_vim({ 'foo/bar', 'baz' }, { fixed = true }), result('\\Vfoo\\/bar\\|baz'))
end)

test('fixed: empty patterns filtered', function()
  eq(rg_to_vim({ '', 'foo', '' }, { fixed = true }), result('\\Vfoo'))
end)

--------------------------------------------------------------------------------
--- Word mode (-w) -------------------------------------------------------------
--------------------------------------------------------------------------------

test('word: single pattern gets boundaries', function()
  eq(rg_to_vim({ 'foo' }, { word = true }), result('\\v<foo>'))
end)

test('word: two patterns each get boundaries', function()
  eq(rg_to_vim({ 'foo', 'bar' }, { word = true }), result('\\v<foo>|<bar>'))
end)

test('word: three patterns', function()
  eq(rg_to_vim({ 'foo', 'bar', 'baz' }, { word = true }), result('\\v<foo>|<bar>|<baz>'))
end)

test('word: pattern with internal alternation', function()
  -- Single pattern foo|bar with -w: boundaries wrap the whole alternation
  -- Two patterns where one has alternation: each translated separately
  eq(rg_to_vim({ 'foo|bar', 'baz' }, { word = true }), result('\\v<foo|bar>|<baz>'))
end)

test('word: empty patterns filtered', function()
  eq(rg_to_vim({ '', 'foo', '' }, { word = true }), result('\\v<foo>'))
end)

--------------------------------------------------------------------------------
--- Fixed + word mode (-wF) ----------------------------------------------------
--------------------------------------------------------------------------------

test('fixed+word: single pattern', function()
  eq(rg_to_vim({ 'foo' }, { fixed = true, word = true }), result('\\V\\<foo\\>'))
end)

test('fixed+word: two patterns', function()
  eq(rg_to_vim({ 'foo', 'bar' }, { fixed = true, word = true }), result('\\V\\<foo\\>\\|\\<bar\\>'))
end)

test('fixed+word: pattern with metacharacters', function()
  eq(rg_to_vim({ '^foo', 'bar$' }, { fixed = true, word = true }), result('\\V\\<^foo\\>\\|\\<bar$\\>'))
end)

--------------------------------------------------------------------------------
--- Case sensitivity -----------------------------------------------------------
--------------------------------------------------------------------------------

test('case-sensitive: single pattern', function()
  eq(rg_to_vim({ 'foo' }, { case = 'case-sensitive' }), result('\\C\\vfoo'))
end)

test('case-sensitive: merged patterns', function()
  eq(rg_to_vim({ 'foo', 'bar' }, { case = 'case-sensitive' }), result('\\C\\vfoo|bar'))
end)

test('case-insensitive: single pattern', function()
  eq(rg_to_vim({ 'foo' }, { case = 'case-insensitive' }), result('\\c\\vfoo'))
end)

test('case-insensitive: merged patterns', function()
  eq(rg_to_vim({ 'foo', 'bar' }, { case = 'case-insensitive' }), result('\\c\\vfoo|bar'))
end)

test('case-sensitive+fixed: merged patterns', function()
  eq(rg_to_vim({ 'foo', 'bar' }, { fixed = true, case = 'case-sensitive' }), result('\\C\\Vfoo\\|bar'))
end)

test('case-insensitive+fixed: merged patterns', function()
  eq(rg_to_vim({ 'foo', 'bar' }, { fixed = true, case = 'case-insensitive' }), result('\\c\\Vfoo\\|bar'))
end)

--------------------------------------------------------------------------------
--- Edge cases -----------------------------------------------------------------
--------------------------------------------------------------------------------

test('edge: single pattern with pipe is not split', function()
  -- A single pattern "a|b" should remain as alternation, not be treated as two patterns
  eq(rg_to_vim({ 'a|b' }, {}), result('\\va|b'))
end)

test('edge: empty list returns nil', function()
  eq(rg_to_vim({}, {}), result(nil))
end)

test('edge: whitespace-only pattern preserved', function()
  -- Whitespace is not empty, should be preserved
  eq(rg_to_vim({ ' ', 'foo' }, {}), result('\\v |foo'))
end)

test('edge: complex patterns merged', function()
  eq(rg_to_vim({ '\\bfoo\\b', '\\bbar\\b' }, {}), result('\\v<foo>|<bar>'))
end)

--------------------------------------------------------------------------------
--- Summary --------------------------------------------------------------------
--------------------------------------------------------------------------------

h.summary()
