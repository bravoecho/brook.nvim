# `setqflist()` performance optimisations

## Status

Implemented (Parts 1–3). Bench instrumentation still present in `exec.lua` —
strip or gate behind a flag before release.

## Summary

Repeated large-scale searches in brook.nvim cause `vim.fn.setqflist()` to
degrade from ~7ms per call to ~260ms per call, turning a 1-second search into
a 70-second one. The root cause is Neovim's O(n) filename-to-buffer resolution
inside `setqflist()`, where n is the total number of buffers. Each search
creates thousands of unlisted buffers as a side effect, and these accumulate
across searches, making every subsequent call slower.

Three mitigations were implemented: a session-local filename-to-bufnr cache
that resolves each unique filename exactly once, an optional unlisted-buffer
wipe between searches to prevent cumulative growth, and a deferred-parsing
redesign that moves per-line work out of the `on_stdout` producer to eliminate
main-loop starvation.

All benchmarks were run against a large multi-repo corpus (`~/ws/large-repos`,
containing repositories at the scale of Firefox, Linux, and LLVM) with
`max_results = 100,000`.

---

## Symptoms

When running a search that populates the quickfix list with a large number of
results (tested at 100,000), the following behaviour is observed.

The first search after launching Neovim completes in under 1 second. The
second search, with identical parameters, takes 6–8 seconds. Each subsequent
search is progressively slower, eventually reaching 60–70 seconds after 10
runs. Neovim's memory usage grows monotonically with each search, reaching
1.2GB after 10 runs and never releasing. Neovim becomes visibly janky during
degraded searches, with multi-second UI freezes. Quitting Neovim with `:q`
takes noticeably longer. The degradation persists across Neovim restarts
(explained separately below). Running `sudo purge` (macOS kernel cache flush)
is the only reliable way to restore first-run performance from outside Neovim.

The degradation is **not caused by** ripgrep slowing down (confirmed via
`hyperfine` benchmarking), quickfix stack accumulation (the `f` action had no
effect), or main-loop contention between producer and consumer (the pattern is
monotonically worsening, not bistable).

---

## Investigation

### Instrumentation

To isolate the bottleneck, we added timing instrumentation to `exec.lua` that
measures three intervals. The first is wall time from `jobstart()` to the
`on_exit` callback (labelled "ripgrep" in the output, though it includes
main-loop scheduling delay). The second is wall time from `on_exit` to the
final phase-3 flush completion (the drain period). The third is cumulative time
spent inside `vim.fn.setqflist()` calls across all three consumer phases.

The instrumentation uses `vim.loop.hrtime()` (nanosecond monotonic clock) and
reports via `print()` to `:messages`.

### Key finding

Across 10 consecutive runs of the same search (`:Rg data -w`, 100,000 results),
`setqflist()` cumulative time accounted for **98–99%** of total wall time in
every run. The per-call average degraded as follows:

- Run 1: 100K items, 814ms total, 7ms/call, ~4K buffers
- Run 2: 100K items, 6,482ms total, 34ms/call, ~8K buffers
- Run 3: 100K items, 7,842ms total, 39ms/call, ~12K buffers
- Run 4: 100K items, 9,544ms total, 34ms/call, ~16K buffers
- Run 5: 100K items, 12,730ms total, 60ms/call, ~20K buffers
- Run 6: 100K items, 13,319ms total, 61ms/call, ~20K buffers (saturated)
- Run 7: 100K items, 13,868ms total, 65ms/call, ~20K buffers (saturated)
- Run 8: 46K items, 33,491ms total, 241ms/call, ~30K buffers (new pattern)

Runs 5–7 show the per-call cost plateauing at ~60–65ms. This is because the
same search pattern (`data -w`) produces matches in the same set of ~4,000
files, so no new buffers are created after the first run. When run 8 uses a
different pattern (`report -w`), ~10,000 new files enter the buffer list and
the per-call cost jumps to 241ms.

`vim.fn.getbufinfo()` confirmed 19,650 buffers after 5 identical runs, rising
to >30,000 after the different-pattern run. The vast majority are unlisted
buffers created as a side effect of `setqflist()`.

