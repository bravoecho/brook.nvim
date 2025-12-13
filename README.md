# brook.nvim

A ripgrep wrapper for Neovim. Streams results asynchronously to the quickfix
list, bypasses shell interpretation for security and portability, and sets the
search register for seamless `n`/`N` navigation.

## Features

- **Asynchronous execution**: results stream to the quickfix list as they
  arrive
- **Shell-safe**: arguments are passed directly to ripgrep, bypassing shell
  interpretation entirely
- **Pattern extraction**: the search pattern is translated to Vim regex and set
  in the search register, so `n`/`N` navigation and `hlsearch` work out of the box
- **Transparent**: no abstraction layer; any ripgrep knowledge transfers
  directly

## Installation

Lazy loading using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
local keymap = '<leader>g'

return {
  'bravoecho/brook.nvim',
  cmd = { 'Rg', desc = 'Grep with rg' },
  keys = {
    { keymap, mode = 'n', desc = 'Grep with rg' },
    { keymap, mode = 'x', desc = 'Grep visual selection' },
  },
  opts = {},
}
```

## Configuration

Minimal.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `keymap` | string | `'<leader>g'` | Keymap for triggering searches |
| `max_results` | integer\|false | `1000` | Maximum results before stopping (false to disable) |

To use a different keymap, update both the `keys` table (for lazy-loading) and
`opts`.

```lua
local keymap = '<C-g>'

return {
  'bravoecho/brook.nvim',
  cmd = { 'Rg', desc = 'Grep with rg' },
  keys = {
    { keymap, mode = 'n', desc = 'Grep with rg' },
    { keymap, mode = 'x', desc = 'Grep visual selection' },
  },
  opts = {
    keymap = keymap, -- default: `<leader>g`
    max_results = 2000, -- default: 1000 (set to `false` for unlimited results)
  },
}
```

No Neovim-specific configuration is required for ripgrep itself, brook.nvim
respects the existing ripgrep configuration:

- `.ripgreprc` (via `RIPGREP_CONFIG_PATH`)
- `.gitignore` and `.ignore` files
- Environment variables inherited by Neovim

## Usage

### Command

```vim
:Rg pattern [options] [path]
```

...or any other argument variant supported by ripgrep (see `rg --help`).

Arguments are forwarded to ripgrep.

When no arguments are provided, brook searches for the word under the cursor.

Path completion is supported.

### Default mappings

| Mode | Mapping | Action |
|------|---------|--------|
| Normal | `<leader>g` | Open the `:Rg` command prompt |
| Normal | `:Rg` (no args) | Search for word under cursor |
| Visual | `<leader>g` | Search for visual selection |

## Examples

### Basic searches

```vim
" Search for a pattern
:Rg function

" Case-insensitive search
:Rg -i function

" Search with context lines
:Rg TODO -C 2

" Search only in specific file types
:Rg --type lua require
```

### Regex patterns

```vim
" Find function definitions
:Rg 'function\s+\w+\s*\('

" Alternation
:Rg 'TODO|FIXME'

" Word boundaries
:Rg '\bconfig\s*='

" Non-greedy matching
:Rg '<div.*?>'
```

### Filtering results

```vim
" Only test files
:Rg -g '*_test.go' 'func Test'

" Exclude directories
:Rg --glob '!vendor/**' 'http\.Client'

" Fixed strings (literal search, no regex)
:Rg -F 'array[0]'
```

## Shell safety

brook.nvim passes arguments directly to ripgrep as an array, bypassing shell
interpretation. This also avoids escaping and quoting incompatibility when
running Neovim in different shells (Bash/Zsh vs Fish, for example).

```vim
" Apostrophes (using double quotes)
:Rg "it's"

" Embedded double quotes (using single quotes)
:Rg 'say "hello"'

" Dollar signs
:Rg '$HOME'
:Rg 'cost: $100'

" Backticks
:Rg 'foo`bar'
:Rg 'template `string`'

" Pipes (regex alternation, not shell pipeline)
:Rg 'foo|bar'

" Glob-like patterns (not expanded by shell)
:Rg '*.lua'
:Rg 'array[0]'

" Angle brackets (not interpreted as redirection)
:Rg 'Vec<T>'
:Rg 'x > 0'

" Backslashes in regex
:Rg 'foo.*bar'
:Rg 'Fatal\(err\)'

