# Pattern Translation Refactoring: Design Document

## Context

The `brook.pattern` module translates ripgrep (Rust regex) patterns to Neovim's
"very magic" (`\v`) regex syntax. This enables search register integration,
match highlighting, and `n`/`N` navigation after ripgrep searches.

The current implementation is a single-pass translator (~550 lines) that
simultaneously handles lexical analysis, semantic analysis, and code generation.
While functionally correct and well-tested (~1100 lines of tests), it has become
increasingly difficult to maintain:

- Each new edge case requires threading state through more places
- The `\b` (word boundary) translation requires tracking "wordness" of preceding
  and following atoms, which interacts with character class handling, quantifiers,
  groups, and alternation
- Character class wordness classification (`_classify_char_class_wordness`) is
  essentially a second parser that re-scans input because the main loop cannot
  easily share its lexical work
- Recent changes have required 1-2 days of work each due to accumulated complexity

The commit history shows continuous churn in this area, and changes are becoming
exponentially harder.

## Design Principle (Preserved)

> Incorrect highlighting is worse than no highlighting.

When a pattern cannot be reliably translated, the translator returns `nil` rather
than producing a potentially incorrect result. This principle is preserved in the
new architecture.

## Proposed Architecture

Replace the single-pass translator with a three-phase pipeline.

Input string: ripgrep regex (default engine)

1. Tokenise: lexical analysis, identify token boundaries. Output: list of tokens
2. Parse: semantic analysis, classify, validate, annotate. Output: annotated tokens (or error)
3. Translate: code generation, emit Vim regex. Output: { vim_pattern, warning }

### Phase 1: Tokenise

**Responsibility:** Identify where tokens begin and end, and categorise each
token as specifically as the lexical grammar allows. Pure lexical analysis with
no consideration of surrounding context.

**Input:** Raw ripgrep pattern string

**Output:** Ordered list of tokens, each with:

- `type`: token category (see Token Types below)
- `value`: the raw string content
- `pos`: starting position in input (1-indexed, for error reporting)
- Type-specific fields (e.g., `negated` for character classes, `greedy` for
  quantifiers, `boundary_kind` for escape boundaries)

**Guiding principles:**

- Aligned with the Rust regex crate's lexical grammar
- Categorises as specifically as possible based solely on the characters being
  scanned and the current lexical mode (inside/outside character class)
- Does not look at preceding tokens to decide a category
- Does not validate whether sequences make semantic sense
- Does not error: it reports what it sees, the parser decides validity

**What it does:**

- Recognises all escape sequence categories:
  - Boundaries: `\b`, `\B`, `\A`, `\z`, `\<`, `\>`, `\b{start}`, `\b{end}`, etc.
  - Character classes: `\d`, `\D`, `\w`, `\W`, `\s`, `\S`, `\h`, `\H`, `\v`, `\V`
  - Literals: `\n`, `\t`, `\r`, `\f`, `\a`, `\e`, `\\`, `\.`, etc.
  - Hex: `\x7F`, `\x{10FFFF}`
  - Unicode: `\u007F`, `\u{7F}`, `\U{...}`
  - Octal: `\0`, `\00`, `\123`
  - Properties: `\p{...}`, `\P{...}`
  - Backreferences: `\1` through `\9`
- Recognises `.` as a distinct token type (not literal)
- Recognises `^` and `$` as anchors
- Recognises quantifiers (`*`, `+`, `?`, `{n,m}`) with greediness and possessiveness
- Extracts complete character classes with their contents tokenised:
  - Handles `]` as first character (literal)
  - Recognises ranges (`a-z`)
  - Recognises POSIX classes (`[:alpha:]`, `[:^digit:]`)
  - Recognises set operations and nesting (`&&`, `[[...]]`, `[^...]` inside a class)
  - Applies different token types inside character classes (`cc_` prefix)
- Identifies group openers with their variants, including flag groups (`(?i)`)
- Handles the `/` search delimiter
- Treats a trailing `\\` as an incomplete escape and emits an `escape_literal` token with value `\\`

