# Ripgrep to "Very Magic" Vim Pattern Translation Specification

## Overview

This specification defines the translation from ripgrep (Rust regex) patterns to
Neovim's patterns in very magic mode (`\v`).

**Target Environment:**

- Neovim with `regexpengine=2` (NFA engine) for predictable behaviour
- Very magic mode (`\v`) for closer semantic alignment with ripgrep

**Design Principle:**

> Incorrect highlighting is worse than no highlighting.

When a pattern cannot be reliably translated, the translator returns `nil`
rather than producing a potentially incorrect result.

## Motivation

Ripgrep uses Rust's regex crate, which has PCRE-like syntax familiar to most
developers. Vim's traditional regex syntax differs significantly. This
translation enables:

1. Search register integration (`@/`) for `n`/`N` navigation
2. Match highlighting in the buffer
3. Seamless workflow between ripgrep results and Vim's native search

## Scope

### Features IN Scope

1. Literal characters and basic metacharacters
2. Vim-special characters requiring escaping
3. Character classes
4. Character class shorthands
5. Word boundaries
6. Quantifiers (greedy and non-greedy)
7. Groups (capturing and non-capturing)
8. Backreferences in patterns

### Features OUT of Scope

These features will cause the translator to return `nil`:

1. Lookarounds: `(?=...)` `(?!...)` `(?<=...)` `(?<!...)`
2. Named groups: `(?P<n>...)` `(?<n>...)`
3. Non-word boundary: `\B`
4. Anchors: `\A` `\z` (use `^` `$` instead)
5. Unicode categories: `\p{...}` `\P{...}`
6. Conditional patterns: `(?(condition)yes|no)`
7. Atomic groups: `(?>...)`
8. Possessive quantifiers: `*+` `++` `?+`

## Translation Rules

### 1. Mode Prefixes

