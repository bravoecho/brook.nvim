--- Pattern translation: ripgrep regex => Vim "very magic" regex.
---
--- While best-effort, it covers a wide range of practical use cases.
---
--- It does not cover:
---
---   * ripgrep features that require PCRE2 (e.g. backreferences), because we
---     disallow PCRE2
---   * ripgrep features not supported by vimgrep
---   * vimgrep syntax with no ripgrep equivalent
---   * lookarounds (high complexity, limited utility in code search)
---
--- When translation is not possible, the search still works; only highlighting and
--- n/N navigation are unavailable.
---
---@module 'brook.pattern'
local M = {}

local types = require 'brook.types'

--- Result of pattern translation.
---
---@class brook.PatternResult
---@field pattern string|nil The translated Vim regex (nil when unsupported)
---@field warning string|nil Warning message for adjustments or failures

--- Translates a ripgrep pattern to Vim regex syntax.
---
--- Targets very magic mode (\v) for closer semantic alignment with ripgrep's
--- Rust regex syntax.
---
--- Supported:
---   - literal characters and basic metacharacters
---   - character classes and shorthands (\d, \w, etc.)
---   - word boundaries (\b)
---   - quantifiers (greedy and non-greedy)
---   - numbered groups (capturing and non-capturing)
---
---@param pattern string The ripgrep search pattern
---@param opts? brook.PatternOpts Options affecting pattern translation
---
---@return brook.PatternResult result The translation result with pattern and optional warning
function M.rg_to_vim(pattern, opts)
  opts = opts or {}

  -- Case 1. Literal search (verbatim, no regex, no translation)
  --------------------------------------------------------------
  -- For literal (fixed-string) searches, use very-nomagic mode (\V).
  -- Only backslash and the search delimiter (/) need escaping.
  if opts.fixed then
    pattern = pattern:gsub('\\', '\\\\'):gsub('/', '\\/')
    if opts.word then
      pattern = '\\<' .. pattern .. '\\>'
    end

    local prefix = '\\V'
    -- Case-sensitivity must be set at the beginning of the pattern, or it will be
    -- interpreted as an escaped character.
    if opts.case == types.search_case.sensitive then
      prefix = '\\C' .. prefix
    elseif opts.case == types.search_case.insensitive then
      prefix = '\\c' .. prefix
    end

    return { pattern = prefix .. pattern, warning = nil }
  end

  -- Case 2. Normal search pattern: translate rg to vim
  -----------------------------------------------------
  local result = {}
  local warnings = {}
  local len = #pattern
  local in_char_class = false
  local i = 1

  while i <= len do
    local char = pattern:sub(i, i)
    local next_char = pattern:sub(i + 1, i + 1)

    if char == '\\' and next_char ~= '' then
      -- Escaped character: handle as a unit
      if in_char_class then
        -- Inside character class: pass through unchanged
        table.insert(result, '\\')
        table.insert(result, next_char)
      elseif next_char == 'b' then
        -- Word boundary: \b -> (<|>) in very magic
        table.insert(result, '(<|>)')
      elseif next_char == 'B' then
        -- Non-word boundary: vimgrep syntax has no direct equivalent; it could
        -- be approximated as a negated boundary check using Vim assertions, but
        -- this would be beyond the scope of the plugin for a rarely used regex
        -- feature.
        table.insert(warnings, '\\B not supported')
        return { pattern = nil, warning = M._format_warnings(warnings) }
      elseif next_char == 'A' then
        -- \A (start of string in ripgrep) is equivalent to ^ under our constraints:
        --   * no multiline patterns
        --   * no PCRE2 (default rg engine only)
        --   * line-oriented matching
        -- Using Vim's \%^ would introduce buffer-level semantics and subtle
        -- differences (e.g. EOF newline handling), so we deliberately map \A -> ^.
        table.insert(result, '^')
        table.insert(warnings, '\\A treated as ^')
      elseif next_char == 'z' then
        -- \z (end of string in ripgrep) is equivalent to $ under our constraints.
        -- Mapping to Vim's \%$ would be incorrect: \%$ matches the absolute end of
        -- the buffer, which fails when a file ends with a newline (the common case).
        -- To preserve ripgrep semantics, we map \z -> $.
        table.insert(result, '$')
        table.insert(warnings, '\\z treated as $')
      elseif next_char == 'p' or next_char == 'P' then
        -- Unicode property classes: no reliable, portable 1:1 mapping from ripgrep to vimgrep.
        table.insert(warnings, 'unicode properties not supported')
        return { pattern = nil, warning = M._format_warnings(warnings) }
      elseif next_char:match('[1-9]') then
        -- Backreferences require PCRE2 in ripgrep, which we disallow.
        table.insert(warnings, 'backreferences require PCRE2')
        return { pattern = nil, warning = M._format_warnings(warnings) }
      else
        -- All other escapes pass through (very magic escaping matches ripgrep)
        table.insert(result, '\\')
        table.insert(result, next_char)
      end
      i = i + 2
    elseif (char == '<' or char == '>') and not in_char_class then
      -- Angle brackets are literal in ripgrep but word boundaries in very magic
      table.insert(result, '\\')
      table.insert(result, char)
      i = i + 1
    elseif char == '[' and not in_char_class then
      -- Start of character class
      in_char_class = true
      table.insert(result, '[')
      i = i + 1

      -- Handle special positions: ^, ], ^]
      if pattern:sub(i, i) == '^' then
        table.insert(result, '^')
        i = i + 1
      end
      if pattern:sub(i, i) == ']' then
        table.insert(result, ']')
        i = i + 1
      end
    elseif char == ']' and in_char_class then
      -- End of character class
      in_char_class = false
      table.insert(result, ']')
      i = i + 1
    elseif char == '{' and not in_char_class then
      -- Non-greedy brace quantifier: {n}? {n,}? {n,m}? -> {-n} {-n,} {-n,m}
      -- Handle it as an independent subsequence, so we can account for ? at
      -- the end without backtracking on the main sequence.
      -- Find the opening brace in the result and insert '-' after it.
      local subresult = {}
      while i <= len do
        -- collect and advance in any case
        local qch, next_qch = pattern:sub(i, i), pattern:sub(i + 1, i + 1)
        table.insert(subresult, qch)
        i = i + 1

        -- if this was the closing of a brace identifer, handle it
        if qch == '}' then
          if next_qch == '?' then
            -- this is a non-greedy brace quantifier: insert the '-' character
            -- after the opening brace: {4,7} => {-4,7} and consume the '?' in
            -- the source
            table.insert(subresult, 2, '-')
            i = i + 1
          end
          -- merge the subsequence back into the main result
          for j = 1, #subresult do
            table.insert(result, subresult[j])
          end
          -- end the brace quantifier sequence
          break
        end
      end
    elseif (char == '*' or char == '+' or char == '?')
        and next_char == '?'
        and not in_char_class
        and i > 1 then
      -- Non-greedy quantifier: *? +? ?? (as long as it's not the first character).
      if char == '*' then
        table.insert(result, '{-}')
      elseif char == '+' then
        table.insert(result, '{-1,}')
      else -- char == '?'
        table.insert(result, '{-0,1}')
      end
      i = i + 2
    elseif (char == '*' or char == '+' or char == '?')
        and next_char == '+'
        and not in_char_class then
      -- Possessive quantifiers: no Vim equivalent
      table.insert(warnings, 'possessive quantifiers not supported')
      return { pattern = nil, warning = M._format_warnings(warnings) }
    elseif char == '(' and next_char == '?' and not in_char_class then
      local third_char = pattern:sub(i + 2, i + 2)
      if third_char == ':' then
        -- Non-capturing group: (?:...) -> %(...)
        table.insert(result, '%(')
        i = i + 3 -- skip (?:
      elseif third_char == 'P' and pattern:sub(i + 3, i + 3) == '<' then
        -- Named capture group (Python style): (?P<name>...) -> (...)
        -- Vim doesn't support named captures, but we can translate it to a
        -- numbered capture group.
        table.insert(result, '(')
        local name_start = i + 4
        local name_end = pattern:find('>', name_start, true)
        if not name_end or name_end == name_start then
          table.insert(warnings, 'invalid group name')
          return { pattern = nil, warning = M._format_warnings(warnings) }
        end
        table.insert(warnings, 'named groups become numbered')
        i = name_end + 1 -- continue after '>'
      elseif third_char == '<' then
        local fourth_char = pattern:sub(i + 3, i + 3)
        -- (?<=...) and (?<!...) are lookbehinds, not named captures.
        -- Not supported, see below: Lookarounds.
        if fourth_char == '=' or fourth_char == '!' then
          table.insert(warnings, 'lookarounds not supported')
          return { pattern = nil, warning = M._format_warnings(warnings) }
        end
        -- Named capture group (PCRE style): (?<name>...) -> (...)
        table.insert(result, '(')
        local name_start = i + 3
        local name_end = pattern:find('>', name_start, true)
        if not name_end or name_end == name_start then
          table.insert(warnings, 'invalid group name')
          return { pattern = nil, warning = M._format_warnings(warnings) }
        end
        table.insert(warnings, 'named groups become numbered')
        i = name_end + 1 -- continue after '>'
      else
        -- Lookarounds: Vim has equivalents (\@=, \@!, \@<=, \@<!), however since
        -- ripgrep's default engine doesn’t support lookarounds and we disallow
        -- PCRE2, we don't support them.
        --
        -- Atomic groups: no Vim equivalent.
        table.insert(warnings, 'lookarounds and atomic groups not supported')
        return { pattern = nil, warning = M._format_warnings(warnings) }
      end
    elseif char == '/' then
      -- Escape search delimiter
      table.insert(result, '\\/')
      i = i + 1
    elseif not in_char_class
        and (char == '=' or char == '~' or char == '@' or char == '&') then
      -- Characters literal in ripgrep, but special in very magic mode, need
      -- escaping.
      table.insert(result, '\\')
      table.insert(result, char)
      i = i + 1
    else
      -- Everything else passes through unchanged
      table.insert(result, char)
      i = i + 1
    end
  end

  local vimgrep_pattern = table.concat(result)
  -- Handle word-bounded searches
  if opts.word then
    vimgrep_pattern = '<' .. table.concat(result) .. '>'
  end
  -- Make the pattern "very magic"
  vimgrep_pattern = '\\v' .. vimgrep_pattern

  -- Case-sensitivity must be set at the beginning of the pattern, or it will be
  -- interpreted as an escaped character.
  if opts.case == types.search_case.sensitive then
    vimgrep_pattern = '\\C' .. vimgrep_pattern
  elseif opts.case == types.search_case.insensitive then
    vimgrep_pattern = '\\c' .. vimgrep_pattern
  end

  return { pattern = vimgrep_pattern, warning = M._format_warnings(warnings) }
end

--- Formats accumulated warnings into a single message.
---
---@param warnings string[] List of warning messages
---@return string|nil warning Formatted warning or nil if empty
function M._format_warnings(warnings)
  if #warnings == 0 then
    return nil
  elseif #warnings == 1 then
    return warnings[1]
  else
    return warnings[1] .. string.format(' (+%d more)', #warnings - 1)
  end
end

return M
