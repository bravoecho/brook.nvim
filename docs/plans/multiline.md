# Multiline search (`-U`)

## Status

Proposed, with no implementation yet.

## Summary

Brook rejects ripgrep's `-U`/`--multiline`/`--multiline-dotall` and multi-line visual selections. The quickfix list holds multi-line entries (see "Verified behaviour"), so the obstacles are in Brook:

- **Result parser:** Brook reads `--vimgrep` output, which keeps only the first line of a multiline match.

- **Pattern translator:** under `-U`, several ripgrep constructs match a newline, and their Vim translations don't.

The plan switches the result parser to `--json` for every search, adds a multiline mode to the translator, and lifts the guards.

---

## Verified behaviour

Verified with Neovim 0.12.6 and ripgrep 16.0.0, against this file (`three.txt`):

```
a foobar()

   
{ b
foobar() { x
```

### The quickfix list holds multi-line entries

A quickfix item carries `end_lnum` and `end_col` next to `lnum` and `col` (`:help getqflist()`), and `errorformat` fills them with `%e` and `%k`. `:vimgrep` matches across line breaks and fills both:

```
:vimgrep /\vfoobar\(\)\_s*\{/ three.txt

three.txt|1-4 col 3-2| a foobar()
three.txt|5 col 1-11| foobar() { x
```

`end_col` is exclusive: the first match ends on the `{` in column 1 of line 4, and `end_col` is 2.

The quickfix window shows one row per entry, and `:vimgrep` stores only the first line of a match as its text.

An item whose `text` holds newlines still renders on one row, with each newline and the whitespace after it collapsed into one space: `"a foobar()\n\n   \n{ b"` shows as `a foobar() { b`.

### Ripgrep's line formats lose the end of a match

For the 4-line match above:

- `-U --vimgrep` prints the first line only: `three.txt:1:3:a foobar()`.

- `-U -n --column` prints every line of the match, each with the match's start column (`1:3:`, `2:3:`, `3:3:`, `4:3:`), so two matches on adjacent lines run together.

`-U --json` keeps the whole match:

```json
{"type":"match","data":{"path":{"text":"three.txt"},"lines":{"text":"a foobar()\n\n   \n{ b\n"},"line_number":1,"absolute_offset":0,"submatches":[{"match":{"text":"foobar()\n\n   \n{"},"start":2,"end":17}]}}
```

`start` and `end` are byte offsets into `lines.text`. The end line is `line_number` plus the count of `\n` before `end`, and the end column is the byte count after the last of them.

### Other `--json` facts that affect a parser

- Matches that share a line share an object, with one element per match in `submatches`. Under `-U`, a match spanning lines 1 and 2 and a match on line 2 arrive as one object.

- Without `-U`, matches on adjacent lines arrive as separate objects.

- `--max-columns` and `--max-columns-preview` have no effect, so a minified line arrives whole. The longest JSON line for the benchmark's search below was 1.5 MB.

- A line or path that isn't valid UTF-8 arrives base64-encoded, under `bytes` in place of `text`.

- Context lines from `-A`/`-B`/`-C` arrive as `"type":"context"` objects, with no `--` separator line.

- `--json` after `--vimgrep` switches the output to JSON, and `--no-json` after `--json` switches it back.

### Newlines in the pattern

- Without `-U`, ripgrep refuses a pattern holding `\n` or a literal newline, with `the literal "\n" is not allowed in a regex` and exit code 2.

- With `-F -U`, a literal newline in the pattern matches a line break: `rg -F -U $'foo\nbar'` finds `foo` on one line and `bar` on the next.

- Under `-U`, ripgrep's `--max-count` counts a multiline match once.

### Cost of decoding JSON

Measured on 100,000 results of `rg -w data` over the Homebrew Cellar and `~/ws` on macOS, timed in headless Neovim, with two runs within 3 ms of each other:

- `M._parse_vimgrep`: 88 ms.

- `vim.json.decode` plus flattening into quickfix items, one per submatch: 240 ms.

- One `setqflist()` call with the parsed items: 2,900 ms.

- Ripgrep alone: 0.96 s for both formats, writing 17 MB as `--vimgrep` (capped at 200 columns) and 45 MB as JSON (uncapped).

- `vim.json.decode` of a 1.4 MB line: 1.1 ms.

JSON decoding adds about 1.5 µs per result. At the default `max_results` of 1,000 that is about 1.5 ms per search, about 5% of the `setqflist()` cost.