**What it does NOT do:**

- Determine if a quantifier has something to quantify (that is semantic)
- Compute wordness
- Validate supported vs unsupported constructs
- Emit any output or errors

**Character class as lexical submode:**

The tokeniser tracks whether it is inside a character class. This is justified
because `[...]` creates a lexical submode where different rules apply:

- `.` is literal, not "any character"
- `*`, `+`, `?` are literal, not quantifiers
- `^` after `[` means negation, not anchor
- `-` between characters means range
- `\b` is literal `b`, not word boundary (in Rust regex)
- POSIX classes `[:alpha:]` are recognised
- `&&` is set intersection, and nested classes (`[[...]]`) are recognised

This is analogous to how a C lexer uses different rules inside string literals.
It is lexical context, not semantic interpretation.

### Phase 2: Parse

**Responsibility:** Attach semantic meaning, validate constraints, annotate
tokens with derived properties.

**Input:** List of tokens from Phase 1

**Output:** Either:

- Annotated token list with semantic metadata, OR
- Error result with warning message (for unsupported constructs)

**What it does:**

- Validates token sequences:
  - Quantifier must follow a quantifiable token (literal, escape, group, class)
  - Consecutive quantifiers are an error (or the second is treated as literal)
  - Groups must be balanced
- Classifies escape sequences semantically:
  - Shorthand word: `\w`, `\d`
  - Shorthand non-word: `\s`, `\W`, `\t`, `\n`, `\r`
  - Shorthand unknown: `\S`, `\D`
  - Other `escape_class` tokens (`\h`, `\H`, `\v`, `\V`) are preserved and currently treated as `unknown` for wordness unless explicitly classified
  - Boundary: `\b`
  - Unsupported: `\B`, `\p{...}`, `\P{...}`, `\1`-`\9`
  - Anchor: `\A`, `\z`
  - Escaped literal: everything else
- Computes `wordness` for each token:
  - `word`: matches only word characters
  - `non_word`: matches only non-word characters
  - `unknown`: could match either
- Annotates `\b` tokens with `prev_wordness` and `next_wordness`
- Detects and rejects unsupported constructs (lookarounds, atomic groups,
  possessive quantifiers, `\B`, unicode properties, backreferences)
- Collects warnings for translatable-with-caveats constructs (`\A`, `\z`,
  named groups)

**What it does NOT do:**

- Emit any Vim regex syntax

### Phase 3: Translate

**Responsibility:** Mechanical transformation from annotated tokens to Vim regex.

**Input:** Annotated token list from Phase 2, plus options (`fixed`, `word`, `case`)

**Output:** `PatternResult { pattern, warning }`

**What it does:**

- Emits mode prefix (`\v` or `\V`)
- Emits case modifier (`\C` or `\c`) if specified
- Walks tokens and emits Vim equivalents:
  - Literals needing escaping: `=`, `~`, `@`, `&`, `<`, `>` => `\=`, etc.
  - Forward slash => `\/`
  - Non-greedy quantifiers => `{-}` syntax
  - Non-capturing groups => `%(...)`
  - Word boundaries => `<`, `>`, or `%(<|>)` based on annotated wordness
  - Named groups => numbered groups
  - Anchors `\A`, `\z` => `^`, `$`
- Wraps in `<...>` if `word` option is set
- Formats accumulated warnings

**What it does NOT do:**

- Re-examine token contents
- Make semantic decisions

## Token Types

### Top-level tokens (outside character classes)

