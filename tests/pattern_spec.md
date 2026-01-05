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
rather than producing a potentially incorrect result. For patterns that can be
translated with minor semantic adjustments, the translator returns the pattern
along with a warning message.

## Motivation

Ripgrep uses Rust's regex crate, which has PCRE-like syntax familiar to most
developers. Vim's traditional regex syntax differs significantly. This
translation enables:

1. Search register integration (`@/`) for `n`/`N` navigation
2. Match highlighting in the buffer
3. Seamless workflow between ripgrep results and Vim's native search

## Return value

The translator returns a result structure with two fields:

- `pattern`: The translated Vim regex string, or `nil` if translation failed
- `warning`: An optional warning message describing any issues or adjustments

When multiple warnings occur, only the first is shown with a count of
additional warnings, e.g. `"named groups become numbered (+1 more)"`.

## Scope

### Features in scope

1. Literal characters and basic metacharacters
2. Vim-special characters requiring escaping
3. Character classes
4. Character class shorthands
5. Word boundaries (`\b`)
6. Quantifiers (greedy and non-greedy)
7. Groups (capturing and non-capturing)
8. Named groups (translated to numbered with warning)
9. Backreferences in patterns
10. Case sensitivity modifiers
11. Anchors `\A` and `\z` (translated with warning)

### Features out of scope

These features will cause the translator to return `nil`:

1. Lookarounds: `(?=...)` `(?!...)` `(?<=...)` `(?<!...)`
2. Non-word boundary: `\B`
3. Unicode categories: `\p{...}` `\P{...}`
4. Atomic groups: `(?>...)`
5. Possessive quantifiers: `*+` `++` `?+`

## Translation rules

### 1. Mode prefixes

