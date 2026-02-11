--- Data structures and reference values used in the main brook module.
---
---@module 'brook.types'

--------------------------------------------------------------------------------

---@class brook.UserConfig
---
--- Normal-mode keymap for triggering current word search (default: '<leader>g')
---@field keymap_cword? string|false
---
--- Visual-mode keymap for triggering current selection search (default: '<leader>g')
---@field keymap_visual? string|false
---
--- Normal-mode keymap for stopping searches (default: '<leader>G')
---@field keymap_stop? string|false
---
--- Normal-mode keymap for opening the prompt (default: '<leader>/')
---@field keymap_prompt? string|false
---
--- Normal-mode keymap for repeating the last search in the session (default: '<leader>r')
---@field keymap_repeat? string|false
---
--- Maximum results before stopping (default: 1000, range: 500-100,000)
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
---@field qf_win_height? number
---
--- Output format: 'one-line-per-match' (default) or 'unique-lines'
---@field output_format? brook.args.OutputFormat
---
--- Whether to set Vim's search register (/) with the pattern, enabling n/N
--- navigation and hlsearch (default: true)
---@field set_search_register? boolean
---
--- Larger batches after ripgrep has finished (default: 5x max_batch_size)
--- (most users should not modify this).
---@field drain_phase_max_batch_size? number
---
--- Less throttling after ripgrep has finished (default: 1/2 of flush_throttle_ms)
--- (most users should not modify this).
---@field drain_phase_flush_throttle_ms? number
---
--- Whether each search should wipe out unlisted buffers that were created in
--- the previous search, but were never opened (default: true)
---@field wipe_unlisted_buffers? boolean
---
--- Maximum number of characters to use for a result preview
--- (default: 200, range: 100-500)
---@field max_preview_chars? number

--------------------------------------------------------------------------------

local M = {}

--------------------------------------------------------------------------------

M.validations = {
  max_results = { min = 500, max = 100000 },
  max_preview_chars = { min = 100, max = 500 },
  max_batch_size = { min = 10, max = 200 },
}

--------------------------------------------------------------------------------

return M
