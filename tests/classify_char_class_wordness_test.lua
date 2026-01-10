-- Run with:
--   nvim --headless -c "luafile tests/classify_char_class_wordness_test.lua" -c "q"

local h = require('tests.harness')
local test = h.test
local eq = h.eq

local m = require('brook.pattern')
local classify = m._classify_char_class_wordness
local WORD = m._wordness.word
local NON_WORD = m._wordness.non_word
local UNKNOWN = m._wordness.unknown

--------------------------------------------------------------------------------
--- Not a character class ------------------------------------------------------
--------------------------------------------------------------------------------

test('not a class: plain word', function()
  eq(classify('hello'), nil)
end)

test('not a class: escaped opening bracket', function()
  eq(classify('\\[a-z]'), nil)
end)

test('not a class: starts with other metachar', function()
  eq(classify('^[a-z]'), nil)
end)

test('not a class: empty string', function()
  eq(classify(''), nil)
end)

--------------------------------------------------------------------------------
--- Word-only: literal characters ----------------------------------------------
--------------------------------------------------------------------------------

test('word-only: single lowercase letter', function()
  eq(classify('[a]'), WORD)
end)

test('word-only: single uppercase letter', function()
  eq(classify('[Z]'), WORD)
end)

test('word-only: single digit', function()
  eq(classify('[5]'), WORD)
end)

test('word-only: underscore', function()
  eq(classify('[_]'), WORD)
end)

test('word-only: multiple word chars', function()
  eq(classify('[aeiou]'), WORD)
end)

test('word-only: mixed case and digits', function()
  eq(classify('[a1B2c3]'), WORD)
end)

--------------------------------------------------------------------------------
--- Word-only: ranges ----------------------------------------------------------
--------------------------------------------------------------------------------

test('word-only: lowercase range', function()
  eq(classify('[a-z]'), WORD)
end)

test('word-only: uppercase range', function()
  eq(classify('[A-Z]'), WORD)
end)

test('word-only: digit range', function()
  eq(classify('[0-9]'), WORD)
end)

test('word-only: partial lowercase range', function()
  eq(classify('[b-y]'), WORD)
end)

test('word-only: partial digit range', function()
  eq(classify('[1-5]'), WORD)
end)

test('word-only: multiple ranges', function()
  eq(classify('[a-zA-Z0-9]'), WORD)
end)

test('word-only: range with underscore', function()
  eq(classify('[a-z_]'), WORD)
end)

test('word-only: reversed range (nonsensical but word chars)', function()
  eq(classify('[z-a]'), WORD)
end)

--------------------------------------------------------------------------------
--- Word-only: escape sequences ------------------------------------------------
--------------------------------------------------------------------------------

test('word-only: \\w', function()
  eq(classify('[\\w]'), WORD)
end)

test('word-only: \\d', function()
  eq(classify('[\\d]'), WORD)
end)

test('word-only: \\w with literal chars', function()
  eq(classify('[\\w_]'), WORD)
end)

test('word-only: \\d with range', function()
  eq(classify('[\\da-f]'), WORD)
end)

--------------------------------------------------------------------------------
--- Non-word: escape sequences -------------------------------------------------
--------------------------------------------------------------------------------

test('non-word: \\s', function()
  eq(classify('[\\s]'), NON_WORD)
end)

test('non-word: \\W', function()
  eq(classify('[\\W]'), NON_WORD)
end)

test('non-word: \\s and \\W together', function()
  eq(classify('[\\s\\W]'), NON_WORD)
end)

--------------------------------------------------------------------------------
--- Non-word: escaped literal non-word chars -----------------------------------
--------------------------------------------------------------------------------

test('non-word: escaped hyphen', function()
  eq(classify('[\\-]'), NON_WORD)
end)

test('non-word: escaped dot', function()
  eq(classify('[\\.]'), NON_WORD)
end)

test('non-word: escaped bracket', function()
  eq(classify('[\\[]'), NON_WORD)
end)

test('non-word: escaped backslash', function()
  eq(classify('[\\\\]'), NON_WORD)
end)

test('non-word: multiple escaped punctuation', function()
  eq(classify('[\\-\\.]'), NON_WORD)
end)

