-- Benchmark: setqflist with parsed entries vs raw lines + efm
--
-- Run with:
--   nvim --headless -c "luafile bench_setqflist.lua" -c "q"

local N = 10000
local RUNS = 10

--------------------------------------------------------------------------------
--- Generate fake vimgrep lines ------------------------------------------------
--------------------------------------------------------------------------------

local function generate_lines(count)
  local lines = {}
  for i = 1, count do
    -- Simulate realistic paths and content
    local depth = (i % 4) + 1
    local path_parts = {}
    for d = 1, depth do
      table.insert(path_parts, string.format('dir%d', (i + d) % 10))
    end
    table.insert(path_parts, string.format('file%d.lua', i % 100))
    local path = table.concat(path_parts, '/')

    local lnum = (i % 500) + 1
    local col = (i % 80) + 1
    local text = string.format('local result_%d = some_function(%d, "arg")', i, i * 2)

    table.insert(lines, string.format('%s:%d:%d:%s', path, lnum, col, text))
  end
  return lines
end

--------------------------------------------------------------------------------
--- Parsing approach (current implementation) ----------------------------------
--------------------------------------------------------------------------------

local function parse_line(vimgrep_result)
  local filename, lnum, col, text = vimgrep_result:match('([^:]+):(%d+):(%d+):(.*)')
  if not filename then
    return nil
  end
  return {
    filename = filename,
    lnum = tonumber(lnum),
    col = tonumber(col),
    text = text,
  }
end

local function bench_parsed(lines)
  local entries = {}
  for _, line in ipairs(lines) do
    local entry = parse_line(line)
    if entry then
      table.insert(entries, entry)
    end
  end
  vim.fn.setqflist({}, 'r')
  vim.fn.setqflist(entries, 'a')
end

--------------------------------------------------------------------------------
--- Raw lines + efm approach ---------------------------------------------------
--------------------------------------------------------------------------------

local function bench_efm(lines)
  vim.fn.setqflist({}, 'r')
  vim.fn.setqflist({}, 'a', {
    lines = lines,
    efm = '%f:%l:%c:%m',
  })
end

--------------------------------------------------------------------------------
--- Benchmark harness ----------------------------------------------------------
--------------------------------------------------------------------------------

local function measure(name, fn, lines)
  -- Warm-up run
  fn(lines)
  vim.fn.setqflist({}, 'r')

  local times = {}
  for _ = 1, RUNS do
    local start = vim.loop.hrtime()
    fn(lines)
    local elapsed = (vim.loop.hrtime() - start) / 1e6 -- convert to ms
    table.insert(times, elapsed)
    vim.fn.setqflist({}, 'r')
  end

  table.sort(times)
  local sum = 0
  for _, t in ipairs(times) do
    sum = sum + t
  end

  return {
    name = name,
    mean = sum / #times,
    min = times[1],
    max = times[#times],
    median = times[math.ceil(#times / 2)],
  }
end

local function format_result(r)
  return string.format(
    '%-20s  mean: %7.2f ms  median: %7.2f ms  min: %7.2f ms  max: %7.2f ms',
    r.name, r.mean, r.median, r.min, r.max
  )
end

--------------------------------------------------------------------------------
--- Main -----------------------------------------------------------------------
--------------------------------------------------------------------------------

print(string.format('\nBenchmarking setqflist: %d entries, %d runs each\n', N, RUNS))

local lines = generate_lines(N)
print(string.format('Generated %d fake vimgrep lines\n', #lines))

local results = {
  measure('parsed entries', bench_parsed, lines),
  measure('raw lines + efm', bench_efm, lines),
}

print('Results:')
print(string.rep('-', 78))
for _, r in ipairs(results) do
  print(format_result(r))
end
print(string.rep('-', 78))

local diff = results[1].mean - results[2].mean
local pct = (diff / results[1].mean) * 100
if diff > 0 then
  print(string.format('\nefm is %.1f%% faster (%.2f ms saved per call)', pct, diff))
else
  print(string.format('\nparsed is %.1f%% faster (%.2f ms saved per call)', -pct, -diff))
end

print()
