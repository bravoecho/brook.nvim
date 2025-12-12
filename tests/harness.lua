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

function M.eq(got, want)
  if got ~= want then
    local got_str = got == nil and 'nil' or string.format('%q', got)
    local want_str = want == nil and 'nil' or string.format('%q', want)
    error(string.format('\n  got:  %s\n  want: %s', got_str, want_str), 2)
  end
end

function M.eq_list(got, want)
  if got == nil and want == nil then
    return
  end

  if got == nil or want == nil or #got ~= #want then
    M._fail_inspect(got, want)
  end

  for i, v in ipairs(got) do
    if v ~= want[i] then
      M._fail_inspect(got, want)
    end
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
