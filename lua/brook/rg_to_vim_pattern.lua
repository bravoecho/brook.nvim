local M = {}

--- Translates a ripgrep pattern to Vim regex syntax.
---
--- Best-effort translation to support results highlighting and navigation.
--- Targets very magic mode (\v) for closer semantic alignment with ripgrep's
--- Rust regex syntax.
---
---@param pattern string The ripgrep search pattern
---@param opts? brook.SearchOpts Options affecting pattern translation
---@return string|nil vim_pattern The translated Vim regex pattern, nil when pattern is unsupported.
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
      elseif next_char == 'B' then
        -- Non-word boundary: unsupported
        return nil
      elseif next_char == 'B' then
        -- Non-word boundary: unsupported
        return nil
      elseif next_char == 'A' or next_char == 'z' then
        -- String anchors: unsupported
        return nil
      elseif next_char == 'p' or next_char == 'P' then
        -- Unicode categories: unsupported
        return nil
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
      -- Handle it as an independent subsequence.
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
      -- Possessive quantifiers: unsupported by Neovim
      return nil
    elseif char == '(' and next_char == '?' and not in_char_class then
      local third_char = pattern:sub(i + 2, i + 2)
      if third_char == ':' then
        -- Non-capturing group: (?:...) -> %(...)
        table.insert(result, '%(')
        i = i + 3 -- skip (?:
      else
        -- Lookarounds, atomic groups, named groups: unsupported either because
        -- the don't have a Neovim correspondent, or because they are complex
        -- and niche.
        return nil
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

  return vimgrep_pattern
end

return M
