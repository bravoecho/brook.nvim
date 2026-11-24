-- Run with:
--   nvim --headless -u NONE -c "set rtp+=." -c "luafile tests/rg/exec_test.lua" -c "q"

local h = require('tests.harness')
local test = h.test
local deep_eq = h.deep_eq
local exec = require('brook.rg.exec')
local args_types = require('brook.args.types')

--- Search context for the given output format, searching for `foo` in a single
--- file.
---@param output_format brook.args.OutputFormat
---@return brook.SearchContext
local function ctx(output_format)
  return {
    args = { 'foo', 'file.txt' },
    parsed_args = {
      patterns = { 'foo' },
      fixed = false,
      word = false,
      case = nil,
      output_format = nil,
      multiline = false,
      pcre2 = false,
      raw = 'foo file.txt',
    },
    cfg = {
      max_preview_chars = 200,
      output_format = output_format,
    },
  }
end

--------------------------------------------------------------------------------
--- _build_rg_cmd --------------------------------------------------------------
--------------------------------------------------------------------------------

for _, output_format in pairs(args_types.output_format) do
  test('build_rg_cmd: --with-filename in ' .. output_format .. ' mode', function()
    local cmd = exec._build_rg_cmd(ctx(output_format))
    local got = vim.tbl_contains(cmd, '--with-filename')
    local want = true
    deep_eq(got, want)
  end)
end

--------------------------------------------------------------------------------
--- Summary --------------------------------------------------------------------
--------------------------------------------------------------------------------

h.summary()
