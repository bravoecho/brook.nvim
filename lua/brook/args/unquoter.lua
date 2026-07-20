--- POSIX shell unquoting: interpreting quoted tokens into plain strings.
---
--- Decouples from the user's shell and from Neovim's unquoting.
---
---@module 'brook.args.unquoter'

local M = {}

--- The set of characters that can be escaped inside double quotes, by mode.
---
--- `literal` (the default) is deliberately narrower than POSIX shells (which
--- also treat \$, \`, and \\ as escapes): Brook never spawns a shell, so
--- there is no variable interpolation or command substitution to guard
--- against, and those extra escapes only caused backslashes meant for
--- ripgrep's own regex syntax (e.g. \$ for a literal dollar sign) to be
--- silently stripped. The only thing that still needs escaping is the
--- delimiter itself, so double quotes behave exactly like single quotes
--- except that \" can be used to embed a literal double quote without
--- closing the token.
---
--- `strict_posix` reproduces full POSIX shell semantics, so a token copied
--- from (or destined for) an actual shell round-trips exactly, at the cost
--- of reintroducing the \$/\`-swallowing surprise for regex patterns. Opt in
--- via the `strict_posix_quoting` setup option.
local DOUBLE_QUOTE_ESCAPES = {
  literal = {
    ['"'] = true,
  },
  strict_posix = {
    ['$'] = true,
    ['`'] = true,
    ['"'] = true,
    ['\\'] = true,
  },
}

---@enum
local states = {
  NORMAL = 0,
  SINGLE = 1,
  DOUBLE = 2,
}

local SINGLE_QUOTE = "'"
local DOUBLE_QUOTE = '"'
local ESCAPE = '\\'

--- Unquotes a shell token, interpreting POSIX shell quoting rules.
---
--- The purpose it to prepare the token to be passed to `vim.fn.jobstart()`.
---
--- This handles:
---   - Single-quoted strings: 'foo bar' => foo bar (no escapes inside)
---   - Double-quoted strings: "foo bar" => foo bar. By default (`strict` =
---     false) only \" is special; all other backslash sequences, including
---     \$, \`, and \\, pass through literally so ripgrep sees exactly what
---     was typed. With `strict` = true, full POSIX escapes apply (\$, \`,
---     \", \\), matching what a real shell would produce.
---   - Backslash escapes outside quotes: foo\ bar => foo bar
---   - The POSIX idiom for single quotes: 'it'\''s' => it's
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
---@param strict? boolean Use full POSIX double-quote escapes (\$, \`, \", \\)
---  instead of the default, regex-friendly literal mode (only \")
---@return string|nil unquoted_token The unquoted value, or nil if malformed
function M.posix_unquote(token, strict)
  local double_quote_escapes = strict and DOUBLE_QUOTE_ESCAPES.strict_posix or DOUBLE_QUOTE_ESCAPES.literal
  local state = states.NORMAL
  local result = {}
  local len = #token
  local i = 1

  while i <= len do
    local ch = token:sub(i, i)
    local next_char = token:sub(i + 1, i + 1)

    if state == states.SINGLE then
      -- CASE 1: Inside single quotes: no escaping, all characters are literal
      ------------------------------------------------------------------------
      if ch == SINGLE_QUOTE then
        state = states.NORMAL -- close single quote
      else
        -- Regular character.
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
---@param strict? boolean Use full POSIX double-quote escapes, see posix_unquote
---@return string[]|nil unquoted_tokens List of unquoted values, or nil if any token is malformed
function M.posix_unquote_all(tokens, strict)
  if not tokens then
    return nil
  end

  local result = {}
  for _, token in ipairs(tokens) do
    local unquoted = M.posix_unquote(token, strict)
    if not unquoted then return nil end
    table.insert(result, unquoted)
  end
  return result
end

return M
