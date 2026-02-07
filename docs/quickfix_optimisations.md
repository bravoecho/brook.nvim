# `setqflist()` performance degradation

## Status

Proposed — not yet scheduled. This document captures the investigation and
proposed solution so that implementation can begin without re-discovery.

## Summary

Repeated large-scale searches in brook.nvim cause `vim.fn.setqflist()` to
degrade from ~7ms per call to ~260ms per call, turning a 1-second search into
a 70-second one. The root cause is Neovim's O(n) filename-to-buffer resolution
inside `setqflist()`, where n is the total number of buffers. Each search
creates thousands of unlisted buffers as a side effect, and these accumulate
across searches, making every subsequent call slower.

The proposed mitigation is a session-local filename-to-bufnr cache that resolves
each unique filename exactly once, combined with an optional unlisted-buffer
wipe between searches to prevent cumulative growth.

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

| Run | Items   | setqflist() total | Per call avg | Buffer count (approx) |
|-----|---------|-------------------|--------------|-----------------------|
| 1   | 100,000 | 814 ms            | 7 ms         | ~4,000                |
| 2   | 100,000 | 6,482 ms          | 34 ms        | ~8,000                |
| 3   | 100,000 | 7,842 ms          | 39 ms        | ~12,000               |
| 4   | 100,000 | 9,544 ms          | 34 ms        | ~16,000               |
| 5   | 100,000 | 12,730 ms         | 60 ms        | ~20,000               |
| 6   | 100,000 | 13,319 ms         | 61 ms        | ~20,000 (saturated)   |
| 7   | 100,000 | 13,868 ms         | 65 ms        | ~20,000 (saturated)   |
| 8   | 46,684  | 33,491 ms         | 241 ms       | ~30,000 (new pattern) |

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

## Proposed Solution

The mitigation has two independent parts that can be implemented separately.

### Part 1: Session-local filename-to-bufnr cache

**Goal:** Reduce the number of `buflist_findname_stat()` calls from
O(total_matches) to O(unique_files) per search.

**Mechanism:** Maintain a Lua hash table that maps filenames to buffer numbers,
populated lazily as results are parsed. Pass `bufnr` instead of `filename` to
`setqflist()`, bypassing Neovim's internal filename resolution entirely.

**Where to implement:** The cache lives on the `session` object (so it is
scoped to a single search and garbage-collected afterwards). The parse functions
(`_parse_vimgrep` and `_parse_line_number`) gain access to the cache and
resolve filenames before constructing the quickfix entry.

**Implementation sketch:**

```lua
-- In the session initialiser inside _exec():
local session = {
    -- ... existing fields ...
    bufnr_cache = {},  -- filename --> bufnr lookup cache
}
```

```lua
-- New helper function: resolve filename to buffer number, caching the result.
-- vim.fn.bufadd() creates the buffer if it doesn't exist, or returns the
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
-- In _parse_vimgrep (and similarly in _parse_line_number):
-- Before (current):
function M._parse_vimgrep(result)
    -- ... parsing logic ...
    return {
        filename = filename,
        lnum = tonumber(lnum),
        col = tonumber(col),
        text = text,
    }
end

-- After (proposed):
-- Note: the signature changes to accept the cache. The caller (_on_stdout)
-- passes session.bufnr_cache. This is a breaking change to the parse_line
-- function signature, which is selected dynamically in _exec().
function M._parse_vimgrep(result, bufnr_cache)
    -- ... parsing logic ...
    return {
        bufnr = M._resolve_bufnr(filename, bufnr_cache),
        lnum = tonumber(lnum),
        col = tonumber(col),
        text = text,
    }
end
```

```lua
-- In _on_stdout, the parse_line call becomes:
local entry = parse_line(line, session.bufnr_cache)
```

**Expected impact:** With 100,000 matches across ~4,000 unique files, this
reduces the number of buffer list lookups from 100,000 to 4,000 per search — a
25x reduction. Each individual `setqflist()` call receives items with `bufnr`
fields, which Neovim resolves in O(1) (direct array index into the buffer
table) rather than O(n) (linear scan by filename).

**Limitation:** `vim.fn.bufadd()` itself performs a buffer list lookup, so the
4,000 calls to `bufadd()` still pay the O(n) cost. However, 4,000 × n is
dramatically better than 100,000 × n. Additionally, if `bufadd()` is called
from Lua in the same main-loop tick as the `on_stdout` callback, it runs
synchronously and does not introduce scheduling overhead.

**Note on `bufadd()`:** This function is called from a `vim.schedule_wrap`
context (the `on_stdout` callback), which means it runs on the main loop and
can safely call Vimscript functions. It does **not** need to be wrapped in
`vim.schedule()` again.

### Part 2: Unlisted buffer cleanup between searches

**Goal:** Prevent cumulative buffer list growth across searches, so the tenth
search is as fast as the first.

**Mechanism:** Before starting a new search, iterate the buffer list and delete
unlisted buffers that are not visible in any window and are not modified.

**Where to implement:** Early in `_exec()`, after cancelling previous
scheduling but before initialising the new session.

**Implementation sketch:**

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

**Expected impact:** The buffer list is reset to approximately its pre-search
size before each new search, preventing the cumulative O(n) degradation. After
this cleanup, only user-opened buffers and actively displayed buffers remain.

**Risk:** This deletes **all** invisible unlisted buffers, not only those
created by `setqflist()`. Other plugins may create unlisted buffers for their
own purposes (e.g. nvim-bqf's preview buffer, LSP hover windows, or
telescope's result buffers). In practice, these plugins typically manage their
own buffer lifecycle (creating and deleting as needed), so the risk is low. If
conflicts arise, a more targeted approach would be to tag brook-created buffers
with a buffer-local variable and only delete those, but this adds complexity
for a problem that may never materialise.

**Performance of the cleanup itself:** Iterating 20,000 buffers and calling
`nvim_buf_delete()` on each takes measurable time. In testing, this should be
profiled to ensure it doesn't introduce its own latency. If it's too slow, it
could be deferred to a `vim.schedule()` callback or batched, though this would
complicate the control flow.

**Configuration:** This behaviour could be gated behind a config option (e.g.
`wipe_unlisted_buffers = true`) to allow users to disable it if it interferes
with their workflow. However, given that the default `max_results` is 1,000 and
the buffer accumulation is barely noticeable at that scale, it may be more
pragmatic to only perform the cleanup when `max_results` exceeds a threshold
(e.g. 5,000).

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
take a string and return a quickfix entry. Part 1 requires them to also accept
the bufnr cache, making them impure (they mutate the cache as a side effect
and call `vim.fn.bufadd()` which is a Vimscript function with its own side
effects).

An alternative design would be to keep the parse functions pure and perform the
bufnr resolution in `_on_stdout` after parsing:

```lua
local entry = parse_line(line)
if entry then
    -- Resolve filename --> bufnr before enqueueing
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

## References

Neovim source: `src/nvim/quickfix.c` (`qf_get_fnum()`),
`src/nvim/buffer.c` (`buflist_findname_stat()`).

Related Neovim API: `vim.fn.setqflist()`, `vim.fn.bufadd()`,
`vim.api.nvim_buf_delete()`, `vim.fn.getbufinfo()`.
