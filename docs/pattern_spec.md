# Ripgrep to Vim Pattern Translation Specification

## Overview

This specification defines the translation from ripgrep (Rust regex) patterns to
Neovim patterns in very magic mode (`\v`).

Target environment:
- Neovim with `regexpengine=2` (NFA engine) for predictable behaviour
- Very magic mode (`\v`) for closer semantic alignment with ripgrep

Design principle:

> Incorrect highlighting is worse than no highlighting.

When a pattern cannot be reliably translated, the translator returns `nil`
rather than producing a potentially incorrect result. For patterns that can be
translated with minor semantic adjustments, the translator returns the pattern
along with a warning message.

## Motivation

Ripgrep uses Rust's regex crate, which has PCRE-like syntax familiar to most
developers. Vim's traditional regex syntax differs significantly. This
translation enables:

- Search register integration (`@/`) for `n`/`N` navigation
- Match highlighting in the buffer
- Seamless workflow between ripgrep results and Vim's native search

## Architecture

The translator uses a three-phase pipeline:

```
Input: ripgrep regex pattern

  1. Tokenise: lexical analysis, identify token boundaries
  2. Parse: semantic analysis, classify, validate, annotate
  3. Translate: code generation, emit Vim regex

Output: { pattern, warning }
```

### Phase 1: Tokenise

Lexical analysis producing a flat list of tokens.

Responsibilities:
- Identify token boundaries
- Categorise tokens as specifically as the lexical grammar allows
- Handle character class as a lexical submode (different rules inside `[...]`)

The tokeniser does not:
- Look at preceding tokens to decide a category
- Validate whether sequences make semantic sense
- Emit errors (invalid sequences become tokens; the parser decides validity)

### Phase 2: Parse

Semantic analysis and annotation.

Responsibilities:
- Classify escape sequences semantically
- Compute wordness for all tokens (for `\b` translation)
- Annotate `\b` tokens with prev/next wordness context
- Detect and reject unsupported constructs
- Collect warnings for translatable-with-caveats constructs

The parser does not:
- Emit any Vim regex syntax

### Phase 3: Translate

Mechanical transformation from annotated tokens to Vim regex.

Responsibilities:
- Emit mode prefix (`\v` or `\V`)
- Emit case modifier (`\C` or `\c`) if specified
- Walk tokens and emit Vim equivalents
- Apply word boundary wrapping if requested
- Format accumulated warnings

The translator does not:
- Re-examine token contents
- Make semantic decisions (already done by parser)

## Return Value

The translator returns a result structure with two fields:

- `pattern`: the translated Vim regex string, or `nil` if translation failed
- `warning`: an optional warning message describing any issues or adjustments

When multiple warnings occur, only the first is shown with a count of
additional warnings: `"named groups become numbered (+1 more)"`.

## Scope

### Features in scope

- Literal characters and basic metacharacters
- Vim-special characters requiring escaping
- Character classes (including ranges, POSIX classes, nesting, intersection)
- Character class shorthands (`\d`, `\w`, `\s`, etc.)
- Word boundaries (`\b`)
- Quantifiers (greedy and non-greedy)
- Groups (capturing, non-capturing, named, flag groups)
- Case sensitivity modifiers
- Anchors `\A` and `\z` (translated with warning)
- Hex, Unicode, and octal escapes

### Features out of scope

These features cause the translator to return `nil`:

- Lookarounds: `(?=...)` `(?!...)` `(?<=...)` `(?<!...)`
- Non-word boundary: `\B`
- Unicode categories: `\p{...}` `\P{...}`
- Atomic groups: `(?>.,.)`
- Possessive quantifiers: `*+` `++` `?+`
- Backreferences: `\1` through `\9`

## Translation Rules

### 1. Mode prefixes