--------------------------------------------------------------------------------
--- Non-word: stray hyphen -----------------------------------------------------
--------------------------------------------------------------------------------

test('non-word: leading hyphen', function()
  eq(classify('[-]'), NON_WORD)
end)

test('non-word: trailing hyphen after non-word', function()
  eq(classify('[\\s-]'), NON_WORD)
end)

--------------------------------------------------------------------------------
--- Unknown: mixed word and non-word -------------------------------------------
--------------------------------------------------------------------------------

test('unknown: word char and space escape', function()
  eq(classify('[a\\s]'), UNKNOWN)
end)

test('unknown: range and non-word escape', function()
  eq(classify('[a-z\\W]'), UNKNOWN)
end)

test('unknown: leading hyphen with word chars', function()
  eq(classify('[-a-z]'), UNKNOWN)
end)

test('unknown: trailing hyphen with word chars', function()
  eq(classify('[a-z-]'), UNKNOWN)
end)

test('unknown: word and literal punctuation', function()
  eq(classify('[a.]'), UNKNOWN)
end)

test('unknown: word and quote', function()
  eq(classify('[a-zA-Z"]'), UNKNOWN)
end)

test('unknown: digit range and punctuation', function()
  eq(classify('[0-9.]'), UNKNOWN)
end)

--------------------------------------------------------------------------------
--- Unknown: negated classes ---------------------------------------------------
--------------------------------------------------------------------------------

test('unknown: negated word range', function()
  eq(classify('[^a-z]'), UNKNOWN)
end)

test('unknown: negated non-word', function()
  eq(classify('[^\\s]'), UNKNOWN)
end)

test('unknown: negated mixed', function()
  eq(classify('[^a-z\\s]'), UNKNOWN)
end)

--------------------------------------------------------------------------------
--- Unknown: ambiguous escapes -------------------------------------------------
--------------------------------------------------------------------------------

test('unknown: \\S (non-whitespace includes word chars)', function()
  eq(classify('[\\S]'), UNKNOWN)
end)

test('unknown: \\D (non-digit includes letters)', function()
  eq(classify('[\\D]'), UNKNOWN)
end)

--------------------------------------------------------------------------------
--- Unknown: problematic ranges ------------------------------------------------
--------------------------------------------------------------------------------

test('unknown: A-z range (includes punctuation)', function()
  eq(classify('[A-z]'), UNKNOWN)
end)

test('unknown: range from digit to letter', function()
  eq(classify('[0-Z]'), UNKNOWN)
end)

test('unknown: range from punctuation to letter', function()
  eq(classify('[!-z]'), UNKNOWN)
end)

--------------------------------------------------------------------------------
--- Unknown: unclosed/malformed ------------------------------------------------
--------------------------------------------------------------------------------

test('unknown: unclosed bracket', function()
  eq(classify('[a-z'), UNKNOWN)
end)

test('unknown: empty class', function()
  eq(classify('[]'), UNKNOWN)
end)

--------------------------------------------------------------------------------
--- Edge cases: ] as first character -------------------------------------------
--------------------------------------------------------------------------------

test('edge: ] as first char is literal (non-word)', function()
  eq(classify('[]]'), NON_WORD)
end)

test('edge: ] as first char with word chars', function()
  eq(classify('[]a-z]'), UNKNOWN)
end)

test('edge: ] after negation', function()
  eq(classify('[^]]'), UNKNOWN)
end)

--------------------------------------------------------------------------------
--- Patterns with content after the class --------------------------------------
--------------------------------------------------------------------------------

test('with suffix: word class followed by quantifier', function()
  eq(classify('[a-z]+'), WORD)
end)

test('with suffix: word class followed by more pattern', function()
  eq(classify('[a-zA-Z][0-9]'), WORD)
end)

test('with suffix: non-word class followed by quantifier', function()
  eq(classify('[\\s]*'), NON_WORD)
end)

test('with suffix: unknown class followed by pattern', function()
  eq(classify('[a-z.]+foo'), UNKNOWN)
end)

--------------------------------------------------------------------------------
--- Combinations: multiple word-char ranges ------------------------------------
--------------------------------------------------------------------------------

test('combo: all three range types', function()
  eq(classify('[a-zA-Z0-9]'), WORD)
end)

