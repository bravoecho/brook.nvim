--- Shared type definitions for the rg plugin.
---@module 'brook'

---@class brook.UserConfig
---@field keymap? string Keymap for triggering searches (default: '<leader>g')
---@field stop_keymap? string Keymap for stopping searches (default: '<leader>G')
---@field max_results? integer Maximum results before stopping (default: 1000, range: 1-10,000)
---@field max_batch_size? integer Maximum number of results to buffer before flushing (default: 100)
---@field flush_throttle_ms? integer A short time, in milliseconds, to give Neovim the opportunity to redraw between batches (default: 10)
---@field qf_open? boolean Whether the quickfix list should be opened when results arrive (default: true)
---@field qf_auto_resize? boolean Whether the quickfix window should grow as results come in (default: true)
---@field qf_win_height? integer Maximum height the quickfix window should grow to (when auto_resize is enabled) or fixed height (when auto_resize is not enabled) (default: 10)
---@field output_format? brook.OutputFormat Output format: 'one-line-per-match' (default) or 'unique-lines'
---@field set_search_register? boolean Whether to set Vim's search register (/) with the pattern, enabling n/N navigation and hlsearch (default: true)

---@class brook.ExecConfig
---@field max_results integer Maximum results before stopping (default: 1000, range 1-10,000)
---@field max_batch_size integer Maximum number of results to buffer before flushing (default: 100)
---@field flush_throttle_ms integer A short time, in milliseconds, to give Neovim the opportunity to redraw between batches (default: 10)
---@field qf_open boolean Whether the quickfix list should be opened when results arrive (default: true)
---@field qf_auto_resize boolean Whether the quickfix window should grow as results come in (default: true)
---@field qf_win_height integer Maximum height the quickfix window should grow to (when auto_resize is enabled) or fixed height (when auto_resize is not enabled) (default: 10)
---@field output_format brook.OutputFormat Output format: 'one-line-per-match' or 'unique-lines'
---@field set_search_register boolean Whether to set Vim's search register (/) with the pattern, enabling n/N navigation and hlsearch (default: true)

--- Options controlling ripgrep search behaviour and pattern translation.
---@class brook.PatternOpts
---@field word? boolean Whether to match whole words only (--word-regexp)
---@field fixed? boolean Whether to treat the pattern as a literal string (--fixed-strings)
---@field case? brook.SearchCase Whether to treat the pattern as case sensitive, case insensitive, or unspecified

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

---@type brook.UserConfig
M.defaults = {
  keymap = '<leader>g',
  stop_keymap = '<leader>G',
  max_results = 1000,
  max_batch_size = 100,
  flush_throttle_ms = 10,
  qf_open = true,
  qf_auto_resize = true,
  qf_win_height = 10,
  output_format = M.output_format.one_line_per_match,
  set_search_register = true,
}

M.max_max_results = 10000

--- Result of parsing ripgrep command-line arguments.
---@class brook.ParsedArgs
---@field pattern string|nil The ripgrep search pattern
---@field fixed boolean Whether --fixed-strings / -F was specified
---@field word boolean Whether --word-regexp / -w was specified
---@field case brook.SearchCase|nil Whether -s, --case-sensitive, -i or --ignore-case were specified
---@field output_format brook.OutputFormat|nil Output format override from command line, or nil to use config default
---@field multiline boolean Whether the pattern should match over multiple lines

return M
