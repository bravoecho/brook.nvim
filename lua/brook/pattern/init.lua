-- lua/brook/pattern/init.lua

--- Pattern translation pipeline: ripgrep regex => Vim "very magic" regex.
---
--- Three-phase architecture:
---
---   1. Tokenise - Lexical analysis: identify token boundaries
---   2. Parse - Semantic analysis: classify, validate, annotate
---   3. Translate - Code generation: emit Vim regex
---
--- This module provides the public API that wraps the pipeline.
---
---@module 'brook.pattern'
local M = {}

local translator = require('brook.pattern.translator')

--------------------------------------------------------------------------------
--- Warning Formatting ---------------------------------------------------------
--------------------------------------------------------------------------------

--- Format collected warnings into a single string.
--- Shows first warning and count of additional warnings.
---@param warnings string[] List of warning messages
---@return string? Formatted warning or nil if empty
local function format_warnings(warnings)
  if #warnings == 0 then
    return nil
  end

  local first = warnings[1]
  if #warnings == 1 then
    return first
  end

  return first .. ' (+' .. (#warnings - 1) .. ' more)'
end

--------------------------------------------------------------------------------
--- Public API -----------------------------------------------------------------
--------------------------------------------------------------------------------

--- Translate a ripgrep pattern to Vim regex.
---
--- Returns result matching legacy interface with single formatted warning.
---
---@param pattern string The ripgrep search pattern
---@param opts? brook.pattern.PatternOpts Options affecting translation
---@return brook.pattern.TranslateResult
function M.rg_to_vim(pattern, opts)
  opts = opts or {}

  -- TODO: wire up tokeniser and parser when implemented
  -- For now, this is a stub that assumes tokens are provided externally

  -- Placeholder: return empty pattern
  -- Real implementation will be:
  --   local tokens = tokeniser.tokenise(pattern)
  --   local parsed = parser.parse(tokens)
  --   if parsed.error then
  --     return { pattern = nil, warning = parsed.error }
  --   end
  --   local result = translator.translate(parsed.tokens, opts)
  --   return {
  --     pattern = result.pattern,
  --     warning = format_warnings(result.warnings),
  --   }

  return { pattern = '\\v', warning = nil }
end

--- Translate pre-parsed tokens to Vim regex.
---
--- Lower-level API for when tokens are already available.
--- Returns result matching legacy interface with single formatted warning.
---
---@param tokens brook.pattern.Token[] Annotated tokens from parser
---@param opts? brook.pattern.PatternOpts Options affecting translation
---@return brook.pattern.TranslateResult
function M.translate(tokens, opts)
  local result = translator.translate(tokens, opts or {})
  return {
    pattern = result.pattern,
    warning = format_warnings(result.warnings),
  }
end

return M