test('combo: ranges and underscore', function()
  eq(classify('[a-z_A-Z]'), WORD)
end)

test('combo: ranges and \\w', function()
  eq(classify('[a-z\\w]'), WORD)
end)

test('combo: ranges and \\d', function()
  eq(classify('[A-Z\\d]'), WORD)
end)

test('combo: \\w and \\d together', function()
  eq(classify('[\\w\\d]'), WORD)
end)

--------------------------------------------------------------------------------
--- Combinations: multiple non-word atoms --------------------------------------
--------------------------------------------------------------------------------

test('combo: \\s and escaped punctuation', function()
  eq(classify('[\\s\\-\\.]'), NON_WORD)
end)

test('combo: \\W and leading hyphen', function()
  eq(classify('[\\W-]'), NON_WORD)
end)

test('combo: multiple escaped punctuation', function()
  eq(classify('[\\[\\]\\\\]'), NON_WORD)
end)

test('combo: ] as first and other non-word', function()
  eq(classify('[]\\-]'), NON_WORD)
end)

--------------------------------------------------------------------------------
--- Combinations: word and non-word (should be unknown) ------------------------
--------------------------------------------------------------------------------

test('combo: \\w and \\s', function()
  eq(classify('[\\w\\s]'), UNKNOWN)
end)

test('combo: \\d and \\W', function()
  eq(classify('[\\d\\W]'), UNKNOWN)
end)

test('combo: word range and escaped dot', function()
  eq(classify('[a-z\\.]'), UNKNOWN)
end)

test('combo: word range and leading hyphen', function()
  eq(classify('[-a-z]'), UNKNOWN)
end)

test('combo: underscore and \\s', function()
  eq(classify('[_\\s]'), UNKNOWN)
end)

test('combo: digit and literal space', function()
  eq(classify('[0-9 ]'), UNKNOWN)
end)

test('combo: \\w and literal punctuation', function()
  eq(classify('[\\w.]'), UNKNOWN)
end)

--------------------------------------------------------------------------------
--- Combinations: ambiguous escapes with others --------------------------------
--------------------------------------------------------------------------------

test('combo: \\S and \\w', function()
  eq(classify('[\\S\\w]'), UNKNOWN)
end)

test('combo: \\D and \\d', function()
  eq(classify('[\\D\\d]'), UNKNOWN)
end)

test('combo: \\S and \\s', function()
  eq(classify('[\\S\\s]'), UNKNOWN)
end)

test('combo: \\D and word range', function()
  eq(classify('[\\Da-z]'), UNKNOWN)
end)

test('combo: \\S alone', function()
  eq(classify('[\\S]'), UNKNOWN)
end)

--------------------------------------------------------------------------------
--- Edge cases: range boundaries -----------------------------------------------
--------------------------------------------------------------------------------

test('edge: range a-a (single char)', function()
  eq(classify('[a-a]'), WORD)
end)

test('edge: range 0-0 (single char)', function()
  eq(classify('[0-0]'), WORD)
end)

test('edge: range Z-Z (single char)', function()
  eq(classify('[Z-Z]'), WORD)
end)

test('edge: adjacent ranges a-mn-z', function()
  eq(classify('[a-mn-z]'), WORD)
end)

test('edge: range /-0 (punctuation to digit)', function()
  eq(classify('[/-0]'), UNKNOWN)
end)

test('edge: range z-{ (letter to punctuation)', function()
  eq(classify('[z-{]'), UNKNOWN)
end)

test('edge: range @-A (punctuation to letter)', function()
  eq(classify('[@-A]'), UNKNOWN)
end)

test('edge: range Z-a (uppercase to lowercase, gap)', function()
  eq(classify('[Z-a]'), UNKNOWN)
end)

test('edge: range 9-A (digit to letter, gap)', function()
  eq(classify('[9-A]'), UNKNOWN)
end)

--------------------------------------------------------------------------------
--- Edge cases: escaped characters ---------------------------------------------
--------------------------------------------------------------------------------

test('edge: escaped word char \\a', function()
  eq(classify('[\\a]'), WORD)
end)

test('edge: escaped digit \\5', function()
  eq(classify('[\\5]'), WORD)
end)

