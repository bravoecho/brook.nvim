-- Run with:
--   nvim --headless -c "luafile tests/fifo_test.lua" -c "q"

local h = require('tests.harness')
local test = h.test
local eq = h.deep_eq
local fifo = require('brook.lib.fifo')

--------------------------------------------------------------------------------
--- new queue state ------------------------------------------------------------
--------------------------------------------------------------------------------

test('new: starts empty', function()
  local q = fifo.new()
  eq(q.is_empty(), true)
end)

test('new: length is zero', function()
  local q = fifo.new()
  eq(q.len(), 0)
end)

--------------------------------------------------------------------------------
--- push -----------------------------------------------------------------------
--------------------------------------------------------------------------------

test('push: single item', function()
  local q = fifo.new()
  q.push('a')
  eq(q.len(), 1)
  eq(q.is_empty(), false)
end)

test('push: multiple calls accumulate', function()
  local q = fifo.new()
  q.push('a')
  q.push('b')
  q.push('c')
  eq(q.len(), 3)
end)

--------------------------------------------------------------------------------
--- pull -----------------------------------------------------------------------
--------------------------------------------------------------------------------

test('pull: from empty queue returns empty table', function()
  local q = fifo.new()
  eq(q.pull(1), {})
end)

test('pull: single item', function()
  local q = fifo.new()
  q.push('a')
  q.push('b')
  q.push('c')
  eq(q.pull(1), { 'a' })
  eq(q.len(), 2)
end)

test('pull: multiple items', function()
  local q = fifo.new()
  q.push('a')
  q.push('b')
  q.push('c')
  eq(q.pull(2), { 'a', 'b' })
  eq(q.len(), 1)
end)

test('pull: more than available returns what exists', function()
  local q = fifo.new()
  q.push('a')
  q.push('b')
  eq(q.pull(5), { 'a', 'b' })
  eq(q.len(), 0)
end)

test('pull: preserves FIFO order', function()
  local q = fifo.new()
  q.push(1)
  q.push(2)
  q.push(3)
  eq(q.pull(1), { 1 })
  eq(q.pull(1), { 2 })
  eq(q.pull(1), { 3 })
end)

test('pull: zero items returns empty table', function()
  local q = fifo.new()
  q.push('a')
  q.push('b')
  eq(q.pull(0), {})
  eq(q.len(), 2)
end)

test('pull: after emptying returns empty table', function()
  local q = fifo.new()
  q.push('a')
  q.pull(1)
  eq(q.pull(1), {})
end)

--------------------------------------------------------------------------------
--- len ------------------------------------------------------------------------
--------------------------------------------------------------------------------

test('len: tracks pushes', function()
  local q = fifo.new()
  eq(q.len(), 0)
  q.push('a')
  eq(q.len(), 1)
  q.push('b')
  q.push('c')
  eq(q.len(), 3)
end)

test('len: tracks pulls', function()
  local q = fifo.new()
  q.push('a')
  q.push('b')
  q.push('c')
  q.pull(1)
  eq(q.len(), 2)
  q.pull(2)
  eq(q.len(), 0)
end)

--------------------------------------------------------------------------------
--- is_empty -------------------------------------------------------------------
--------------------------------------------------------------------------------

test('is_empty: true when new', function()
  local q = fifo.new()
  eq(q.is_empty(), true)
end)

test('is_empty: false after push', function()
  local q = fifo.new()
  q.push('a')
  eq(q.is_empty(), false)
end)

test('is_empty: true after pulling all items', function()
  local q = fifo.new()
  q.push('a')
  q.pull(1)
  eq(q.is_empty(), true)
end)

--------------------------------------------------------------------------------
--- mixed operations -----------------------------------------------------------
--------------------------------------------------------------------------------

test('mixed: push after pull', function()
  local q = fifo.new()
  q.push('a')
  q.push('b')
  q.pull(1)
  q.push('c')
  eq(q.len(), 2)
  eq(q.pull(2), { 'b', 'c' })
end)

--------------------------------------------------------------------------------
--- various value types --------------------------------------------------------
--------------------------------------------------------------------------------

test('values: numbers', function()
  local q = fifo.new()
  q.push(1)
  q.push(2)
  q.push(3)
  eq(q.pull(3), { 1, 2, 3 })
end)

test('values: booleans', function()
  local q = fifo.new()
  q.push(true)
  q.push(false)
  q.push(true)
  eq(q.pull(3), { true, false, true })
end)

test('values: tables', function()
  local q = fifo.new()
  local t1, t2 = { x = 1 }, { y = 2 }
  q.push(t1)
  q.push(t2)
  local result = q.pull(2)
  eq(result[1], t1)
  eq(result[2], t2)
end)

test('values: mixed types', function()
  local q = fifo.new()
  q.push('a')
  q.push(1)
  q.push(true)
  q.push({})
  eq(q.len(), 4)
end)

h.summary()
