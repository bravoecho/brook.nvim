-- lua/brook/pattern/types.lua

--- Type definitions for the pattern translation pipeline.
---
--- Defines token types, classifications, and enums used across tokenise, parse
--- and translate phases.
---
---@module 'brook.pattern.types'
local M = {}

--------------------------------------------------------------------------------
--- Token Types ----------------------------------------------------------------
--------------------------------------------------------------------------------

--- Top-level token types (outside character classes).
---
---@enum brook.pattern.TokenType
M.token_type = {
  literal = 'literal',                   -- f, =, <
  escape = 'escape',                     -- \w, \b, \p{L}
  quantifier = 'quantifier',             -- *, +?, {2,3}
  group_open = 'group_open',             -- (, (?:, (?P<n>
  group_close = 'group_close',           -- )
  alternation = 'alternation',           -- |
  anchor = 'anchor',                     -- ^, $
  slash = 'slash',                       -- /
  char_class_open = 'char_class_open',   -- [, [^
  char_class_close = 'char_class_close', -- ]
}

--- Character class token types (inside [...]).
--- The cc_ prefix distinguishes them from top-level tokens.
---
---@enum brook.pattern.CCTokenType
M.cc_token_type = {
  cc_literal = 'cc_literal', -- a, !, ] (at start)
  cc_range = 'cc_range',     -- a-z, 0-9
  cc_escape = 'cc_escape',   -- \w, \s, \]
}

--------------------------------------------------------------------------------
--- Group Kinds ----------------------------------------------------------------
--------------------------------------------------------------------------------

--- Kinds of group openings.
---
---@enum brook.pattern.GroupKind
M.group_kind = {
  capturing = 'capturing',           -- (
  non_capturing = 'non_capturing',   -- (?:
  named_python = 'named_python',     -- (?P<name>
  named_pcre = 'named_pcre',         -- (?<name>
  lookahead_pos = 'lookahead_pos',   -- (?=
  lookahead_neg = 'lookahead_neg',   -- (?!
  lookbehind_pos = 'lookbehind_pos', -- (?<=
  lookbehind_neg = 'lookbehind_neg', -- (?<!
  atomic = 'atomic',                 -- (?>
}

--------------------------------------------------------------------------------
--- Escape Classifications -----------------------------------------------------
--------------------------------------------------------------------------------

--- Semantic classifications for escape sequences (assigned by parser).
---
---@enum brook.pattern.EscapeClass
M.escape_class = {
  shorthand_word = 'shorthand_word',       -- \w, \d
  shorthand_nonword = 'shorthand_nonword', -- \s, \W, \t, \n, \r
  shorthand_unknown = 'shorthand_unknown', -- \S, \D
  boundary = 'boundary',                   -- \b
  boundary_neg = 'boundary_neg',           -- \B (unsupported)
  anchor_start = 'anchor_start',           -- \A
  anchor_end = 'anchor_end',               -- \z
  unicode_prop = 'unicode_prop',           -- \p{...}, \P{...} (unsupported)
  backref = 'backref',                     -- \1-\9 (unsupported)
  escaped_literal = 'escaped_literal',     -- \(, \., \\, etc.
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
---@field type brook.pattern.TokenType|brook.pattern.CCTokenType Token category
---@field value string Raw string content
---@field pos integer Starting position in input (1-indexed)

--- Literal token (top-level).
---
---@class brook.pattern.LiteralToken : brook.pattern.TokenBase
---@field type 'literal'

--- Escape sequence token (top-level).
---
---@class brook.pattern.EscapeToken : brook.pattern.TokenBase
---@field type 'escape'
---@field escape_class? brook.pattern.EscapeClass Semantic classification (added by parser)
---@field wordness? brook.pattern.Wordness Wordness classification (added by parser)
---@field prev_wordness? brook.pattern.Wordness For \b: wordness of preceding atom (added by parser)
---@field next_wordness? brook.pattern.Wordness For \b: wordness of following atom (added by parser)

--- Quantifier token.
---
---@class brook.pattern.QuantifierToken : brook.pattern.TokenBase
---@field type 'quantifier'
---@field greedy boolean Whether the quantifier is greedy

--- Group open token.
---
---@class brook.pattern.GroupOpenToken : brook.pattern.TokenBase
---@field type 'group_open'
---@field kind brook.pattern.GroupKind Kind of group
---@field name? string For named groups: the capture name

--- Group close token.
---
---@class brook.pattern.GroupCloseToken : brook.pattern.TokenBase
---@field type 'group_close'

--- Alternation token.
---
---@class brook.pattern.AlternationToken : brook.pattern.TokenBase
---@field type 'alternation'

--- Anchor token (^ or $).
---
---@class brook.pattern.AnchorToken : brook.pattern.TokenBase
---@field type 'anchor'

--- Forward slash token.
---
---@class brook.pattern.SlashToken : brook.pattern.TokenBase
---@field type 'slash'

--- Character class open token.
---
---@class brook.pattern.CharClassOpenToken : brook.pattern.TokenBase
---@field type 'char_class_open'
---@field negated boolean Whether the class is negated ([^...)
---@field wordness? brook.pattern.Wordness Computed wordness of entire class (added by parser)

--- Character class close token.
---
---@class brook.pattern.CharClassCloseToken : brook.pattern.TokenBase
---@field type 'char_class_close'

--- Character class literal token (inside [...]).
---
---@class brook.pattern.CCLiteralToken : brook.pattern.TokenBase
---@field type 'cc_literal'

--- Character class range token (inside [...]).
---
---@class brook.pattern.CCRangeToken : brook.pattern.TokenBase
---@field type 'cc_range'
---@field from string Start of range
---@field to string End of range

--- Character class escape token (inside [...]).
---
---@class brook.pattern.CCEscapeToken : brook.pattern.TokenBase
---@field type 'cc_escape'

--- Union of all token types.
---
---@alias brook.pattern.Token
---| brook.pattern.LiteralToken
---| brook.pattern.EscapeToken
---| brook.pattern.QuantifierToken
---| brook.pattern.GroupOpenToken
---| brook.pattern.GroupCloseToken
---| brook.pattern.AlternationToken
---| brook.pattern.AnchorToken
---| brook.pattern.SlashToken
---| brook.pattern.CharClassOpenToken
---| brook.pattern.CharClassCloseToken
---| brook.pattern.CCLiteralToken
---| brook.pattern.CCRangeToken
---| brook.pattern.CCEscapeToken

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
  a = true,
  b = true,
  c = true,
  d = true,
  e = true,
  f = true,
  g = true,
  h = true,
  i = true,
  j = true,
  k = true,
  l = true,
  m = true,
  n = true,
  o = true,
  p = true,
  q = true,
  r = true,
  s = true,
  t = true,
  u = true,
  v = true,
  w = true,
  x = true,
  y = true,
  z = true,
  A = true,
  B = true,
  C = true,
  D = true,
  E = true,
  F = true,
  G = true,
  H = true,
  I = true,
  J = true,
  K = true,
  L = true,
  M = true,
  N = true,
  O = true,
  P = true,
  Q = true,
  R = true,
  S = true,
  T = true,
  U = true,
  V = true,
  W = true,
  X = true,
  Y = true,
  Z = true,
  ['0'] = true,
  ['1'] = true,
  ['2'] = true,
  ['3'] = true,
  ['4'] = true,
  ['5'] = true,
  ['6'] = true,
  ['7'] = true,
  ['8'] = true,
  ['9'] = true,
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
