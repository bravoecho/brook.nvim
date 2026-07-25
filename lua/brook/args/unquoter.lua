--- Shell-style unquoting: interpreting quoted tokens into plain strings.
---
--- By default, quotes are interpreted literally rather than with full POSIX
--- shell semantics; an opt-in strict mode reproduces POSIX rules exactly. See
--- brook.args.Quoting (types.lua) for the two available quoting modes.
---
--- Decouples from the user's shell and from Neovim's unquoting.
---
---@module 'brook.args.unquoter'

local M = {}

---@enum
local states = {
  NORMAL = 0,
  SINGLE = 1,
  DOUBLE = 2,
}

local SINGLE_QUOTE = "'"
local DOUBLE_QUOTE = '"'
local ESCAPE = '\\'

--- Unquotes a shell token, interpreting its quoting rules.
---
--- The purpose it to prepare the token to be passed to `vim.fn.jobstart()`.
---
--- This handles:
---   - Single-quoted strings: 'foo bar' => foo bar. With `quoting.literal`
---     (see types.lua) only \' is special, letting a literal single quote be
---     embedded without closing the token. All other backslash sequences
---     pass through literally. With `quoting.strict_posix`, no escapes apply
---     inside single quotes at all, matching real POSIX shells.
---   - Double-quoted strings: "foo bar" => foo bar. With `quoting.literal`
---     only \" is special; all other backslash sequences, including \$, \`,
---     and \\, pass through literally so ripgrep sees exactly what was
---     typed. With `quoting.strict_posix`, full POSIX escapes apply (\$,
---     \`, \", \\), matching what a real shell would produce.
---   - Backslash escapes outside quotes: foo\ bar => foo bar
---   - The POSIX idiom for single quotes: 'it'\''s' => it's (still works in
---     both modes, though with `quoting.literal`, \' inside the quotes
---     achieves the same result more directly)
---   - Mixed quoting: foo"bar"'baz' => foobarbaz
---
--- Returns nil for malformed input (unterminated quotes).
---
--- NOTE: This function reproduces the shell parsing layer, NOT a command's
--- internal escape processing (like 'echo -e'). For example, for input
--- `"foo\nbar"`, this function correctly returns the literal string "foo\nbar",
--- which is what the external command receives.
---
---@param token string The shell token to unquote
---@param quoting brook.args.Quoting Which characters are escapable, see types.lua
---@return string|nil unquoted_token The unquoted value, or nil if malformed
function M.unquote(token, quoting)
  local double_quote_escapes = quoting.double
  local single_quote_escapes = quoting.single
  local state = states.NORMAL
  local result = {}
  local len = #token
  local i = 1

  while i <= len do
    local ch = token:sub(i, i)
    local next_char = token:sub(i + 1, i + 1)

    if state == states.SINGLE then
      -- CASE 1: Inside single quotes: handle escapes (mirrors double quotes)
      ------------------------------------------------------------------------
      if ch == SINGLE_QUOTE then
        state = states.NORMAL -- close single quote
      elseif ch == ESCAPE and single_quote_escapes[next_char] then
        -- Escape: collect the next char and skip the backslash.
        table.insert(result, next_char)
        i = i + 1
      else
        -- Unrecognised escapes pass through literally, same as double quotes.
        table.insert(result, ch)
      end
    elseif state == states.DOUBLE then
      -- CASE 2: Inside a double quotes: handle escapes
      -------------------------------------------------
      if ch == DOUBLE_QUOTE then
        state = states.NORMAL -- close double quote
      elseif ch == ESCAPE and double_quote_escapes[next_char] then
        -- POSIX escape: collect the next char and skip the backslash.
        table.insert(result, next_char)
        i = i + 1
      else
        -- Unrecognised escapes (including \n) are preserved literally, the
        -- shell passes "backslash + n" to the command; interpretation is up to
        -- the receiving program.
        table.insert(result, ch)
      end
    else
      -- CASE 3: Normal mode (not quoted)
      -----------------------------------
      if ch == SINGLE_QUOTE then
        state = states.SINGLE
      elseif ch == DOUBLE_QUOTE then
        state = states.DOUBLE
      elseif ch == ESCAPE and i == len then
        -- Trailing backslash is malformed.
        return nil
      elseif ch == ESCAPE then
        -- Backslash escape outside quotes: next character is literal. Collect
        -- the next char and skip the backslash.
        table.insert(result, next_char)
        i = i + 1
      else
        -- Regular character.
        table.insert(result, ch)
      end
    end

    i = i + 1
  end

  if state ~= states.NORMAL then
    -- An unclosed quote is malformed.
    return nil
  end

  return table.concat(result)
end

--- Unquotes all tokens in a list.
---
--- Returns nil if any token is malformed (unterminated quotes).
---
---@param tokens string[]|nil List of shell tokens
---@param quoting brook.args.Quoting Which characters are escapable, see unquote
---@return string[]|nil unquoted_tokens List of unquoted values, or nil if any token is malformed
function M.unquote_all(tokens, quoting)
  if not tokens then
    return nil
  end

  local result = {}
  for _, token in ipairs(tokens) do
    local unquoted = M.unquote(token, quoting)
    if not unquoted then return nil end
    table.insert(result, unquoted)
  end
  return result
end

return M
