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
9. Case sensitivity modifiers

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

### 2. Case Sensitivity

Case sensitivity is controlled by ripgrep's `-s`/`--case-sensitive` and
`-i`/`--ignore-case` flags. When specified, these translate to Vim's `\C`
and `\c` pattern modifiers respectively.

The case modifier must appear at the very beginning of the pattern, before the
magic mode prefix, or Vim will interpret it as an escaped literal character.

**Translation:**

- `-s` / `--case-sensitive` => prepend `\C`
- `-i` / `--ignore-case` => prepend `\c`
- Neither specified => no modifier (defer to Vim's `'ignorecase'`/`'smartcase'`)

**Flag precedence:** When multiple case flags are specified, the last one wins.
This matches ripgrep's behaviour.

**Test Cases (regex mode):**

- `hello` with `-s` => `\C\vhello`
- `hello` with `-i` => `\c\vhello`
- `hello` (no flag) => `\vhello`
- `foo.*bar` with `-s` => `\C\vfoo.*bar`
- `foo=bar` with `-i` => `\c\vfoo\=bar`

**Test Cases (fixed string mode):**

- `hello` with `-F -s` => `\C\Vhello`
- `hello` with `-F -i` => `\c\Vhello`
- `hello` with `-F` (no case flag) => `\Vhello`
- `[a+b].*` with `-F -s` => `\C\V[a+b].*`
- `foo/bar` with `-F -i` => `\c\Vfoo\/bar`

**Test Cases (with word boundaries):**

- `hello` with `-w -s` => `\C\v<hello>`
- `hello` with `-w -i` => `\c\v<hello>`
- `hello` with `-F -w -s` => `\C\V\<hello\>`
- `hello` with `-F -w -i` => `\c\V\<hello\>`

**Test Cases (flag precedence):**

- `pattern` with `-i -s` => `\C\vpattern` (last wins: case-sensitive)
- `pattern` with `-s -i` => `\c\vpattern` (last wins: case-insensitive)

**Note on `--smart-case`:**

Ripgrep's `-S`/`--smart-case` flag has no direct Vim pattern equivalent. Users
who want consistent smart-case behaviour should configure both tools similarly:

- Ripgrep: Set `--smart-case` in `~/.ripgreprc`
- Neovim: Set `vim.o.ignorecase = true` and `vim.o.smartcase = true`

When neither `-s` nor `-i` is explicitly passed, the translator omits any case
modifier, allowing Vim's native settings to govern match highlighting.

### 3. Characters Literal in Ripgrep, Special in Very Magic

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

### 4. Characters Special in Both Engines

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

### 5. Escaped Metacharacters (Literal in Both)

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

### 6. Character Class Shorthands

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

### 7. Word Boundaries

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

### 8. Quantifiers

#### 8.1 Greedy Quantifiers (Pass Through)

- `a*` => `a*`
- `a+` => `a+`
- `a?` => `a?`
- `a{3}` => `a{3}`
- `a{3,}` => `a{3,}`
- `a{3,5}` => `a{3,5}`

#### 8.2 Non-Greedy Quantifiers (Translation Required)

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

### 9. Character Classes

Inside `[...]`, most metacharacters lose their special meaning.

#### 9.1 Basic Syntax (Pass Through)

- `[abc]` => `[abc]` (simple class)
- `[a-z]` => `[a-z]` (range)
- `[^abc]` => `[^abc]` (negated class)
- `[a-zA-Z0-9]` => `[a-zA-Z0-9]` (multiple ranges)

#### 9.2 Special Positions Within Classes

- `[]abc]` => `[]abc]` (literal `]` at start)
- `[^]abc]` => `[^]abc]` (literal `]` at start of negated)
- `[-abc]` => `[-abc]` (literal `-` at start)
- `[abc-]` => `[abc-]` (literal `-` at end)
- `[a-z-]` => `[a-z-]` (range then literal `-`)

#### 9.3 Vim-Special Characters Inside Classes (No Escaping Needed)

Characters that need escaping outside classes are literal inside:

- `[~=]` => `[~=]` (literal tilde and equals)
- `[<>]` => `[<>]` (literal angle brackets)
- `[@&]` => `[@&]` (literal at and ampersand)
- `[~=]= nil` => `[~=]\= nil` (inside literal, outside escaped)

#### 9.4 Escapes Inside Classes

- `[\d\w]` => `[\d\w]` (shorthands work)
- `[\]]` => `[\]]` (escaped `]`)
- `[\\]` => `[\\]` (escaped backslash)
- `[\^]` => `[\^]` (escaped caret, literal)
- `[\-]` => `[\-]` (escaped hyphen)

#### 9.5 Metacharacters Literal Inside Classes

- `[+*?]` => `[+*?]` (quantifiers literal)
- `[()]` => `[()]` (parens literal)
- `[{}]` => `[{}]` (braces literal)
- `[|]` => `[|]` (pipe literal)
- `[.]` => `[.]` (dot literal)

### 10. Groups

#### 10.1 Capturing Groups (Pass Through)

- `(foo)` => `(foo)`
- `(a|b)` => `(a|b)`
- `(foo)(bar)` => `(foo)(bar)`
- `((nested))` => `((nested))`

#### 10.2 Non-Capturing Groups (Translation Required)

- `(?:foo)` => `%(foo)` (non-capturing)
- `(?:a|b)` => `%(a|b)` (with alternation)
- `(?:foo)+` => `%(foo)+` (with quantifier)
- `(?:foo)?` => `%(foo)?` (optional group)
- `(a)(?:b)(c)` => `(a)%(b)(c)` (mixed)

#### 10.3 Named Groups (Unsupported)

- `(?P<n>...)` => `nil` (unsupported)
- `(?<n>...)` => `nil` (unsupported)

### 11. Backreferences in Patterns

Numbered backreferences work the same in both engines:

- `(\w+) \1` => `(\w+) \1` (repeat word)
- `(.).*\1` => `(.).*\1` (palindrome-ish)
- `(a)(b)\2\1` => `(a)(b)\2\1` (multiple refs)

### 12. Forward Slash (Search Delimiter)

The `/` character is Vim's default search delimiter and must be escaped:

- `foo/bar` => `foo\/bar` (path)
- `/api/v1` => `\/api\/v1` (URL path)
- `[/]` => `[\/]` (inside class too)
- `a/b/c` => `a\/b\/c` (multiple)

### 13. Fixed String Mode (`-F` / `--fixed-strings`)

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
- `:help /\c` - case insensitive modifier
- `:help /\C` - case sensitive modifier
- `:help 'ignorecase'` - global ignore case setting
- `:help 'smartcase'` - smart case setting
- Rust regex documentation: <https://docs.rs/regex/latest/regex/>
- Ripgrep user guide: <https://github.com/BurntSushi/ripgrep/blob/master/GUIDE.md>
