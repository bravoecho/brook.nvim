--- Editor utilities: helpers for interacting with Neovim.
---
---@module 'brook.util'
local M = {}

---@return string text The currently selected text
function M.get_visual_selection()
  local pos1 = vim.fn.getpos('v') -- start of visual selection
  local pos2 = vim.fn.getpos('.') -- cursor (end of visual selection)
  local lines = vim.fn.getregion(pos1, pos2, { type = vim.fn.mode() })
  return table.concat(lines, '\n')
end

return M
