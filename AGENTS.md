# AGENTS.md — brook.nvim Project Context

This file provides context for Claude Code sessions working on this repository.

## What This Is

brook.nvim is a Neovim plugin that wraps ripgrep (`rg`) and streams results into Neovim's native quickfix list. It translates ripgrep regex patterns to Vim `\\v`-mode regex so that `n`/`N` navigation works after a search.

**Requirements:** Neovim >= 0.10.0, ripgrep must be in `$PATH`.

---

## Commands

**Run all tests:**

```bash
./bin/test
```

**Run a single test file:**

```bash
nvim --headless -u NONE -c "set rtp+=." -c "luafile tests/pattern/tokeniser_literals_test.lua"
```

**Lint:** `selene` (configured via `selene.toml` with the `neovim` standard library).

---

## Module Map

```
lua/brook/
  init.lua              — Plugin entry, config validation, command/keymap registration
  types.lua             — UserConfig class (all user-facing config fields + defaults)
  util.lua              — Editor helpers (get_visual_selection)

  rg/
    init.lua            — Public search API: selection(), word(), raw(), repeat_last()
    exec.lua            — Async job management, producer-consumer pipeline, quickfix streaming
    types.lua           — ExecConfig class (execution params), RawOpts

  pattern/
    init.lua            — Public pattern API: translate()
    types.lua           — Token types, group kinds, escape classes, wordness enums
    tokeniser.lua       — Phase 1: lexical analysis, identifies token boundaries
    parser.lua          — Phase 2: semantic classification, wordness analysis for \b translation, validation
    translator.lua      — Phase 3: emits Vim \v regex

  args/
    parser.lua          — Extracts ripgrep search pattern and flags from unquoted tokens
    tokeniser.lua       — Shell-style tokenisation (splits on whitespace, respects quotes)
    unquoter.lua        — POSIX shell unquoting (interprets single/double quotes, escapes)
    types.lua           — ParsedArgs class, SearchCase enum, OutputFormat enum

  lib/
    fifo.lua            — Lock-free FIFO queue for producer-consumer decoupling
    rg_named_args.lua   — Auto-generated list of all ripgrep flags and options (from `--help`)
```

---

## Data Flow

```
User invokes command
  -> args module: tokenises and unquotes input (POSIX shell rules),
     extracts ripgrep pattern and flags
  -> pattern module: translates ripgrep regex to Vim \v-mode regex
     (tokeniser -> parser -> translator)
  -> rg/exec: spawns ripgrep without a shell,
     streams stdout through a FIFO into the quickfix list
```

### Key Design Decisions

- **No shell invocation.** Arguments are passed as arrays to `jobstart()` using `execve()` directly. This avoids shell escaping issues, shell compatibility differences (fish vs POSIX), and shell injection vulnerabilities.
- **Three-phase quickfix streaming** in `exec.lua`:
  1. **First paint** — small initial batch so results appear immediately
  2. **Streaming** — medium batches while ripgrep is still running
  3. **Drain** — large batches (5x max_batch_size) once ripgrep exits, with reduced throttle (half flush_throttle_ms)
- **bufnr cache** (filename → buffer number) avoids O(n) `vim.fn.bufnr()` scans at high result counts.
- Each search creates a new quickfix list (preserving history).

---

## Configuration (UserConfig defaults)

| Field | Default | Notes |
|-------|---------|-------|
| `keymap_cword` | `<leader>g` | Normal-mode keymap for current-word search |
| `keymap_visual` | `<leader>g` | Visual-mode keymap for selection search |
| `keymap_prompt` | `<leader>/` | Normal-mode keymap to open Rg prompt |
| `keymap_stop` | `<leader>G` | Normal-mode keymap to stop current search |
| `keymap_repeat` | `<leader>r` | Normal-mode keymap to repeat last search |
| `max_results` | 1000 | Maximum results before stopping |
| `max_batch_size` | 100 | Max results buffered before flushing (range: 10-200) |
| `flush_throttle_ms` | 10 | Delay between flushes for streaming |
| `qf_open` | true | Open quickfix list when results arrive |
| `qf_auto_resize` | true | Let quickfix window grow as results come in |
| `qf_win_height` | 10 | Max/fixed height of quickfix window |
| `output_format` | `one-line-per-match` | Or `unique-lines` (line-number format) |
| `set_search_register` | true | Set Vim search register for n/N navigation |
| `max_preview_chars` | 200 | Truncate result preview (range: 100-500) |

Notably, `drain_phase_max_batch_size` defaults to `max_batch_size * 5` and `drain_phase_flush_throttle_ms` defaults to `math.floor(flush_throttle_ms / 2)`.

---

## Pattern Translation Pipeline