| Type               | Example                   | Fields                                     |
|--------------------|---------------------------|--------------------------------------------|
| `literal`          | `a`, `1`, `=`             | `value`                                    |
| `dot`              | `.`                       | `value`                                    |
| `anchor`           | `^`, `$`                  | `value`                                    |
| `alternation`      | `\|`                      | `value`                                    |
| `quantifier`       | `*`, `+?`, `{2,3}`        | `value`, `greedy`, `possessive`            |
| `group_open`       | `(`, `(?:`, `(?P<n>`      | `value`, `kind`, `name`, `flags`, `scoped` |
| `group_close`      | `)`                       | `value`                                    |
| `char_class_open`  | `[`, `[^`                 | `value`, `negated`                         |
| `char_class_close` | `]`                       | `value`                                    |
| `escape_boundary`  | `\b`, `\B`, `\A`, `\z`    | `value`, `boundary_kind`                   |
| `escape_class`     | `\d`, `\w`, `\s`, `\h`    | `value`                                    |
| `escape_literal`   | `\n`, `\t`, `\e`, `\\`    | `value`                                    |
| `escape_hex`       | `\x7F`, `\x{...}`         | `value`                                    |
| `escape_unicode`   | `\u{...}`, `\U{...}`      | `value`                                    |
| `escape_octal`     | `\0`, `\123`              | `value`                                    |
| `escape_property`  | `\p{L}`, `\P{Greek}`      | `value`, `negated`                         |
| `escape_backref`   | `\1`, `\9`                | `value`                                    |
| `slash`            | `/`                       | `value`                                    |

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

### Character class tokens

These tokens appear only between `char_class_open` and `char_class_close`. The
`cc_` prefix distinguishes them from top-level tokens, making it explicit that
they follow different lexical rules.

| Type                  | Example          | Fields                           |
|-----------------------|------------------|----------------------------------|
| `cc_literal`          | `a`, `]` (first) | `value`                          |
| `cc_range`            | `a-z`, `0-9`     | `value`, `from`, `to`            |
| `cc_escape_class`     | `\d`, `\w`       | `value`                          |
| `cc_escape_literal`   | `\]`, `\\`, `\b` | `value`                          |
| `cc_escape_hex`       | `\x7F`           | `value`                          |
| `cc_escape_unicode`   | `\u{20}`         | `value`                          |
| `cc_escape_octal`     | `\0`             | `value`                          |
| `cc_escape_property`  | `\p{L}`          | `value`, `negated`               |
| `cc_posix`            | `[:alpha:]`      | `value`, `class_name`, `negated` |
| `cc_intersection`     | `&&`             | `value`                          |
| `cc_nested_open`      | `[`, `[^`        | `value`, `negated`               |
| `cc_nested_close`     | `]`              | `value`                          |

### Note: `\b` inside character classes

In the Rust regex crate (and therefore ripgrep), `\b` inside a character class
is NOT backspace (unlike PCRE/Perl). It is simply an escaped `b`, matching the
literal character `b`. The tokeniser emits `cc_escape_literal` for `\b` inside
`[...]`.

### Note: why no `in_char_class` flag on tokens?

The tokeniser tracks character class context internally, but we don't attach
this as metadata to tokens:

1. **Redundant with structure.** The "in character class" fact is implicit in
   position between `char_class_open` and `char_class_close`. Adding a flag
   would be denormalised data that could become inconsistent.

2. **Parser tracks nesting anyway.** For group validation and potential future
   features, the parser maintains nesting state as it walks tokens.

3. **Separation of concerns.** "What are the atoms" is lexical (tokeniser).
   "What is the relationship between atoms" is structural (parser).

The `cc_` token type prefix serves the legitimate need: distinguishing tokens
that came from inside a character class (where lexical rules differ).

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

### Escape classifications (added by parser)

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

Wordness is assigned to tokens that can appear adjacent to `\b`:

| Token                        | Wordness                           |
|------------------------------|------------------------------------|
| `\w`, `\d`                   | `word`                             |
| `\s`, `\W`, `\t`, `\n`, `\r` | `non_word`                         |
| `\S`, `\D`                   | `unknown`                          |
| `\h`, `\H`, `\v`, `\V`       | `unknown` (currently unclassified) |
| `.`                          | `unknown`                          |
| `^`, `$`, `|`, `(`, `)`      | `non_word` (structural)            |
| Literal `[a-zA-Z0-9_]`       | `word`                             |
| Literal non-word char        | `non_word`                         |
| Character class              | Computed from contents             |
| Quantifier                   | Inherits from preceding token      |

