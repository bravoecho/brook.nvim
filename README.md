# brook.nvim

> The ripgrep wrapper Neovim deserves: fast, shell-safe, and built for the
> quickfix workflow

**brook.nvim** is an asynchronous ripgrep wrapper for Neovim that prioritises
performance and seamless navigation. It doesn't try to be a fuzzy finder; it's
a precision tool for code exploration and refactoring, the Vim way.

## Why Brook?

When it comes to code search, and search-and-replace, most Neovim users end up
choosing between legacy Vimscript plugins or modern fuzzy finders. **Brook**
sits in the sweet spot for power users:

* **Fast & Asynchronous**: Ingests results as they arrive and updates quickfix
  incrementally using cooperative scheduling. Even in large monorepos, results
  appear as soon as ripgrep returns them, and then in incremental batches,
  minimising UI locking as much as possible.

* **Shell-Agnostic & Safe**: Unlike other wrappers, Brook bypasses the shell
  entirely. Whether you use Bash, Zsh, or the Fish shell, your patterns won't
  break due to shell escaping quirks. If it works with `rg`, it works with
  `:Rg`.

* **Quickfix-Centric**: It embraces the built-in quickfix list for persistent
  results that integrate with native navigation and batch operations.

* **Native Search Integration**: Finding text is only half the battle. Brook
  accurately translates ripgrep patterns to the search register. This turns
  search results into editable targets, enabling powerful automation. Explore
  the [pattern translation spec](./tests/pattern_spec.md) for more
  details.

  Search-and-replace is a native Neovim feature, use:

  ```vim
  :cfdo %s//replacement/gc
  ```

* **Complementing LSPs**: While LSPs handle symbol renaming, Brook handles
  everything else: refactoring string constants, CSS classes, or complex patterns
  across the entire project with regex precision.

* **Zero Abstraction**: No new syntax to learn. If you know `ripgrep` flags, you
  already know how to use Brook.

* **Neovim-Native**: Built specifically for Neovim (0.7+) using Lua to leverage
  modern API capabilities.

---

