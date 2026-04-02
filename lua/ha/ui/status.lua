-- Status line integration with dynamic progress system
local M = {}

local config = require "ha.config"
local utils = require "ha.utils"

-- Status state
local _state = {
  connection_status = "disconnected",
  instance_name = nil,
}

---Setup status line integration  
function M.setup()
  if not config.get_value("ui.statusline.enabled", true) then return end

  -- Initialize progress renderer
  local progress_renderer = require("ha.ui.progress_renderer")
  progress_renderer.setup()

  utils.logger.debug "Status line integration setup with dynamic progress"
end

---Update connection status
---@param status string Connection status ('connected', 'error', 'disconnected', 'connecting')
---@param info? table Connection info
function M.update(status, info)
  _state.connection_status = status

  if info and info.name then 
    _state.instance_name = info.name 
  end

  M._update_statusline()
  utils.logger.debug("Status updated: " .. status)
end

---Get current status for display
---@return string Status text
function M.get_status_text()
  local progress_renderer = require("ha.ui.progress_renderer")
  
  -- Show progress if active
  local progress_text = progress_renderer.get_display_text()
  if progress_text ~= "" then
    return "󰦖 " .. progress_text
  end
  
  -- Otherwise show connection status
  local icon = M._get_status_icon()
  local text = M._get_status_text()
  return icon .. " " .. text
end

---Get status icon
---@return string Icon
function M._get_status_icon()
  local icons = {
    connected = "󰟢", -- Connected icon
    error = "󰅖", -- Error icon
    disconnected = "󰤭", -- Disconnected icon
    connecting = "󰤱", -- Connecting icon
  }
  
  return icons[_state.connection_status] or icons.disconnected
end

---Get status text
---@return string Status text
function M._get_status_text()
  if _state.connection_status == "connected" then
    return _state.instance_name or "HA"
  elseif _state.connection_status == "connecting" then
    return "Connecting..."
  elseif _state.connection_status == "error" then
    return "Error"
  else
    return "Connect"
  end
end

---Update status line display
function M._update_statusline()
  -- Trigger statusline refresh
  vim.schedule(function()
    vim.cmd "redrawstatus"
  end)
end

---Cleanup status line integration
function M.cleanup()
  local progress_renderer = require("ha.ui.progress_renderer")
  progress_renderer.cleanup()
  
  _state.connection_status = "disconnected"
  _state.instance_name = nil
  M._update_statusline()
end

-- Export internal state for statusline integration
M._state = _state

---Get statusline component for manual integration
---@return string Statusline component
function M.get_statusline_component()
  return M.get_status_text()
end

-- Legacy API compatibility (deprecated)
---@deprecated Use progress system instead
function M.start_progress(title, message)
  utils.logger.warn("start_progress() is deprecated - use ha.utils.progress instead")
  local progress = require("ha.utils.progress")
  return progress.add_background(title)
end

---@deprecated Use progress system instead  
function M.update_progress(message)
  utils.logger.warn("update_progress() is deprecated - use ha.utils.progress instead")
end

---@deprecated Use progress system instead
function M.stop_progress()
  utils.logger.warn("stop_progress() is deprecated - use ha.utils.progress instead")
end

return M
