-- tests/harness.lua
local M = {}

local tests_run = 0
local tests_passed = 0

-- Capture the call site info before running the test
local current_test_info = {
  test_file = nil,
  test_line = nil,
}

function M.test(name, fn)
  tests_run = tests_run + 1

  -- Capture where the test was defined
  local test_info = debug.getinfo(2, 'Sl')
  current_test_info = {
    test_file = test_info.short_src,
    test_line = test_info.currentline,
  }

  local ok, err = xpcall(fn, function(msg)
    -- msg is our structured error table from eq/deep_eq
    if type(msg) == 'table' and msg._assertion_error then
      return msg
    end
    -- For unexpected errors, capture a traceback
    return { _unexpected = true, message = debug.traceback(msg, 2) }
  end)

  if ok then
    tests_passed = tests_passed + 1
    print('✓ ' .. name)
  else
    print('✗ ' .. name)
    if err._unexpected then
      print(err.message)
    else
      print(string.format('\t--> test:        %s:%d', err.test_file, err.test_line))
      print(string.format('\t--> expectation: %s:%d', err.assert_file, err.assert_line))
      if err.err_msg then
        print(string.format('\t--> message:     %s:%d', err.err_msg))
      end
      print('  got:')
      print(M._indent(err.got_str, '    '))
      print('  want:')
      print(M._indent(err.want_str, '    '))
    end
  end

  current_test_info = nil
end

---@generic T
---@param got T
---@param want T
---@param msg? string
function M.eq(got, want, msg)
  if got ~= want then
    M._raise_assertion_error(M._display_string(got), M._display_string(want), msg)
  end
end

---@generic T
---@param got T
---@param want T
---@param msg? string
function M.deep_eq(got, want, msg)
  if not vim.deep_equal(got, want) then
    M._raise_assertion_error(vim.inspect(got), vim.inspect(want), msg)
  end
end

function M._display_string(s)
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

function M._indent(s, prefix)
  local lines = {}
  for line in (s .. '\n'):gmatch('([^\n]*)\n') do
    table.insert(lines, prefix .. line)
  end
  return table.concat(lines, '\n')
end

function M._raise_assertion_error(got_str, want_str, msg)
  -- Capture where the assertion was called (2 levels up: raise -> eq/deep_eq -> test code)
  local info = debug.getinfo(3, 'Sl')
  error({
    _assertion_error = true,
    test_file = current_test_info.test_file,
    test_line = current_test_info.test_line,
    assert_file = info.short_src,
    assert_line = info.currentline,
    got_str = got_str,
    want_str = want_str,
    err_msg = msg,
  }, 0) -- level 0 prevents Lua from adding location prefix
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