" The POSIX idiom for single quotes inside single-quoted strings
:Rg 'it'\''s a test'
```

### How it works

When you type a command like `:Rg 'foo|bar'`, Neovim passes the raw string
`'foo|bar'` (quotes included) to brook. Brook then applies POSIX-compliant shell
unquoting to extract the intended pattern (`foo|bar`), and passes it directly to
ripgrep via `jobstart()` as an argument array: no shell ever interprets the
pattern.

Malformed input (such as unterminated quotes or a trailing backslash) is
rejected rather than passed through incorrectly.

## Technical notes

Building a "transparent" ripgrep wrapper presents a few challenges.

**POSIX shell unquoting.** When you type `:Rg 'foo bar'`, Neovim passes the
literal string `'foo bar'` (quotes included) to the plugin. Brook must interpret
these quotes the way a shell would: removing them while respecting the
differences between single quotes, double quotes, and backslash escapes.

**Pattern extraction.** To set Vim's search register, brook needs to identify
which argument is the search pattern. This requires parsing ripgrep's CLI:
distinguishing flags from options that take values, handling stacked short flags
(`-wie`), long options with attached values (`--regexp=pattern`), and the `--`
separator. Setting the search register is useful when performing global
search+replace with `:cfdo %s//my-new-thing/`, so that the search pattern
doesn't have to be typed in again.

**Regex dialect translation.** Ripgrep uses Rust's regex syntax; Vim has its
own. Brook translates patterns to Vim's "very magic" mode (`\v`), which closely
mirrors ripgrep's syntax: most metacharacters pass through unchanged. The main
transformations are non-greedy quantifiers (`+?` → `{-1,}`, `*?` → `{-}`) and
word boundaries (`\b` → `(<|>)`). This is best-effort but covers most real-world
patterns, enabling accurate `n`/`N` navigation and highlighting.

**Argument classification.** Brook maintains a generated list of ripgrep flags
and options (extracted from `rg --help`) to correctly classify arguments,
enabling accurate pattern extraction even with complex command lines.

**Ripgrep stdin handling.** When called through `jobstart()`, ripgrep expects
content on stdin, which never arrives. Brook disables the `stdin` option to
avoid blocking indefinitely.

## Troubleshooting

**Search highlighting and `n`/`N` navigation don't work.** This feature relies
on a hardcoded list of ripgrep flags. If your ripgrep version has newer options,
run `./bin/generate-rg-named-args` to regenerate the list, or submit a pull
request.

**Case-sensitivity is not reflected correctly in highlighting.** Translating
flags like `--case-sensitive`, `--smart-case` and more would add significant
complexity for marginal benefit. As a workaround, if both ripgrep and Neovim are
configured to use smart case by default, the corresponding Vim search should
do what you expect in most cases.

**Results are truncated.** By default, brook stops after 1000 results to keep
the quickfix list manageable. Increase or disable the limit with `max_results`
in your configuration.

**Multiple patterns are not highlighted.** At the moment only the first pattern
is used to set the search register. This is because I suspect it would be
a seldom used feature in the context of code editing. Support for multiple
patterns may be added in the future.

## Other plugins

### brook.nvim vs vim-grepper

[vim-grepper](https://github.com/mhinz/vim-grepper) is an excellent,
battle-tested plugin I used for many years. It supported my workflows where no
other plugin could. Surely thousands more people have experienced the same.

Main motivations for brook.nvim were:

- I ran into edge cases with Fish shell compatibility
- I couldn't find a ripgrep plugin written in Lua
- I was interested in extended search register support

| Aspect | brook.nvim | vim-grepper |
|--------|------------|-------------|
| Language | Lua | Vimscript |
| Target | Neovim only | Vim + Neovim |
| Tools | ripgrep only | 9 tools |
| Config | Minimal | Many options |
| Shell | Bypassed (direct execution) | Per-tool escaping |

**vim-grepper** abstracts over multiple grep tools with rich configuration:
prompt modes, tool switching, directory strategies, side windows, and more.

**brook.nvim** only supports ripgrep and streams results to quickfix: no shell
interpretation, identical behaviour across Fish/Zsh/Bash. brook.nvim omits
multi-tool support, interactive prompt, location list, side window, append mode,
auto-jump, and Vim support.

If switching from vim-grepper, these work the same: async streaming to quickfix,
search register (`n`/`N` navigation), word-under-cursor search, visual selection
search, arbitrary ripgrep flags, and environment (`.gitignore`, `.ripgreprc`).

### brook.nvim vs Telescope and FzfLua

Fuzzy finders are excellent for tasks where partial information is sufficient to
find the resource, like opening a file, switching buffers, finding
a lesser-known command. The transient UI fits that interaction: find, select,
move on.

Grepping is different, for code exploration and modification. The results need
to remain available, to navigate between them, and often act on them. The
quickfix list is best suited to this purpose:

- it persists, and it can be kept open or hidden
- it integrates with built-in navigation commands and shortcuts
- supports batch operations via `:cfdo`

### Global Search and Replace

Grepping plugins that populate the quickfix list and set the search register,
like vim-grepper and brook.nvim, support global search-and-replace out of the
box:

```vim
:cfdo %s//replacement/gc
```

...will replace all matches across files, using the pattern you already searched
for. No additional UI required, just Vim, working as designed.

## Requirements

- Neovim 0.7+
- [ripgrep](https://github.com/BurntSushi/ripgrep)

## License: MIT
