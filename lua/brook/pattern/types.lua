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
  literal = 'literal',         -- a, 1, =, <
  dot = 'dot',                 -- .
  anchor = 'anchor',           -- ^, $
  alternation = 'alternation', -- |
  quantifier = 'quantifier',   -- *, +, ?, {n}, {n,}, {n,m}

  -- grouping
  group_open = 'group_open',   -- (, (?:, (?P<foo>, (?<foo>, (?=, (?!, (?<=, (?<!, (?>
  group_close = 'group_close', -- )

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
  cc_literal = 'cc_literal',                 -- a, !, ] (when literal)
  cc_range = 'cc_range',                     -- a-z, 0-9
  cc_escape_class = 'cc_escape_class',       -- \d, \D, \w, \W, \s, \S
  cc_escape_literal = 'cc_escape_literal',   -- \n, \], \\, \b (literal b)
  cc_escape_hex = 'cc_escape_hex',           -- \x7F, \x{...}
  cc_escape_unicode = 'cc_escape_unicode',   -- \u{...}
  cc_escape_octal = 'cc_escape_octal',       -- \0, \00, \123, \o{...}
  cc_escape_property = 'cc_escape_property', -- \p{...}, \P{...}
  cc_posix = 'cc_posix',                     -- [:alpha:], [:digit:], etc.
  cc_intersection = 'cc_intersection',       -- && (set intersection)
  cc_nested_open = 'cc_nested_open',         -- [ (nested class open)
  cc_nested_close = 'cc_nested_close',       -- ] (nested class close)
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
  capturing = 'capturing',         -- (
  non_capturing = 'non_capturing', -- (?:

  -- named groups: name is extracted into token.name field
  named_python = 'named_python', -- (?P<foo>
  named_pcre = 'named_pcre',     -- (?<foo>

  -- lookarounds (PCRE2 only, not default rust regex)
  lookahead_pos = 'lookahead_pos',   -- (?=
  lookahead_neg = 'lookahead_neg',   -- (?!
  lookbehind_pos = 'lookbehind_pos', -- (?<=
  lookbehind_neg = 'lookbehind_neg', -- (?<!

  -- atomic group (PCRE2 only)
  atomic = 'atomic', -- (?>

  -- flag groups
  flags = 'flags', -- (?i), (?-i), (?im-s), (?i:...), etc.
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
  boundary = 'boundary',         -- \b
  boundary_neg = 'boundary_neg', -- \B
  anchor_start = 'anchor_start', -- \A
  anchor_end = 'anchor_end',     -- \z

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
--- Token Structure ------------------------------------------------------------
--------------------------------------------------------------------------------

--- Unified token type for all pattern tokens.
---
--- All tokens share common fields (type, value, pos). Additional fields are
--- present only for specific token types:
---
--- quantifier:
---   greedy, possessive
---
--- group_open:
---   kind, name (named groups), flags (flag groups), scoped (flag groups)
---
--- char_class_open, cc_nested_open:
---   negated
---
--- escape_boundary:
---   boundary_kind, prev_wordness, next_wordness, escape_class
---
--- escape_class, escape_literal, escape_hex, escape_unicode, escape_octal:
---   escape_class (semantic classification from parser)
---
--- cc_range:
---   from, to
---
--- cc_posix:
---   class_name, negated
---
--- cc_escape_property:
---   negated
---
--- Most token types (added by parser):
---   wordness
---
---@class brook.pattern.Token
---@field type brook.pattern.TokenType|brook.pattern.CCTokenType
---@field value string Raw string content
---@field pos integer Starting position in input (1-indexed)
---@field greedy? boolean Quantifier: whether greedy
---@field possessive? boolean Quantifier: whether possessive
---@field kind? brook.pattern.GroupKind Group open: group kind
---@field name? string Named groups: capture name
---@field flags? string Flag groups: flag string
---@field scoped? boolean Flag groups: scoped or standalone
---@field negated? boolean Char class open, cc_nested_open, cc_posix, cc_escape_property: negated
---@field boundary_kind? string Escape boundary: word, word_neg, start, end, etc.
---@field prev_wordness? brook.pattern.Wordness Escape boundary \b: wordness before
---@field next_wordness? brook.pattern.Wordness Escape boundary \b: wordness after
---@field escape_class? brook.pattern.EscapeClass Parser semantic classification
---@field wordness? brook.pattern.Wordness Token wordness (added by parser)
---@field from? string CC range: start character
---@field to? string CC range: end character
---@field class_name? string CC POSIX: class name

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

--- Options controlling pattern translation.
---
---@class brook.pattern.TranslateOpts
---@field word? boolean Match whole words only
---@field fixed? boolean Treat pattern as literal string
---@field case? brook.args.SearchCase Case sensitivity

--------------------------------------------------------------------------------
--- Translation Results --------------------------------------------------------
--------------------------------------------------------------------------------

--- Internal result from translator: includes full warnings list.
---
---@class brook.pattern.TranslatorResult
---@field prefix string Mode and case prefix (e.g. \C\v)
---@field body string Pattern body without prefix
---@field pattern string Full Vim regex pattern (prefix .. body)
---@field error? string Error message, if any
---@field warnings? string[] All warnings (may be empty)

--- Public result matching legacy interface: single formatted warning.
---
---@class brook.pattern.TranslateResult
---@field pattern string Vim regex pattern
---@field error? string Error message, if any
---@field warning? string Warning message (nil if none)

return M
