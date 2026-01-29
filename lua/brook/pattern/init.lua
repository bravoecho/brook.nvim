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

--- Result of pattern translation.
---
---@class brook.pattern.Result
---@field pattern string|nil The translated Vim regex (nil when unsupported)
---@field warning string|nil Warning message for adjustments or failures

--------------------------------------------------------------------------------

--- Translate ripgrep patterns to Vim regex.
---
--- Accepts a list of patterns (from multiple -e options or a single positional
--- argument). Each pattern is translated individually, then merged into an
--- alternation. This ensures word boundaries and other options apply correctly
--- to each pattern.
---
--- Returns result matching legacy interface with single formatted warning.
--- When translation fails, returns pattern = nil with warning explaining why.
---
---@param patterns string[] The ripgrep search patterns
---@param opts? brook.pattern.TranslateOpts Options affecting translation
---@return brook.pattern.Result
function M.rg_to_vim(patterns, opts)
  opts = opts or {}

  -- Filter empty patterns
  local filtered = {}
  for _, p in ipairs(patterns) do
    if p ~= '' then
      filtered[#filtered + 1] = p
    end
  end

  -- Empty list: nothing to translate
  if #filtered == 0 then
    return { pattern = nil, warning = nil }
  end

  -- Fixed mode: bypass pipeline entirely.
  -- No regex syntax to parse; just escape and wrap.
  if opts.fixed then
    return M._translate_fixed_merged(filtered, opts)
  end

  -- Translate each pattern individually, then merge
  return M._translate_and_merge(filtered, opts)
end

--------------------------------------------------------------------------------
--- Pattern Merging ------------------------------------------------------------
--------------------------------------------------------------------------------

--- Translate multiple patterns and merge into alternation.
---
--- Each pattern is translated independently with full options applied,
--- then results are merged by joining the pattern bodies with |.
---
---@param patterns string[] Non-empty list of patterns
---@param opts brook.pattern.TranslateOpts Translation options
---@return brook.pattern.Result
function M._translate_and_merge(patterns, opts)
  local bodies = {}
  local all_warnings = {}
  local prefix = nil

  for _, pattern in ipairs(patterns) do
    -- Phase 1: tokenise
    local tokens = tokeniser.tokenise(pattern)

    -- Phase 2: parse
    local parse_result = parser.parse(tokens)

    -- Phase 3: translate
    local trans_result = translator.translate(
      parse_result.tokens or {},
      opts,
      parse_result.warnings,
      parse_result.error
    )

    -- Collect warnings
    if trans_result.warnings then
      for _, w in ipairs(trans_result.warnings) do
        all_warnings[#all_warnings + 1] = w
      end
    end

    -- Handle errors: bail on first error
    if trans_result.error then
      table.insert(all_warnings, 1, trans_result.error)
      return {
        pattern = nil,
        warning = M._format_warnings(all_warnings),
      }
    end

    -- Extract prefix and body from translated pattern
    local p_prefix, p_body = M._split_prefix(trans_result.pattern)

    -- All patterns should have the same prefix (same opts)
    if prefix == nil then
      prefix = p_prefix
    end

    bodies[#bodies + 1] = p_body
  end

  -- Merge bodies with alternation
  local merged = prefix .. table.concat(bodies, '|')

  return {
    pattern = merged,
    warning = M._format_warnings(all_warnings),
  }
end

--- Split a translated pattern into prefix and body.
---
--- Prefix consists of optional case modifier (\c or \C) followed by
--- magic mode (\v, \V, \m, \M). Body is everything after.
---
---@param pattern string Translated Vim regex
---@return string prefix The mode/case prefix
---@return string body The pattern body
function M._split_prefix(pattern)
  -- Match optional case modifier + required magic mode
  local prefix, body = pattern:match('^(\\[cC]?\\[vVmM])(.*)')
  if prefix then
    return prefix, body
  end

  -- Just magic mode, no case modifier
  prefix, body = pattern:match('^(\\[vVmM])(.*)')
  if prefix then
    return prefix, body
  end

  -- No recognised prefix (shouldn't happen with our translator)
  return '', pattern
end

--------------------------------------------------------------------------------
--- Fixed Mode -----------------------------------------------------------------
--------------------------------------------------------------------------------

--- Translate literal patterns (fixed-string mode) with merging.
---
--- Uses very-nomagic mode (\V) where only backslash and search delimiter
--- need escaping. Multiple patterns are joined with \| (literal alternation
--- in \V mode). No tokenisation or parsing required.
---
---@param patterns string[] The literal search strings
---@param opts brook.pattern.TranslateOpts Translation options
---@return brook.pattern.Result
function M._translate_fixed_merged(patterns, opts)
  local escaped = {}
  for _, p in ipairs(patterns) do
    -- Escape backslashes and forward slashes
    local esc = p:gsub('\\', '\\\\'):gsub('/', '\\/')

    -- Wrap with word boundaries if requested
    if opts.word then
      esc = '\\<' .. esc .. '\\>'
    end

    escaped[#escaped + 1] = esc
  end

  -- Join with \| (alternation in \V mode)
  local body = table.concat(escaped, '\\|')

  -- Build prefix: case modifier (if any) + \V
  local prefix = '\\V'
  if opts.case == 'case-sensitive' then
    prefix = '\\C' .. prefix
  elseif opts.case == 'case-insensitive' then
    prefix = '\\c' .. prefix
  end

  return { pattern = prefix .. body, warning = nil }
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
