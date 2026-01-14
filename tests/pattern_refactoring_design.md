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

1. Tokenise - Lexical analysis: identify token boundaries. Output: list of tokens
2. Parse - Semantic analysis: classify, validate, annotate. Output: annotated tokens (or error)
3. Translate - Code generation: emit Vim regex. Output: { vim_pattern, warning }

### Phase 1: Tokenise

**Responsibility:** Identify where tokens begin and end. Pure lexical analysis
with no semantic interpretation.

**Input:** Raw ripgrep pattern string

**Output:** Ordered list of tokens, each with:

- `type`: token category (see Token Types below)
- `value`: the raw string content
- `pos`: starting position in input (1-indexed, for error reporting)
- Type-specific fields (e.g., `negated` for character classes, `greedy` for
  quantifiers)

**What it does:**

- Recognises escape sequences (including multi-character like `\p{...}`)
- Extracts complete character classes, handling edge cases:
  - `]` as first character (or after `^`) is literal
  - `\]` is escaped, not a closer
  - `\\]` is escaped backslash followed by closer
- Identifies quantifiers and their greediness
- Recognises group openers with their variants
- Handles the `/` search delimiter

**What it does NOT do:**

- Classify escapes semantically (`\w` vs `\b` vs `\p`)
- Compute wordness
- Validate supported vs unsupported constructs
- Emit any output

### Phase 2: Parse

**Responsibility:** Attach semantic meaning, validate constraints, annotate
tokens with derived properties.

**Input:** List of tokens from Phase 1

**Output:** Either:

- Annotated token list with semantic metadata, OR
- Error result with warning message (for unsupported constructs)

**What it does:**

- Classifies escape sequences:
  - Shorthand word: `\w`, `\d`
  - Shorthand non-word: `\s`, `\W`, `\t`, `\n`, `\r`
  - Shorthand unknown: `\S`, `\D`
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

### Top-level tokens

| Type               | Example              | Fields             |
|--------------------|----------------------|--------------------|
| `literal`          | `f`, `=`, `<`        | `value`            |
| `escape`           | `\w`, `\b`, `\p{L}`  | `value`            |
| `quantifier`       | `*`, `+?`, `{2,3}`   | `value`, `greedy`  |
| `group_open`       | `(`, `(?:`, `(?P<n>` | `value`, `kind`    |
| `group_close`      | `)`                  | `value`            |
| `alternation`      | `\|`                 | `value`            |
| `anchor`           | `^`, `$`             | `value`            |
| `slash`            | `/`                  | `value`            |
| `char_class_open`  | `[`, `[^`            | `value`, `negated` |
| `char_class_close` | `]`                  | `value`            |

### Character class tokens

These tokens appear only between `char_class_open` and `char_class_close`. The
`cc_` prefix distinguishes them from top-level tokens, making it explicit that
they follow different lexical rules (most metacharacters are literal, `-` can
be a range operator, etc.).

| Type         | Example                  | Fields                |
|--------------|--------------------------|-----------------------|
| `cc_literal` | `a`, `!`, `]` (at start) | `value`               |
| `cc_range`   | `a-z`, `0-9`             | `value`, `from`, `to` |
| `cc_escape`  | `\w`, `\s`, `\]`         | `value`               |

### Note: why no `in_char_class` or `in_group` flags?

The tokeniser has context information (whether it's inside a character class or
group), but we deliberately don't attach this as metadata to tokens:

1. **Redundant with structure.** The "in character class" fact is implicit in
   position between `char_class_open` and `char_class_close`. Adding a flag
   would be denormalised data that could become inconsistent.

2. **Parser tracks nesting anyway.** For group validation and potential future
   features, the parser maintains nesting state as it walks tokens. The flag
   wouldn't save meaningful work.

3. **Separation of concerns.** "What are the atoms" is lexical (tokeniser).
   "What is the relationship between atoms" is structural (parser).

The `cc_` token type prefix serves the legitimate need: distinguishing tokens
that came from inside a character class (where lexical rules differ) without
adding redundant context flags.

### Group kinds

- `capturing`: `(`
- `non_capturing`: `(?:`
- `named_python`: `(?P<name>`
- `named_pcre`: `(?<name>`
- `lookahead_pos`: `(?=`
- `lookahead_neg`: `(?!`
- `lookbehind_pos`: `(?<=`
- `lookbehind_neg`: `(?<!`
- `atomic`: `(?>`

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
- `escaped_literal`: `\(`, `\.`, `\\`, etc.

## Wordness Classification

Wordness is assigned to tokens that can appear adjacent to `\b`:

