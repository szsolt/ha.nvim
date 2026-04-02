-- Area picker with C-s functionality
local M = {}

local utils = require "ha.utils"
local registry = require "ha.utils.registry"
local core = require "ha.ui.picker.core"
local actions = require "ha.ui.picker.actions"

---Generate area preview content
---@param item table Picker item containing area data
---@return table Preview content
local function generate_area_preview(item)
  local area = item.area
  local area_id = item.area_id
  
  if not area or not area_id then
    return {
      text = "# No Area Data\n\nArea information not available.",
      ft = "markdown",
    }
  end

  local preview_lines = {}
  table.insert(preview_lines, "# " .. (area.name or area_id))
  table.insert(preview_lines, "")
  table.insert(preview_lines, "**Area ID:** " .. area_id)
  table.insert(preview_lines, "**Entities:** " .. item.entity_count)

  if area.aliases and #area.aliases > 0 then
    table.insert(preview_lines, "**Aliases:** " .. table.concat(area.aliases, ", "))
  end

  return {
    text = table.concat(preview_lines, "\n"),
    ft = "markdown",
  }
end

---Show area picker with C-s functionality
---@param callback function Selection callback
function M.show_area_picker(callback)
  if not registry.get_stats().initialized then
    utils.logger.warn "Registry not initialized, initializing now..."
    registry.initialize(function(success, error)
      if success then
        M.show_area_picker(callback)
      else
        vim.notify("Failed to initialize registry: " .. tostring(error), vim.log.levels.ERROR)
      end
    end)
    return
  end

  local areas = registry.get_areas()

  if vim.tbl_isempty(areas) then
    vim.notify("No areas found", vim.log.levels.INFO)
    return
  end

  local items = {}
  local i = 0
  for area_id, area in pairs(areas) do
    i = i + 1

    local entity_count = #registry.get_entities_by_area(area_id)

    table.insert(items, {
      idx = i,
      text = area.name or area_id,
      area_id = area_id,
      area = area,
      entity_count = entity_count,
      description = entity_count .. " entities",
    })
  end

  table.sort(items, function(a, b) return a.text < b.text end)

  local picker_config = {
    source = "home_assistant_areas",
    items = items,
    title = "Select Area (" .. #items .. " available)",
    preview = core.create_preview_function(generate_area_preview),
    format = core.create_format_function("text", "description"),
    confirm = core.create_confirm_function("area", callback),
    actions = actions.create_actions_with_insertion("area"),
    win = {
      input = {
        keys = actions.create_keybindings_with_insertion("area"),
      },
    },
  }

  core.show_picker(picker_config)
end

return M