The time `M._on_stdout` spends joining output chunks into lines is unmeasured. It grows with bytes, and JSON writes about 2.6 times as many, most of them from minified files.

---

## Decisions

- **JSON for every search.** One parser serves both output formats, gives context lines their type, and removes the `\x1f` separator. It costs about 1.5 ms per search at the default `max_results`.

- **Ripgrep handles what Brook doesn't need.** A `\n` typed without `-U` reaches ripgrep unchanged, and ripgrep's error is shown.

- **`max_results` follows ripgrep's `--max-count`.** A multiline match is one quickfix entry and counts once, and context lines don't count.

- **Joined text.** An entry's `text` holds the lines its own match spans, with the trailing newline removed and each newline plus the whitespace after it replaced by one space. The quickfix window renders newlines the same way, and joining in Brook keeps `getqflist()` output on one line for other plugins.

---

## Implementation plan

### 1. Parse `--json` output

In `M._output_format_args` (`lua/brook/rg/exec.lua`), pass `--json` in place of `--vimgrep`, `--column`, `--no-column` and the separator flags.

Remove `--max-columns` and `--max-columns-preview` from `M._build_rg_cmd`, because they have no effect under `--json`.

Replace `M._parse_vimgrep` and `M._parse_line_number` with one parser that decodes a line and returns a list of entries:

- Objects other than `"type":"match"` give no entry. Context objects join in under `docs/plans/context_lines.md`.

- The file name is `path.text`, or `path.bytes` base64-decoded. The same goes for `lines`.

- One-line-per-match mode gives one entry per submatch. Unique-lines mode gives one entry per object, at its first submatch.

- `lnum`, `col`, `end_lnum` and `end_col` come from `line_number` and each submatch's byte offsets into `lines.text`.

- `text` is joined as in "Decisions", then cut to `max_preview_chars`.

`M._parse_batch` and the `max_results` count take a list of entries per line in place of one.

Then check against ripgrep 13, the minimum version:

- Every flag Brook passes or overrides behaves as above under `--json`.

- Which flags in `UNSUPPORTED_FLAGS` still need rejecting, and which ones `--json` overrides.

- Whether the README's advice to keep `--vimgrep` out of `~/.ripgreprc` still holds.

Benchmark end to end with the bench instrumentation in `exec.lua`, at `max_results` 1,000 and 100,000, against the `--vimgrep` path.

### 2. Add a multiline mode to the translator

Pass `parsed_args.multiline` to the pattern module. Under it, the translator emits the newline-matching Vim form of each construct that matches a newline in ripgrep:

- `\s`, `\W` and `\D` become `\_s`, `\_W` and `\_D`.

- A negated class `[^…]` becomes `\_[^…]`.

- `.` becomes `\_.` under `--multiline-dotall` or an `s` flag group.

- `\A` and `\z` become Vim's start-of-file and end-of-file atoms, `%^` and `%$` in `\v` mode.

- A literal newline in a `-F` pattern becomes `\n`.

Each rule needs checking against ripgrep before it goes in `docs/pattern_spec.md`, including how flag groups such as `(?s)` and `(?-s)` scope `.`.

### 3. Lift the guards

- Remove the multiline rejection in `M.raw` (`lua/brook/rg/init.lua`).

- Keep the hard-coded `--no-multiline` in `M._build_rg_cmd`. It overrides a `-U` in `~/.ripgreprc`, and a `-U` typed in `:Rg` comes after it and wins.

- Let the visual-selection keymap (`lua/brook/init.lua`) accept a selection holding newlines, and search it with `-F -U`.

### 4. Tests

- Parser: match objects in both output formats, multi-line submatches, several submatches in one object, `bytes` paths and lines, and objects of other types.

- Translator: each rule in step 2, with and without multiline mode.

- Selection: a multi-line selection builds `-F -U` with the text unchanged.

### 5. Docs

- `README.md`, "Unsupported search modes": remove the multiline paragraph, and document multiline search with an example.

- `docs/pattern_spec.md`: add the multiline rules, and update section 11 on `\A` and `\z`.

- `docs/quickfix_optimisations.md`, "Ripgrep JSON output": record the end-to-end benchmark, and move the section out of "Future Work".

---

## Out of scope

- Adding `-U` when the pattern holds `\n`: ripgrep's own error covers it.

- Highlighting the whole matched range in the quickfix window: `end_lnum` and `end_col` are stored for a later `quickfixtextfunc`.

<!-- vim: set tw=0 ft=markdown: -->
