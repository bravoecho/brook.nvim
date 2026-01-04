--- Data structures and reference values used throughout brook.nvim.
---
---@module 'brook.types'

---@class brook.UserConfig
---
--- Keymap for triggering searches (default: '<leader>g')
---@field keymap? string
---
--- Keymap for stopping searches (default: '<leader>G')
---@field stop_keymap? string
---
--- Maximum results before stopping (default: 1000, range: 1-10,000)
---@field max_results? integer
---
--- Maximum number of results to buffer before flushing (default: 100)
---@field max_batch_size? integer
---
--- A short time, in milliseconds, to give Neovim the opportunity to redraw
--- between batches (default: 10)
---@field flush_throttle_ms? integer
---
--- Whether the quickfix list should be opened when results arrive (default: true)
---@field qf_open? boolean
---
--- Whether the quickfix window should grow as results come in (default: true)
---@field qf_auto_resize? boolean
---
--- Maximum height the quickfix window should grow to (when auto_resize is
--- enabled) or fixed height (when auto_resize is not enabled) (default: 10)
---@field qf_win_height? integer
---
--- Output format: 'one-line-per-match' (default) or 'unique-lines'
---@field output_format? brook.OutputFormat
---
--- Whether to set Vim's search register (/) with the pattern, enabling n/N
--- navigation and hlsearch (default: true)
---@field set_search_register? boolean

---@class brook.ExecConfig
---
--- Maximum results before stopping (default: 1000, range 1-10,000)
---@field max_results integer
---
--- Maximum number of results to buffer before flushing (default: 100)
---@field max_batch_size integer
---
--- A short time, in milliseconds, to give Neovim the opportunity to redraw
--- between batches (default: 10)
---@field flush_throttle_ms integer
---
--- Whether the quickfix list should be opened when results arrive (default: true)
---@field qf_open boolean
---
--- Whether the quickfix window should grow as results come in (default: true)
---@field qf_auto_resize boolean
---
--- Maximum height the quickfix window should grow to (when auto_resize is
--- enabled) or fixed height (when auto_resize is not enabled) (default: 10)
---@field qf_win_height number
---
--- Output format: 'one-line-per-match' or 'unique-lines'
---@field output_format brook.OutputFormat
---
--- Whether to set Vim's search register (/) with the pattern, enabling n/N
--- navigation and hlsearch (default: true)
---@field set_search_register boolean
---
--- Larger batches after ripgrep has finished (default: 10x max_batch_size)
---@field phase3_batch_size number
---
--- Less throttling after ripgrep has finished (default: 1)
---@field phase3_throttle_ms number

--- Options controlling ripgrep search behaviour and pattern translation.
---@class brook.PatternOpts
---
--- Whether to match whole words only (--word-regexp)
---@field word? boolean
---
--- Whether to treat the pattern as a literal string (--fixed-strings)
---@field fixed? boolean
---
--- Whether to treat the pattern as case sensitive, case insensitive, or unspecified
---@field case? brook.SearchCase

local M = {}

---@enum brook.SearchCase
M.search_case = {
  sensitive = 'case-sensitive',
  insensitive = 'case-insensitive',
}

---@enum brook.OutputFormat
M.output_format = {
  one_line_per_match = 'one-line-per-match',
  unique_lines = 'unique-lines',
}

M.max_max_results = 10000

--- Result of parsing ripgrep command-line arguments.
---@class brook.ParsedArgs
---
--- The ripgrep search pattern
---@field pattern string|nil
---
--- Whether --fixed-strings / -F was specified
---@field fixed boolean
---
--- Whether --word-regexp / -w was specified
---@field word boolean
---
--- Whether -s, --case-sensitive, -i or --ignore-case were specified
---@field case brook.SearchCase|nil
---
--- Output format override from command line, or nil to use config default
---@field output_format brook.OutputFormat|nil
---
--- Whether the pattern should match over multiple lines
---@field multiline boolean
---
--- Original user command, forwarded so it can be echoed back
---@field raw string

return M