### Root cause: `qf_get_fnum()` and the buffer list

When `setqflist()` receives items with a `filename` field (as opposed to
`bufnr`), Neovim internally calls `qf_get_fnum()` for each item. This function
calls `buflist_findname_stat()`, which performs a **linear scan** of the entire
buffer list, doing a string comparison against every buffer's full path.

The buffer list in Neovim is a linked list, inherited from Vim's original C
codebase. This was a reasonable choice when the expected buffer count was in the
low dozens (a human opening files by hand), but it produces O(n) lookup cost
that becomes painful at thousands of entries.

For each `setqflist()` call with a batch of 500 items, Neovim performs
500 × n string comparisons, where n is the buffer list size. At 20,000 buffers,
that is 10 million string comparisons per batch. This is where the time goes.

### Why buffers accumulate

When `qf_get_fnum()` encounters a filename that is not already in the buffer
list, it creates a new **unlisted buffer** via `buflist_add()`. Freeing the
quickfix list (via the `f` action) frees the quickfix entries but does **not**
remove these unlisted buffers. They persist for the lifetime of the Neovim
session, accumulating across searches.

This also explains the cross-restart degradation observed on macOS: it was
initially attributed to filesystem cache eviction (and `sudo purge` did restore
performance), but the primary mechanism is the buffer list growth within a
single session.

### Why this only matters at scale

With the default `max_results = 1000`, a typical search creates at most a few
hundred unlisted buffers (since many results share the same file). Even after
dozens of searches, the buffer list might grow to 2,000–3,000 entries, and the
per-call overhead remains imperceptible. The problem only becomes visible at
extreme result counts (tens of thousands), which is why it has not been
reported by users.

---

## Implemented Solution

Three changes were implemented, each building on the previous.

### Part 1: Session-local filename-to-bufnr cache

**Goal:** Reduce the number of `buflist_findname_stat()` calls from
O(total_matches) to O(unique_files) per search.

**Mechanism:** A Lua hash table (`session.bufnr_cache`) maps filenames to
buffer numbers, populated lazily as results are parsed. `vim.fn.bufadd()` is
called once per unique filename, and the resulting `bufnr` is passed to
`setqflist()` instead of `filename`. Neovim resolves `bufnr` in O(1) (direct
array index into the buffer table) rather than O(n) (linear scan by filename).

**Implementation:** `_resolve_bufnr(filename, cache)` wraps the lookup-or-add
logic. The resolution happens after parsing, keeping the parse functions
(`_parse_vimgrep`, `_parse_line_number`) pure. The cache lives on the session
object and is garbage-collected when the search completes.

```lua
-- In the session initialiser inside _exec():
local session = {
    -- ... existing fields ...
    bufnr_cache = {},  -- filename --> bufnr lookup cache
}
```

```lua
-- Resolve filename to buffer number, caching the result.
--
-- `vim.fn.bufadd()` creates the buffer if it doesn't exist, or returns the
-- existing bufnr if it does. We call it once per unique filename rather than
-- letting setqflist() call buflist_findname_stat() once per match.
---@param filename string
---@param cache table<string, number>
---@return number bufnr
function M._resolve_bufnr(filename, cache)
    local bufnr = cache[filename]
    if not bufnr then
        bufnr = vim.fn.bufadd(filename)
        cache[filename] = bufnr
    end
    return bufnr
end
```

```lua
-- In _on_stdout, after parsing:
local entry = parse_line(line)
if entry then
    -- Resolve filename --> bufnr before enqueueing
    entry.bufnr = M._resolve_bufnr(entry.filename, session.bufnr_cache)
    entry.filename = nil
    session.queue.push(entry)
    session.total_results = session.total_results + 1
end
```

**Note on `bufadd()`:** This function is called from a `vim.schedule_wrap`
context (the `on_stdout` callback), which means it runs on the main loop and
can safely call Vimscript functions. It does not need to be wrapped in
`vim.schedule()` again. `bufadd()` itself performs a buffer list lookup, so the
4,000 calls to `bufadd()` still pay the O(n) cost. However, 4,000 × n is
dramatically better than 100,000 × n.

