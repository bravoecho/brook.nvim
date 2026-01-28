# brook.nvim: Pattern Merging and Quickfix Append

Design document for two related features: merging multiple `-e` patterns into a
single search register pattern, and appending search results across multiple
invocations.

## Problem Statement

Two feature requests have emerged:

1. Support for multiple `-e` options passed to ripgrep, with proper search
   register integration so `n`/`N` navigation works across all patterns
2. Append mode: add results from a new search to the existing quickfix list
   without clearing it (vim-grepper parity)

These features are related. The second depends on solving the first cleanly.

## Key Insight

some ^foobar
some ^barbaz

Alternation already works. When searching for `foo|bar` with ripgrep, brook
translates it to `\vfoo|bar` for the search register, and `n`/`N` jumps to
matches of either pattern. Users already have the correct mental model.

The idea is to treat `-e foo -e bar` as equivalent to `foo|bar` at pattern
construction time, before translation.

## Feature 1: Multiple `-e` Pattern Merging

### Approach

1. Parse `-e` arguments from the command line
2. Join extracted patterns with `|` into a single ripgrep pattern
3. Pass the merged pattern through the existing translation pipeline
4. Set the search register with the translated result

Ripgrep still receives the original arguments unchanged: it handles `-e`
natively. The merging is only for Vim's benefit.

### Implementation Location

Early in argument parsing, before the pattern reaches the translator. The
translator remains a pure function from one regex dialect to another.

### Edge Cases

- Anchors: `rg -e '^foo' -e '^bar'` becomes `^foo|^bar`. Anchors bind tighter
  than alternation in both dialects, so this should translate correctly.
- Empty patterns: `-e '' -e 'foo'` should filter out empty strings before
  joining.
- Escaped pipe: a literal `|` in a pattern is already escaped as `\|` in
  ripgrep syntax, so joining with unescaped `|` is safe.
- Per-pattern flags: ripgrep's `-e` does not support per-pattern flags, so all
  patterns share the same matching semantics. No special handling needed.
- Word mode: when the `-w`/`--word-regexp` flags are set, each pattern should be
  surrounded with word boundaries before merging, so `-e 'foo' -e 'bar' -w`
  should result in `\v<foo>|<bar>`
- Fixed-string mode: when the `-F`/`--fixed-strings` flags are set, the patterns
  should be merged using an escaped bar character `\|`,
  so `-e '^foo' -e '^bar' -F` should result in `\V^foo\|^bar`
- Word+fixed combined: when both modes are set, the strategies should be
  combined, using the escapes `\<` and `\>` for the boundaries,
  so `-e 'foo' -e 'bar' -wF` should result in `\V\<foo\>\|\<bar\>`
- Case sensitivity: when the case-sensitive/case-insensitive flags are set, the
  combined pattern will be prepended with the `\c`/`\C` modifiers as usual.

### Testing

- Single `-e`: equivalent to current behaviour
- Multiple `-e`: verify joined pattern translates correctly
- Mixed with positional pattern: decide semantics (error? combine?)
- Anchors in multiple patterns
- Patterns containing literal pipe characters

## Feature 2: Quickfix Append Mode

### The Provenance Problem

Neovim does not track why the quickfix list contains what it contains. The list
could have been modified by LSP, diagnostics, `:cdo`, or manual filtering.
Blindly appending risks incoherent results.

### The Pattern Problem (solved by Feature 1)

If appending results from `foo.*bar` to results from `\bquux\b`, what goes in
the search register? Options are all bad:

- Overwrite with new pattern: `n` misses items from first search
- Keep old pattern: `n` misses items from second search
- Construct alternation from translated patterns: fragile, potentially invalid

Solution: accumulate source patterns in ripgrep syntax, merge them, translate
the merged result. The translator remains pure.

### Data Model

Use the quickfix context field to store brook metadata:

```lua
context = {
  brook = true,
  patterns = {
    {'foo', 'bar'},      -- first search: -e foo -e bar
    {'baz'},             -- second search (appended): -e baz
    {'quux', 'xyzzy'},   -- third search (appended): -e quux -e xyzzy
  },
}
```

The nested structure preserves which search contributed which patterns. This
could support "undo last append" in future, though that may be over-engineering.

### Workflow

1. Normal search (no append flag):
   - Run ripgrep with the given pattern(s)
   - Replace quickfix list unconditionally
   - Set context with `brook = true` and `patterns = {{...}}`
   - Set search register from translated merged pattern

2. Append search:
   - Check `getqflist({context = 1})`: if `context.brook` is not true, either
     refuse or warn (user's quickfix may contain unrelated items)
   - Run ripgrep with new pattern(s)
   - Append new results to quickfix list
   - Append new pattern group to `context.patterns`
   - Flatten all patterns, join with `|`, translate, set search register

### Search Register Update

On append:

1. Flatten: `{'foo', 'bar', 'baz', 'quux', 'xyzzy'}`
2. Join: `foo|bar|baz|quux|xyzzy`
3. Translate: `\(foo\|bar\|baz\|quux\|xyzzy\)`
4. Set search register

This reuses the exact pipeline from Feature 1.

### API Considerations

- New flag or command variant to trigger append mode (e.g. `:BrookAppend` or
  `:Brook --append`)
- Behaviour when context check fails: refuse with error? warn and proceed?
  make it configurable?
- Whether to expose "clear append history" as a separate command

## Implementation Order

1. Implement Feature 1 (multiple `-e` merging) first
   - Self-contained and valuable on its own
   - Establishes the "join patterns, translate once" pipeline
   - Can be tested independently

2. Implement Feature 2 (append mode) second
   - Becomes a thin layer over Feature 1
   - Adds context management and accumulation logic
   - Reuses the merging pipeline directly

## Open Questions

- Mixed positional and `-e` patterns: is this an error, or should they combine?
- Staleness: should context include a timestamp? Would brook ever refuse to
  append to a "stale" quickfix list? Probably not: user knows best.
- Provenance check failure: error vs warning vs configurable
- Maximum pattern accumulation: is there a point where the alternation becomes
  unwieldy? Probably not a practical concern.

## References

- `:help setqflist()` for context field documentation
- `:help quickfix-context` for context semantics
- Existing pattern translation module in brook.nvim
