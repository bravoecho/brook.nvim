--- Simple FIFO queue.
---
---@module 'brook.lib.fifo'

---@class brook.Fifo
---@field push function
---@field pull function
---@field len function
---@field is_empty function

local M = {}

function M.new()
  local F = {}

  F._items = {}
  F._cursor = 1

  --- Adds an item to the end of the queue.
  ---
  ---@param item any Item to enqueue
  function F.push(item)
    table.insert(F._items, item)
  end

  --- Removes and returns up to n items from the front of the queue.
  ---
  --- Returns fewer than n items if the queue contains fewer than n items.
  --- Returns an empty table if the queue is empty.
  ---
  ---@param n integer Maximum number of items to dequeue
  ---@return any[] items The dequeued items (may be empty)
  function F.pull(n)
    if F._cursor > #F._items then return {} end
    local current_cursor = F._cursor
    local slice_end = math.min(#F._items, current_cursor + n - 1)
    F._cursor = slice_end + 1
    local slice = {}
    for i = current_cursor, slice_end do
      slice[#slice + 1] = F._items[i]
    end
    return slice
  end

  --- Returns the number of items currently in the queue.
  ---
  ---@return integer
  function F.len()
    return #F._items - F._cursor + 1
  end

  --- Returns true if the queue is empty.
  ---
  ---@return boolean
  function F.is_empty()
    return F._cursor > #F._items
  end

  return F
end

return M
