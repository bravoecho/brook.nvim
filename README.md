# brook.nvim – Ripgrep that feels like Vim

**brook.nvim** brings seamless ripgrep search to Neovim. It's not a fuzzy
finder, it's a precision tool for code exploration and refactoring.

---

## Usage

### Workflow

Brook is designed for a "Search-Navigate-Edit" loop powered by the quickfix list.

> [!TIP]
> [Learn more about the quickfix list](/doc/quickfix_primer.md)

1. **Search**
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
* **Unique lines** – Use the `-n` flag to set it on a single search
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

### Constraints

Brook follows ripgrep's defaults in two important ways:

* **Multiline search** – Brook aborts with a warning if you use `-U` or search
  a multiline selection. The quickfix format is inherently line-based.

* **PCRE2** – only ripgrep's default regexp engine is supported. Commands
  setting it to PCRE2 will result in an error. This guarantees predictable
  performance and more accurate search pattern translation.

---

## Installation & Setup

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'bravoecho/brook.nvim',
  dependencies = {
    -- Optional but recommended for context preview and result filtering.
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

  -- Defaults (you only need to specify the fields you want to customise)
  opts = {
    -- Keymaps (set to false to disable)
    keymap_cword = '<leader>g',
    keymap_visual = '<leader>g',
    keymap_prompt = '<leader>/',
    keymap_stop = '<leader>G',
    keymap_repeat = '<leader>r',

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

## Why Brook?

Most Neovim users choose between legacy Vimscript plugins, find-and-replace
dashboards with their own UI, or modern fuzzy finders.

Brook sits in the sweet spot for power users:

* **Fast & Asynchronous** – Results stream to the quickfix list using carefully
  tuned cooperative scheduling, to keep the UI responsive even in the most
  extreme scenarios.

* **Shell-Agnostic & Safe** – Brook is immune to shell injection, and it won't
  break due to escaping quirks. If it works with `rg`, it works with `:Rg`.

* **Quickfix-Centric** – Embraces the built-in [quickfix list](/doc/quickfix_primer.md)
  for persistent results that integrate with native navigation and batch
  operations.

* **Native Search Integration** – Brook translates ripgrep patterns to Vim's
  search register, enabling highlighting and `n`/`N` navigation. Combined with
  `:cfdo %s//replacement/gc`, this makes search-and-replace seamless.

* **LSP Complement** – LSPs handle symbol renaming; Brook handles everything
  else: string constants, CSS classes, complex patterns across the entire
  project with regex precision.

* **Zero Abstraction** – If you know Vim and Ripgrep, you know Brook.
  No screenshots required.

* **Neovim-Native** – Built for Neovim 0.7+ in Lua.

---

## Comparisons with other plugins

### Brook vs. find-and-replace dashboards

Modern Neovim search plugins often present a self‑contained interface:
a dedicated buffer, custom navigation keys, inline previews, live updates, and
replace actions tightly coupled to their own UI.

Brook takes the opposite approach. It acknowledges that Vim already *is* the
interface, and that power comes from reuse and composition.

| UI‑Driven Plugins        | Brook                             |
| ------------------------ | --------------------------------- |
| Custom buffers and views | Native quickfix list              |
| Live, reactive queries   | Explicit, snapshot‑based searches |
| UI mediates all actions  | Vim commands operate directly     |
| Discoverability first    | Composability first               |
| Steep learning curve     | Plug-and-Play                     |
| Depend on a plugin       | Master Vim (see "Pro Tips")       |
| Centralised workflows    | User‑defined workflows            |

### Brook vs. fuzzy finders

Fuzzy finders excel at locating a single file or symbol quickly. Brook is
designed for *systematic exploration*:

* persistent result sets
* ordered navigation
* batch edits across files

The quickfix list remains available after the search window closes, and its
contents can be reused by any other command. Brook does not replace fuzzy
finders; it complements them.

### Brook vs. traditional grep wrappers

Compared to traditional, pre-Neovim grep plugins, Brook preserves the model and
modernises the execution:

* native Lua APIs
* highly optimised multi-stage buffered streaming to the quickfix
* shell‑independent argument handling
* advanced pattern translation for search register integration

The result is familiar behaviour with contemporary performance characteristics.

## License

MIT
