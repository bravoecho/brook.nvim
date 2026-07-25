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

--- Which characters can be backslash-escaped inside single- and
--- double-quoted tokens. Shared contract between the tokeniser (which needs
--- to know whether an escaped quote closes its token) and the unquoter
--- (which needs to know exactly which characters to unescape).
---@class brook.args.Quoting
---@field double table<string, boolean> Characters escapable inside double quotes
---@field single table<string, boolean> Characters escapable inside single quotes

M.quoting = {
  --- Only the enclosing quote character is escapable, in both single and
  --- double quotes. Everything else (including \\, \$, \`) passes through
  --- literally, so ripgrep sees exactly what was typed. This is the default:
  --- Brook never spawns a shell, so there is no variable interpolation or
  --- command substitution to guard against, and full POSIX escaping only
  --- caused backslashes meant for ripgrep's own regex syntax (e.g. \$ for a
  --- literal dollar sign) to be silently stripped.
  ---@type brook.args.Quoting
  literal = {
    double = { ['"'] = true },
    single = { ["'"] = true },
  },

  --- Full POSIX shell semantics, so a token copied from (or destined for) an
  --- actual shell round-trips exactly: \$, \`, \", \\ are escapable inside
  --- double quotes, and single quotes allow no escapes at all (use the
  --- 'foo'\''bar' idiom to embed a literal single quote instead). Opt in via
  --- the `strict_posix_quoting` setup option.
  ---@type brook.args.Quoting
  strict_posix = {
    double = {
      ['$'] = true,
      ['`'] = true,
      ['"'] = true,
      ['\\'] = true,
    },
    single = {},
  },
}

--------------------------------------------------------------------------------

return M
