--- Shared type definitions for the rg plugin.
---
--- This file contains only LuaDoc annotations and is not meant to be required
--- at runtime. It exists solely to provide type information to the Lua
--- language server.

--- A quickfix list entry, as expected by `vim.fn.setqflist()`.
---@class brook.QfEntry
---@field filename string Path to the file containing the match
---@field lnum integer Line number (1-indexed)
---@field col integer Column number (1-indexed)
---@field text string The matched line content

--- Options controlling ripgrep search behaviour and pattern translation.
---@class brook.SearchOpts
---@field word? boolean Whether to match whole words only (--word-regexp)
---@field fixed? boolean Whether to treat the pattern as a literal string (--fixed-strings)

--- Result of parsing ripgrep command-line arguments.
---@class brook.ParsedArgs
---@field patterns string[] One or more search patterns
---@field fixed boolean Whether --fixed-strings / -F was specified
---@field word boolean Whether --word-regexp / -w was specified

---@class brook.PluginOpts
---@field keymap? string Keymap for triggering searches (default: '<leader>g')
---@field max_results? integer Maximum results before stopping (default: 1000, nil for unlimited)
