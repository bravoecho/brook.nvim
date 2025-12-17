# brook.nvim

> The ripgrep wrapper Neovim deserves: fast, shell-safe, and built for the
> quickfix workflow

**brook.nvim** is an asynchronous ripgrep wrapper for Neovim that prioritizes
performance and seamless navigation. It doesn't try to be a fuzzy finder; it's
a precision tool for code exploration and refactoring.

## Why Brook?

When it comes to code search, most Neovim users end up choosing between legacy
Vimscript plugins or modern fuzzy finders. **Brook** sits in the sweet spot for
power users:

* **Fast & Asynchronous**: Streams results to the quickfix list asynchronously.
  Even in massive monorepos, results appear instantly without ever locking your
  UI.

* **Shell-Agnostic & Safe**: Unlike other wrappers, Brook bypasses the shell
  entirely. Whether you use Bash, Zsh, or Fish, your patterns won't break due to
  shell escaping quirks.

* **Quickfix-Centric**: It embraces the built-in quickfix list for persistent
  results that integrate with native navigation and batch operations.

* **Native Search Integration**: Automatically translates your `rg` pattern to
  Vim regex and populates the search register. Use `n`/`N` to jump between
  matches within a buffer with full `hlsearch` support.

* **Zero Abstraction**: No new syntax to learn. If you know `ripgrep` flags, you
  already know how to use Brook.

* **Neovim-Native**: Built specifically for Neovim (0.7+) using Lua to leverage
  modern API capabilities like `jobstart()`.

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
  },
}
```

---

## Usage

### Workflow

Brook is designed for a "Search-Navigate-Edit" loop that stays out of your way
and feels like a natural extension of Vim:

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

   > *Pro Tip: Ensure `:cnext` and `:cprev` are mapped `]q` and `[q`, a widely
   > used convention for faster browsing.*

3. **Navigate**: Navigate matches inside each file using `n` and `N` (the search
   is already highlighted).

4. **Refactor**: Perform global search-and-replace across all found files using
   `:cfdo %s//replacement/gc`.

   > *(The empty `//` in the substitute command tells Vim to use the last search
   > pattern, which Brook has already set for you)*

### Tips & Tricks

* **Filter by File Type**: Leverage `ripgrep`'s built-in type filtering.

  - `:Rg -t lua my_config` (search only in Lua files)
  - `:Rg -T js bug_fix` (search everywhere *except* JavaScript files)

* **Literal Searches**: If your search term contains many special characters
  (like `($[0].item)`), use the `-F` (fixed strings) flag to treat the pattern
  literally:

  - `:Rg -F "($[0].item)"`

---

## Philosophy & Comparisons

Brook is inspired by existing search tools. Apart from being a fun and
satisfying project, Brook focuses on specific requirements.

### vs. vim-grepper

[vim-grepper](https://github.com/mhinz/vim-grepper) is a legendary Vim plugin
with a long-history, and it's _the_ top choice for classic Vim. Brook on the
other hand is built from the ground up for the Neovim stack:

* **Fish Shell Support**: By executing `rg` directly, Brook avoids some
  escaping issues `vim-grepper` faces with the Fish shell.

* **Lua-First**: Neovim has a superior asynchronous API, smoother and more
  ergonomic. It does all the heavy-lifting, Brook simply taps into that
  power.

* **Precise Search Sync**: While not perfect, Brook’s translation of patterns to
  the search register is a core feature. See the [rg-to-vim translation
  spec](./tests/rg_to_vim_pattern_spec.md) for more details on the choices made.

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

---

## Technical Notes

* **Job Pipeline**: Brook uses Neovim's `jobstart()` to spawn `ripgrep` as
  a separate process directly, without involving a shell. This is why it's safe
  from shell injection it works reliably across different environments.

* **Stdin Handling**: Disables `stdin` to prevent ripgrep from blocking.

* **Custom, POSIX-compliant unquoting logic**: This ensures that when you type
  `:Rg 'foo bar'`, the quotes are handled correctly before being passed directly
  to the `ripgrep` executable.

* **Resource Management**: To keep the UI responsive, Brook stops after
  a configurable `max_results` (default 1000).

* **Pattern Extraction**: Brook parses the `rg` CLI to distinguish flags from
  search patterns.

* **Regex Translation**: Patterns are translated to Vim’s "very magic" (`\v`)
  mode to ensure highlighting matches what `ripgrep` found.

* **Streaming Logic**: Results are processed line-by-line as they are emitted by
  `rg`. This prevents "UI lag" because the quickfix list is updated
  incrementally rather than waiting for the entire search to finish.

* **Lazy execution**: Argument parsing, pattern extraction and search register
  handling are performed only when and if at least one result is found.

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
    raw patterns,  |                                     |      stream...    |
 flags and options |                                     |                   |
                   v                                     v                   |
            Parse and Extract                      Quickfix List <-----------+
                   |
   ripgrep pattern |
     + options     |
                   v
               Translate
                   |
                   | vimgrep pattern (very magic)
                   v
           Set Search Register
```

## License

MIT
