-- lua/brook/pattern/init.lua

--- Pattern translation pipeline: ripgrep regex => Vim "very magic" regex.
---
--- Three-phase architecture:
---
---   1. Tokenise: lexical analysis, identify token boundaries
---   2. Parse: semantic analysis, classify, validate, annotate
---   3. Translate: code generation, emit Vim regex
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
--- When translation fails, returns pattern = nil with warning explaining why.
---
---@param pattern string The ripgrep search pattern
---@param opts? brook.pattern.TranslateOpts Options affecting translation
---@return brook.pattern.TranslateResult
function M.rg_to_vim(pattern, opts)
  opts = opts or {}

  -- Fixed mode: bypass pipeline entirely.
  -- No regex syntax to parse; just escape and wrap.
  if opts.fixed then
    return M._translate_fixed(pattern, opts)
  end

  -- Phase 1: tokenise
  local tokens = tokeniser.tokenise(pattern)

  -- Phase 2: parse
  local parse_result = parser.parse(tokens)

  -- Phase 3: translate (forward warnings and error from parser)
  local trans_result = translator.translate(
    parse_result.tokens or {},
    opts,
    parse_result.warnings,
    parse_result.error
  )

  -- Handle errors: demote to warning, return nil pattern
  if trans_result.error then
    local all_warnings = trans_result.warnings or {}
    table.insert(all_warnings, 1, trans_result.error)
    return {
      pattern = nil,
      warning = M._format_warnings(all_warnings),
    }
  end

  return {
    pattern = trans_result.pattern,
    warning = M._format_warnings(trans_result.warnings or {}),
  }
end

--------------------------------------------------------------------------------
--- Fixed Mode -----------------------------------------------------------------
--------------------------------------------------------------------------------

--- Translate a literal pattern (fixed-string mode).
---
--- Uses very-nomagic mode (\V) where only backslash and search delimiter
--- need escaping. No tokenisation or parsing required.
---
---@param pattern string The literal search string
---@param opts brook.pattern.TranslateOpts Translation options
---@return brook.pattern.TranslateResult
function M._translate_fixed(pattern, opts)
  -- Escape backslashes and forward slashes
  pattern = pattern:gsub('\\', '\\\\'):gsub('/', '\\/')

  -- Wrap with word boundaries if requested
  if opts.word then
    pattern = '\\<' .. pattern .. '\\>'
  end

  -- Build prefix: case modifier (if any) + \V
  local prefix = '\\V'
  if opts.case == 'case-sensitive' then
    prefix = '\\C' .. prefix
  elseif opts.case == 'case-insensitive' then
    prefix = '\\c' .. prefix
  end

  return { pattern = prefix .. pattern, warning = nil }
end

--------------------------------------------------------------------------------
--- Helpers --------------------------------------------------------------------
--------------------------------------------------------------------------------

--- Format collected warnings into a single string.
--- Shows first warning and count of additional warnings.
---
---@param warnings string[] List of warning messages
---@return string|nil Formatted warning or nil if empty
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
