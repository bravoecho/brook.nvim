local M = {}

--- Translates a ripgrep pattern to Vim regex syntax.
---
--- Best-effort translation to support results highlighting and navigation.
--- Targets very magic mode (\v) for closer semantic alignment with ripgrep's
--- Rust regex syntax.
---
---@param pattern string The ripgrep search pattern
---@param opts? brook.SearchOpts Options affecting pattern translation
---@return string vim_pattern The translated Vim regex pattern
function M._rg_to_vim_pattern(pattern, opts)
  opts = opts or {}

  -- For literal (fixed-string) searches, use very-nomagic mode (\V).
  -- Only backslash and the search delimiter (/) need escaping.
  if opts.fixed then
    local escaped = pattern:gsub('\\', '\\\\'):gsub('/', '\\/')
    if opts.word then
      return '\\V\\<' .. escaped .. '\\>'
    end
    return '\\V' .. escaped
  end

  local result = {}
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
    elseif (char == '*' or char == '+' or char == '?')
        and next_char == '?'
        and not in_char_class
        and i > 1 then
      -- Non-greedy quantifier: *? +? ?? (as long as it's not the first
      -- character).
      if char == '*' then
        table.insert(result, '{-}')
      elseif char == '+' then
        table.insert(result, '{-1,}')
      else -- char == '?'
        table.insert(result, '{-0,1}')
      end
      i = i + 2
    elseif char == '/' then
      -- Escape search delimiter
      table.insert(result, '\\/')
      i = i + 1
    else
      -- Everything else passes through unchanged
      table.insert(result, char)
      i = i + 1
    end
  end

  local vimgrep_pattern = '\\v' .. table.concat(result)

  if opts.word then
    vimgrep_pattern = '\\v<' .. table.concat(result) .. '>'
  end

  return vimgrep_pattern
end

return M
