-- Run with:
--   nvim --headless -u NONE -c "set rtp+=." -c "luafile tests/rg/exec_test.lua" -c "q"
--
-- Runs ripgrep, which must be in $PATH.

local h = require('tests.harness')
local test = h.test
local deep_eq = h.deep_eq
local exec = require('brook.rg.exec')
local args_types = require('brook.args.types')

--- Searches a single file with the command brook builds, and parses each output
--- line with the output format's parser.
---
---@param output_format brook.args.OutputFormat
---@param config string[] Lines of the ripgrep config file
---@return table[] entries Quickfix entries, or the raw line where parsing fails
local function search(output_format, config)
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir)
  vim.fn.writefile({ 'x', 'hello there' }, dir .. '/a.txt')
  vim.fn.writefile(config, dir .. '/rgrc')

  local cmd = exec._build_rg_cmd({
    args = { 'hello', 'a.txt' },
    parsed_args = {
      patterns = { 'hello' },
      fixed = false,
      word = false,
      multiline = false,
      pcre2 = false,
      raw = 'hello a.txt',
    },
    cfg = { max_preview_chars = 200, output_format = output_format },
  })
  local res = vim.system(cmd, {
    cwd = dir,
    env = { RIPGREP_CONFIG_PATH = dir .. '/rgrc' },
    text = true,
  }):wait(5000)
  vim.fn.delete(dir, 'rf')

  local parse = output_format == args_types.output_format.unique_lines
      and exec._parse_line_number
      or exec._parse_vimgrep
  local entries = {}
  for _, line in ipairs(vim.split(res.stdout or '', '\n', { trimempty = true })) do
    table.insert(entries, parse(line) or line)
  end
  return entries
end

--------------------------------------------------------------------------------
--- _build_rg_cmd --------------------------------------------------------------
--------------------------------------------------------------------------------

-- Flags in the ripgrep config file that the base command overrides.
local configs = {
  {},
  { '--no-filename' },
  { '--no-line-number' },
  { '--heading' },
  { '--column' },
  { '--no-column' },
  { '--stats' },
  { '--json' },
  { '--pretty' },
  { '--color=always' },
  { '--field-match-separator=:' },
}

for _, output_format in pairs(args_types.output_format) do
  for _, config in ipairs(configs) do
    local name = #config == 0 and 'no config' or table.concat(config, ' ')
    test('build_rg_cmd: single file, ' .. output_format .. ', ' .. name, function()
      local got = search(output_format, config)
      local want = { { filename = 'a.txt', lnum = 2, col = 1, text = 'hello there' } }
      deep_eq(got, want)
    end)
  end
end

--------------------------------------------------------------------------------
--- Summary --------------------------------------------------------------------
--------------------------------------------------------------------------------

h.summary()
