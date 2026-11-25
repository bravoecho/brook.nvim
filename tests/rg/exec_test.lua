-- Run with:
--   nvim --headless -u NONE -c "set rtp+=." -c "luafile tests/rg/exec_test.lua" -c "q"
--
-- Runs ripgrep, which must be in $PATH.

local h = require('tests.harness')
local test = h.test
local deep_eq = h.deep_eq
local exec = require('brook.rg.exec')
local args_types = require('brook.args.types')

--- Runs the command brook builds in a directory holding a.txt and b.lua, and
--- parses each output line with the output format's parser.
---
---@param output_format brook.args.OutputFormat
---@param config string[] Lines of the ripgrep config file
---@param args string[] Arguments typed in :Rg
---@return table[] entries Quickfix entries, or the raw line where parsing fails
local function search(output_format, config, args)
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir)
  vim.fn.writefile({ 'x', 'hello there' }, dir .. '/a.txt')
  vim.fn.writefile({ 'x', '-- hello' }, dir .. '/b.lua')
  vim.fn.writefile(config, dir .. '/rgrc')

  local cmd = exec._build_rg_cmd({
    args = args,
    parsed_args = {
      patterns = {},
      fixed = false,
      word = false,
      multiline = false,
      pcre2 = false,
      raw = table.concat(args, ' '),
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

-- Flags that the base command overrides, in the ripgrep config file or in :Rg.
local overridden = {
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

local a_txt = { { filename = 'a.txt', lnum = 2, col = 1, text = 'hello there' } }

for _, output_format in pairs(args_types.output_format) do
  for _, flags in ipairs(overridden) do
    local name = #flags == 0 and 'no flags' or table.concat(flags, ' ')

    test('build_rg_cmd: ' .. output_format .. ', config ' .. name, function()
      local got = search(output_format, flags, { 'hello', 'a.txt' })
      deep_eq(got, a_txt)
    end)

    test('build_rg_cmd: ' .. output_format .. ', :Rg ' .. name, function()
      local got = search(output_format, {}, vim.list_extend(vim.deepcopy(flags), { 'hello', 'a.txt' }))
      deep_eq(got, a_txt)
    end)
  end

  test('build_rg_cmd: ' .. output_format .. ', overrides before the separator', function()
    local got = search(output_format, {}, { '--heading', '--', 'hello', 'a.txt' })
    deep_eq(got, a_txt)
  end)

  test('build_rg_cmd: ' .. output_format .. ', -- as an option value', function()
    local got = search(output_format, {}, { '--heading', '-e', '--', 'b.lua' })
    local want = { { filename = 'b.lua', lnum = 2, col = 1, text = '-- hello' } }
    deep_eq(got, want)
  end)
end

--------------------------------------------------------------------------------
--- Summary --------------------------------------------------------------------
--------------------------------------------------------------------------------

h.summary()
