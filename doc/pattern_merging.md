# brook.nvim: Pattern Merging

Design document for merging multiple `-e` patterns into a single search register
pattern.

## Problem Statement

Support for multiple `-e` options passed to ripgrep, with proper search register
integration so `n`/`N` navigation works across all patterns.

## Key Insight

Alternation already works. When searching for `foo|bar` with ripgrep, brook
translates it to `\vfoo|bar` for the search register, and `n`/`N` jumps to
matches of either pattern. Users already have the correct mental model.

The idea is to treat `-e foo -e bar` as equivalent to `foo|bar` at pattern
construction time, before translation.

## Multiple `-e` Pattern Merging

### Approach

1. Parse `-e` arguments from the command line
2. Join extracted patterns with `|` into a single ripgrep pattern
3. Pass the merged pattern through the existing translation pipeline
4. Set the search register with the translated result

Ripgrep still receives the original arguments unchanged: it handles `-e`
natively. The merging is only for Vim's benefit.

### Positional vs `-e` Patterns

These modes are mutually exclusive. When `-e` is present, ripgrep treats the
first positional argument as a path, not a pattern:

```
> rg foo -e bar
rg: foo: IO error for operation on foo: No such file or directory (os error 2)
```

Brook should detect `-e` presence and only extract patterns from `-e` arguments
in that case. No "mixed mode" handling is needed.

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
  should result in `\v<foo>|<bar>`.
- Fixed-string mode: when the `-F`/`--fixed-strings` flags are set, the patterns
  should be merged using an escaped bar character `\|`,
  so `-e '^foo' -e '^bar' -F` should result in `\V^foo\|^bar`.
- Word+fixed combined: when both modes are set, the strategies should be
  combined, using the escapes `\<` and `\>` for the boundaries,
  so `-e 'foo' -e 'bar' -wF` should result in `\V\<foo\>\|\<bar\>`.
- Case sensitivity: when the case-sensitive/case-insensitive flags are set, the
  combined pattern will be prepended with the `\c`/`\C` modifiers as usual.

### Testing

- Single `-e`: equivalent to current behaviour
- Multiple `-e`: verify joined pattern translates correctly
- Anchors in multiple patterns
- Patterns containing literal pipe characters

## Rejected: Quickfix Append Mode

We considered but rejected a feature to append search results across multiple
invocations (vim-grepper's `--append` flag).

### Why It Was Considered

The idea was to accumulate results: run `:Brook foo`, see the results, then run
`:Brook --append bar` to add matches for `bar` to the existing quickfix list.

### Why It Was Rejected

1. Conflicting options across searches: if the first search is case-sensitive
   and the second is case-insensitive, what should the merged search register
   contain? Vim's `\c`/`\C` modifiers apply to the entire pattern, not to
   individual alternation branches. The same problem applies to `--fixed-strings`
   vs regex mode (though `\V`/`\v` can technically be switched mid-pattern, the
   semantics become confusing).

2. Mental overhead: the user must remember what's currently accumulated in the
   quickfix and why. The quickfix title would show only the last search, not the
   full history.

3. Fragile state: running a normal `:Brook` search after several appends would
   silently discard the accumulated results. Easy to do by accident.

4. Multi-pattern already solves the use case: if you realise you want to search
   for both `foo` and `bar`, press `<Up>` to recall the last command and edit it
   to `:Brook -e foo -e bar`. The quickfix title then clearly shows the complete
   search, and the search register is unambiguous.

The command-line history approach is transparent: the quickfix always reflects
exactly what you asked for, and the title is the authoritative source of truth.

## References

- `:help setqflist()` for context field documentation
- `:help quickfix-context` for context semantics
- Existing pattern translation module in brook.nvim