- Regex (default) => `\v` (very magic: most punctuation is special)
- Fixed string (`-F`) => `\V` (very nomagic: only `\` is special)

### 2. Case sensitivity

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

**Note on `--smart-case`:**

Ripgrep's `-S`/`--smart-case` flag has no direct Vim pattern equivalent. Users
who want consistent smart-case behaviour should configure both tools similarly:

- Ripgrep: Set `--smart-case` in `~/.ripgreprc`
- Neovim: Set `vim.o.ignorecase = true` and `vim.o.smartcase = true`

When neither `-s` nor `-i` is explicitly passed, the translator omits any case
modifier, allowing Vim's native settings to govern match highlighting.

### 3. Characters literal in ripgrep, special in very magic

These must be escaped when they appear as literals outside character classes:

- `=` - quantifier in `\v` (synonym for `?`) => escape as `\=`
- `<` - start of word boundary in `\v` => escape as `\<`
- `>` - end of word boundary in `\v` => escape as `\>`
- `~` - last substitute string in `\v` => escape as `\~`
- `@` - complex pattern atoms (`@=`, `@!`, etc.) => escape as `\@`
- `&` - branch concatenation (rare) => escape as `\&`

**Test Cases:**

- `foo=bar` => `\vfoo\=bar` (literal equals)
- `x~y` => `\vx\~y` (literal tilde)
- `a@b` => `\va\@b` (literal at-sign)
- `a&b` => `\va\&b` (literal ampersand)
- `a<b` => `\va\<b` (literal less-than)
- `x > 0` => `\vx \> 0` (literal greater-than)
- `Vec<T>` => `\vVec\<T\>` (generic type syntax)
- `<div>` => `\v\<div\>` (HTML tag)
- `[~=]= nil` => `\v[~=]\= nil` (inside class literal, outside escaped)
- `foo==bar` => `\vfoo\=\=bar` (multiple equals)
- `@decorator` => `\v\@decorator` (Python decorator)
- `a && b` => `\va \&\& b` (logical AND)

### 4. Characters special in both engines

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

- `a.b` => `\va.b` (any char)
- `a*b` => `\va*b` (zero or more)
- `a+b` => `\va+b` (one or more)
- `a?b` => `\va?b` (zero or one)
- `(foo)` => `\v(foo)` (capturing group)
- `foo|bar` => `\vfoo|bar` (alternation)
- `^start` => `\v^start` (line start)
- `end$` => `\vend$` (line end)
- `a{2,3}` => `\va{2,3}` (range quantifier)

### 5. Escaped metacharacters (literal in both)

When ripgrep escapes a metacharacter to make it literal, the escape passes
through (very magic uses the same convention):

**Test Cases:**

- `\(` => `\v\(` (literal parenthesis)
- `\)` => `\v\)` (literal parenthesis)
- `\+` => `\v\+` (literal plus)
- `\?` => `\v\?` (literal question mark)
- `\{` => `\v\{` (literal brace)
- `\}` => `\v\}` (literal brace)
- `\[` => `\v\[` (literal bracket)
- `\]` => `\v\]` (literal bracket)
- `\|` => `\v\|` (literal pipe)
- `\.` => `\v\.` (literal dot)
- `\*` => `\v\*` (literal asterisk)
- `\\` => `\v\\` (literal backslash)
- `\^` => `\v\^` (literal caret)
- `\$` => `\v\$` (literal dollar)

### 6. Character class shorthands

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

**Test cases:**

- `\d+` => `\v\d+`
- `\w+` => `\v\w+`
- `\s*` => `\v\s*`
- `[\d\w]` => `\v[\d\w]`

### 7. Word boundaries

- `\b` => `(<|>)` (word boundary, either side)
- `\B` => **unsupported**, return `nil` with warning `"\B not supported"`; it
  could be approximated as a negated boundary check using Vim assertions, but
  this would be beyond the scope of the plugin for a rarely used regex feature.

Ripgrep's `\b` matches at any word boundary. Vim has separate `\<` (start) and
`\>` (end). Since we cannot determine from the pattern alone which side is
intended, we use `(<|>)` as a conservative translation that matches either.

**Test Cases:**

- `\bword\b` => `\v(<|>)word(<|>)` (word boundaries)
- `\btest` => `\v(<|>)test` (start boundary)
- `test\b` => `\vtest(<|>)` (end boundary)
- `foo\bbar` => `\vfoo(<|>)bar` (mid-pattern boundary)
- `\b\w+\b` => `\v(<|>)\w+(<|>)` (with shorthand)
- `\B` => `nil` with warning (unsupported)
- `foo\Bbar` => `nil` with warning (unsupported)

**Note on `-w` / `--word-regexp` flag:**

When the user passes `-w`, ripgrep wraps the pattern in `\b...\b` internally.
However, for the Vim pattern, we use the cleaner `<...>` word boundary syntax
since we know definitively it's a whole-word match:

- `-w hello` => `\v<hello>`
- `-w foo.*bar` => `\v<foo.*bar>`

### 8. Quantifiers

#### 8.1 Greedy quantifiers (pass through)

- `a*` => `\va*`
- `a+` => `\va+`
- `a?` => `\va?`
- `a{3}` => `\va{3}`
- `a{3,}` => `\va{3,}`
- `a{3,5}` => `\va{3,5}`

#### 8.2 Non-greedy quantifiers (translation required)

Vim uses `\{-}` syntax for non-greedy matching:

- `a*?` => `\va{-}` (zero or more, non-greedy)
- `a+?` => `\va{-1,}` (one or more, non-greedy)
- `a??` => `\va{-0,1}` (zero or one, non-greedy)
- `a{3}?` => `\va{-3}` (exactly 3, non-greedy)
- `a{3,}?` => `\va{-3,}` (3 or more, non-greedy)
- `a{3,5}?` => `\va{-3,5}` (3 to 5, non-greedy)

**Test Cases:**

- `.*?` => `\v.{-}` (common: match minimal)
- `.+?` => `\v.{-1,}` (at least one, minimal)
- `<.*?>` => `\v\<.{-}\>` (HTML tag, non-greedy)
- `".*?"` => `\v".{-}"` (quoted string)
- `\w+?` => `\v\w{-1,}` (word chars, minimal)
- `a{2,4}?` => `\va{-2,4}` (range, non-greedy)
- `(ab)+?` => `\v(ab){-1,}` (group, non-greedy)

### 9. Character classes

Inside `[...]`, most metacharacters lose their special meaning.

#### 9.1 Basic syntax (pass through)

- `[abc]` => `\v[abc]` (simple class)
- `[a-z]` => `\v[a-z]` (range)
- `[^abc]` => `\v[^abc]` (negated class)
- `[a-zA-Z0-9]` => `\v[a-zA-Z0-9]` (multiple ranges)

#### 9.2 Special positions within classes

- `[]abc]` => `\v[]abc]` (literal `]` at start)
- `[^]abc]` => `\v[^]abc]` (literal `]` at start of negated)
- `[-abc]` => `\v[-abc]` (literal `-` at start)
- `[abc-]` => `\v[abc-]` (literal `-` at end)
- `[a-z-]` => `\v[a-z-]` (range then literal `-`)

#### 9.3 Vim-Special characters inside classes (no escaping needed)

Characters that need escaping outside classes are literal inside:

- `[~=]` => `\v[~=]` (literal tilde and equals)
- `[<>]` => `\v[<>]` (literal angle brackets)
- `[@&]` => `\v[@&]` (literal at and ampersand)
- `[~=]= nil` => `\v[~=]\= nil` (inside literal, outside escaped)

#### 9.4 Escapes inside classes

- `[\d\w]` => `\v[\d\w]` (shorthands work)
- `[\]]` => `\v[\]]` (escaped `]`)
- `[\\]` => `\v[\\]` (escaped backslash)
- `[\^]` => `\v[\^]` (escaped caret, literal)
- `[\-]` => `\v[\-]` (escaped hyphen)

#### 9.5 Metacharacters literal inside classes

- `[+*?]` => `\v[+*?]` (quantifiers literal)
- `[()]` => `\v[()]` (parens literal)
- `[{}]` => `\v[{}]` (braces literal)
- `[|]` => `\v[|]` (pipe literal)
- `[.]` => `\v[.]` (dot literal)

### 10. Groups

#### 10.1 Capturing groups (pass through)

- `(foo)` => `\v(foo)`
- `(a|b)` => `\v(a|b)`
- `(foo)(bar)` => `\v(foo)(bar)`
- `((nested))` => `\v((nested))`

#### 10.2 Non-capturing groups (translation required)

- `(?:foo)` => `\v%(foo)` (non-capturing)
- `(?:a|b)` => `\v%(a|b)` (with alternation)
- `(?:foo)+` => `\v%(foo)+` (with quantifier)
- `(?:foo)?` => `\v%(foo)?` (optional group)
- `(a)(?:b)(c)` => `\v(a)%(b)(c)` (mixed)

#### 10.3 Named groups (translated with warning)

Vim doesn't support named capture groups. The translator converts them to
numbered capture groups and emits a warning:

- `(?P<n>foo)` => `\v(foo)` with warning `"named groups become numbered"`
- `(?<n>foo)` => `\v(foo)` with warning `"named groups become numbered"`
- `(?P<id>ab|cd)+` => `\v(ab|cd)+` with warning

**Validation:** Named groups with empty or missing names return `nil`:

- `(?P<>foo)` => `nil` with warning `"invalid group name"`
- `(?<>foo)` => `nil` with warning `"invalid group name"`
- `(?P<name` (unterminated) => `nil` with warning `"invalid group name"`

**Note:** Named group syntax inside character classes is treated as literal:

- `[(?P<n>]` => `\v[(?P<n>]` (no warning)

### 11. Backreferences (unsupported)

Numbered backreferences work the same in both engines:

- `(\w+) \1` => `\v(\w+) \1` (repeat word)
- `(.).*\1` => `\v(.).*\1` (palindrome-ish)
- `(a)(b)\2\1` => `\v(a)(b)\2\1` (multiple refs)

### 12. Forward slash (search Delimiter)

The `/` character is Vim's default search delimiter and must be escaped
everywhere, including inside character classes:

- `foo/bar` => `\vfoo\/bar` (path)
- `/api/v1` => `\v\/api\/v1` (URL path)
- `[/]` => `\v[\/]` (inside class too)
- `a/b/c` => `\va\/b\/c` (multiple)

### 13. Fixed-string mode (`-F` / `--fixed-strings`)

When ripgrep's `-F` flag is active, the pattern is treated as a literal string.
Use Vim's very-nomagic mode (`\V`):

- `hello` => `\Vhello` (simple)
- `foo\bar` => `\Vfoo\\bar` (backslash escaped)
- `foo/bar` => `\Vfoo\/bar` (slash escaped)
- `[a+b].*` => `\V[a+b].*` (metacharacters literal)
- `path/to/file.txt` => `\Vpath\/to\/file.txt` (path)

With `-w` (word boundary) combined with `-F`:

- `-F -w hello` => `\V\<hello\>` (literal word)
- `-F -w foo.bar` => `\V\<foo.bar\>` (dot is literal)

### 14. Anchors: `\A` and `\z`

Ripgrep's `\A` (start of string) and `\z` (end of string) are translated to
`^` and `$` respectively, with warnings. This is semantically correct under
the translator's constraints:

- No multiline patterns
- No PCRE2 (default ripgrep engine only)
- Line-oriented matching

Using Vim's `\%^` and `\%$` would introduce buffer-level semantics and subtle
differences (e.g. EOF newline handling), so we deliberately map to line anchors.

**Test Cases:**

- `\Afoo` => `\v^foo` with warning `"\A treated as ^"`
- `foo\z` => `\vfoo$` with warning `"\z treated as $"`
- `\Afoo\z` => `\v^foo$` with warning `"\A treated as ^ (+1 more)"`

## Unsupported features detection

The translator detects these patterns and returns `nil` with an appropriate
warning message:

### Lookarounds

- `(?=...)` - positive lookahead => warning: `"lookarounds and atomic groups not supported"`
- `(?!...)` - negative lookahead => warning: `"lookarounds and atomic groups not supported"`
- `(?<=...)` - positive lookbehind => warning: `"lookarounds not supported"`
- `(?<!...)` - negative lookbehind => warning: `"lookarounds not supported"`

### Atomic groups

- `(?>...)` - atomic group => warning: `"lookarounds and atomic groups not supported"`

### Possessive quantifiers

- `*+` => warning: `"possessive quantifiers not supported"`
- `++` => warning: `"possessive quantifiers not supported"`
- `?+` => warning: `"possessive quantifiers not supported"`

### Unicode properties

- `\p{...}` => warning: `"unicode properties not supported"`
- `\P{...}` => warning: `"unicode properties not supported"`

### Non-word boundary

- `\B` => warning: `"\B not supported"`

### Backreferences

- `\1` through `\9` => warning: `"backreferences require PCRE2"`

## Edge cases

The translator handles various malformed or edge-case inputs gracefully:

- Empty string: `""` => `\v`
- Single trailing backslash: `\` => `\v\` (passed through)
- Unclosed bracket: `[abc` => `\v[abc` (passed through)
- Unclosed group: `(foo` => `\v(foo` (passed through)
- Only metacharacters: `+?|` => `\v+?|`
- Only Vim-special chars: `~=@&<>` => `\v\~\=\@\&\<\>`
- Consecutive escapes: `\\\d` => `\v\\\d`

## Warning format

When multiple issues occur during translation, warnings are formatted as:

```
"first warning (+N more)"
```

where N is the count of additional warnings beyond the first.

**Examples:**

- Single warning: `"named groups become numbered"`
- Two warnings: `"\A treated as ^ (+1 more)"`
- Three warnings: `"named groups become numbered (+2 more)"`

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
