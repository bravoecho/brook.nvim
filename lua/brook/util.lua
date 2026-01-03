--- Editor utilities: helpers for interacting with Neovim.
---
---@module 'brook.util'
local M = {}

---@return string text The currently selected text
function M.get_visual_selection()
  -- 1. Save the current state of a register, in our case 'v', that we will use
  --    to temporarily store the visual selection.
  local reg = vim.fn.getreg('v')
  local regtype = vim.fn.getregtype('v')
  -- 2. Copy the visual selection into the chosen register.
  vim.cmd('noautocmd normal! "vy')
  -- 3. Store the selection content
  local selection = vim.fn.getreg('v')
  -- 4. Reinstate the chosen register
  vim.fn.setreg('v', reg, regtype)

  return selection
end

return M