Character class wordness is computed by examining the tokens between
`char_class_open` and `char_class_close`:

- Negated classes (`char_class_open.negated = true`) => `unknown`
- Contains only word-character tokens:
  - `cc_range` with both endpoints in `[a-zA-Z0-9_]` => `word`
  - `cc_literal` matching `[a-zA-Z0-9_]` => `word`
  - `cc_escape_class` of `\w`, `\d` => `word`
- Contains only non-word tokens:
  - `cc_literal` not matching `[a-zA-Z0-9_]` => `non_word`
  - `cc_escape_class` of `\s`, `\W` => `non_word`
  - `cc_escape_literal` of `\t`, `\n`, `\r` => `non_word`
- `cc_escape_class` of `\S`, `\D` => `unknown`
- `cc_range` spanning word and non-word (e.g., `A-z`) => `unknown`
- Mixed word and non-word tokens => `unknown`

This classification happens in the parser by iterating over the already-tokenised
character class contents: no re-parsing of the raw string is needed.

## File Structure

```
lua/brook/
  pattern.lua             # existing (preserved during development)
  pattern/
    init.lua              # new public API
    tokenise.lua          # phase 1
    parse.lua             # phase 2
    translate.lua         # phase 3
    types.lua             # token type definitions and enums

tests/
  pattern_test.lua        # existing integration tests (preserved)
  pattern/
    tokeniser_test.lua    # phase 1 unit tests
    parser_test.lua       # phase 2 unit tests
    translator_test.lua   # phase 3 unit tests
```

## Implementation Plan

### Step 1: Token types

Create `lua/brook/pattern/types.lua` with:

- Token type enums (top-level and character class)
- Group kind enum
- Escape classification enum
- Wordness enum
- Type definitions for token structures

**Deliverable:** Type definitions, no behaviour
**Validation:** Types load without error

### Step 2: Tokeniser

Create `lua/brook/pattern/tokenise.lua`:

- Single function `tokenise(pattern: string): Token[]`
- Categorise tokens as specifically as possible
- Handle character class lexical submode
- No semantic validation

**Deliverable:** Tokeniser function
**Validation:** `tests/pattern/tokeniser_test.lua` passes

### Step 3: Parser

Create `lua/brook/pattern/parse.lua`:

- Single function `parse(tokens: Token[]): ParseResult`
- Validate token sequences
- Classify escapes semantically
- Compute wordness for all tokens
- Annotate `\b` tokens with context
- Detect and reject unsupported constructs
- Collect warnings

**Deliverable:** Parser function
**Validation:** `tests/pattern/parser_test.lua` passes

### Step 4: Translator

Create `lua/brook/pattern/translate.lua`:

- Single function `translate(parsed: ParsedTokens, opts: PatternOpts): PatternResult`
- Pure mechanical mapping from annotated tokens to Vim regex

**Deliverable:** Translator function
**Validation:** `tests/pattern/translator_test.lua` passes

### Step 5: Wire up new pipeline

Create `lua/brook/pattern/init.lua`:

- New `rg_to_vim` that calls tokenise => parse => translate
- Identical signature to existing `pattern.rg_to_vim`

**Deliverable:** New public API
**Validation:** Existing `tests/pattern_test.lua` passes unchanged

### Step 6: Replace old implementation

- Update `lua/brook/pattern.lua` to delegate to new pipeline
- Or replace it entirely with `require('brook.pattern.init')`

**Deliverable:** Single implementation
**Validation:** All tests pass, manual testing confirms behaviour

### Step 7: Clean up

- Remove `_classify_char_class_wordness` and `_extract_leading_char_class`
- Remove any dead code
- Update documentation if needed

