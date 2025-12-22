# brook.nvim

> The ripgrep wrapper Neovim deserves: fast, shell-safe, and built for the
> quickfix workflow

**brook.nvim** is an asynchronous ripgrep wrapper for Neovim that prioritizes
performance and seamless navigation. It doesn't try to be a fuzzy finder; it's
a precision tool for code exploration and refactoring, the Vim way.

## Why Brook?

When it comes to code search, most Neovim users end up choosing between legacy
Vimscript plugins or modern fuzzy finders. **Brook** sits in the sweet spot for
power users:

* **Fast & Asynchronous**: Streams results to the quickfix list asynchronously.
  Even in massive monorepos, results appear as soon as ripgrep returns them,
  without ever locking your UI.

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
  -- Lazy-load by setting cmd and keys.
  cmd = { 'Rg' },
  keys = {
    { '<leader>g', mode = 'n', desc = 'Grep (word under cursor)' },
    { '<leader>g', mode = 'x', desc = 'Grep (visual selection)' },
  },
  -- Default options:
  opts = {
    keymap = '<leader>g',
    max_results = 1000, -- Set to false for unlimited

    -- Buffering and debouncing: adjust to balance performance and responsiveness.
    buffer_size = 100,  -- Results to accumulate before flushing to quickfix
    debounce = 80,      -- Max wait (ms) before flushing buffered results

    -- Quickfix list management
    qf_open = true,         -- Auto-open the quickfix window when results are found
    qf_auto_resize = true,  -- Resize the quickfix window when more results arrive
    qf_win_height = 10,     -- Fixed or max height (depending on auto-resizing on/off)
  },
}
```

See the Technical Notes below for more details on buffering and debouncing.

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
   [nvim-bqf](https://github.com/kevinhwang91/nvim-bqf), which I recommend.

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

## Philosophy & Comparisons

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
  a configurable `max_results` (default 1000).

* **Pattern Extraction**: Brook parses the `rg` CLI to distinguish flags from
  search patterns.

* **Regex Translation**: Patterns are translated to Vim's "very magic" (`\v`)
  mode to ensure highlighting matches what `ripgrep` found. Case sensitivity
  flags (`-s`, `-i`) are translated to `\C` and `\c` modifiers respectively.

* **Streaming Logic**: Results are processed line-by-line as they are emitted by
  `rg`. This prevents "UI lag" because the quickfix list is updated
  incrementally rather than waiting for the entire search to finish.

* **Buffering and Debouncing**: The `buffer_size` and `debounce` options
  optimize Brook’s streaming from ripgrep. Because ripgrep flushes results to
  stdout very frequently, Brook accumulates them in a buffer instead of updating
  the quickfix list for every single stdout output event. It then flushes either
  when the buffer reaches `buffer_size` entries, or after `debounce` milliseconds
  of inactivity, whichever comes first. This debouncing strikes a balance
  between responsiveness and efficiency.

* **Lazy execution**: Argument parsing, pattern translation and search register
  handling are performed only when-and-if at least one result is found.

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
                   +------------------+------------------+
                   |                                     |
                   |                                     v
                   |                          Spawn ripgrep (no shell) ------+
                   |                                     |                   |
                   v                                     v                   v
             Expand Tokens <----------------------- First results       More results...
                   |          ✓ pattern is valid         |                   |
    raw patterns,  |                                     |     buffer...     |
 flags and options |                                     |                   |
                   v                                     v                   |
            Parse and Extract                    Buffered Flush <------------+
                   |                                     |
   ripgrep pattern |                                     v
     + options     |                              Quickfix List
                   v
               Translate
                   |
   vimgrep pattern |
    (very magic)   |
                   v
           Set Search Register
```

## License

MIT
