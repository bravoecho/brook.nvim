--- Shared type definitions for the rg plugin.
---@module 'brook'

---@class brook.Config
---@field keymap? string Keymap for triggering searches (default: '<leader>g')
---@field max_results? integer Maximum results before stopping (default: 1000, nil for unlimited)
---@field debounce? integer Maximum wait in ms before flushing results (default: 80)
---@field buffer_size? integer Maximum number of results to buffer before flushing (default: 100)
---@field qf_open? boolean Whether the quickfix list should be opened when results arrive (default: true)
---@field qf_auto_resize? boolean Whether the quickfix window should grow as results come in (default: true)
---@field qf_win_height? integer Maximum height the quickfix window should grow to (when auto_resize is enabled) or fixed height (when auto_resize is not enabled) (default: 10)

---@class brook.ExecOpts
---@field max_results integer Maximum results before stopping (default: 1000, nil for unlimited)
---@field debounce integer Maximum wait in ms before flushing results (default: 80)
---@field buffer_size integer Maximum number of results to buffer before flushing (default: 100)
---@field qf_open boolean Whether the quickfix list should be opened when results arrive (default: true)
---@field qf_auto_resize boolean Whether the quickfix window should grow as results come in (default: true)
---@field qf_win_height integer Maximum height the quickfix window should grow to (when auto_resize is enabled) or fixed height (when auto_resize is not enabled) (default: 10)

--- Options controlling ripgrep search behaviour and pattern translation.
---@class brook.SearchOpts
---@field word? boolean Whether to match whole words only (--word-regexp)
---@field fixed? boolean Whether to treat the pattern as a literal string (--fixed-strings)
---@field case? search_case Whether to treat the pattern as case sensitive, case insensitive, or unspecified

local M = {}

---@enum search_case
M.search_case = {
  sensitive = 'case-sensitive',
  insensitive = 'case-insensitive',
  unset = 'unset',
}

--- Result of parsing ripgrep command-line arguments.
---@class brook.ParsedArgs
---@field patterns string[] One or more search patterns
---@field fixed boolean Whether --fixed-strings / -F was specified
---@field word boolean Whether --word-regexp / -w was specified
---@field case search_case Whether -s, --case-sensitive, -i or --ignore-case were specified

return M
