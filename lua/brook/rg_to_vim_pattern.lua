-- Some ripgrep metacharacters are instead literals in vimgrep.
local vim_magic_literals = {
  ['+'] = true,
  ['?'] = true,
  ['('] = true,
  [')'] = true,
  ['{'] = true,
  ['}'] = true,
  ['|'] = true,
}

local M = {}

--- Translates a ripgrep pattern to Vim regex syntax.
---
--- Best-effort translation to support results highlighting and navigation.
--- Only handles patterns that commonly appear in code searches.
---
---@param pattern string The ripgrep search pattern
---@param opts? brook.SearchOpts Options affecting pattern translation
---@return string vim_pattern The translated Vim regex pattern
function M._rg_to_vim_pattern(pattern, opts)
  opts = opts or {}

  -- For literal (fixed-string) searches, translate to very-no-magic mode.
  -- In very-no-magic mode, only backslash and delimiter (forward slash) need to
  -- be escaped.
  if opts.fixed then
    local escaped = pattern:gsub('\\', '\\\\'):gsub('/', '\\/')
    local vimgrep_pattern = '\\V' .. escaped
    if opts.word then
      vimgrep_pattern = '\\<' .. vimgrep_pattern .. '\\>'
    end
    return vimgrep_pattern
  end

  -- a list of individual characters and metacharacters that will be joined at
  -- the end
  local result = {}
  local len = #pattern
  -- used to track whether we are parsing the symbols inside a character class
  -- of the given regex, because escaping rules change in that case
  local in_char_class = false
  -- the parsing cursor
  local i = 1

  while i <= len do
    local char = pattern:sub(i, i)
    local next_char = pattern:sub(i + 1, i + 1)

    if char == '\\' and next_char ~= '' then
      -- this is an escaped character, handling it as a unit
      local escaped_char = next_char

      if in_char_class then
        table.insert(result, '\\')
        table.insert(result, escaped_char)
      elseif vim_magic_literals[escaped_char] then
        -- some ripgrep metacharacters need to be escaped to be considered
        -- metacharacters in vimgrep
        table.insert(result, escaped_char)
      elseif escaped_char == 'b' then
        -- we support word boundaries only at the beginning and end of the
        -- pattern
        if i == 1 then
          table.insert(result, '\\<')
        else
          table.insert(result, '\\>')
        end
      elseif escaped_char == '\\' then
        table.insert(result, '\\\\')
      else
        -- pass through the other metacharacters, which work the same in ripgrep
        -- and vimgrep
        table.insert(result, '\\')
        table.insert(result, escaped_char)
      end
      i = i + 2
    elseif char == '[' and not in_char_class then
      -- We have detected the beginning of a character class in the ripgrep
      -- pattern. Character classes boundaries are literal in both ripgrep and
      -- vimgrep.
      --
      -- 1. mark the start of the character class processing section
      in_char_class = true
      -- 2. add it as-is to the vimgrep pattern
      table.insert(result, '[')
      -- 3. advance the cursor
      i = i + 1

      -- Handle special situations in the first one or two positions of
      -- a character class:
      --
      -- * negation '^'
      -- * litaral, unescaped ']'
      -- * negated literal bracket '^]`
      if pattern:sub(i, i) == '^' then
        table.insert(result, '^')
        i = i + 1
      end
      if pattern:sub(i, i) == ']' then
        table.insert(result, ']')
        i = i + 1
      end
    elseif char == ']' and in_char_class then
      -- we have detected the end of a character class pattern
      in_char_class = false
      table.insert(result, ']')
      i = i + 1
    elseif vim_magic_literals[char] and not in_char_class then
      -- handle ripgrep metacharacters that need to be escaped to be interpreted
      -- as vimgrep metacharacters
      table.insert(result, '\\')
      table.insert(result, char)
      i = i + 1
    elseif char == '/' then
      -- escape the search delimiter
      table.insert(result, '\\')
      table.insert(result, '/')
      i = i + 1
    else
      table.insert(result, char)
      i = i + 1
    end
  end

  local vimgrep_pattern = table.concat(result)

  if opts.word then
    vimgrep_pattern = '\\<' .. vimgrep_pattern .. '\\>'
  end

  return vimgrep_pattern
end

return M
