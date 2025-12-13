-- tests/harness.lua
local M = {}

local tests_run = 0
local tests_passed = 0

function M.test(name, fn)
  tests_run = tests_run + 1
  local ok, err = pcall(fn)
  if ok then
    tests_passed = tests_passed + 1
    print('✓ ' .. name)
  else
    print('✗ ' .. name)
    print('  ' .. err)
  end
end

-- function M.eq(got, want)
--   if got ~= want then
--     local got_str = got == nil and 'nil' or string.format('%q', got)
--     local want_str = want == nil and 'nil' or string.format('%q', want)
--     error(string.format('\n  got:  %s\n  want: %s', got_str, want_str), 2)
--   end
-- end

local function display_string(s)
  if s == nil then return 'nil' end
  -- Only escape control characters and non-printables
  return (s:gsub('[%c]', function(c)
    local b = string.byte(c)
    if c == '\n' then
      return '\\n'
    elseif c == '\t' then
      return '\\t'
    elseif c == '\r' then
      return '\\r'
    else
      return string.format('\\x%02x', b)
    end
  end))
end

function M.eq(got, want)
  if got ~= want then
    error(string.format('\n  got:  %s\n  want: %s', display_string(got), display_string(want)), 2)
  end
end

function M.deep_eq(got, want)
  if not vim.deep_equal(got, want) then
    M._fail_inspect(got, want)
  end
end

function M._fail_inspect(got, want)
  error(string.format('\n  got:  %s\n  want: %s', vim.inspect(got), vim.inspect(want)), 2)
end

function M.summary()
  print(string.format('\n%d/%d tests passed', tests_passed, tests_run))

  if tests_passed == tests_run then
    print('All tests passed\n')
    vim.cmd('cquit 0')
  else
    print('Some tests failed\n')
    vim.cmd('cquit 1')
  end
end

return M
