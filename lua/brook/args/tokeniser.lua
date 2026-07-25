--- Shell-style tokenisation: splitting a command string into logical arguments
--- (beyond the whitespace-based splitting provided by Neovim for user commands.)
---
--- See also the companion module unquoter.lua
---
---@module 'brook.tokeniser'
local M = {}

local SINGLE_QUOTE = "'"
local DOUBLE_QUOTE = '"'
local ESCAPE = '\\'

--- Tokenises a command-line string into individual arguments.
---
--- Splits the input string on whitespace while respecting shell quoting rules:
---   - Single-quoted strings: 'foo bar' is a single token
---   - Double-quoted strings: "foo bar" is a single token
---   - Backslash escapes: foo\ bar is a single token (outside single quotes)
---   - Escaped quotes: by default (`strict` = false), a backslash-escaped
---     quote character does not close its enclosing quotes, in both single-
---     and double-quoted tokens (e.g. 'it\'s' or "say \"hi\""), matching the
---     default literal unquoting mode. With `strict` = true, backslash has no
---     special meaning inside single quotes, matching real POSIX shells.
---   - POSIX single-quote escape: 'it'\''s' is a single token (in both modes)
---
--- Quotes and escapes are preserved in the output tokens; use unquote
--- to interpret them.
---
--- See:
---   - https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html#tag_18_06_07
---   - https://www.gnu.org/software/bash/manual/html_node/Quote-Removal.html
---
---@param qargs string The raw command-line string to tokenise
---@param strict? boolean Match real POSIX shells: no escapes inside single
---  quotes. Should mirror the `strict_posix_quoting` setup option, see
---  unquote.
---@return string[] tokens List of tokens (may be empty if input is blank)
function M.tokenise(qargs, strict)
  qargs = vim.trim(qargs)
  local tokens = {}
  local current = {}
  local i = 1
  local len = #qargs

  --- Emits the current token buffer to the tokens list and resets it.
  local emit = function()
    if #current > 0 then
      table.insert(tokens, table.concat(current))
      current = {}
    end
  end

  local in_single = false
  local in_double = false
  local escaped = false

  while i <= len do
    local ch = qargs:sub(i, i)

    if ch:match('%s') and not in_single and not in_double and not escaped then
      -- this is a delimiter space: discard it and emit the token
      emit()
    else
      -- collect everything else
      table.insert(current, ch)

      -- update state for the next iteration
      if escaped then
        escaped = false
      elseif ch == ESCAPE and (not in_single or not strict) then
        escaped = true
      elseif ch == SINGLE_QUOTE and not in_double then
        in_single = not in_single
      elseif ch == DOUBLE_QUOTE and not in_single then
        in_double = not in_double
      end
    end

    i = i + 1
  end

  -- emit the final token
  emit()

  return tokens
end

return M
