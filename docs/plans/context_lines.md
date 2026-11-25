# Ripgrep context-line support (`-A`/`-B`/`-C`)

## Status

Proposed, with no implementation yet.

## Summary

Brook rejects ripgrep's `-U`/`--multiline`, because its `--vimgrep` parser and its pattern translator are line-based. The quickfix list itself holds multi-line entries: see `docs/plans/multiline.md`.

Ripgrep's `-A`/`-B`/`-C` context flags keep the match itself single-line. Each context line maps to its own quickfix entry.

The motivating case: searching for a field name to check nothing was missed during a change, where the field is used inside a SQL query formatted across many lines. The match is one line; reviewing it safely needs the surrounding query text.

`-A`/`-B`/`-C` are not currently blocked. They already pass through `:Rg pattern -C 3` today.

The multiline rejection in `M.raw` (`lua/brook/rg/init.lua`) only checks for `-U`/`--multiline`/`--multiline-dotall`. The flag tokenizer (`lua/brook/lib/rg_named_args.lua`) already recognises `-A`/`-B`/`-C` as value-taking flags.

The output silently breaks instead. Ripgrep's context lines use a different, dash-delimited format from match lines, which the current `\x1f`-separator-based parser cannot parse.

`M._parse_batch`'s `if entry then` guard silently drops every context line and the `--` group-separator line, with no feedback to the user.

This is a latent bug: a flag is accepted today and silently produces no effect.

`-U` multiline matching is a separate change, and this proposal keeps its rejection as it is. This proposal is purely additive.

---

## Verified ripgrep behaviour

Ripgrep has a `--field-context-separator` flag, parallel to the `--field-match-separator` flag Brook already sends, that makes context lines as unambiguous to parse as match lines. Verified empirically against real `rg` output:

```
$ printf 'a1\na2\na3 pattern one\na4\na5\n' | rg --vimgrep -C 2 \
    --field-match-separator $'\x1f' --field-context-separator $'\x1f' pattern
<stdin>\x1f1\x1fa1              <- context line: filename\x1flnum\x1ftext (3 fields, no col)
<stdin>\x1f2\x1fa2
<stdin>\x1f3\x1f4\x1fa3 pattern one   <- match line: filename\x1flnum\x1fcol\x1ftext (4 fields, unchanged)
<stdin>\x1f4\x1fa4
<stdin>\x1f5\x1fa5
```

Setting `--field-context-separator` when no `-A`/`-B`/`-C` is passed is a verified no-op. It is safe to add unconditionally, the same way `--field-match-separator` already is.

A bare `--` line, with no separators at all, still appears between non-adjacent context groups. The recommendation is to drop it explicitly in the parser, documented as a deliberate choice.

Quickfix has no native "separator row" concept. Synthesising a fake entry risks confusing `:cnext`/`:cfdo`.

`--line-number` (unique-lines mode, `-n`) also accepts `-C` and produces sensible output: match and context lines end up structurally identical (both 3 fields, no column), since unique-lines mode never carried a column.

Unique-lines mode gains full context-line support under this change. It cannot visually distinguish which line was the actual match from its surrounding context: an accepted, documented limitation of that mode.

---

## Relation to multiline support

`docs/plans/multiline.md` moves the result parser to `--json`, which changes this plan:

- **Steps 1 to 3:** context entries come from `"type":"context"` objects, so neither `--field-context-separator` nor the `--` line needs handling, and unique-lines mode can tell matches from context.

- **Step 5:** `max_results` follows ripgrep's `--max-count`, so only `"type":"match"` objects count towards it.

With the JSON parser in place first, steps 1 and 2 drop out.

---

## Implementation plan

### 1. Build the ripgrep command

In `M._build_rg_cmd` (`lua/brook/rg/exec.lua`), add `'--field-context-separator', ASCII_UNIT_SEPARATOR` to the unconditional flag block, alongside the existing `--field-match-separator`.

### 2. Parsing

Extend `M._parse_vimgrep` (`lua/brook/rg/exec.lua`) in place: it already runs `vim.split(line, ASCII_UNIT_SEPARATOR, {plain=true})`, so the fix is a branch on `#parts`.

- `#parts >= 4`: match line, current behaviour unchanged (`filename`, `lnum`, `col`, `text`).

- `#parts == 3`: context line: `filename`, `lnum`, `col = 1` (same default convention `M._parse_line_number` already uses), `text`.

- Anything else (the bare `--` line has 1 part, no separator): `nil`, same as today's fallback.

Add a short comment at that fallback branch stating that dropping the `--` group separator there is deliberate.