- Regex (default) => `\v` (very magic: most punctuation is special)
- Fixed string (`-F`) => `\V` (very nomagic: only `\` is special)

### 2. Case sensitivity

Case sensitivity is controlled by ripgrep's `-s`/`--case-sensitive` and
`-i`/`--ignore-case` flags.

Translation:
- `-s` / `--case-sensitive` => prepend `\C`
- `-i` / `--ignore-case` => prepend `\c`
- Neither specified => no modifier (defer to Vim's `'ignorecase'`/`'smartcase'`)

The case modifier appears before the magic mode prefix.

Test cases (regex mode):
- `hello` with `-s` => `\C\vhello`
- `hello` with `-i` => `\c\vhello`
- `hello` (no flag) => `\vhello`
- `foo.*bar` with `-s` => `\C\vfoo.*bar`
- `foo=bar` with `-i` => `\c\vfoo\=bar`

Test cases (fixed string mode):
- `hello` with `-F -s` => `\C\Vhello`
- `hello` with `-F -i` => `\c\Vhello`
- `[a+b].*` with `-F -s` => `\C\V[a+b].*`
- `foo/bar` with `-F -i` => `\c\Vfoo\/bar`

Test cases (with word boundaries):
- `hello` with `-w -s` => `\C\v<hello>`
- `hello` with `-w -i` => `\c\v<hello>`
- `hello` with `-F -w -s` => `\C\V\<hello\>`

Note on `--smart-case`: ripgrep's `-S`/`--smart-case` flag has no direct Vim
pattern equivalent. Users who want consistent smart-case behaviour should
configure both tools similarly.

### 3. Characters literal in ripgrep, special in very magic

These must be escaped when they appear as literals outside character classes:

- `=` => `\=` (quantifier in `\v`, synonym for `?`)
- `<` => `\<` (start of word boundary)
- `>` => `\>` (end of word boundary)
- `~` => `\~` (last substitute string)
- `@` => `\@` (complex pattern atoms)
- `&` => `\&` (branch concatenation)

Test cases:
- `foo=bar` => `\vfoo\=bar`
- `x~y` => `\vx\~y`
- `a@b` => `\va\@b`
- `a&b` => `\va\&b`
- `a<b` => `\va\<b`
- `x > 0` => `\vx \> 0`
- `Vec<T>` => `\vVec\<T\>`
- `<div>` => `\v\<div\>`
- `[~=]= nil` => `\v[~=]\= nil` (inside class literal, outside escaped)

### 4. Characters special in both engines

These pass through unchanged:

- `.` any character
- `*` zero or more
- `+` one or more
- `?` zero or one
- `(` `)` grouping
- `[` `]` character class
- `|` alternation
- `^` start of line / negation in class
- `$` end of line
- `\` escape character
- `{` `}` range quantifier

Test cases:
- `a.b` => `\va.b`
- `a*b` => `\va*b`
- `a+b` => `\va+b`
- `(foo)` => `\v(foo)`
- `foo|bar` => `\vfoo|bar`
- `a{2,3}` => `\va{2,3}`

### 5. Escaped metacharacters

When ripgrep escapes a metacharacter to make it literal, the escape passes
through unchanged:

- `\(` => `\v\(`
- `\)` => `\v\)`
- `\+` => `\v\+`
- `\.` => `\v\.`
- `\\` => `\v\\`

### 6. Character class shorthands

These are compatible between engines:

- `\d` digit `[0-9]`
- `\D` non-digit
- `\w` word character `[a-zA-Z0-9_]`
- `\W` non-word character
- `\s` whitespace
- `\S` non-whitespace
- `\t` tab
- `\n` newline
- `\r` carriage return

Test cases:
- `\d+` => `\v\d+`
- `\w+` => `\v\w+`
- `[\d\w]` => `\v[\d\w]`

### 7. Word boundaries

Ripgrep's `\b` matches at any word boundary. Vim has separate `\<` (start) and
`\>` (end). The translator uses wordness analysis to choose the appropriate
boundary:

- `\b` before word character => `<` (word start)
- `\b` after word character => `>` (word end)
- `\b` in ambiguous context => `%(<|>)` (either boundary)

The `%()` non-capturing group ensures `\b` does not affect capture numbering.

Test cases:
- `\bword` => `\v<word` (start boundary, word char follows)
- `word\b` => `\vword>` (end boundary, word char precedes)
- `\bword\b` => `\v<word>` (both determined by context)
- `\b\w+\b` => `\v<\w+>` (word chars on both sides)
- `foo\bbar` => `\vfoo%(<|>)bar` (ambiguous mid-pattern)
- `\b` alone => `\v%(<|>)` (no context)
- `\B` => `nil` with warning `"\B not supported"`

The `-w` flag (whole word match) wraps the pattern in word boundaries:
- `-w foo` => `\v<foo>`
- `-w foo.*bar` => `\v<foo.*bar>`

### 8. Quantifiers

#### 8.1 Greedy quantifiers (pass through)

- `a*` => `\va*`
- `a+` => `\va+`
- `a?` => `\va?`
- `a{3}` => `\va{3}`
- `a{3,}` => `\va{3,}`
- `a{3,5}` => `\va{3,5}`

#### 8.2 Non-greedy quantifiers

Vim uses `\{-}` syntax for non-greedy matching:

- `a*?` => `\va{-}`
- `a+?` => `\va{-1,}`
- `a??` => `\va{-0,1}`
- `a{3}?` => `\va{-3}`
- `a{3,}?` => `\va{-3,}`
- `a{3,5}?` => `\va{-3,5}`

Test cases:
- `.*?` => `\v.{-}`
- `.+?` => `\v.{-1,}`
- `<.*?>` => `\v\<.{-}\>`
- `".*?"` => `\v".{-}"`

#### 8.3 Possessive quantifiers (unsupported)

- `*+` => `nil` with warning `"possessive quantifiers not supported"`
- `++` => `nil` with warning
- `?+` => `nil` with warning

### 9. Character classes

Inside `[...]`, most metacharacters lose their special meaning.

#### 9.1 Basic syntax

- `[abc]` => `\v[abc]`
- `[a-z]` => `\v[a-z]`
- `[^abc]` => `\v[^abc]`
- `[a-zA-Z0-9]` => `\v[a-zA-Z0-9]`

#### 9.2 Special positions

- `[]abc]` => `\v[]abc]` (literal `]` at start)
- `[^]abc]` => `\v[^]abc]` (literal `]` at start of negated)
- `[-abc]` => `\v[-abc]` (literal `-` at start)
- `[abc-]` => `\v[abc-]` (literal `-` at end)

#### 9.3 Vim-special characters inside classes

Characters that need escaping outside classes are literal inside:

- `[~=]` => `\v[~=]`
- `[<>]` => `\v[<>]`
- `[@&]` => `\v[@&]`

#### 9.4 Escapes inside classes

- `[\d\w]` => `\v[\d\w]` (shorthands work)
- `[\]]` => `\v[\]]` (escaped `]`)
- `[\\]` => `\v[\\]` (escaped backslash)
- `[\^]` => `\v[\^]` (escaped caret)

#### 9.5 POSIX classes

- `[:alpha:]` => `\v[:alpha:]`
- `[:digit:]` => `\v[:digit:]`
- `[:^digit:]` => `\v[:^digit:]` (negated)

#### 9.6 Nesting and intersection

The tokeniser recognises nested classes and set intersection:

- `[a-z&&[^aeiou]]` => nested class with intersection
- `[[a-z][A-Z]]` => nested classes

Note: negated nested classes lose the `^` in Vim's syntax.

#### 9.7 `\b` inside character classes

In Rust regex (and ripgrep), `\b` inside a character class is the literal
character `b`, not a word boundary. The tokeniser emits `cc_escape_literal`.

### 10. Groups

#### 10.1 Capturing groups

- `(foo)` => `\v(foo)`
- `(a|b)` => `\v(a|b)`
- `((nested))` => `\v((nested))`

#### 10.2 Non-capturing groups

- `(?:foo)` => `\v%(foo)`
- `(?:a|b)` => `\v%(a|b)`
- `(a)(?:b)(c)` => `\v(a)%(b)(c)` (mixed)

#### 10.3 Named groups

Vim does not support named capture groups. The translator converts them to
numbered groups and emits a warning:

- `(?P<n>foo)` => `\v(foo)` with warning `"named groups become numbered"`
- `(?<n>foo)` => `\v(foo)` with warning

Invalid names return an error:

- `(?P<>foo)` => `nil` with error `"invalid group name"`
- `(?<>foo)` => `nil` with error

#### 10.4 Flag groups

Flag groups pass through unchanged in very magic mode:

- `(?i)foo` => `\v(?i)foo` (case insensitive)
- `(?i:foo)` => `\v(?i:foo)` (scoped)

Supported flags: `i`, `m`, `s`, `U`, `u`, `x`, `R`

### 11. Anchors: `\A` and `\z`

Ripgrep's `\A` (start of string) and `\z` (end of string) are translated to
`^` and `$` respectively, with warnings:

- `\Afoo` => `\v^foo` with warning `"\A treated as ^"`
- `foo\z` => `\vfoo$` with warning `"\z treated as $"`
- `\Afoo\z` => `\v^foo$` with warning `"\A treated as ^ (+1 more)"`

This is semantically correct under the translator's constraints: no multiline
patterns, no PCRE2, line-oriented matching.

### 12. Forward slash

The `/` character is Vim's default search delimiter and must be escaped
everywhere, including inside character classes:

- `foo/bar` => `\vfoo\/bar`
- `/api/v1` => `\v\/api\/v1`
- `[/]` => `\v[\/]`

### 13. Fixed-string mode (`-F`)

When ripgrep's `-F` flag is active, the pattern is treated as a literal string.
The translator uses Vim's very-nomagic mode (`\V`):

- `hello` => `\Vhello`
- `foo\bar` => `\Vfoo\\bar` (backslash escaped)
- `foo/bar` => `\Vfoo\/bar` (slash escaped)
- `[a+b].*` => `\V[a+b].*` (metacharacters literal)

With `-w` (word boundary):

- `-F -w hello` => `\V\<hello\>`
- `-F -w foo.bar` => `\V\<foo.bar\>`

### 14. Numeric escapes

Hex, Unicode, and octal escapes pass through unchanged:

- `\x7F` => `\v\x7F`
- `\x{10FFFF}` => `\v\x{10FFFF}`
- `\u0041` => `\v\u0041`
- `\u{41}` => `\v\u{41}`
- `\0` => `\v\0`
- `\123` => `\v\123`
- `\o{177}` => `\v\o{177}`

### 15. Backreferences (unsupported)

Backreferences require PCRE2 in ripgrep, which the plugin actively rejects:

- `(\w+) \1` => `nil` with error `"backreferences require PCRE2"`
- `(.).*\1` => `nil` with error

### 16. Unicode properties (unsupported)

- `\p{L}` => `nil` with error `"unicode properties not supported"`
- `\P{Greek}` => `nil` with error

### 17. Lookarounds and atomic groups (unsupported)

- `(?=...)` => `nil` with error `"lookarounds and atomic groups not supported"`
- `(?!...)` => `nil` with error
- `(?<=...)` => `nil` with error `"lookarounds not supported"`
- `(?<!...)` => `nil` with error
- `(?>...)` => `nil` with error `"lookarounds and atomic groups not supported"`

## Token Types

### Top-level tokens (outside character classes)

- `literal`: literal character (`a`, `1`, `=`)
- `dot`: any character (`.`)
- `anchor`: line anchor (`^`, `$`)
- `alternation`: alternation (`|`)
- `quantifier`: quantifier (`*`, `+`, `?`, `{n,m}`), with `greedy` and `possessive` fields
- `group_open`: group opener, with `kind`, `name`, `flags`, `scoped` fields
- `group_close`: group closer (`)`)
- `char_class_open`: character class opener (`[`, `[^`), with `negated` field
- `char_class_close`: character class closer (`]`)
- `escape_boundary`: boundary or anchor (`\b`, `\B`, `\A`, `\z`), with `boundary_kind` field
- `escape_class`: character class shorthand (`\d`, `\w`, `\s`, `\h`, `\v`, etc.)
- `escape_literal`: escaped literal (`\n`, `\t`, `\\`, `\.`, etc.)
- `escape_hex`: hex escape (`\x7F`, `\x{...}`)
- `escape_unicode`: unicode escape (`\u{...}`, `\U{...}`)
- `escape_octal`: octal escape (`\0`, `\123`, `\o{...}`)
- `escape_property`: unicode property (`\p{...}`, `\P{...}`), with `negated` field
- `escape_backref`: backreference (`\1` through `\9`)
- `slash`: forward slash (`/`)

### Character class tokens (inside `[...]`)

These tokens use a `cc_` prefix to indicate they follow character class rules:

- `cc_literal`: literal character
- `cc_range`: character range (`a-z`), with `from` and `to` fields
- `cc_escape_class`: shorthand (`\d`, `\w`)
- `cc_escape_literal`: escaped character (`\]`, `\\`, `\b` as literal `b`)
- `cc_escape_hex`: hex escape
- `cc_escape_unicode`: unicode escape
- `cc_escape_octal`: octal escape
- `cc_escape_property`: unicode property
- `cc_posix`: POSIX class (`[:alpha:]`), with `class_name` and `negated` fields
- `cc_intersection`: set intersection (`&&`)
- `cc_nested_open`: nested class open (`[`, `[^`)
- `cc_nested_close`: nested class close (`]`)

### Boundary kinds

The `escape_boundary` token includes a `boundary_kind` field:

- `word`: `\b`
- `word_neg`: `\B`
- `start`: `\A`
- `end`: `\z`
- `word_start`: `\<`, `\b{start}`
- `word_end`: `\>`, `\b{end}`
- `word_start_half`: `\b{start-half}`
- `word_end_half`: `\b{end-half}`

### Group kinds

- `capturing`: `(`
- `non_capturing`: `(?:`
- `named_python`: `(?P<n>`
- `named_pcre`: `(?<n>`
- `lookahead_pos`: `(?=`
- `lookahead_neg`: `(?!`
- `lookbehind_pos`: `(?<=`
- `lookbehind_neg`: `(?<!`
- `atomic`: `(?>`
- `flags`: `(?i)`, `(?i:...)`

### Escape classifications (assigned by parser)

- `shorthand_word`: `\w`, `\d`
- `shorthand_nonword`: `\s`, `\W`, `\t`, `\n`, `\r`
- `shorthand_unknown`: `\S`, `\D`
- `boundary`: `\b`
- `boundary_neg`: `\B` (unsupported)
- `anchor_start`: `\A`
- `anchor_end`: `\z`
- `unicode_prop`: `\p{...}`, `\P{...}` (unsupported)
- `backref`: `\1`-`\9` (unsupported)
- `escaped_literal`: everything else

## Wordness Classification

Wordness determines how `\b` translates based on adjacent tokens.

| Token                        | Wordness   |
|------------------------------|------------|
| `\w`, `\d`                   | word       |
| `\s`, `\W`, `\t`, `\n`, `\r` | non_word   |
| `\S`, `\D`                   | unknown    |
| `\h`, `\H`, `\v`, `\V`       | unknown    |
| `.`                          | unknown    |
| `^`, `$`, `\|`, `(`, `)`     | non_word   |
| `/`                          | non_word   |
| Literal `[a-zA-Z0-9_]`       | word       |
| Literal other                | non_word   |
| Character class              | computed   |
| Quantifier                   | inherited  |

Character class wordness is computed from contents:

- Negated class => unknown
- All members are word characters => word
- All members are non-word characters => non_word
- Mixed or contains unknown => unknown

Quantifiers inherit wordness from their target token.

## Edge Cases

The translator handles malformed or edge-case inputs gracefully:

- Empty string: `""` => `\v`
- Trailing backslash: `\` => `\v\` (passed through)
- Unclosed bracket: `[abc` => `\v[abc` (passed through)
- Unclosed group: `(foo` => `\v(foo` (passed through)
- Only metacharacters: `+?|` => `\v+?|`
- Only Vim-special chars: `~=@&<>` => `\v\~\=\@\&\<\>`

## Warning Format

When multiple issues occur during translation:

```
"first warning (+N more)"
```

Examples:
- Single warning: `"named groups become numbered"`
- Two warnings: `"\A treated as ^ (+1 more)"`
- Three warnings: `"named groups become numbered (+2 more)"`

## File Structure

```
lua/brook/pattern/
  init.lua       # public API: rg_to_vim()
  tokeniser.lua  # phase 1: lexical analysis
  parser.lua     # phase 2: semantic analysis
  translator.lua # phase 3: code generation
  types.lua      # type definitions and enums
```

## References

- `:help /magic` Vim magic modes
- `:help /\v` very magic mode
- `:help pattern-atoms` Vim pattern atoms
- `:help /character-classes` character class syntax
- `:help /\c` case insensitive modifier
- `:help /\C` case sensitive modifier
- Rust regex documentation: https://docs.rs/regex/latest/regex/
- Ripgrep user guide: https://github.com/BurntSushi/ripgrep/blob/master/GUIDE.md