- Regex (default) => `\v` (very magic: most punctuation is special)
- Fixed string (`-F`) => `\V` (very nomagic: only `\` is special)

### 2. Characters Literal in Ripgrep, Special in Very Magic

These must be escaped when they appear as literals outside character classes:

- `=` - quantifier in `\v` (synonym for `?`) => escape as `\=`
- `<` - start of word boundary in `\v` => escape as `\<`
- `>` - end of word boundary in `\v` => escape as `\>`
- `~` - last substitute string in `\v` => escape as `\~`
- `@` - complex pattern atoms (`@=`, `@!`, etc.) => escape as `\@`
- `&` - branch concatenation (rare) => escape as `\&`

**Test Cases:**

- `foo=bar` => `foo\=bar` (literal equals)
- `x~y` => `x\~y` (literal tilde)
- `a@b` => `a\@b` (literal at-sign)
- `a&b` => `a\&b` (literal ampersand)
- `a<b` => `a\<b` (literal less-than)
- `x > 0` => `x \> 0` (literal greater-than)
- `Vec<T>` => `Vec\<T\>` (generic type syntax)
- `<div>` => `\<div\>` (HTML tag)
- `[~=]= nil` => `[~=]\= nil` (inside class literal, outside escaped)
- `foo==bar` => `foo\=\=bar` (multiple equals)
- `@decorator` => `\@decorator` (Python decorator)
- `a && b` => `a \&\& b` (logical AND)

### 3. Characters Special in Both Engines

These pass through unchanged (both engines treat them as metacharacters):

- `.` - any character
- `*` - zero or more
- `+` - one or more
- `?` - zero or one
- `(` `)` - grouping
- `[` `]` - character class
- `|` - alternation
- `^` - start of line / negation in class
- `$` - end of line
- `\` - escape character
- `{` `}` - range quantifier

**Test Cases:**

- `a.b` => `a.b` (any char)
- `a*b` => `a*b` (zero or more)
- `a+b` => `a+b` (one or more)
- `a?b` => `a?b` (zero or one)
- `(foo)` => `(foo)` (capturing group)
- `foo|bar` => `foo|bar` (alternation)
- `^start` => `^start` (line start)
- `end$` => `end$` (line end)
- `a{2,3}` => `a{2,3}` (range quantifier)

### 4. Escaped Metacharacters (Literal in Both)

When ripgrep escapes a metacharacter to make it literal, the escape passes
through (very magic uses the same convention):

**Test Cases:**

- `\(` => `\(` (literal paren)
- `\)` => `\)` (literal paren)
- `\+` => `\+` (literal plus)
- `\?` => `\?` (literal question mark)
- `\{` => `\{` (literal brace)
- `\}` => `\}` (literal brace)
- `\[` => `\[` (literal bracket)
- `\]` => `\]` (literal bracket)
- `\|` => `\|` (literal pipe)
- `\.` => `\.` (literal dot)
- `\*` => `\*` (literal asterisk)
- `\\` => `\\` (literal backslash)
- `\^` => `\^` (literal caret)
- `\$` => `\$` (literal dollar)

### 5. Character Class Shorthands

These are compatible between engines and pass through:

- `\d` - digit `[0-9]`
- `\D` - non-digit
- `\w` - word character `[a-zA-Z0-9_]`
- `\W` - non-word character
- `\s` - whitespace
- `\S` - non-whitespace
- `\t` - tab
- `\n` - newline
- `\r` - carriage return

**Test Cases:**

- `\d+` => `\d+`
- `\w+` => `\w+`
- `\s*` => `\s*`
- `[\d\w]` => `[\d\w]`

### 6. Word Boundaries

- `\b` => `(<|>)` (word boundary, either side)
- `\B` => **unsupported**, return `nil`

Ripgrep's `\b` matches at any word boundary. Vim has separate `\<` (start) and
`\>` (end). Since we cannot determine from the pattern alone which side is
intended, we use `(<|>)` as a conservative translation that matches either.

**Test Cases:**

- `\bword\b` => `(<|>)word(<|>)` (word boundaries)
- `\btest` => `(<|>)test` (start boundary)
- `test\b` => `test(<|>)` (end boundary)
- `foo\bbar` => `foo(<|>)bar` (mid-pattern boundary)
- `\b\w+\b` => `(<|>)\w+(<|>)` (with shorthand)
- `\B` => `nil` (unsupported)
- `foo\Bbar` => `nil` (unsupported)

**Note on `-w` / `--word-regexp` flag:**

When the user passes `-w`, ripgrep wraps the pattern in `\b...\b` internally.
However, for the Vim pattern, we use the cleaner `<...>` word boundary syntax
since we know definitively it's a whole-word match:

- `-w hello` => `<hello>`
- `-w foo.*bar` => `<foo.*bar>`

### 7. Quantifiers

#### 7.1 Greedy Quantifiers (Pass Through)

- `a*` => `a*`
- `a+` => `a+`
- `a?` => `a?`
- `a{3}` => `a{3}`
- `a{3,}` => `a{3,}`
- `a{3,5}` => `a{3,5}`

#### 7.2 Non-Greedy Quantifiers (Translation Required)

Vim uses `\{-}` syntax for non-greedy matching:

- `a*?` => `a{-}` (zero or more, non-greedy)
- `a+?` => `a{-1,}` (one or more, non-greedy)
- `a??` => `a{-0,1}` (zero or one, non-greedy)
- `a{3}?` => `a{-3}` (exactly 3, non-greedy - vacuously)
- `a{3,}?` => `a{-3,}` (3 or more, non-greedy)
- `a{3,5}?` => `a{-3,5}` (3 to 5, non-greedy)

**Test Cases:**

- `.*?` => `.{-}` (common: match minimal)
- `.+?` => `.{-1,}` (at least one, minimal)
- `<.*?>` => `\<.{-}\>` (HTML tag, non-greedy)
- `".*?"` => `".{-}"` (quoted string)
- `\w+?` => `\w{-1,}` (word chars, minimal)
- `a{2,4}?` => `a{-2,4}` (range, non-greedy)
- `(ab)+?` => `(ab){-1,}` (group, non-greedy)

### 8. Character Classes

Inside `[...]`, most metacharacters lose their special meaning.

#### 8.1 Basic Syntax (Pass Through)

- `[abc]` => `[abc]` (simple class)
- `[a-z]` => `[a-z]` (range)
- `[^abc]` => `[^abc]` (negated class)
- `[a-zA-Z0-9]` => `[a-zA-Z0-9]` (multiple ranges)

#### 8.2 Special Positions Within Classes

- `[]abc]` => `[]abc]` (literal `]` at start)
- `[^]abc]` => `[^]abc]` (literal `]` at start of negated)
- `[-abc]` => `[-abc]` (literal `-` at start)
- `[abc-]` => `[abc-]` (literal `-` at end)
- `[a-z-]` => `[a-z-]` (range then literal `-`)

#### 8.3 Vim-Special Characters Inside Classes (No Escaping Needed)

Characters that need escaping outside classes are literal inside:

- `[~=]` => `[~=]` (literal tilde and equals)
- `[<>]` => `[<>]` (literal angle brackets)
- `[@&]` => `[@&]` (literal at and ampersand)
- `[~=]= nil` => `[~=]\= nil` (inside literal, outside escaped)

#### 8.4 Escapes Inside Classes

- `[\d\w]` => `[\d\w]` (shorthands work)
- `[\]]` => `[\]]` (escaped `]`)
- `[\\]` => `[\\]` (escaped backslash)
- `[\^]` => `[\^]` (escaped caret, literal)
- `[\-]` => `[\-]` (escaped hyphen)

#### 8.5 Metacharacters Literal Inside Classes

- `[+*?]` => `[+*?]` (quantifiers literal)
- `[()]` => `[()]` (parens literal)
- `[{}]` => `[{}]` (braces literal)
- `[|]` => `[|]` (pipe literal)
- `[.]` => `[.]` (dot literal)

### 9. Groups

#### 9.1 Capturing Groups (Pass Through)

- `(foo)` => `(foo)`
- `(a|b)` => `(a|b)`
- `(foo)(bar)` => `(foo)(bar)`
- `((nested))` => `((nested))`

#### 9.2 Non-Capturing Groups (Translation Required)

- `(?:foo)` => `%(foo)` (non-capturing)
- `(?:a|b)` => `%(a|b)` (with alternation)
- `(?:foo)+` => `%(foo)+` (with quantifier)
- `(?:foo)?` => `%(foo)?` (optional group)
- `(a)(?:b)(c)` => `(a)%(b)(c)` (mixed)

#### 9.3 Named Groups (Unsupported)

- `(?P<n>...)` => `nil` (unsupported)
- `(?<n>...)` => `nil` (unsupported)

### 10. Backreferences in Patterns

Numbered backreferences work the same in both engines:

- `(\w+) \1` => `(\w+) \1` (repeat word)
- `(.).*\1` => `(.).*\1` (palindrome-ish)
- `(a)(b)\2\1` => `(a)(b)\2\1` (multiple refs)

### 11. Forward Slash (Search Delimiter)

The `/` character is Vim's default search delimiter and must be escaped:

- `foo/bar` => `foo\/bar` (path)
- `/api/v1` => `\/api\/v1` (URL path)
- `[/]` => `[\/]` (inside class too)
- `a/b/c` => `a\/b\/c` (multiple)

### 12. Fixed String Mode (`-F` / `--fixed-strings`)

When ripgrep's `-F` flag is active, the pattern is treated as a literal string.
Use Vim's very-nomagic mode (`\V`):

- `hello` => `\Vhello` (simple)
- `foo\bar` => `\Vfoo\\bar` (backslash escaped)
- `foo/bar` => `\Vfoo\/bar` (slash escaped)
- `[a+b].*` => `\V[a+b].*` (metacharacters literal)
- `path/to/file` => `\Vpath\/to\/file` (path)

With `-w` (word boundary) combined with `-F`:

- `-F -w hello` => `\V\<hello\>` (literal word)
- `-F -w foo.bar` => `\V\<foo.bar\>` (dot is literal)

## Unsupported Features Detection

The translator should detect these patterns and return `nil`:

### Lookarounds

- `(?=...)` - positive lookahead
- `(?!...)` - negative lookahead
- `(?<=...)` - positive lookbehind
- `(?<!...)` - negative lookbehind

### Other Unsupported

- `\B` - non-word boundary
- `(?P<n>...)` - named capture group (Python style)
- `(?<n>...)` - named capture group (PCRE style)
- `(?>...)` - atomic group
- `*+`, `++`, `?+` - possessive quantifiers
- `\p{...}` - unicode category
- `\P{...}` - negated unicode category
- `\A`, `\z` - string anchors

## References

- `:help /magic` - Vim magic modes
- `:help /\v` - very magic mode
- `:help pattern-atoms` - Vim pattern atoms
- `:help /character-classes` - character class syntax
- Rust regex documentation: <https://docs.rs/regex/latest/regex/>
- Ripgrep user guide: <https://github.com/BurntSushi/ripgrep/blob/master/GUIDE.md>