## Installation & Setup

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'bravoecho/brook.nvim',
  dependencies = {
    -- Result context and Preview
    -----------------------------
    -- Optional, highly recommended.
    -- See: https://github.com/kevinhwang91/nvim-bqf
    { 'kevinhwang91/nvim-bqf', optional = true },
  },

  -- Lazy-loading
  ---------------
  -- Lazy-load by setting cmd and keys.
  cmd = { 'Rg' },
  keys = {
    -- Same as 'keymap', to preserve lazy loading
    { '<leader>g', mode = 'n', desc = 'Grep (word under cursor)' },
    { '<leader>g', mode = 'x', desc = 'Grep (visual selection)' },
  },

  -- Default options
  ------------------
  opts = {
    -- Basics
    ---------
    keymap = '<leader>g', -- Same as 'keys', to preserve lazy loading.
    max_results = 1000, -- Valid values: 1-10,000.

    -- Performance & Responsiveness
    --------------------------------
    -- maximum number of results appended to quickfix per update
    -- (lower = smoother/more updates; higher = faster/fewer updates)
    max_batch_size = 100,

    -- tiny delay (ms) between quickfix updates, to allow UI redraws under fast output
    -- (lower = faster throughput; higher = smoother redraws)
    --
    -- NOTE: zero (meaning throttling is completely disabled) or very small
    -- values are not recommended. They can result in pauses and sudden jumps
    -- in the number of results. The right value depends on your preferences,
    -- workflow, and hardware.
    --
    -- For the best experience, experimenting with different values of
    -- max_batch_size and flush_throttle_ms is encouraged.
    flush_throttle_ms = 10,

    -- Quickfix window behaviour
    ----------------------------
    qf_open = true,         -- Auto-open the quickfix window when results are found
    qf_auto_resize = true,  -- Resize the quickfix window when more results arrive
    qf_win_height = 10,     -- Fixed or max height (depending on auto-resizing on/off)

    -- Results per line
    -------------------
    -- Output format: how ripgrep results are displayed in the quickfix list
    -- 'one-line-per-match' (default): each match appears separately, with column position
    -- 'unique-lines': each line appears only once (cursor lands at column 1)
    output_format = 'one-line-per-match',
  },
}
```

See the Technical Notes below for more details on batching.

> [!TIP]
> For consistent results, it's recommended to configure both ripgrep and Neovim
> with "smart case". Override with the `-s` and `-i` flags when needed.
>
> `init.lua`:
>
> ```lua
> vim.o.ignorecase = true
> vim.o.smartcase = true
> ```
>
> `~/.ripgreprc`:
>
> ```
> --smart-case
> ```

---

## Usage

### Workflow

Brook is designed for a "Search-Navigate-Edit" loop that feels like a natural
extension of Vim:

1. **Search**:

   - *Search for a word*: Press `<leader>g<CR>` (or your mapped key) to search
      for the word under the cursor.

   - *Visual selection*: Simply press `<leader>g`

   - *Manual Search*: Type `:Rg your_query` in the command line.

   - *Complex Queries*: Use quotes for spaces or add `ripgrep` flags directly:
      `:Rg --hidden "function handle_click"` (include hidden files).

2. **Explore**: Browse results with `:cnext`/`:cprev` or your favourite quickfix
   mappings. Benefit from quickfix plugins, like
   [nvim-bqf](https://github.com/kevinhwang91/nvim-bqf).

   > *Pro Tip: Ensure `:cnext` and `:cprev` are mapped to `]q` and `[q`,
   > a widely used convention for faster browsing.*

3. **Navigate**: Navigate matches inside each file using `n` and `N` (the search
   is already highlighted).

4. **Refactor**: Perform global search-and-replace across all found files using
   `:cfdo %s//replacement/gc`. Brook automatically populates Neovim's search
   register, so the empty `//` correctly targets exactly what ripgrep found: no
   double-typing complex regex.

### Tips & Tricks

* **Filter by File Type**: Leverage `ripgrep`'s built-in type filtering.

  - `:Rg -t lua my_config` (search only in Lua files)
  - `:Rg -T js bug_fix` (search everywhere *except* JavaScript files)

* **Literal Searches**: If your search term contains many special characters
  (like `($[0].item)`), use the `-F` (fixed strings) flag to treat the pattern
  literally:

  - `:Rg -F "($[0].item)"`

* **Case Sensitivity**: Control case matching with ripgrep's flags:

  - `:Rg -s MyClass` (case-sensitive: matches `MyClass` but not `myclass`)
  - `:Rg -i error` (case-insensitive: matches `error`, `ERROR`, `Error`)

  Brook translates these to Vim's `\C` and `\c` modifiers, so `n`/`N` navigation
  and highlighting respect your choice.

* **Stopping Long Searches**: If a search is taking too long or returning too
  many results, use `:RgStop` to terminate it immediately. The results collected
  so far remain in the quickfix list.

* **One Result Per Line**: By default, Brook shows one quickfix entry per match,
  meaning a line with multiple matches appears multiple times. If you prefer
  each line to appear only once (useful for `:cfdo` workflows where you visit
  each line anyway), set `output_format = 'unique-lines'` in your config. The
  trade-off is that the cursor will land at column 1 rather than at the exact
  match position. You can also override this per-search using the ripgrep flags
  `-n`/`--line-number` (for unique lines) or `--vimgrep` (for one line per
  match).

### Limitations

* **No multiline search**: Ripgrep by default does not allow multiline search,
  requiring to enable it explicitly. Brook does not support it either. When you
  search a multiline selection, or add flags like `-U`/`--multiline`, Brook will
  display a warning and abort. This is a deliberate limitation; ripgrep's
  `--vimgrep` output format and the quickfix list are designed around line-based
  results.

* **No multiple patterns**: When using multiple `-e` flags (e.g., `-e foo -e
  bar`), Brook only uses the first pattern for search register integration. The
  ripgrep search itself works correctly with all patterns, but only the first
  will be highlighted and available for `n`/`N` navigation. This avoids
  complexity for a seldom used ripgrep feature.

---

## Design Principles & Comparisons

Brook is inspired by existing search tools. Apart from being a fun and
satisfying project, Brook focuses on specific requirements.

### vs. vim-grepper

[vim-grepper](https://github.com/mhinz/vim-grepper) is a legendary Vim plugin
with a long history, and it's _the_ top choice for classic Vim. Brook on the
other hand is built from the ground up for the Neovim stack.

* **Fish Shell Support**: By executing `rg` directly, Brook avoids some
  escaping issues `vim-grepper` faces with the Fish shell.

* **Lua-First**: Brook leverages Neovim's elite async API to harness the speed
  of Ripgrep, enabling seamless, interactive text search and manipulation.

* **Stability**: Like vim-grepper, Brook aspires to achieving a state of
  "finished software": built on top of reliable API, following UNIX principles,
  unlikely to change.

### vs. Telescope / fzf-lua

Fuzzy finders excel at locating a single resource. Brook is built for **code
exploration across many files**.

* **Persistence**: The quickfix list stays open as you work while staying out of
  your way; fuzzy finders are usually transient because by default they obscure
  the rest of the UI.

* **Refactoring**: It is significantly easier to run `:cfdo` commands on
  quickfix results than on a fuzzy finder's buffer.

* **Memory/Performance**: Fuzzy finders often hold the entire result set in
  memory to allow for filtering. Brook streams directly to the quickfix, making
  it significantly lighter for massive searches (millions of lines) where you
  already know your query.

---

## Technical Notes

* **Job Pipeline**: Brook uses Neovim's `jobstart()` to spawn `ripgrep` as
  a separate process directly, without involving a shell. This is why it's safe
  from shell injection and it works reliably across different environments.

* **Stdin Handling**: Disables `stdin` to prevent ripgrep from blocking.

* **Custom, POSIX-compliant unquoting logic**: This ensures that when you type
  `:Rg 'foo bar'`, the quotes are handled correctly before being passed directly
  to the `ripgrep` executable.

* **Resource Management**: To keep the UI responsive, Brook stops after
  a configurable `max_results` (default 1000). The maximum accepted value is
  10,000, and the maximum recommended value is 5,000. Neovim's performance
  degrades rapidly when the number of items grows too much, memory usage grows
  unbounded and it doesn't get reclaimed promptly. Any workflow that involves
  that many entries is unlikely in an interactive editor, and probably best
  suited for different tools.

* **Long Line Protection**: Minified JavaScript, large JSON blobs, and other
  abnormally long lines can cause memory issues: a single line with many matches
  could generate gigabytes of output. Brook uses `--max-columns 300` with
  `--max-columns-preview` to truncate the *preview* shown in the quickfix list
  while still matching the full line content. You can also choose to output each
  line only once, to mitigate this issue (use the `-n`/`--line-number` flag, or
  see config).

* **Pattern Extraction**: Brook parses the `rg` CLI to distinguish flags from
  search patterns.

* **Regex Translation**: Patterns are translated to Vim's "very magic" (`\v`)
  mode to ensure highlighting matches what `ripgrep` found. The pattern-related
  ripgrep flags are translated to the corresponding modifiers. For example,
  case sensitivity flags (`-s`, `-i`) are translated to `\C` and `\c` modifiers
  respectively. See also [pattern translation spec](./tests/pattern_spec.md).

* **Streaming Logic**: Results are processed line-by-line as they are emitted by
  `rg`. This prevents "UI lag" because the quickfix list is updated
  incrementally rather than waiting for the entire search to finish.

* **Batching**: The `max_batch_size` option controls how frequently Brook
  updates the quickfix list. More frequent updates would feel more responsive,
  but each UI update is expensive and slows down the search. Also, results
  beyond the quickfix window height are below the fold, and would not benefit
  from immediate flushing. After the initial results, batching kicks in, and
  results are then flushed only after `max_batch_size` entries. Internally, the
  same value is also used as the queue threshold for requesting an update.

* **Throttling**: Under extremely fast output scenarios, redraw starvation can
  still happen even if flushing is batched. For this reason a tiny delay is
  introduced after each flush (in the second phase of the search, after the
  visible quickfix window is filled). You are encouraged to experiment with
  different values of `flush_throttle_ms` depending on preference and hardware.
  Can be disabled completely by setting `flush_throttle_ms` to 0 (not
  recommended).

* **Lazy execution**: Pattern translation and search register handling are
  performed only when-and-if at least one result is found.

Below is a representation of the processing pipeline:

```
                                Neovim Command
                                      |
                                      |  args string
                                      v
                                   Tokenise
                                      |
                                      |  user-quoted tokens
                                      v
                          POSIX Shell-Unquote (custom)
                                      |
                                      | unquoted user tokens
                                      |
                                Expand Tokens
                                      |
                                      | raw patterns, flags and options
                                      |
                                      v
                               Parse and Extract
                                      |
                                      | ripgrep pattern + options
                                      |
                   +------------------+------------------+
                   |                                     |
                   |                                     v
                   |                          Spawn ripgrep (no shell) ------+
                   |                                     |                   |
                   v                                     v                   v
               Translate <------------------------- First results       More results...
                    |         ✓ pattern is valid         |                   |
    vimgrep pattern |                                    |     buffer...     |
     (very magic)   |                                    |                   |
                    v                                    v                   |
            Set Search Register                  Buffered Flush <------------+
                                                         |
                                                         v
                                                  Quickfix List
```

## License

MIT
