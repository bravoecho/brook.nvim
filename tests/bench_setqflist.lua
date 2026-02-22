-- Benchmark: setqflist with parsed entries vs raw lines + efm
--
-- Compares different approaches:
--   1. Parsed vimgrep entries (file:line:col:text)
--   2. Same, with bufnr cache - current default
--   3. Parsed line-number entries (file:line:text) - unique_lines mode
--   4. Raw lines with errorformat
--
-- Run with:
--   nvim --headless -c "luafile bench_setqflist.lua" -c "q"

local N = 10000
local RUNS = 10

--------------------------------------------------------------------------------
--- Generate fake vimgrep lines ------------------------------------------------
--------------------------------------------------------------------------------

local function generate_vimgrep_lines(count)
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

local function generate_line_number_lines(count)
  local lines = {}
  for i = 1, count do
    -- Simulate realistic paths and content (same as vimgrep, but without column)
    local depth = (i % 4) + 1
    local path_parts = {}
    for d = 1, depth do
      table.insert(path_parts, string.format('dir%d', (i + d) % 10))
    end
    table.insert(path_parts, string.format('file%d.lua', i % 100))
    local path = table.concat(path_parts, '/')

    local lnum = (i % 500) + 1
    local text = string.format('local result_%d = some_function(%d, "arg")', i, i * 2)

    table.insert(lines, string.format('%s:%d:%s', path, lnum, text))
  end
  return lines
end

--------------------------------------------------------------------------------
--- Parsing approach: vimgrep format (current default) -------------------------
--------------------------------------------------------------------------------

local function parse_vimgrep(result)
  local filename, lnum, col, text = result:match('([^:]+):(%d+):(%d+):(.*)')
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

local function bench_parsed_vimgrep(lines)
  local entries = {}
  for _, line in ipairs(lines) do
    local entry = parse_vimgrep(line)
    if entry then
      table.insert(entries, entry)
    end
  end
  vim.fn.setqflist({}, 'r')
  vim.fn.setqflist(entries, 'a')
end

local function bench_parsed_vimgrep_cache(lines)
  local entries = {}
  local cache = {}
  for _, line in ipairs(lines) do
    local entry = parse_vimgrep(line)
    if entry then
      local filename = entry.filename
      local bufnr = cache[filename]
      if not bufnr then
        bufnr = vim.fn.bufadd(filename)
        cache[filename] = bufnr
      end
      entry.bufnr = bufnr
      entry.filename = nil
      table.insert(entries, entry)
    end
  end
  vim.fn.setqflist({}, 'r')
  vim.fn.setqflist(entries, 'a')
end

--------------------------------------------------------------------------------
--- Parsing approach: line-number format (unique_lines mode) -------------------
--------------------------------------------------------------------------------

local function parse_line_number(result)
  local filename, lnum, text = result:match('([^:]+):(%d+):(.*)')
  if not filename then
    return nil
  end
  return {
    filename = filename,
    lnum = tonumber(lnum),
    col = 1,
    text = text,
  }
end

local function bench_parsed_line_number(lines)
  local entries = {}
  for _, line in ipairs(lines) do
    local entry = parse_line_number(line)
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
    '%-22s  mean: %7.2f ms  median: %7.2f ms  min: %7.2f ms  max: %7.2f ms',
    r.name, r.mean, r.median, r.min, r.max
  )
end

--------------------------------------------------------------------------------
--- Main -----------------------------------------------------------------------
--------------------------------------------------------------------------------

print(string.format('\nBenchmarking setqflist: %d entries, %d runs each\n', N, RUNS))

local vimgrep_lines = generate_vimgrep_lines(N)
local line_number_lines = generate_line_number_lines(N)
print(string.format('Generated %d fake lines for each format\n', N))

local results = {
  measure('parsed (vimgrep)', bench_parsed_vimgrep, vimgrep_lines),
  measure('parsed (vimgrep, cache)', bench_parsed_vimgrep_cache, vimgrep_lines),
  measure('parsed (line-num)', bench_parsed_line_number, line_number_lines),
  measure('raw lines + efm', bench_efm, vimgrep_lines),
}

print('Results:')
print(string.rep('-', 78))
for _, r in ipairs(results) do
  print(format_result(r))
end
print(string.rep('-', 78))

-- Find the fastest
table.sort(results, function(a, b) return a.mean < b.mean end)
local fastest = results[1]
local slowest = results[#results]

print(string.format('\nFastest: %s', fastest.name))
for i = 2, #results do
  local r = results[i]
  local diff = r.mean - fastest.mean
  local pct = (diff / r.mean) * 100
  print(string.format('  vs %-18s: %.1f%% faster (%.2f ms saved)', r.name, pct, diff))
end

print()
