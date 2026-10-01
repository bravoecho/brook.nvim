# Search isolation with a `vim.async` consumer

## Status

Proposed. Not yet implemented.

Requires Neovim 0.13. Support for Neovim 0.12 and earlier is dropped.

## Summary

Starting a search while another is streaming leaks the old search into the new one. The old search keeps writing into the new search's quickfix list, and its SIGTERM exit is reported as an error.

The cause is scheduling state shared at module level in `lua/brook/rg/exec.lua`: `active_rg_job_id`, `flush_timer` and `flush_scheduled`. Callbacks belonging to a replaced search act on whatever search is current.

The fix rewrites the consumer as one `vim.async` task per search. Replacing a search closes its task, which stops its rg process, cancels its pending flush, and turns its late callbacks into no-ops.

Two related defects are fixed alongside: appends going to whichever quickfix list is current, and a failed command discarding the running search's cancel function.

---

## Observed behaviour

### Live reproduction

Corpus: 300 files, each with 200 lines containing `alpha` and one line containing `beta`. Search A (`alpha`, `max_results = 50000`) starts; search B (`beta`) starts as soon as A has painted 10 entries.

Result, identical on Neovim 0.12.5 and 0.13 nightly:

```
setqflist rg alpha create    items=10
setqflist rg beta  create    items=1
setqflist rg beta  append    items=299
setqflist rg alpha append    items=674     <- A still writing after B started
notify: rg: exited with code 143           <- A's SIGTERM reported as ERROR
current list title="rg beta"  beta(want 300)=300  alpha(want 0)=174
```

The leak is timing-dependent: 3 of 4 runs leaked 174 entries. The 143 error appeared in every run.

### Deterministic reproduction

Stubbing `vim.fn.jobstart` and `vim.fn.jobstop` lets a test fire each job's `on_stdout`/`on_exit` callbacks in a fixed order. The leaking order is:

1. A receives 5000 lines; first paint completes and streaming starts.
2. B starts.
3. B receives 3 lines and creates its list.
4. A's `on_exit` arrives with code 143.
5. B's `on_exit` arrives with code 0.

With `flush_throttle_ms = 10` (the default), the current list ends up titled `rg alpha` and holds 3500 to 4000 `alpha` entries next to B's 3 entries. With `flush_throttle_ms = 0`, A drains before B starts, so no entries leak; the `exited with code 143` error still appears.

---

## Root cause

### Shared scheduling state

Each step below follows from the current code.

1. B's `M._exec` calls `vim.fn.jobstop` on A's job, which sends SIGTERM (exit code 143).
2. A's `on_exit` callback still runs. It calls `M._start_draining` with A's session.
3. `M._start_draining` calls `M._cancel_flush_scheduling()`, which stops B's timer, since `flush_timer` is shared.
4. `M._flush_streaming(A)` calls `setqflist({}, 'a', …)`, which appends to the current list. The current list is B's.
5. A stores its next timer in `flush_timer`. B's `M._schedule_flush` sees a timer and returns, so the two searches take turns on one timer.
6. A reaches `M._notify_completion` with exit code 143 and `stopped_by_user = false`, which reports an error.

`M._on_stdout` guards on `active_rg_job_id`, which by then holds B's job id. A's already-queued stdout callbacks pass the guard and push into A's queue.

In schedule mode (`flush_throttle_ms = 0`), `vim.schedule` returns no handle. A closure queued by a replaced search cannot be cancelled, and runs with the old session.

### Appends target the current list

`setqflist({}, 'a', …)` appends to whichever list is current. Any other command that creates or selects a quickfix list during streaming (`:vimgrep`, `:make`, `:colder`, an LSP "references" call) receives brook's remaining results.

### `cancel_fn` is overwritten on validation failures

This one comes from reading the code and has not been reproduced. In `lua/brook/init.lua`, every search entry point assigns `cancel_fn = rg.raw(…)` (or `rg.word`, `rg.selection`, `rg.repeat_last`).

