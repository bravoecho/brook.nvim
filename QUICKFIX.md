# The Quickfix List: A Primer

If you're coming to Neovim through a distribution like LazyVim, NvChad, or
LunarVim, you might have been using the quickfix list for years without knowing
its name. This document explains what it is, why it matters, and how Brook uses
it.

## What is the quickfix list?

The quickfix list is one of Vim's oldest features, dating back to the 1980s.
It's a global, navigable list of locations: file paths, line numbers, column
positions, and some context text.

The name comes from its original purpose: capturing compiler errors so you could
quickly fix them, jumping from error to error without manually opening files and
hunting for line numbers.

Today, the quickfix list is used by many tools:

- `:make` populates it with build errors
- `:grep` and `:vimgrep` populate it with search results
- diagnostics has built-in functions to populate it
- the LSP client uses it for references, implementations and more
- countless plugins
- ...and Brook populates it with ripgrep matches

Think of it as a universal "results list" that any tool can write to and any
navigation command can read from. The fact that such a venerable feature remains
the integration point for modern tooling is confirmation that its design works
well with Vim.

## The quickfix list is a snapshot

One of the most important things to realise about the quickfix list is that it's
a _snapshot_, not a live query.

When you run a search, the quickfix captures the state of your codebase at that
moment: which files contained matches, at which line and column, with what
surrounding text. From that point on, the list is static, it doesn't update when
files change.

This is actually a powerful feature:

**You can navigate back to results even after editing.** Say you're working
through 50 search results, making changes as you go. At result 30, you realise
you want to revisit result 12, but you've already modified that file. With a
"live" system, result 12 might have moved or disappeared entirely. With the
quickfix, it's still there, pointing to where the match *was* when you searched.

**Line numbers adjust within your session.** The quickfix is smarter than it
first appears. If you add or remove lines in a buffer, Vim tracks those changes
and adjusts the quickfix positions accordingly, as long as the buffer remains
open. Jump to result 12, and you'll land in the right place even if it's now on
a different line number than when you searched.

**Stable results are breadcrumbs, not bugs.** The results that no longer match
your search pattern? They're a record of where you've been and what you've
changed. Some workflows depend on this: you might *want* to see all the places
that originally matched, precisely so you can verify you've handled them all.

This design supports a workflow of: take a snapshot, work through the results,
navigate back and forth as your understanding evolves, and trust that your
breadcrumbs won't disappear mid-task.

Brook leans into all of that; not doing so would be at odds with Brook's goals
of control, performance and predictable response. For example, automatically
refreshing results as the file contents change could trigger searches that in
large repositories would take too long, even in pure ripgrep time. Conversely,
trying to surgically edit the list would still be an O(n) operation, potentially
causing lag. Finally, regenerating the list would raise the question of how to
restore the result the user was on at the time of update.

## Quickfix vs location list

Vim actually has two such lists:

| Quickfix list                     | Location list                  |
| --------------------------------- | ------------------------------ |
| Global (one per Neovim instance)  | Window-local (one per window)  |
| Commands start with `:c`          | Commands start with `:l`       |
| Opened with `:copen`              | Opened with `:lopen`           |

Brook uses the quickfix list because search results typically span multiple
files and you'll want to access them regardless of which window you're in.

## Basic navigation

| Command              | Action                             |
| -------------------- | -----------------------------------|
| `:copen`, `:cclose`  | Open and close the quickfix window |
| `:cnext`, `:cprev`   | Jump to the next and previous item |
| `:cfirst`, `:clast`  | Jump to the first and last item    |
| `:cc 42`             | Jump to item number 42             |

Most users map `:cnext` and `:cprev` to something faster. Common choices:

```lua
vim.keymap.set('n', ']q', ':cnext<CR>')
vim.keymap.set('n', '[q', ':cprev<CR>')
```

These `]q`/`[q` bindings are a convention popularised by vim-unimpaired and now
adopted by many modern configurations.

## The quickfix window

When you run `:copen`, Neovim opens a special window showing all items in the
list. You can:

