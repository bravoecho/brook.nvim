# brook.nvim

**brook.nvim** brings seamless ripgrep search to Neovim. It's a precision tool
for code exploration and refactoring.

Brook integrates ripgrep directly with Neovim's quickfix list and search
register, producing persistent results that compose with native commands rather
than replacing them.

While Neovim uses ripgrep by default under the hood via `grepprg`, Brook offers
better ergonomics and deeper integration with Neovim's search features.

---

## Design and UX principles

Brook is a Neovim-native search-and-replace tool for users who already know
Vim and ripgrep, and want those tools to work together at scale.

Brook is built around Neovim's existing primitives – the quickfix list and the
search register – and avoids introducing new modes, buffers, or workflows.

The goal is composability. Results are persistent and immediately available to
native commands and other plugins. Once a search completes, Brook steps aside:
navigation, editing, and transformation are handled by Vim itself.

This design targets systematic exploration and transformation of codebases:
ordered navigation, reusable result sets, and batch operations across files.

---

## Core properties

**Quickfix-centric** – Results are streamed into the quickfix list, where they
remain available for navigation, batch operations, and reuse. The quickfix
list has persisted for decades because it solves a simple problem well: given a
list of locations, navigate and act on them.

> [!TIP]
> [Learn more about the quickfix list](/docs/quickfix_primer.md)

**Native search integration** – Ripgrep patterns are translated into Neovim's
search register, enabling highlighting and `n` / `N` navigation within buffers,
as well as project-wide replacement with `:cfdo %s//replacement/`, without
repeating the pattern.

**Transparency** – Brook adds no abstraction layer over ripgrep. The command you
type is the command that runs; flags behave exactly as documented.

**Safe and shell-agnostic** – Argument handling is independent of the user's
shell, immune to injection, and unaffected by escaping quirks. If a command
works with `rg`, it works with Brook.

**Fast and responsive** – Results are streamed using carefully tuned cooperative
scheduling, keeping the UI responsive even for extremely large searches.

**Understated, refined UX** – Operates quietly and discreetly, with a small
number of direct, intuitive keymaps. Brook respects the user's workflow,
produces helpful warnings and errors, and integrates cleanly with search and
command history.

**Minimal footprint** – Brook is small with no dependencies and no required
configuration.

---

## Installation & Setup

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'bravoecho/brook.nvim',
  dependencies = {
    -- Recommended for context preview and result filtering.
    -- See: https://github.com/kevinhwang91/nvim-bqf
    { 'kevinhwang91/nvim-bqf', optional = true },
  },

  -- Lazy loading
  cmd = {
    'Rg',
    'RgStop',
    'RgRepeat',
  },
  keys = {
    { '<leader>g', mode = 'n', desc = 'Search for current word with ripgrep' },
    { '<leader>g', mode = 'x', desc = 'Search for visual selection with ripgrep' },
    { '<leader>/', mode = 'n', desc = 'Open ripgrep prompt' },
    { '<leader>G', mode = 'n', desc = 'Stop ripgrep search' },
    { '<leader>r', mode = 'n', desc = 'Repeat last ripgrep search' },
  },

  -- Defaults: only specify the fields you want to customise; if you are happy
  -- with the defaults, you only need to set `opts = {}`
  opts = {
    -- Keymaps (set to false to disable)
    keymap_cword  = '<leader>g',
    keymap_visual = '<leader>g',
    keymap_prompt = '<leader>/',
    keymap_stop   = '<leader>G',
    keymap_repeat = '<leader>r',

    -- Result limits
    max_results       = 1000, -- 500-100,000
    max_preview_chars = 200,  -- 100-500

    -- Performance tuning
    max_batch_size    = 100, -- results per quickfix update, 10-200
    flush_throttle_ms = 10,  -- delay between updates (0 to disable)

    -- Quickfix window
    qf_open        = true,
    qf_auto_resize = true,
    qf_win_height  = 10,

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

Brook is designed for a simple "Search-Navigate-Edit" loop powered by the
quickfix list.

1. **Search** – Brook provides a small set of direct entry points into ripgrep
   searches:
   - `<leader>g` – search word under cursor (normal mode) or selection (visual mode)
   - `<leader>/` – open prompt for manual search
   - `<leader>G` – stop current search if any
   - `<leader>r` – repeat last search
   - `:Rg your_query` – manual search
   - `:Rg --hidden "function handle_click"` – with ripgrep flags
   - `:RgStop` – stop current search if any
   - `:RgRepeat` – repeat last search

2. **Explore** – Browse with `:cnext`/`:cprev` (map these to `]q`/`[q`).

3. **Navigate** – Use `n`/`N` to jump between matches within each file.

4. **Refactor** – Search and replace with `:cfdo %s//replacement/gc`: the search
   register is already populated, so empty `//` targets exactly what ripgrep
   found.

### Pro Tips

* **Filter by file type** – `:Rg -t lua config` or `:Rg -T js bug`
* **Literal search** – `:Rg -F "($[0].item)"` for special characters
* **Multiple patterns** – `:Rg -e TODO -e FIXME` searches and navigates both, and
  combines with other flags like `-w` (whole-word) and `-F` (literal)
* **Case control** – `:Rg -s MyClass` (sensitive) or `:Rg -i error` (insensitive)
* **Unique lines** – Use the `-n` flag to enable it for a single search
* **Search path** – Press `<Tab>` in the command to autocomplete relative paths
* **Report each file only once** – `:Rg mypattern -n -m1`
* **Open all files with matches** – `:cfdo edit`
* **Search only the current file** – `:Rg mypattern %`
* **Stop early** – `<leader>G` or `:RgStop`, results so far remain in quickfix
* **Recall previous searches**: Word and selection searches are added to command
  history, so you can press `:` then arrow-up (or `q:`) to recall, edit, and
  re-run them
* **Customise ripgrep** – Add default options to `~/.ripgreprc` and specify
  which paths to exclude in `~/.rgignore`

### Unsupported search modes

Brook by design is restricted to ripgrep's defaults in two important ways:

* **No multiline search** – Brook aborts with a warning if you use `-U` or
  search a multiline selection. The quickfix format is inherently line-based.

* **No PCRE2** – only ripgrep's default regexp engine is supported. Commands
  setting it to PCRE2 will result in an error. This guarantees predictable
  performance and more accurate search pattern translation.

---

## License

MIT

---

## Disclaimer

Brook.nvim is a personal project. It's feature-complete, but comes with no
stability guarantees. Breaking changes or history rewrites may occur.