Three-phase compiler in `lua/brook/pattern/`:

1. **Tokeniser** — Lexical analysis. Identifies token boundaries: literals, metacharacters, quantifiers, groups (capturing, named, lookarounds, atomic, flags), character classes (including nested), escape sequences (boundaries, character classes, literals, hex/unicode/octal, properties, backreferences), slashes.
2. **Parser** — Semantic classification. Assigns wordness to tokens for `\b` boundary translation, validates unsupported constructs (PCRE2-only features rejected in default mode), computes word/anchor properties for escapes.
3. **Translator** — Emits Vim `\v` regex. Handles mode prefix (`\C`/`\c`/`\Cv`), word boundaries, group translation, character class translation.

Key enums in `types.lua`: `TokenType`, `CCTokenType`, `GroupKind`, `EscapeClass`, `Wordness`.

The full translation spec (all supported/unsupported constructs, edge cases) lives in `docs/pattern_spec.md`.

---

## Args Module

`lua/brook/args/` implements POSIX-compatible shell tokenisation and unquoting so the user can pass `:Rg 'hello world'` exactly as they would on the command line.

- **tokeniser.lua** — Splits input string on whitespace while respecting single quotes, double quotes, backslash escapes, and the POSIX `'it'\\''s'` idiom. Quotes and escapes are *preserved* in output.
- **unquoter.lua** — Interprets quoted tokens into plain strings. Handles single-quoted (no escapes), double-quoted (only `\\`, `\"`, `\$`, `\`` escapes), and backslash-escaped characters.
- **parser.lua** — Extracts ripgrep search pattern (first positional or `-e`/`--regexp`), interprets a minimal subset of ripgrep flags (`-F`, `-w`, `-s`, `-i`, `-S`, `-n`, `--vimgrep`, `-P`, `--multiline`, `--engine`) to support Neovim features (search register, n/N navigation).

---

## Testing

Tests live in `tests/` and are plain Lua scripts using assertion helpers from `tests/harness.lua`. No external test framework.

**Test structure:**

- `tests/harness.lua` — Custom assertion library with `test()`, `eq()`, `deep_eq()`, and formatted failure output (shows got vs want, file/line info).
- Tests are run via `./bin/test` which invokes `nvim --headless -u NONE -c "set rtp+=." -c "luafile tests/<name>_test.lua"`.
- `bin/test` runs ~28 test files covering all modules.

**Test coverage areas:**

- `lib/fifo` — FIFO queue push/pull/len/is_empty
- `args/parser` — Token extraction, option parsing, stacked short args, long args with =
- `args/tokeniser` — Shell-style tokenisation with quotes and escapes
- `args/unquoter` — POSIX unquoting of single, double, mixed, and escaped tokens
- `pattern/tokeniser` (5 files) — Basic tokens, groups, escapes, character classes, complex patterns
- `pattern/parser` (5 files) — Escape classification, wordness, boundary handling, validation, complex
- `pattern/translator` (8 files) — Basics, literals, escapes, boundaries, quantifiers, groups, char classes, complex
- `pattern/pattern_integration` — Full pipeline integration
- `pattern/pattern_merging` — Multiple pattern merging for search register

**CI:** `./bin/test` runs inside an Alpine container via `.github/workflows/test.yml`.

---

## Constraints & Gotchas

- **Single-line search only.** Multiline search is explicitly rejected with a notification.
- **PCRE2 not supported.** `-P` / `--pcre2` / `--engine=pcre2` are blocked. The plugin targets ripgrep's default Rust regex engine.
- **Visual selections containing newlines are rejected.**
- **No word under cursor** — `:Rg` with no arguments calls `expand('<cword>')`; if empty, shows an error.
- **The `rg_named_args.lua` file is generated** by `bin/generate-rg-named-args` from ripgrep's `--help` output. Do not edit it by hand.
- **Tests must use `nvim --headless -u NONE -c "set rtp+=."`** — do not load any plugins during testing.

---

## Key Implementation Details

- `exec.lua` is a singleton with module-level state: `active_rg_job_id`, `flush_timer`, `flush_scheduled`, `last_search_context`. Use `M._exec()` (underscore-prefixed, internal) for actual execution; `rg/init.lua` calls it directly.
- The FIFO queue uses a cursor-based approach (not compaction) to avoid O(n) shifts; it's garbage collected at the end of each search.
- Quickfix operations use `setqflist()` with `op = 'a'` (append) after the initial list creation.
- The `state` enum drives a three-phase flush strategy: `first-paint` -> `streaming` -> `draining` -> `done`.
- Benchmark mode (`_benchmark = true`) collects nanosecond-level timing data for `setqflist()` calls, stdout callbacks, and batch sizes.
