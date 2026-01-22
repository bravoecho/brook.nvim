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

local tokeniser = require('brook.pattern.tokeniser')
local parser = require('brook.pattern.parser')
local translator = require('brook.pattern.translator')

--------------------------------------------------------------------------------
--- Public API -----------------------------------------------------------------
--------------------------------------------------------------------------------

--- Translate a ripgrep pattern to Vim regex.
---
--- Returns result matching legacy interface with single formatted warning.
---
---@param pattern string The ripgrep search pattern
---@param opts? brook.pattern.TranslateOpts Options affecting translation
---@return brook.pattern.TranslateResult
function M.rg_to_vim(pattern, opts)
  opts = opts or {}

  -- TODO: wire up tokeniser, parser and translator when implemented

  return { pattern = '\\v', error = nil, warning = nil }
end

--------------------------------------------------------------------------------
--- Helpers --------------------------------------------------------------------
--------------------------------------------------------------------------------

--- Format collected warnings into a single string.
--- Shows first warning and count of additional warnings.
---@param warnings string[] List of warning messages
---@return string? Formatted warning or nil if empty
function M._format_warnings(warnings)
  if #warnings == 0 then
    return nil
  end

  local first = warnings[1]
  if #warnings == 1 then
    return first
  end

  return first .. ' (+' .. (#warnings - 1) .. ' more)'
end

return M