**Measured impact:** `setqflist()` cumulative time on the first run dropped
from 814ms to 202ms. Per-call cost dropped from 7ms to ~2ms. However,
cumulative degradation across runs persisted (202, 478, 741, 1,052ms) because
`bufadd()` itself does an O(n) buffer list scan, and the buffer list grows
with each search.

### Part 2: Unlisted buffer wipe between searches

**Goal:** Prevent cumulative buffer list growth across searches, so the tenth
search is as fast as the first.

**Mechanism:** Before starting a new search, iterate the buffer list and delete
unlisted buffers that are not visible in any window and are not modified.

**Where to implement:** Early in `_exec()`, after cancelling previous
scheduling but before initialising the new session. Gated behind
`ctx.cfg.wipe_unlisted_buffers` (defaults to `false`).

```lua
-- In _exec(), after M._cancel_phase3_scheduling() and before session init:

-- Wipe unlisted buffers accumulated by previous searches.
--
-- Each setqflist() call with filename fields causes Neovim to create unlisted
-- buffers via buflist_add(). These persist after the quickfix list is freed,
-- causing the buffer list to grow indefinitely. Since setqflist() resolves
-- filenames via a linear scan of the buffer list (O(n) per item), accumulated
-- buffers degrade performance on subsequent searches.
--
-- This cleanup targets only buffers that are:
--   * not listed (not opened by the user)
--   * not displayed in any window
--   * not modified (no unsaved changes)
--
-- The pcall() guard handles edge cases where a buffer becomes invalid
-- between the nvim_list_bufs() snapshot and the delete call.
for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf)
        and not vim.bo[buf].buflisted
        and not vim.bo[buf].modified
        and vim.fn.bufwinid(buf) == -1
    then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
end
```

**Measured impact:** `setqflist()` cumulative time became flat across runs
(~420–460ms). The wipe itself costs ~350–400ms at ~12,000 buffers, which is a
worthwhile trade at 100K results. At normal `max_results = 1000`, the wipe
would be near-instant and the degradation it prevents would be imperceptible —
hence the default-off flag.