`rg.raw` returns `nil` without starting a search when the command is malformed, uses `-U` or `-P`, or has no arguments. A search that is still running loses its cancel function: `:RgStop` does nothing, and the stop keymap reports "rg: no search in progress".

---

## Relevant `vim.async` behaviour

These were verified on nightly `v0.13.0-dev-1761+gd5e7c7e55c`:

- Calling a callback captured by `async.await(function(cb) … end)` resumes the task synchronously, inside the caller. The producer's push can still trigger the first paint before control returns to the event loop.
- `task:close()` closes the task's children and the closable it is suspended on (timer, or a `{ close = fn }` table). Calling a captured callback after close is a no-op, and the task body does not resume.
- An error in a top-level task that nobody observes is discarded: no message, empty `v:errmsg`. `:raise_on_error()` reports it as a `vim.schedule callback` error, matching today's behaviour for errors in scheduled flushes.
- Closing a child task delivers `"closed"` to `pawait(child)` as a failure.
- 20,000 `async.await(1, vim.schedule)` hops took 39.4 ms; a plain `vim.schedule` chain took 6.5 ms. The difference is 1.6 µs per batch.

Re-check these against the 0.13 release before implementing. The API was taken from a nightly build.

---

## Implementation plan

### 1. Raise the minimum version

- `README.md`: change the requirement to Neovim 0.13.0.
- `CLAUDE.md`: change the stated requirement.
- `.github/workflows/test.yml`: check which Neovim version the `alpine:3.21` `neovim` package provides; switch to an image or install step that provides 0.13.
- `selene.toml`: check that the `neovim` standard library declares `vim.async`; extend it if not.

### 2. Write the regression tests first

Add `tests/rg/exec_session_test.lua` and register it in `bin/test` with `run_test 'rg/exec_session'`. The name avoids `tests/rg/exec_test.lua`, which `docs/plans/context_lines.md` reserves for parser tests.