| Token                        | Wordness                      |
|------------------------------|-------------------------------|
| `\w`, `\d`                   | `word`                        |
| `\s`, `\W`, `\t`, `\n`, `\r` | `non_word`                    |
| `\S`, `\D`                   | `unknown`                     |
| `.`                          | `unknown`                     |
| `^`, `$`, `\|`, `(`, `)`     | `non_word` (structural)       |
| Literal `[a-zA-Z0-9_]`       | `word`                        |
| Literal non-word char        | `non_word`                    |
| Character class              | Computed from contents        |
| Quantifier                   | Inherits from preceding token |

Character class wordness is computed by examining the tokens between
`char_class_open` and `char_class_close`:

- Negated classes (`char_class_open.negated = true`) => `unknown`
- Contains only word-character tokens:
  - `cc_range` with both endpoints in `[a-zA-Z0-9_]` => `word`
  - `cc_literal` matching `[a-zA-Z0-9_]` => `word`
  - `cc_escape` of `\w`, `\d` => `word`
- Contains only non-word tokens:
  - `cc_literal` not matching `[a-zA-Z0-9_]` => `non_word`
  - `cc_escape` of `\s`, `\W`, `\t`, `\n`, `\r` => `non_word`
- `cc_escape` of `\S`, `\D` => `unknown` (matches both word and non-word)
- `cc_range` spanning word and non-word (e.g., `A-z`) => `unknown`
- Mixed word and non-word tokens => `unknown`

This classification happens in the parser by iterating over the already-tokenised
character class contents: no re-parsing of the raw string is needed.

## File Structure

* `lua/brook/`
  * `pattern.lua`: Existing (preserved during development)
  * `pattern/`
    * `init.lua`: New public API (rg_to_vim wrapper)
    * `tokenize.lua`: Phase 1
    * `parse.lua`: Phase 2
    * `translate.lua`: Phase 3
    * `types.lua`: Token type definitions and enums
* `tests/`
  * `pattern_test.lua`: Existing integration tests (preserved and reused)
  * `pattern/`
    * `tokenize_test.lua`: Phase 1 unit tests
    * `parse_test.lua`: Phase 2 unit tests
    * `translate_test.lua`: Phase 3 unit tests

## Implementation Plan

### Step 1: Token types

Create `lua/brook/pattern/types.lua` with:
- Token type enum
- Group kind enum
- Escape classification enum
- Wordness enum (can reuse existing `_wordness`)
- Type definitions for token structures

**Deliverable:** Type definitions, no behaviour
**Validation:** Types load without error

### Step 2: Tokeniser

Create `lua/brook/pattern/tokenize.lua`:
- Single function `tokenize(pattern: string): Token[]`
- Handle all lexical edge cases (character class extraction, escape sequences,
  quantifier greediness, group variants)
- No semantic classification

**Deliverable:** Tokeniser function
**Validation:** `tests/pattern/tokenize_test.lua` passes

### Step 3: Parser

Create `lua/brook/pattern/parse.lua`:
- Single function `parse(tokens: Token[]): ParseResult`
- Classify escapes
- Compute wordness for all tokens
- Annotate `\b` tokens with context
- Detect and reject unsupported constructs
- Collect warnings

**Deliverable:** Parser function
**Validation:** `tests/pattern/parse_test.lua` passes

### Step 4: Translator

Create `lua/brook/pattern/translate.lua`:
- Single function `translate(parsed: ParsedTokens, opts: PatternOpts): PatternResult`
- Pure mechanical mapping from annotated tokens to Vim regex

**Deliverable:** Translator function
**Validation:** `tests/pattern/translate_test.lua` passes

### Step 5: Wire up new pipeline

Create `lua/brook/pattern/init.lua`:
- New `rg_to_vim` that calls tokenize => parse => translate
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
  (functionality subsumed by tokeniser and parser)
- Remove any dead code
- Update `pattern_spec.md` if needed

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
- Ability to abandon the refactoring if it proves unworkable (unlikely given
  the clear architecture)

## Testing Strategy

### Unit tests (new)

Each phase has its own test suite:

- `tokenize_test.lua`: exhaustive coverage of lexical edge cases
- `parse_test.lua`: semantic classification, wordness computation, error detection

### Integration tests (existing)

The existing `pattern_test.lua` (~1100 lines) serves as regression/integration
testing. It validates the complete pipeline produces identical output to the
current implementation.

### Test case migration

Some existing test cases (especially character class wordness) may be moved to
phase-specific test files, with the integration tests retaining representative
coverage.

## Risks and Mitigations

| Risk                   | Likelihood   | Impact   | Mitigation                                                           |
|------------------------|--------------|----------|----------------------------------------------------------------------|
| New bugs in tokeniser  | Medium       | High     | Extensive tokeniser tests; integration tests catch regressions       |
| Performance regression | Low          | Low      | Pattern translation is already microseconds; multi-pass won't matter |
| Incomplete coverage    | Low          | Medium   | Map existing test cases to new structure before removing old code    |
| Scope creep            | Medium       | Medium   | Strict phase responsibilities; don't add features during refactoring |

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