**Risk:** This deletes **all** invisible unlisted buffers, not only those
created by `setqflist()`. Other plugins may create unlisted buffers for their
own purposes (e.g. nvim-bqf's preview buffer, LSP hover windows, or
telescope's result buffers). In practice, these plugins typically manage their
own buffer lifecycle (creating and deleting as needed), so the risk is low. If
conflicts arise, a more targeted approach would be to tag brook-created buffers
with a buffer-local variable and only delete those, but this adds complexity
for a problem that may never materialise.

**Observation:** For repeated different-pattern searches (e.g. alternating
`data -w` and `report -w`), the wipe deletes buffers that `bufadd()` will
immediately recreate. This is a known inefficiency; a more targeted approach
(tagging brook-created buffers) could address it if it becomes a real problem.

### Part 3: Deferred parsing (producer-consumer redesign)

**Problem.** With Parts 1 and 2 in place, `setqflist()` was no longer the
bottleneck. Benchmarking revealed that `ripgrep (start --> exit)` wall time
was 4,500–5,400ms for a search where raw ripgrep completes in ~100ms.
The `on_stdout` callback was doing too much work per invocation: parsing every
line, calling `bufadd()` for each match, and checking queue length — all
synchronously on the main loop. With batches of 700–2,800 lines, each callback
blocked the main loop for tens of milliseconds, starving redraws and causing
visible stutter during phase 2.

**Key insight.** Phase 3 never stuttered because ripgrep had exited and the
consumer had the main loop to itself. The fix was to make phase 2 behave like
phase 3 by moving all per-line work out of the producer.

**Solution.** `_on_stdout` was stripped down to buffer stitching, raw line
enqueueing (strings, not parsed entries), result counting, and limit checking.
A new `_parse_batch(n, session)` function pulls raw lines from the queue,
parses them, resolves bufnr, and returns `vim.quickfix.entry[]`. All three
flush functions call `_parse_batch` instead of `queue.pull` directly.

**Implementation details:**

- The queue now holds raw strings instead of parsed entries
- `session.parse_line` stores the parser function (moved from a local in
  `_exec` to a session field) so the consumer can access it
- The mid-loop `_request_flush` trigger (fired when
  `queue.len() >= max_batch_size`) was removed — with a lightweight producer,
  the single `_request_flush` at the end of each callback is sufficient
- `_parse_batch` returns fewer entries than requested if some lines fail to
  parse (the count mismatch is harmless)

**Measured impact.** `ripgrep (start --> exit)` dropped from ~4,500–5,400ms to
~1,100–1,500ms. The callback count increased from ~150 to ~4,000–7,000
(the main loop cycles faster, so libuv dispatches more frequent, smaller
batches). Total wall time remained similar (~5–6s) because the parsing work
moved to the drain phase, but the UI is now responsive throughout — the work
happens in bounded batches with idle gaps.

The ultra-fast first run (~700ms) observed before Part 3 disappeared. This is
expected: previously, run 1 benefited from eager parsing in `on_stdout` with a
clean buffer list, leaving the drain with nothing to do. Now the producer is
always fast and the consumer always does the heavy lifting — consistent
behaviour regardless of session state.

---

## Benchmark Summary

All runs use `:Rg data -w` at 100,000 results unless noted.

### Before any changes (baseline)

- Run 1: 814ms setqflist, 7ms/call
- Run 5: 12,730ms setqflist, 60ms/call
- Run 8 (different pattern): 33,491ms setqflist, 241ms/call

### After Part 1 only (bufnr cache)

- Run 1: 202ms setqflist, ~720ms wall
- Run 4 (different pattern): 1,052ms setqflist, ~11,773ms wall
- Cumulative degradation still present

### After Parts 1+2 (bufnr cache + buffer wipe)

- setqflist: flat at ~420–460ms across runs
- Wipe cost: ~350–400ms per search (~12K buffers)
- Wall time: ~5,000–6,000ms
- Bottleneck shifted to `ripgrep (start --> exit)`: 4,500–5,400ms

### After Parts 1+2+3 (+ deferred parsing)

- setqflist: flat at ~225–255ms (further improvement)
- `ripgrep (start --> exit)`: 1,100–1,500ms (down from 4,500–5,400ms)
- Drain: 3,500–4,700ms (where parsing now happens)
- Wall time: ~4,700–6,200ms (similar total, work redistributed)
- on_stdout: ~4,000–7,000 callbacks, ~25 lines/callback avg
- Phase 2 visibly smoother

---

## Design Considerations

### Why not fix Neovim instead?

The proper fix would be to add a hash map from normalised file paths to buffer
numbers inside Neovim's `buffer.c`, maintained in parallel with the existing
linked list. This would turn `buflist_findname_stat()` from O(n) to O(1).
This is a well-understood pattern (Python's `OrderedDict` uses the same
approach), and the reproduction case is clean enough for a Neovim issue or PR.

However, the buffer list implementation is deeply entangled with many Neovim
subsystems (syntax highlighting, autocommands, signs, marks, undo, quickfix),
and the core team's bandwidth is limited. A plugin-side mitigation is the
pragmatic choice, and it also serves as a case study in working around
framework limitations — which aligns with brook.nvim's educational goals.

### Part 1 vs Part 2: which matters more?

Part 1 (the bufnr cache) has the larger impact on **each individual search**.
It reduces the number of O(n) lookups by a factor equal to the average number
of matches per file (roughly 25x at the tested scale). Even without Part 2,
a single search would be dramatically faster.

Part 2 (the buffer wipe) addresses **cumulative degradation** across searches.
Without it, the bufnr cache still calls `vim.fn.bufadd()` once per unique
file, and `bufadd()` itself does an O(n) scan. So the 4,000 `bufadd()` calls
would still get slower as the buffer list grows. Part 2 keeps the buffer list
small, ensuring that even the `bufadd()` calls remain fast.

For maximum impact, both parts should be implemented together.

### Impact on normal usage (max_results = 1,000)

At the default `max_results = 1,000`, a typical search produces matches across
perhaps 200–500 unique files. The buffer list grows by at most 500 entries per
search, and `setqflist()` with filename fields is already fast at that scale.
Part 1 would still provide a measurable improvement (reducing 1,000 filename
lookups to 500 `bufadd()` calls), but the absolute time saved would be in the
low tens of milliseconds — imperceptible to the user.

Part 2 would prevent very gradual degradation over hundreds of searches in a
long-running Neovim session. This is a real but subtle benefit.

Both parts are low-risk and low-complexity, so the cost of implementing them is
minimal even if the benefit at normal scale is small.

### Interaction with the parse function signature

Currently, `_parse_vimgrep` and `_parse_line_number` are pure functions that
take a string and return a quickfix entry. Part 1 requires bufnr resolution,
but we chose to keep the parse functions pure and perform the resolution after
parsing (in `_on_stdout` originally, then in `_parse_batch` after Part 3):

```lua
local entry = parse_line(line)
if entry then
    entry.bufnr = M._resolve_bufnr(entry.filename, session.bufnr_cache)
    entry.filename = nil
    session.queue.push(entry)
    session.total_results = session.total_results + 1
end
```

This is slightly less efficient (it creates the `filename` field and then
replaces it) but preserves the parse functions' purity and avoids changing
their signature. The efficiency difference is negligible.

---

## Remaining Observations

### Phase 3 stutter on `report -w`

Some stutter was observed during phase 3 of `:Rg report -w` searches. Two
contributing factors:

- **Memory pressure.** Neovim was at ~480MB RAM by this point. Each `bufadd()`
  and `setqflist()` call allocates.
- **Higher unique file count.** `report -w` matches ~12,500 unique files vs
  ~4,000 for `data -w`, tripling the bufnr cache misses and `bufadd()` calls.
  `setqflist()` confirms this: ~720ms for `report` vs ~240ms for `data`.

### Wipe cost for alternating patterns

When alternating between search patterns, the wipe deletes buffers that the
next search will recreate via `bufadd()`. At ~12K buffers, this costs ~350ms
of wasted work. A more targeted approach (tagging brook-created buffers with a
buffer-local variable) could avoid this, at the cost of added complexity.

### Callback volume

The deferred-parsing version produces 4,000–7,000 `on_stdout` callbacks per
search. Each callback is lightweight (buffer stitching + table inserts), but
the sheer volume of `vim.schedule_wrap` dispatches has its own overhead. This
is not currently a problem, but worth monitoring.

---

## Alternative Approaches Not Taken

### Chunked processing within `on_stdout`

Rather than moving all parsing to the consumer, `on_stdout` could process
lines in bounded chunks (e.g. 100 at a time), yielding back to the main loop
between chunks via `vim.schedule`. This would keep parsing in the producer but
prevent any single callback from monopolising the main loop.

The tradeoff is complexity: `on_stdout` would need to manage partial
processing state (where it left off in the `data` array) across multiple
scheduled continuations, while new `on_stdout` callbacks could arrive in the
gaps. The deferred-parsing approach avoids this entirely by making `on_stdout`
trivially fast.

### Coroutine-based cooperative yielding

Lua coroutines could wrap the parsing loop in `on_stdout`, yielding after every
N lines and resuming on the next main-loop tick. This is a more idiomatic Lua
approach to cooperative multitasking and would avoid the state management
complexity of the chunked approach.

The concern is that coroutines interact subtly with `vim.schedule` and Neovim's
event loop — resuming a coroutine from a scheduled callback is possible but
adds a layer of indirection that could make the control flow harder to reason
about. It also doesn't change the fundamental insight that the producer
shouldn't be doing expensive work.

### Batch `bufadd()` at flush time only

Instead of resolving bufnr per-line in `_parse_batch`, collect all unique
filenames in the batch first, resolve them in a single pass, then build the
quickfix entries. This would allow potential future optimisation (e.g. a
hypothetical batch `bufadd()` API) and makes the cache-miss pattern more
visible. The current per-line approach is simpler and the performance
difference is negligible, but this could be revisited if `bufadd()` cost
becomes dominant.

### Intermediate transformer (third actor)

After the deferred-parsing redesign, the producer has one responsibility
(collect raw lines) while the consumer has two (transform and render). A
natural question is whether a third actor could handle transformation
separately, perhaps "in the background".

In Neovim's single-threaded environment, a separate transformer would still
run on the same main loop. A two-queue pipeline (raw lines, parsed entries,
quickfix) would add a scheduling layer without reducing total work, and would
introduce latency: the flush must wait for the transformer to produce enough
entries before it can run. The current design where `_parse_batch` does both
transform and render in one step is optimal for a single-threaded environment
— it minimises main-loop ticks needed to go from raw line to visible quickfix
entry.

The one genuine concurrency option is `vim.loop.new_work()` (libuv thread
pool), which can run Lua off the main thread. Parsing (`string:find()`,
`string:sub()`) could happen there, but `bufadd()` must run on the main thread
(it's a Vimscript function that touches Neovim internals). Since parsing is
cheap compared to `bufadd()`, this would add significant complexity for
marginal gain. Discarded.

---

## Future Work

### Ripgrep JSON output

The ripgrep documentation specifically advises programmatic clients not to use
`--vimgrep` and to prefer `--json` instead. This is worth investigating as a
potential improvement to the parsing phase.

**Current approach (`--vimgrep`).** The `--vimgrep` flag produces
colon-delimited lines (`file:line:col:text`). The parser uses
`result:find(':(%d+):(%d+):')` to locate the line:col boundary and
`string:sub()` to extract components. This works but is a heuristic —
filenames containing colons in specific patterns could theoretically confuse
it.

**What `--json` offers.** The `--json` flag emits one JSON object per line
with structured fields: filename, line number, column number, match text,
byte offsets, and submatches, all unambiguously separated. Potential benefits:

- **No colon ambiguity.** Eliminates an entire class of edge-case bugs around
  filenames with colons.
- **Richer data.** Byte offsets, submatches, and normalised paths could enable
  features like precise match highlighting in the quickfix preview.
- **`vim.json.decode` is C-backed.** It calls `cjson` under the hood, which
  may be faster than Lua pattern matching for structured data. Whether the
  difference is measurable at per-line scale is an empirical question.

Potential costs:

- **More verbose output.** JSON lines carry field names and structural
  characters, increasing pipe throughput. At 100K lines, the extra bytes
  could slow down the producer if the pipe becomes a bottleneck.
- **Higher memory churn.** `vim.json.decode` constructs a nested table per
  line, which must then be flattened into a quickfix entry. The current parser
  constructs a single flat table with four fields.

**Architectural fit.** The queue currently holds raw `--vimgrep` lines. With
JSON, there are two options:

- **Decode in `_parse_batch`** (same pattern as now): queue holds raw JSON
  strings, consumer decodes and transforms. Clean separation, no producer
  changes beyond the ripgrep flags.
- **Decode in `on_stdout`**: since `vim.json.decode` is a single C call
  rather than multiple Lua string operations, the per-line cost in the
  producer would be low. This adds some work back to `on_stdout` but avoids
  storing large JSON strings in the queue.

**Recommendation.** Benchmark the same search with `--json`, decoding in
`_parse_batch`, and compare total wall time and `setqflist()` cost against
the current `--vimgrep` path. If performance is comparable or better, the
correctness and extensibility benefits make JSON a clear win.

### Unify phase 2 and phase 3

With deferred parsing (Part 3), the producer no longer competes meaningfully
for the main loop. The original reason for distinct phase 2 and phase 3
strategies — different contention characteristics — has largely disappeared.
Both phases now do the same thing: pull raw lines, parse, resolve bufnr, flush
to quickfix, reschedule. The only difference is batch size and throttle
interval.

**Current structure:**

- Phase 2: smaller batches (`max_batch_size`), longer throttle
  (`flush_throttle_ms`), own timer (`phase2_timer`) and schedule guard
  (`phase2_scheduled`).
- Phase 3: larger batches (`drain_phase_max_batch_size`), shorter throttle
  (`drain_phase_flush_throttle_ms`), own timer (`phase3_timer`).
- Transition: `_start_phase3` cancels phase 2 scheduling, sets the phase
  enum, and kicks off the first phase 3 flush.

This requires two timers, two cancel functions, phase transition logic, and a
phase enum value that is only meaningful for choosing batch parameters.

**Proposed design.** A single consumer phase that adjusts its parameters based
on whether ripgrep has exited:

```lua
function M._flush_phase2(ctx, session)
  if session.current_phase ~= phases.phase_2 or session.queue.is_empty() then
    return
  end

  local draining = session.exit_code ~= nil
  local base_batch = draining
      and ctx.cfg.drain_phase_max_batch_size
      or ctx.cfg.max_batch_size
  local throttle = draining
      and ctx.cfg.drain_phase_flush_throttle_ms
      or ctx.cfg.flush_throttle_ms

  local batch_size = M._with_jitter(base_batch, ctx.cfg.batch_jitter)
  M._update_quickfix(M._parse_batch(batch_size, session), ctx, session)

  if session.queue.is_empty() and draining then
    session.current_phase = phases.done
    M._notify_completion(ctx, session)
    return
  end

  -- Reschedule (single timer, single guard)
  ...
end
```

The `on_exit` handler sets `exit_code` and, if phase 2 is already running,
does nothing else — the next flush iteration will pick up the drain parameters
automatically. If ripgrep exits during phase 1, the existing phase 1 / phase 2
transition still applies; phase 2 will see `exit_code` immediately and use
drain parameters from the start.

**What this eliminates:**

- `phase3_timer` and `_cancel_phase3_scheduling()`
- `_flush_phase3()` and `_start_phase3()`
- The `phase_3` enum value
- The phase 2 / phase 3 transition in `_on_exit`

**Edge case to test.** Ripgrep exits before phase 1 completes. Currently
`_on_exit` flushes phase 1 synchronously, then starts phase 3. With a unified
phase 2, the sequence would be: `_on_exit` sets `exit_code`, flushes phase 1
synchronously, phase 1 transitions to phase 2, and phase 2 sees `exit_code`
is set and uses drain parameters immediately. This should work but needs
careful testing, as the timing of `on_exit` relative to `on_stdout` callbacks
can vary.

---

## Verification Plan

After implementing both parts, the following should be verified.

**Benchmark at 100,000 results:** Run the instrumented version (with the bench
timing from the investigation phase) for 10 consecutive identical searches.
The `setqflist()` cumulative time should remain approximately constant across
runs (no cumulative degradation), and each run should be significantly faster
than the pre-mitigation baseline.

**Benchmark at 1,000 results:** Confirm that normal usage is not negatively
affected. The total wall time should be the same or slightly faster.

**Buffer count check:** After 10 searches, `len(getbufinfo())` should remain
roughly constant (not growing by thousands per search).

**Compatibility:** Verify that quickfix navigation (`:cnext`, `:cprev`,
`:copen`, jumping to entries) still works correctly when entries use `bufnr`
instead of `filename`. Verify that nvim-bqf's preview functionality is not
broken by the unlisted buffer cleanup.

---

## Files Modified

- `lua/brook/rg/exec.lua` — all three parts implemented here
- `lua/brook/rg/types.lua` — added `wipe_unlisted_buffers` field to
  `brook.rg.ExecConfig`

The bench instrumentation (`brook.BenchData` fields and `_emit_bench_summary`)
is included in the current state of `exec.lua`. It should be stripped or gated
behind a flag before release.

---

## References

Neovim source: `src/nvim/quickfix.c` (`qf_get_fnum()`),
`src/nvim/buffer.c` (`buflist_findname_stat()`).

Related Neovim API: `vim.fn.setqflist()`, `vim.fn.bufadd()`,
`vim.api.nvim_buf_delete()`, `vim.fn.getbufinfo()`.