The file stubs `vim.fn.jobstart` (records each job's `opts` and returns increasing fake ids), `vim.fn.jobstop` (records ids), and `vim.notify` (records messages and levels). CI needs no ripgrep.

Callbacks are fired by hand. Waits use `vim.wait` with predicates (for example "current list has 10 items"), avoiding fixed sleeps.

Cases, named with `want`/`got`:

1. Replaced search, timer mode, using the five-step order from "Deterministic reproduction": the current list has title `rg beta` and only `beta` items.
2. Replaced search, both throttle modes: A's late `on_exit(143)` produces no notification.
3. Replaced search: A's late `on_stdout` produces no quickfix write.
4. User stop: `cancel_fn()` mid-stream, then `on_exit(143)`; queued items still drain and the notification is `rg: stopped manually` at WARN.
5. Limit reached: `on_stdout` beyond `max_results`; `jobstop` is called with the session's own id and the notification is `rg: stopped at limit (…)`.
6. Foreign list mid-stream: the test calls `setqflist({}, ' ', { title = 'other' })` during streaming; brook's remaining items go to brook's list and the `other` list stays empty.
7. Evicted list: the test creates 10 lists mid-stream; brook stops writing, `jobstop` is called, and no notification is shown.
8. Validation failure keeps `cancel_fn`: after `setup()`, run `:Rg alpha`, then `:Rg 'unterminated`, then `:RgStop`; `jobstop` receives the first job's id.
9. jobstart failure: the stub returns 0; the notification is `rg: failed to start: is ripgrep installed?` and the search task completes.

Run the file against `main` before changing `exec.lua`. A prototype confirmed that cases 1 and 2 fail there; from reading the code, cases 3, 6, 7 and 8 fail too.

Cases 4 and 5 pass on `main` and pin down behaviour the rewrite keeps.

Commit the tests together with steps 3 to 5, so that CI never runs failing tests.

### 3. Rewrite the consumer as a task per search

Each search is one top-level task, named `brook.search`, with `:raise_on_error()`. It owns one child task, `brook.rg`, which waits for the rg process to exit.

```lua
local async = vim.async

function M._exec(ctx)
  last_search_context = ctx
  if active_task then
    active_task:close() -- closes brook.rg (jobstop) and any pending pause or wake
  end

  local session = M._new_session(ctx)
  active_task = async.run('brook.search', function()
    async.run('brook.rg', M._run_rg, ctx, session)

    while not (session.exit_code and session.queue.is_empty()) do
      if session.queue.is_empty() then
        async.await(function(cb) session.wake = cb end)
        session.wake = nil
      else
        local items = M._parse_batch(M._batch_size(ctx, session), session)
        if not M._update_quickfix(items, ctx, session) then
          M._stop_job(session)
          return -- list evicted, see step 4
        end
        if not M._first_paint_pending(ctx, session) then
          M._pause(session)
        end
      end
    end

    M._notify_completion(ctx, session)
  end):raise_on_error()

  return M._user_cancel_function(session)
end
```

`M._run_rg` wraps `jobstart` in an `await` whose closable stops the job:

```lua
--- @async
function M._run_rg(ctx, session)
  async.await(function(done)
    local job_id = vim.fn.jobstart(M._build_rg_cmd(ctx), {
      stdin = 'null',
      stderr_buffered = true,
      on_stdout = vim.schedule_wrap(function(_, data) M._on_stdout(data, ctx, session) end),
      on_stderr = function(_, data) M._on_stderr(data, session) end,
      on_exit = vim.schedule_wrap(function(_, code)
        session.exit_code = code
        done()
        M._wake(session)
      end),
    })
    session.job_id = job_id
    return {
      close = function(_, cb)
        vim.fn.jobstop(job_id)
        session.job_id = nil
        if cb then cb() end
      end,
    }
  end)
end
```

`on_exit` resumes the child (`done()`) and then the parent (`M._wake`) from plain callback context, so no coroutine resumes another. After `task:close()`, both calls are no-ops.

A `jobstart` failure (id ≤ 0) notifies, sets `session.exit_code`, and calls `done()` immediately. The parent loop then exits without flushing.

Helpers:

- `M._wake(session)`: calls `session.wake` when set.
- `M._stop_job(session)`: `jobstop(session.job_id)` and clears `session.job_id`, when set. Used by user stops, the result limit, and list eviction.
- `M._batch_size(ctx, session)`: remaining visible slots during first paint; `drain_phase_max_batch_size` once `session.exit_code` is set; `max_batch_size` (with jitter) otherwise.
- `M._pause(session)`: `async.sleep(ms)` when the current throttle is positive, `async.await(1, vim.schedule)` when it is 0. The throttle is `drain_phase_flush_throttle_ms` once `session.exit_code` is set.
- `M._first_paint_pending(ctx, session)`: `ctx.cfg.qf_open` and remaining visible slots above 0.

`M._on_stdout` keeps its current stitching and enqueueing.

Its guard changes from `active_rg_job_id` to `session.job_id`, and it calls `M._wake(session)` in place of `M._request_flush`. The limit branch calls `M._stop_job(session)`.

### 4. Cancellation

- Replaced by a new search: `active_task:close()`. The rg child's closable stops the job, the pending pause or wake is closed, and `M._notify_completion` is never reached.
- Stopped by the user: `M._user_cancel_function(session)` sets `session.stopped_by_user` and calls `M._stop_job(session)`. rg exits, `on_exit` completes the child normally, and the loop drains the queue and notifies.
- Limit reached: `M._on_stdout` sets `session.stopped_at_limit` and calls `M._stop_job(session)`; the rest follows the user-stop path.
- List evicted: see step 5.

User stops call `jobstop` directly. Closing the `brook.rg` child would deliver `"closed"` as a child failure, which the parent would have to tell apart from a real failure.

Once `M._stop_job` has cleared `session.job_id`, `M._on_stdout` drops further output. This keeps today's behaviour, where output arriving after a stop is discarded.

### 5. Append to the search's own list by id

In `M._update_quickfix`, after the `create` call, store `session.qf_id = vim.fn.getqflist({ id = 0 }).id`. Every `append` call passes `id = session.qf_id` in the `what` table.

Verified on 0.12.5 and nightly: an append with `id` set adds to that list while another list is current. Once the list has been pushed out of the 10-list history, `setqflist()` returns -1 and writes nothing.

`M._update_quickfix` returns `false` when `setqflist()` returns -1, and `true` otherwise. The task loop then stops the job and returns without notifying; the task completes once rg exits.

The resize logic (`getqflist({ winid = 0 })`) and `copen` operate on the current list and need no change.

### 6. Keep `cancel_fn` when a command fails validation

In `lua/brook/init.lua`, change each assignment to keep the previous value when the call returns `nil`:

```lua
cancel_fn = rg.raw(raw_opts, exec_cfg) or cancel_fn
```

This applies to the six call sites: `:Rg` (word and raw branches), `:RgRepeat`, and the cword, visual and repeat keymaps.

### 7. Remove the old scheduling code

- Module state: `flush_timer`, `flush_scheduled`, `active_rg_job_id`. `active_task` and `last_search_context` remain.
- Functions: `M._request_flush`, `M._schedule_flush`, `M._start_streaming`, `M._cancel_flush_scheduling`, `M._start_draining`, `M._flush_first_paint`, `M._flush_streaming`.
- `M._on_exit`: its work moves into the `on_exit` callback in `M._run_rg` and the task loop.
- The module header comment: describe the task loop in place of the state transitions.

The `state` enum stays only if benchmark accounting needs it; otherwise the bench counters derive the phase from `M._first_paint_pending` and `session.exit_code`.

`M._update_quickfix` (apart from step 5), `M._parse_batch`, the parsers, `M._on_stderr` and `M._notify_completion` stay as they are.

`docs/quickfix_optimisations.md` describes the three-phase consumer. Update the parts that refer to the removed functions or the shared timer.

---

## Behavioural differences

- Draining starts after the current pause completes, at most `flush_throttle_ms` (default 10 ms) after rg exits. Today `on_exit` cancels the timer and flushes immediately.
- Each batch costs 1.6 µs more in scheduling.
- A replaced search shows no notification. Today it shows `rg: exited with code 143` at ERROR.

---

## Verification

1. `./bin/test` passes on Neovim 0.13, locally and in CI.
2. Add one case to the test file: after a replacing `M._exec`, the previous task reports `completed()` once its stub `on_exit` has fired. This needs `active_task` exposed through a test-only accessor, following the existing `M.last_search_context()` pattern.
3. The live reproduction from "Observed behaviour", run five times, shows `alpha(want 0)=0` and no `exited with code 143` notification.
4. Manually, in a large repository: `:Rg <common word>`, then `:Rg <other word>` while the first is streaming. The quickfix list shows only the second search's results.
5. Manually: `:RgStop` mid-stream still shows the results received so far and the "stopped manually" notice.
6. Manually: `:Rg <common word>`, then `:vimgrep /x/ %` while it streams. brook's list still receives the remaining results, and the `:vimgrep` list does not.
7. `_benchmark = true` on a large search before and after the change: wall time and `setqflist()` cumulative time within run-to-run noise.

---

## Out of scope

- Migrating from `vim.fn.jobstart` to `vim.system`: independent of this change.
- Replacing the `cancel_fn` closures returned by `brook.rg` with a module-level `cancel()` on `brook.rg.exec`.
- The stop keymap staying silent when `cancel_fn` belongs to a finished search.

<!-- vim: set tw=0 ft=markdown: -->
