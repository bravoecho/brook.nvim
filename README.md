# brook.nvim

> The ripgrep wrapper Neovim deserves: fast, shell-safe, and built for the
> quickfix workflow

**brook.nvim** is an asynchronous ripgrep wrapper for Neovim that prioritises
performance and native navigation. It's not a fuzzy finder – it's a precision
tool for code exploration and refactoring, the Vim way.

## Why Brook?

Most Neovim users choose between legacy Vimscript plugins or modern fuzzy
finders. Brook sits in the sweet spot for power users:

* **Fast & Asynchronous**: Results stream to the quickfix list as ripgrep emits
  them, with cooperative scheduling to keep the UI responsive even in large
  monorepos.

* **Shell-Agnostic & Safe**: Brook bypasses the shell entirely, so it won't
  break due to escaping quirks. If it works with `rg`, it works with `:Rg`.

* **Quickfix-Centric**: Embraces the built-in quickfix list for persistent
  results that integrate with native navigation and batch operations.

* **Native Search Integration**: Brook translates ripgrep patterns to Vim's
  search register, enabling highlighting and `n`/`N` navigation. Combined with
  `:cfdo %s//replacement/gc`, this makes search-and-replace seamless.

* **LSP Complement**: LSPs handle symbol renaming; Brook handles everything
  else – string constants, CSS classes, complex patterns across the entire
  project with regex precision.

* **Zero Abstraction**: No new syntax. If you know ripgrep, you know Brook.

* **Neovim-Native**: Built for Neovim 0.7+ in Lua.

---

## Installation & Setup

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'bravoecho/brook.nvim',
  dependencies = {
    -- Optional, highly recommended for result context and preview.
    -- See: https://github.com/kevinhwang91/nvim-bqf
    { 'kevinhwang91/nvim-bqf', optional = true },
  },

  -- Lazy loading
  cmd = { 'Rg', 'RgStop' },
  keys = {
    { '<leader>g', mode = 'n', desc = 'Search for current word with ripgrep' },
    { '<leader>g', mode = 'x', desc = 'Search for visual selection with ripgrep' },
    { '<leader>/', mode = 'n', desc = 'Open ripgrep prompt' },
    { '<leader>G', mode = 'n', desc = 'Stop ripgrep search' },
  },

  -- Defaults (you only need to specify the fields you want to customise)
  opts = {
    -- Keymaps (set to false to disable)
    keymap_cword = '<leader>g',
    keymap_visual = '<leader>g',
    keymap_prompt = '<leader>/',
    keymap_stop = '<leader>G',

    -- Result limits
    max_results = 1000, -- 1-10,000
    max_preview_chars = 200, -- 100-500

    -- Performance tuning
    max_batch_size = 100,    -- results per quickfix update
    flush_throttle_ms = 10,  -- delay between updates (0 to disable)

    -- Quickfix window
    qf_open = true,
    qf_auto_resize = true,
    qf_win_height = 10,

    -- 'one-line-per-match' (default) or 'unique-lines'
    output_format = 'one-line-per-match',

    -- Populate search register for n/N navigation and :cfdo substitutions
    set_search_register = true,
  },
}
```

> [!TIP]
> For consistent results, configure both ripgrep and Neovim with smart case.
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

Brook is designed for a "Search-Navigate-Edit" loop:

1. **Search**:
   - `<leader>g` in normal mode – word under cursor
   - `<leader>g` in visual mode – selection
   - `<leader>/` in normal mode – open prompt for manual search
   - `<leader>G` in normal mode – stop current search if any
   - `:Rg your_query` – manual search
   - `:Rg --hidden "function handle_click"` – with ripgrep flags

2. **Explore**: Browse with `:cnext`/`:cprev` (map these to `]q`/`[q`).

3. **Navigate**: Use `n`/`N` to jump between matches within each file.

4. **Refactor**: Search and replace with `:cfdo %s//replacement/gc` – the search
   register is already populated, so empty `//` targets exactly what ripgrep
   found.

### Tips

* **Filter by type**: `:Rg -t lua config` or `:Rg -T js bug`
* **Literal search**: `:Rg -F "($[0].item)"` for special characters
* **Case control**: `:Rg -s MyClass` (sensitive) or `:Rg -i error` (insensitive)
* **Stop early**: `<leader>G` or `:RgStop` – results so far remain in quickfix
* **Unique lines**: Set `output_format = 'unique-lines'` or use `-n` flag
* **Search path**: Press `<Tab>` in the command to autocomplete relative paths

### Limitations

* **No multiline search**: Brook aborts with a warning if you use `-U` or search
  a multiline selection. The quickfix format is inherently line-based.

* **No PCRE2**: only ripgrep's default regexp engine is supported. Commands
  setting it to PCRE2 will result in an error. This guarantees predictable
  performance and more accurate search pattern translation.

* **Multiple patterns**: With multiple `-e` flags, only the first pattern is
  used for highlighting and `n`/`N` navigation. The ripgrep search itself works
  correctly with all patterns.

---

## Comparisons

### vs. vim-grepper

[vim-grepper](https://github.com/mhinz/vim-grepper) is the classic choice for
Vim. Brook is built from the ground up for Neovim:

* **Shell independence**: Direct `rg` execution avoids escaping issues with Fish
  and other non-POSIX shells.
* **Lua-native**: Leverages Neovim's async API for responsive streaming.
* **Stability**: Like vim-grepper, provides focused features and is built on
  stable APIs.

### vs. Telescope / fzf-lua

Fuzzy finders excel at locating a single resource. Brook is built for code
exploration across many files:

* **Persistence**: The quickfix list stays open while you work; fuzzy finders
  are transient by design.
* **Refactoring**: `:cfdo` commands work naturally on quickfix results.
* **Scale**: Brook streams directly to quickfix without holding results in
  memory – tested on codebases exceeding 4 million lines.

---

## Technical Notes

* **Direct Execution**: Spawns `rg` via `jobstart()` without a shell – safe from
  injection, works everywhere.
* **Stdin Disabled**: Prevents ripgrep from blocking on empty input.
* **POSIX Unquoting**: Custom parser handles quoted arguments before passing to
  ripgrep.
* **Result Limiting**: Caps at `max_results` (default 1000, max 10K) – Neovim's
  quickfix degrades badly beyond this.
* **Long Line Protection**: Uses `--max-columns 300` to prevent memory issues
  from minified files.
* **Pattern Extraction**: Parses the CLI to separate flags from search patterns.
* **Regex Translation**: Converts patterns to Vim's "very magic" mode;
  translates case flags (`-s`/`-i`) to `\C`/`\c`. See [pattern translation
  spec](./tests/pattern_spec.md).
* **Streaming**: Results flow to quickfix as ripgrep emits them.
* **Three-Phase Batching**: (1) Fill visible window fast, (2) throttled batches
  during search, (3) rapid drain after exit.
* **Lazy Translation**: Pattern translation only happens if results are found.

```
   Command --> Tokenise --> Unquote --> Parse --> Spawn rg
                                                     |
                                    +----------------+
                                    |
                                    v
                              Stream results
                                    |
                      +-------------+-------------+
                      |                           |
                      v                           v
              Translate pattern             Batch & flush
                      |                           |
                      v                           v
               Search register                 Quickfix
```

## License

MIT
