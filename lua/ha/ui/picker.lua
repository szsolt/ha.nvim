-- Backward compatibility wrapper for the refactored picker system
-- This file re-exports everything from the new modular picker system

-- Import all picker modules directly to avoid circular dependency
local entity = require "ha.ui.picker.entity"
local service = require "ha.ui.picker.service" 
local integration = require "ha.ui.picker.integration"
local area = require "ha.ui.picker.area"
local reload = require "ha.ui.picker.reload"
local core = require "ha.ui.picker.core"
local actions = require "ha.ui.picker.actions"

local M = {}

---Setup picker integration
function M.setup()
  local utils = require "ha.utils"
  utils.logger.debug "Picker integration setup"
  return true
end

-- Re-export all picker functions for backward compatibility
M.show_entity_picker = entity.show_entity_picker
M.show_entity_picker_internal = entity.show_entity_picker_internal
M.show_service_picker = service.show_service_picker
M.show_integration_picker = integration.show_integration_picker
M.show_area_picker = area.show_area_picker
M.show_reload_options = reload.show_reload_options

-- Export core utilities for advanced usage
M.core = core
M.actions = actions

-- Export individual modules for direct access
M.entity = entity
M.service = service
M.integration = integration
M.area = area
M.reload = reload

return M
