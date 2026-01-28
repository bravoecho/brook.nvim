--- Data structures and reference values used in command line argument parsing
---
---@module 'brook.args.types'
local M = {}

--------------------------------------------------------------------------------

--- Result of parsing ripgrep command-line arguments.
---@class brook.args.ParsedArgs
---
--- The ripgrep search patterns (from -e/--regexp options or first positional)
---@field patterns string[]
---
--- Whether --fixed-strings / -F was specified
---@field fixed boolean
---
--- Whether --word-regexp / -w was specified
---@field word boolean
---
--- Whether -s, --case-sensitive, -i or --ignore-case were specified
---@field case brook.args.SearchCase|nil
---
--- Output format override from command line, or nil to use config default
---@field output_format brook.args.OutputFormat|nil
---
--- Whether the pattern should match over multiple lines
---@field multiline boolean
---
--- Whether PCRE2 regex engine is enabled (-P, --pcre2, --engine=pcre2, --engine=auto)
---@field pcre2 boolean
---
--- Original user command, forwarded so it can be echoed back
---@field raw string

--------------------------------------------------------------------------------

---@enum brook.args.SearchCase
M.search_case = {
  sensitive = 'case-sensitive',
  insensitive = 'case-insensitive',
}

--------------------------------------------------------------------------------

---@enum brook.args.OutputFormat
M.output_format = {
  one_line_per_match = 'one-line-per-match',
  unique_lines = 'unique-lines',
}

--------------------------------------------------------------------------------

return M