`M._parse_line_number` needs no logic change. In unique-lines mode, match and context lines are already structurally identical (3 fields each), so the existing `#parts >= 3` handling covers both.

Its docstring gains two facts: it receives context lines, and this mode can't tell which line was the actual match.

`M._parse_batch` needs no change. Its existing `if entry then ... end` guard already does the right thing once the parsers above return entries for context lines.

### 3. Distinguishing match vs. context entries in the quickfix window

In vimgrep mode, field count tells match (4 fields) from context (3 fields) apart at parse time.

Set `entry.type` to a distinct marker (for example `'I'`) on context entries, leaving match entries as today. This is the minimal-diff option, confined to the parser.

A custom `quickfixtextfunc` is a possible follow-up if the native `type`-based rendering looks wrong once seen in a running Neovim instance. Build it only then.

In unique-lines mode, match and context lines cannot be told apart. Leave both untyped: an accepted, documented limitation of that mode.

### 4. Config

No new config field is needed.

`-A`/`-B`/`-C` already flow through `:Rg pattern -C 3` today via the existing raw-args passthrough (tokenizer, unquoter, `M.parse_args`, `ctx.args`, `M._build_rg_cmd`). Fixing the parser is sufficient to make that path work for the SQL-review use case.

A persistent "always show N lines of context" config default is a plausible future addition, following the `output_format` precedence pattern already used in `M.raw` (`lua/brook/rg/init.lua`). Leave it out of this change; revisit only if requested separately.

### 5. Streaming and bookkeeping

`max_results` follows ripgrep's `--max-count`, which leaves context lines out of its count. `session.total_results` counts only match entries, so `-C 5` still lists up to `max_results` matches.

Under the `\x1f` parser, unique-lines mode can't tell a context line from a match, so this step needs the JSON parser from `docs/plans/multiline.md`.

Update the `max_results` doc comments in `lua/brook/types.lua` and `lua/brook/rg/types.lua` to state that context lines don't count.

No `vim.notify` call site reports a live count (checked `M._notify_completion`), so no wording change is needed there.

### 6. Other docs

- `README.md`: state that `-A`/`-B`/`-C` context lines are supported, each one quickfix entry per line.

### 7. Tests

No correctness test file exists yet for `exec.lua`'s parse functions.

`tests/bench_setqflist.lua` is a standalone benchmark with its own reimplementation, outside `bin/test`, so it stays untouched.

- Add `tests/rg/exec_test.lua`, covering a mixed batch (match line, leading context, trailing context, bare `--`) that parses to the right `vim.quickfix.entry` shapes, with correct `col` defaulting and the `--` line producing no entry.

- Same file: cover the same batch through unique-lines mode, parsing both line kinds identically, documenting the known can't-distinguish limitation.

- Same file: cover a malformed or unparseable line, confirming it is still silently dropped without erroring.

- Register the new file in `bin/test` via `run_test 'rg/exec'`, following the existing one-line-per-test-file pattern.

- Add a case to `tests/args/parser_test.lua` asserting that `-A`/`-B`/`-C`/`--after-context`/`--before-context`/`--context` never set `parsed_args.multiline = true`, to lock in that context-line support and the `-U` rejection stay independent as this code evolves.

---

## Explicitly out of scope

- `-U`/`--multiline` pattern matching, planned in `docs/plans/multiline.md`: it stays rejected in all three existing guard locations: the multiline check in `M.raw` (`lua/brook/rg/init.lua`), the visual-selection newline check (`lua/brook/init.lua`), and the hard-coded `--no-multiline` flag in `M._build_rg_cmd`. None of these need to change.

- A dedicated "always show context" config option: the raw-args passthrough already covers the use case; add a config field later only if requested.

- Custom `quickfixtextfunc` rendering: start with the `entry.type` marker; build this only if the default rendering proves insufficient in practice.

---

## Verification

1. `bin/test` passes, including the new `rg/exec` test and the extended `args/parser` test.

2. Manually, in a running Neovim instance with a multi-line SQL-like test file: run `:Rg field_name -C 3` and confirm the quickfix list shows the match plus 3 lines of context above and below, with no dropped lines. Confirm `-C`/`-A`/`-B` combinations all work, and that non-context searches (`:Rg foo`) render exactly as before.

3. Confirm `:Rg pattern -U` (and other multiline-triggering inputs) still gets rejected with the existing error message: a regression check that this proposal does not loosen the `-U` guard.

4. Confirm `-n -C 3` (unique-lines mode plus context) does not error and produces a reasonable, if visually undifferentiated, quickfix list.

<!-- vim: set tw=0 ft=markdown: -->