- Press `<CR>` on any line to jump to that location
- Use `/` to search within the results
- Close it with `:cclose` or `:q`

This is the window you see after running a Brook search.

A common misconception is that this window *is* the quickfix list. It's not,
it's just a view into the list. The list itself exists independently; you can
close the window, navigate with `:cnext`/`:cprev`, and reopen it later with
`:copen`. The data persists until you run another command that populates the
quickfix.

## Operating on quickfix files with `:cfdo`

The quickfix list isn't just for navigation, it's a foundation for batch
operations across files. The `:cfdo` command executes a command once _per file_
in the quickfix list (as opposed to `:cdo`, which runs once _per entry_).

The "c" prefix means quickfix, and "f" means file-wise. So `:cfdo` means "on
each file in the quickfix list, do this."

### Search and replace

The classic use case. After running a Brook search for `handleClick`:

```vim
:cfdo %s//handleSubmit/gc
```

Let's break this down:

- `:cfdo`: for each file in the quickfix list

- `%s`: substitute across the entire buffer (`%` means all lines)

- `//`: empty pattern reuses the last search (which Brook set to your ripgrep
  query)

- `handleSubmit`: the replacement text

- `g`: all occurrences on each line (default in many configurations)

- `c`: confirm each replacement (optional, but recommended)

The empty `//` is made possible by Brook's advanced pattern translation, so you
don't need to retype it in a different regex syntax.

After confirming your changes, save all modified buffers:

```vim
:cfdo update
```

Or combine into one command:

```vim
:cfdo %s//handleSubmit/g | update
```

### Beyond search and replace

`:cfdo` runs *any* Ex command, not just substitutions. Some examples:

* Delete all lines matching the search

  ```vim
  :cfdo g//d
  ```

  The `:g//` command operates on lines matching the last search pattern; `d`
  deletes them.

* Add a comment above each match

  ```vim
  :cfdo g//normal O\/\/ TODO: review this
  ```

  This uses `:g//` to find matching lines, then `normal O` to open a line above
  and insert a comment. (The backslashes escape the forward slashes in the
  comment.)

* Run a macro on each file

  ```vim
  :cfdo normal @q
  ```

  If you've recorded a macro in register `q`, this executes it once per file.

* Change file formatting

  ```vim
  :cfdo set fileformat=unix | update
  ```

  Converts line endings to Unix format for every file in the quickfix list.

* Delete trailing whitespace

  ```vim
  :cfdo %s/\s\+$//e | update
  ```

  The `e` flag suppresses errors if no match is found in a particular file.

### `:cdo` vs `:cfdo`

There's also `:cdo`, which runs once per *entry* rather than once per file:

- `:cfdo`: once per file (useful for file-wide operations like `%s`)
- `:cdo`: once per quickfix entry (useful when you want to operate on each
  specific match location)

For search and replace, `:cfdo` with `%s` is usually what you want. But if you
need to do something at each exact match location, like adding a log statement
after every occurrence, `:cdo` gives you that precision.

## How Brook uses the quickfix list

When you search with Brook:

1. Results stream into the quickfix list as ripgrep finds them
2. The quickfix window opens automatically (if results exist)
3. The search pattern is saved to Vim's search register (`@/`)

This third point is what enables the workflows above. After a Brook search, the
pattern is ready for use in `:s` commands, `:g` commands, and `n`/`N` navigation
within files.

## Enhancing the quickfix experience

Brook (like every quickfix-oriented plugin) works well with
[nvim-bqf](https://github.com/kevinhwang91/nvim-bqf), which adds:

- Fuzzy filtering within results (narrow down without re-searching)
- Preview windows showing match context
- Additional navigation keybindings

If you find yourself using Brook frequently, `nvim-bqf` is without question
worth the addition.

## Further reading

- `:help quickfix`: Vim's comprehensive quickfix documentation
- `:help location-list`: the window-local alternative
- `:help :cfdo`: run a command on each file in the quickfix list
- `:help :cdo`: run a command on each entry in the quickfix list