**Deliverable:** Clean codebase
**Validation:** All tests pass

## Migration Strategy

During development:

1. New code lives in `lua/brook/pattern/` directory
2. Existing `lua/brook/pattern.lua` remains unchanged and functional
3. Each phase can be developed and tested independently
4. Integration tests (`pattern_test.lua`) validate the complete pipeline
5. Switch-over happens only when integration tests pass

This allows:

- Continued use of the plugin during refactoring
- Safe experimentation without risk of regression
- Ability to abandon the refactoring if it proves unworkable

## Testing Strategy

### Unit tests (new)

Each phase has its own test suite:

- `tokeniser_test.lua`: exhaustive coverage of lexical edge cases
- `parser_test.lua`: semantic classification, wordness computation, error detection
- `translator_test.lua`: Vim regex generation

### Integration tests (existing)

The existing `pattern_test.lua` (~1100 lines) serves as regression/integration
testing. It validates the complete pipeline produces identical output to the
current implementation.

### Test case migration

Some existing test cases (especially character class wordness) may be moved to
phase-specific test files, with the integration tests retaining representative
coverage.

## Risks and Mitigations

| Risk                   | Likelihood | Impact | Mitigation                                                           |
|------------------------|------------|--------|----------------------------------------------------------------------|
| New bugs in tokeniser  | Medium     | High   | Extensive tokeniser tests; integration tests catch regressions       |
| Performance regression | Low        | Low    | Pattern translation is already microseconds; multi-pass is fine      |
| Incomplete coverage    | Low        | Medium | Map existing test cases to new structure before removing old code    |
| Scope creep            | Medium     | Medium | Strict phase responsibilities; don't add features during refactoring |

## Success Criteria

The refactoring is complete when:

1. All existing tests pass unchanged
2. New unit tests provide clear coverage of each phase
3. The `\b` wordness logic is declarative and localised in the parser
4. Character class handling is clean and non-duplicated
5. Adding a new edge case requires changes to at most one phase
6. Total line count is comparable or lower (complexity moved to tests is fine)

## Non-Goals

This refactoring explicitly does NOT:

- Add support for new regex features
- Change any user-visible behaviour
- Modify the public API
- Change the pattern spec
- Optimise performance (already adequate)

## Appendix: Current Pain Points

For reference, these are the specific issues the refactoring addresses:

1. **Wordness tracking is scattered:** The main loop tracks `wordness_before`,
   `pending_class_wordness`, `was_quantifier`: state that interacts in subtle ways

2. **Character class parsing is duplicated:** `_extract_leading_char_class` and
   `_classify_char_class_wordness` re-parse character classes that the main loop
   also processes. The new design tokenises character class contents once; the
   parser then classifies wordness by examining the tokens.

3. **`\b` translation is embedded in escape handling:** The logic to look ahead
   and behind is interleaved with output generation

4. **Adding new escape handling is fragile:** Each new escape type must consider
   its interaction with wordness, character class context, and output

5. **Tests validate output, not intermediate representations:** When a test fails,
   it's unclear whether tokenisation, classification, or generation is wrong

## Appendix: Tokeniser Design Principles

The tokeniser follows these principles, refined through design discussion:

1. **Categorise as specifically as possible.** If the lexical grammar
   unambiguously identifies something as a quantifier, emit `quantifier`, not
   `literal`. The parser decides if it's valid in context.

2. **No backward context.** The tokeniser does not look at preceding tokens to
   decide a category. A `*` at pattern start is still `quantifier`.

3. **Character class is a lexical submode.** Inside `[...]`, different lexical
   rules apply. This is tracked internally, producing `cc_` prefixed tokens.

4. **Aligned with Rust regex.** Token categories match the Rust regex crate's
   grammar. For example, `\b` inside `[...]` is `cc_escape_literal` (literal `b`),
   not backspace.

5. **Never errors.** The tokeniser reports what it sees. Invalid sequences
   (like `**`) produce valid tokens; the parser decides what to do.
