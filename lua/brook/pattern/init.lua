-- This file: lua/brook/pattern/init.lua

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

-- TODO: Wire up the pipeline once all phases are implemented.
-- For now, this module exists to establish the directory structure.

return M
