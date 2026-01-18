-- lua/brook/pattern/types.lua

--- Type definitions for the pattern translation pipeline.
---
--- Defines token types, classifications, and enums used across tokenise, parse
--- and translate phases. Token types are aligned with the rust regex crate's
--- lexical grammar.
---
---@module 'brook.pattern.types'
local M = {}

--------------------------------------------------------------------------------
--- Token Types (outside character classes) ------------------------------------
--------------------------------------------------------------------------------

---@enum brook.pattern.TokenType
M.token_type = {
  -- literals and metacharacters
  literal = 'literal',           -- a, 1, =, <
  dot = 'dot',                   -- .
  anchor = 'anchor',             -- ^, $
  alternation = 'alternation',   -- |
  quantifier = 'quantifier',     -- *, +, ?, {n}, {n,}, {n,m}

  -- grouping
  group_open = 'group_open',     -- (, (?:, (?P<foo>, (?<foo>, (?=, (?!, (?<=, (?<!, (?>
  group_close = 'group_close',   -- )

  -- character classes
  char_class_open = 'char_class_open',   -- [, [^
  char_class_close = 'char_class_close', -- ]

  -- escape sequences: boundaries and anchors
  escape_boundary = 'escape_boundary', -- \b, \B, \b{start}, \b{end}, \<, \>

  -- escape sequences: character classes
  escape_class = 'escape_class', -- \d, \D, \w, \W, \s, \S, \h, \H, \v, \V

  -- escape sequences: literals (including special chars)
  escape_literal = 'escape_literal', -- \n, \r, \t, \f, \a, \\, \., \*, etc.

  -- escape sequences: numeric
  escape_hex = 'escape_hex',         -- \x7F, \x{10FFFF}
  escape_unicode = 'escape_unicode', -- \u007F, \u{7F}, \U0000007F, \U{7F}
  escape_octal = 'escape_octal',     -- \0, \00, \123, \o{177}

  -- escape sequences: unicode properties
  escape_property = 'escape_property', -- \p{...}, \P{...}

  -- escape sequences: backreferences (unsupported in default rust regex, but
  -- recognised for PCRE2 mode)
  escape_backref = 'escape_backref', -- \1 through \9

  -- special: forward slash (search delimiter in Vim)
  slash = 'slash', -- /
}

--------------------------------------------------------------------------------
--- Character Class Token Types (inside [...]) ---------------------------------
--------------------------------------------------------------------------------

--- The cc_ prefix distinguishes them from top-level tokens.
---
---@enum brook.pattern.CCTokenType
M.cc_token_type = {
  cc_literal = 'cc_literal',             -- a, !, ] (when literal)
  cc_range = 'cc_range',                 -- a-z, 0-9
  cc_escape_class = 'cc_escape_class',   -- \d, \D, \w, \W, \s, \S
  cc_escape_literal = 'cc_escape_literal', -- \n, \], \\, \b (literal b)
  cc_escape_hex = 'cc_escape_hex',       -- \x7F, \x{...}
  cc_escape_unicode = 'cc_escape_unicode', -- \u{...}
  cc_escape_octal = 'cc_escape_octal',   -- \0, \00, \123, \o{...}
  cc_escape_property = 'cc_escape_property', -- \p{...}, \P{...}
  cc_posix = 'cc_posix',                 -- [:alpha:], [:digit:], etc.
  cc_intersection = 'cc_intersection',   -- && (set intersection)
  cc_nested_open = 'cc_nested_open',     -- [ (nested class open)
  cc_nested_close = 'cc_nested_close',   -- ] (nested class close)
}

--------------------------------------------------------------------------------
--- Group Kinds ----------------------------------------------------------------
--------------------------------------------------------------------------------

--- Group kinds recognised by the tokeniser.
---
--- The tokeniser identifies the syntactic form of each group opener. Some
--- kinds (lookarounds, atomic) are not supported by default Rust regex but
--- are supported by ripgrep with PCRE2. The tokeniser recognises them all;
--- the parser decides what to reject.
---
---@enum brook.pattern.GroupKind
M.group_kind = {
  -- standard groups
  capturing = 'capturing',           -- (
  non_capturing = 'non_capturing',   -- (?:

  -- named groups: name is extracted into token.name field
  named_python = 'named_python',     -- (?P<foo>
  named_pcre = 'named_pcre',         -- (?<foo>

  -- lookarounds (PCRE2 only, not default rust regex)
  lookahead_pos = 'lookahead_pos',   -- (?=
  lookahead_neg = 'lookahead_neg',   -- (?!
  lookbehind_pos = 'lookbehind_pos', -- (?<=
  lookbehind_neg = 'lookbehind_neg', -- (?<!

  -- atomic group (PCRE2 only)
  atomic = 'atomic',                 -- (?>

  -- flag groups
  flags = 'flags',                   -- (?i), (?-i), (?im-s), (?i:...), etc.
}

--------------------------------------------------------------------------------
--- Escape Classifications (assigned by parser) --------------------------------
--------------------------------------------------------------------------------

--- Semantic classifications for escape sequences.
--- These are assigned by the parser, not the tokeniser.
---
---@enum brook.pattern.EscapeClass
M.escape_class = {
  -- character class shorthands
  shorthand_word = 'shorthand_word',       -- \w, \d
  shorthand_nonword = 'shorthand_nonword', -- \s, \W, \t, \n, \r
  shorthand_unknown = 'shorthand_unknown', -- \S, \D

  -- boundaries
  boundary = 'boundary',           -- \b
  boundary_neg = 'boundary_neg',   -- \B
  anchor_start = 'anchor_start',   -- \A
  anchor_end = 'anchor_end',       -- \z

  -- unicode properties (unsupported)
  unicode_prop = 'unicode_prop', -- \p{...}, \P{...}

  -- backreferences (unsupported)
  backref = 'backref', -- \1-\9

  -- escaped literals
  escaped_literal = 'escaped_literal', -- \(, \., \\, etc.
}

--------------------------------------------------------------------------------
--- Wordness -------------------------------------------------------------------
--------------------------------------------------------------------------------

--- Wordness classification for boundary translation.
---
---@enum brook.pattern.Wordness
M.wordness = {
  word = 'word',         -- matches only word characters
  non_word = 'non_word', -- matches only non-word characters
  unknown = 'unknown',   -- could match either
}

--------------------------------------------------------------------------------
--- Token Structures -----------------------------------------------------------
--------------------------------------------------------------------------------

--- Base token fields shared by all tokens.
---
---@class brook.pattern.TokenBase
---@field type brook.pattern.TokenType|brook.pattern.CCTokenType
---@field value string Raw string content
---@field pos integer Starting position in input (1-indexed)

--- Literal token.
---
---@class brook.pattern.LiteralToken : brook.pattern.TokenBase
---@field type 'literal'

--- Dot token.
---
---@class brook.pattern.DotToken : brook.pattern.TokenBase
---@field type 'dot'

--- Anchor token (^ or $).
---
---@class brook.pattern.AnchorToken : brook.pattern.TokenBase
---@field type 'anchor'

--- Alternation token.
---
---@class brook.pattern.AlternationToken : brook.pattern.TokenBase
---@field type 'alternation'

--- Quantifier token.
---
---@class brook.pattern.QuantifierToken : brook.pattern.TokenBase
---@field type 'quantifier'
---@field greedy boolean Whether the quantifier is greedy
---@field possessive? boolean Whether the quantifier is possessive

--- Group open token.
---
--- For named groups (named_python, named_pcre), the `name` field contains the
--- capture group name extracted from the pattern.
---
--- For flag groups, the `flags` field contains the flag characters. This may
--- include a hyphen for flag negation (e.g., "i-m" for `(?i-m:...)`).
---
---@class brook.pattern.GroupOpenToken : brook.pattern.TokenBase
---@field type 'group_open'
---@field kind brook.pattern.GroupKind
---@field name? string For named groups: the capture name (e.g., "foo" from (?P<foo>)
---@field flags? string For flag groups: the flag string (e.g., "i", "-i", "im-s")
---@field scoped? boolean For flag groups: true if scoped (?i:...), false if standalone (?i)

--- Group close token.
---
---@class brook.pattern.GroupCloseToken : brook.pattern.TokenBase
---@field type 'group_close'

--- Character class open token.
---
---@class brook.pattern.CharClassOpenToken : brook.pattern.TokenBase
---@field type 'char_class_open'
---@field negated boolean Whether the class is negated ([^...)
---@field wordness? brook.pattern.Wordness Computed wordness (added by parser)

--- Character class close token.
---
---@class brook.pattern.CharClassCloseToken : brook.pattern.TokenBase
---@field type 'char_class_close'

--- Escape boundary token (\b, \B, \A, \z, etc.).
---
---@class brook.pattern.EscapeBoundaryToken : brook.pattern.TokenBase
---@field type 'escape_boundary'
---@field boundary_kind string The specific boundary: 'word', 'word_neg', 'start', 'end', 'word_start', 'word_end', 'word_start_half', 'word_end_half'
---@field prev_wordness? brook.pattern.Wordness For \b: wordness of preceding atom (added by parser)
---@field next_wordness? brook.pattern.Wordness For \b: wordness of following atom (added by parser)

--- Escape class token (\d, \w, \s, etc.).
---
---@class brook.pattern.EscapeClassToken : brook.pattern.TokenBase
---@field type 'escape_class'
---@field wordness? brook.pattern.Wordness Wordness classification (added by parser)

--- Escape literal token (\n, \t, \\, \., etc.).
---
---@class brook.pattern.EscapeLiteralToken : brook.pattern.TokenBase
---@field type 'escape_literal'

--- Escape hex token (\x7F, \x{...}).
---
---@class brook.pattern.EscapeHexToken : brook.pattern.TokenBase
---@field type 'escape_hex'

--- Escape unicode token (\u{...}, \U{...}).
---
---@class brook.pattern.EscapeUnicodeToken : brook.pattern.TokenBase
---@field type 'escape_unicode'

--- Escape octal token (\0, \00, \123, \o{...}).
---
---@class brook.pattern.EscapeOctalToken : brook.pattern.TokenBase
---@field type 'escape_octal'

--- Escape property token (\p{...}, \P{...}).
---
---@class brook.pattern.EscapePropertyToken : brook.pattern.TokenBase
---@field type 'escape_property'
---@field negated boolean Whether it's \P (negated) vs \p

--- Escape backref token (\1-\9).
---
---@class brook.pattern.EscapeBackrefToken : brook.pattern.TokenBase
---@field type 'escape_backref'

--- Forward slash token.
---
---@class brook.pattern.SlashToken : brook.pattern.TokenBase
---@field type 'slash'

--- Character class literal token.
---
---@class brook.pattern.CCLiteralToken : brook.pattern.TokenBase
---@field type 'cc_literal'

--- Character class range token.
---
---@class brook.pattern.CCRangeToken : brook.pattern.TokenBase
---@field type 'cc_range'
---@field from string Start of range
---@field to string End of range

--- Character class escape class token.
---
---@class brook.pattern.CCEscapeClassToken : brook.pattern.TokenBase
---@field type 'cc_escape_class'

--- Character class escape literal token.
---
---@class brook.pattern.CCEscapeLiteralToken : brook.pattern.TokenBase
---@field type 'cc_escape_literal'

--- Character class escape hex token.
---
---@class brook.pattern.CCEscapeHexToken : brook.pattern.TokenBase
---@field type 'cc_escape_hex'

--- Character class escape unicode token.
---
---@class brook.pattern.CCEscapeUnicodeToken : brook.pattern.TokenBase
---@field type 'cc_escape_unicode'

--- Character class escape octal token.
---
---@class brook.pattern.CCEscapeOctalToken : brook.pattern.TokenBase
---@field type 'cc_escape_octal'

--- Character class escape property token.
---
---@class brook.pattern.CCEscapePropertyToken : brook.pattern.TokenBase
---@field type 'cc_escape_property'
---@field negated boolean

--- Character class POSIX token.
---
---@class brook.pattern.CCPosixToken : brook.pattern.TokenBase
---@field type 'cc_posix'
---@field class_name string The POSIX class name (alpha, digit, etc.)
---@field negated boolean Whether it's [:^alpha:] (negated)

--- Character class intersection token.
---
---@class brook.pattern.CCIntersectionToken : brook.pattern.TokenBase
---@field type 'cc_intersection'

--- Nested character class open token.
---
---@class brook.pattern.CCNestedOpenToken : brook.pattern.TokenBase
---@field type 'cc_nested_open'
---@field negated boolean

--- Nested character class close token.
---
---@class brook.pattern.CCNestedCloseToken : brook.pattern.TokenBase
---@field type 'cc_nested_close'

--- Union of all token types.
---
---@alias brook.pattern.Token
---| brook.pattern.LiteralToken
---| brook.pattern.DotToken
---| brook.pattern.AnchorToken
---| brook.pattern.AlternationToken
---| brook.pattern.QuantifierToken
---| brook.pattern.GroupOpenToken
---| brook.pattern.GroupCloseToken
---| brook.pattern.CharClassOpenToken
---| brook.pattern.CharClassCloseToken
---| brook.pattern.EscapeBoundaryToken
---| brook.pattern.EscapeClassToken
---| brook.pattern.EscapeLiteralToken
---| brook.pattern.EscapeHexToken
---| brook.pattern.EscapeUnicodeToken
---| brook.pattern.EscapeOctalToken
---| brook.pattern.EscapePropertyToken
---| brook.pattern.EscapeBackrefToken
---| brook.pattern.SlashToken
---| brook.pattern.CCLiteralToken
---| brook.pattern.CCRangeToken
---| brook.pattern.CCEscapeClassToken
---| brook.pattern.CCEscapeLiteralToken
---| brook.pattern.CCEscapeHexToken
---| brook.pattern.CCEscapeUnicodeToken
---| brook.pattern.CCEscapeOctalToken
---| brook.pattern.CCEscapePropertyToken
---| brook.pattern.CCPosixToken
---| brook.pattern.CCIntersectionToken
---| brook.pattern.CCNestedOpenToken
---| brook.pattern.CCNestedCloseToken

--------------------------------------------------------------------------------
--- Parse Result ---------------------------------------------------------------
--------------------------------------------------------------------------------

--- Result of parsing: either success with tokens or failure with error.
---
---@class brook.pattern.ParseResult
---@field tokens? brook.pattern.Token[] Annotated tokens (nil if error)
---@field warnings string[] Collected warnings (may be empty)
---@field error? string Error message (nil if success)

--------------------------------------------------------------------------------
--- Helper Sets ----------------------------------------------------------------
--------------------------------------------------------------------------------

--- Characters that are word characters for wordness classification.
M.word_chars = {
  a = true, b = true, c = true, d = true, e = true, f = true, g = true,
  h = true, i = true, j = true, k = true, l = true, m = true, n = true,
  o = true, p = true, q = true, r = true, s = true, t = true, u = true,
  v = true, w = true, x = true, y = true, z = true,
  A = true, B = true, C = true, D = true, E = true, F = true, G = true,
  H = true, I = true, J = true, K = true, L = true, M = true, N = true,
  O = true, P = true, Q = true, R = true, S = true, T = true, U = true,
  V = true, W = true, X = true, Y = true, Z = true,
  ['0'] = true, ['1'] = true, ['2'] = true, ['3'] = true, ['4'] = true,
  ['5'] = true, ['6'] = true, ['7'] = true, ['8'] = true, ['9'] = true,
  ['_'] = true,
}

--- Escape sequences that represent word characters.
M.word_escapes = {
  ['\\w'] = true,
  ['\\d'] = true,
}

--- Escape sequences that represent non-word characters.
M.non_word_escapes = {
  ['\\s'] = true,
  ['\\W'] = true,
  ['\\t'] = true,
  ['\\n'] = true,
  ['\\r'] = true,
}

--- Escape sequences with unknown wordness (match both word and non-word).
M.unknown_escapes = {
  ['\\S'] = true,
  ['\\D'] = true,
}

--------------------------------------------------------------------------------
--- Pattern Options ------------------------------------------------------------
--------------------------------------------------------------------------------

---@enum brook.pattern.SearchCase
M.search_case = {
  sensitive = 'case-sensitive',
  insensitive = 'case-insensitive',
}

--- Options controlling pattern translation.
---
---@class brook.pattern.TranslateOpts
---@field word? boolean Match whole words only
---@field fixed? boolean Treat pattern as literal string
---@field case? brook.pattern.SearchCase Case sensitivity

--------------------------------------------------------------------------------
--- Translation Results --------------------------------------------------------
--------------------------------------------------------------------------------

--- Internal result from translator: includes full warnings list.
---
---@class brook.pattern.TranslatorResult
---@field pattern string Vim regex pattern
---@field warnings string[] All warnings (may be empty)

--- Public result matching legacy interface: single formatted warning.
---
---@class brook.pattern.TranslateResult
---@field pattern string Vim regex pattern
---@field warning? string Warning message (nil if none)

return M