test('edge: escaped underscore \\_', function()
  eq(classify('[\\_]'), WORD)
end)

test('edge: escaped caret \\^', function()
  eq(classify('[\\^]'), NON_WORD)
end)

test('edge: escaped dollar \\$', function()
  eq(classify('[\\$]'), NON_WORD)
end)

test('edge: escaped space \\ (backslash-space)', function()
  eq(classify('[\\ ]'), NON_WORD)
end)

--------------------------------------------------------------------------------
--- Edge cases: ] positioning --------------------------------------------------
--------------------------------------------------------------------------------

test('edge: ] only', function()
  eq(classify('[]]'), NON_WORD)
end)

test('edge: ] with word chars after', function()
  eq(classify('[]abc]'), UNKNOWN)
end)

test('edge: ] with word range after', function()
  eq(classify('[]a-z]'), UNKNOWN)
end)

test('edge: ] at end is not special', function()
  -- [a]] would be class [a] followed by literal ]
  eq(classify('[a]'), WORD)
end)

--------------------------------------------------------------------------------
--- Edge cases: hyphen positioning ---------------------------------------------
--------------------------------------------------------------------------------

test('edge: hyphen only', function()
  eq(classify('[-]'), NON_WORD)
end)

test('edge: hyphen at start and end', function()
  eq(classify('[--]'), NON_WORD)
end)

test('edge: escaped hyphen in middle', function()
  eq(classify('[a\\-z]'), UNKNOWN)
end)

test('edge: hyphen between non-range chars', function()
  -- _-_ is a range meaning just '_', which is word-only
  eq(classify('[_-_]'), WORD)
end)

--------------------------------------------------------------------------------
--- Edge cases: literal special chars ------------------------------------------
--------------------------------------------------------------------------------

test('edge: literal dot', function()
  eq(classify('[.]'), NON_WORD)
end)

test('edge: literal asterisk', function()
  eq(classify('[*]'), NON_WORD)
end)

test('edge: literal plus', function()
  eq(classify('[+]'), NON_WORD)
end)

test('edge: literal question mark', function()
  eq(classify('[?]'), NON_WORD)
end)

test('edge: literal caret not at start', function()
  eq(classify('[a^]'), UNKNOWN)
end)

test('edge: literal dollar', function()
  eq(classify('[$]'), NON_WORD)
end)

test('edge: literal pipe', function()
  eq(classify('[|]'), NON_WORD)
end)

test('edge: literal parentheses', function()
  eq(classify('[()]'), NON_WORD)
end)

test('edge: literal braces', function()
  eq(classify('[{}]'), NON_WORD)
end)

--------------------------------------------------------------------------------
--- Real-world patterns --------------------------------------------------------
--------------------------------------------------------------------------------

test('real: identifier start [a-zA-Z_]', function()
  eq(classify('[a-zA-Z_]'), WORD)
end)

test('real: identifier continue [a-zA-Z0-9_]', function()
  eq(classify('[a-zA-Z0-9_]'), WORD)
end)

test('real: hex digit [0-9a-fA-F]', function()
  eq(classify('[0-9a-fA-F]'), WORD)
end)

test('real: whitespace [\\s]', function()
  eq(classify('[\\s]'), NON_WORD)
end)

test('real: word boundary adjacent [\\w]', function()
  eq(classify('[\\w]'), WORD)
end)

test('real: punctuation set [.,;:]', function()
  eq(classify('[.,;:]'), NON_WORD)
end)

test('real: quote set ["\\\'`]', function()
  eq(classify('["\\\'`]'), NON_WORD)
end)

test('real: operator set [+\\-*/]', function()
  eq(classify('[+\\-*/]'), NON_WORD)
end)

test('real: bracket set [()\\[\\]{}]', function()
  eq(classify('[()\\[\\]{}]'), NON_WORD)
end)

test('real: word or hyphen [a-zA-Z-]', function()
  eq(classify('[a-zA-Z-]'), UNKNOWN)
end)

test('real: CSS identifier [a-zA-Z0-9_-]', function()
  eq(classify('[a-zA-Z0-9_-]'), UNKNOWN)
end)

--------------------------------------------------------------------------------
--- Summary --------------------------------------------------------------------
--------------------------------------------------------------------------------

h.summary()
