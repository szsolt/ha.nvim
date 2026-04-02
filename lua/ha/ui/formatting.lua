-- UI formatting utilities for Home Assistant entities and data
-- Shared formatting functions for consistent display across UI components

local M = {}

---Format a value for display in documentation
---@param value any The value to format
---@param indent number Indentation level (default: 0)
---@param max_depth number Maximum recursion depth (default: 3)
---@return string Formatted value
function M.format_value_for_docs(value, indent, max_depth)
  indent = indent or 0
  max_depth = max_depth or 3

  if indent > max_depth then return "..." end

  local indent_str = string.rep("  ", indent)

  -- Handle vim.NIL first
  if value == vim.NIL then return "*not set*" end

  if type(value) == "table" then
    -- Check if table is empty first
    local has_content = false
    for _ in pairs(value) do
      has_content = true
      break
    end

    if not has_content then return "*empty*" end

    -- Check if it's an array-like table
    local is_array = true
    local count = 0
    for k, _ in pairs(value) do
      count = count + 1
      if type(k) ~= "number" or k ~= count then
        is_array = false
        break
      end
    end

    if is_array and count > 0 then
      -- Check if this looks like a key-value pair array (Home Assistant style)
      -- e.g., {{"mqtt", "zigbee2mqtt_0xa4c138849725b7a2"}, {"mac", "10:06:1c:cb:b1:64"}}
      local is_kv_pairs = count > 0 and type(value[1]) == "table" and #value[1] == 2

      if is_kv_pairs then
        -- Format as key-value pairs
        local items = {}
        for i, pair in ipairs(value) do
          if i > 10 then
            table.insert(items, indent_str .. "  ... (" .. (#value - 10) .. " more)")
            break
          end
          if type(pair) == "table" and #pair >= 2 then
            table.insert(items, indent_str .. "  `" .. tostring(pair[1]) .. "`: `" .. tostring(pair[2]) .. "`")
          else
            -- Fallback to regular array formatting for malformed pairs
            local formatted_item = M.format_value_for_docs(pair, indent + 1, max_depth)
            table.insert(items, indent_str .. "  - " .. formatted_item)
          end
        end
        return "\n" .. table.concat(items, "\n")
      else
        -- Format as regular array
        local items = {}
        for i, v in ipairs(value) do
          if i > 10 then
            table.insert(items, indent_str .. "  ... (" .. (#value - 10) .. " more)")
            break
          end
          -- Handle arrays containing only vim.NIL
          if v == vim.NIL then
            table.insert(items, indent_str .. "  - *not set*")
          else
            local formatted_item = M.format_value_for_docs(v, indent + 1, max_depth)
            table.insert(items, indent_str .. "  - " .. formatted_item)
          end
        end
        return "\n" .. table.concat(items, "\n")
      end
    else
      -- Format as object
      local items = {}
      local item_count = 0
      for k, v in pairs(value) do
        item_count = item_count + 1
        if item_count > 10 then
          local remaining = 0
          for _ in pairs(value) do
            remaining = remaining + 1
          end
          remaining = remaining - 10
          table.insert(items, indent_str .. "  ... (" .. remaining .. " more)")
          break
        end
        local formatted_value = M.format_value_for_docs(v, indent + 1, max_depth)
        table.insert(items, indent_str .. "  **" .. tostring(k) .. ":** " .. formatted_value)
      end
      return "\n" .. table.concat(items, "\n")
    end
  elseif type(value) == "string" then
    -- Truncate very long strings
    if #value > 100 then
      return "`" .. value:sub(1, 97) .. "...`"
    else
      return "`" .. value .. "`"
    end
  elseif type(value) == "number" then
    return "`" .. tostring(value) .. "`"
  elseif type(value) == "boolean" then
    return "`" .. tostring(value) .. "`"
  elseif value == nil then
    return "*not available*"
  else
    -- Handle any other special cases
    local str_value = tostring(value)
    if str_value == "vim.NIL" then
      return "*not set*"
    else
      return "`" .. str_value .. "`"
    end
  end
end

---Generate dynamic preview content for an entity
---@param entity table Entity data from registry
---@return table Preview content
function M.generate_entity_preview(entity)
  if not entity or not entity.entity_id then
    return {
      text = "# No Entity Data\n\nEntity information not available.",
      ft = "markdown",
    }
  end

  local preview_lines = {}
  local registry = require "ha.utils.registry"

  table.insert(preview_lines, "# " .. entity.entity_id)
  table.insert(preview_lines, "")

  local friendly_name = entity.attributes and entity.attributes.friendly_name or ""
  if friendly_name and friendly_name ~= "" then table.insert(preview_lines, "**Name:** " .. friendly_name) end

  table.insert(preview_lines, "**State:** `" .. tostring(entity.state or "unknown") .. "`")

  if entity.unique_id then table.insert(preview_lines, "**Unique ID:** `" .. entity.unique_id .. "`") end
  if entity.entity_category then table.insert(preview_lines, "**Category:** `" .. entity.entity_category .. "`") end
  if entity.disabled_by and entity.disabled_by ~= vim.NIL then
    table.insert(preview_lines, "**Disabled by:** `" .. tostring(entity.disabled_by) .. "`")
  end
  if entity.hidden_by and entity.hidden_by ~= vim.NIL then
    table.insert(preview_lines, "**Hidden by:** `" .. tostring(entity.hidden_by) .. "`")
  end
  if entity.translation_key then
    table.insert(preview_lines, "**Translation key:** `" .. entity.translation_key .. "`")
  end
  if entity.original_name then table.insert(preview_lines, "**Original name:** `" .. entity.original_name .. "`") end
  if entity.has_entity_name ~= nil then
    table.insert(preview_lines, "**Has entity name:** `" .. tostring(entity.has_entity_name) .. "`")
  end
  if entity.config_entry_id then table.insert(preview_lines, "**Config entry:** `" .. entity.config_entry_id .. "`") end

  if entity.area_id then
    local areas = registry.get_areas()
    local area = areas[entity.area_id]
    local area_name = area and area.name or entity.area_id
    table.insert(preview_lines, "**Area:** " .. area_name)
  end

  if entity.device_name then table.insert(preview_lines, "**Device:** " .. entity.device_name) end
  if entity.platform then table.insert(preview_lines, "**Platform:** " .. entity.platform) end

  local domain = entity.entity_id:match "^([^%.]+)%."
  if domain then table.insert(preview_lines, "**Domain:** " .. domain) end

  table.insert(preview_lines, "")
  table.insert(preview_lines, "## Attributes")

  if entity.attributes and type(entity.attributes) == "table" then
    local attr_count = 0
    for key, value in pairs(entity.attributes) do
      if not key:match "^_" and key ~= "friendly_name" and key ~= "icon" and key ~= "entity_picture" then
        local formatted_key = key:gsub("_", " "):gsub("^%l", string.upper)
        local formatted_value = M.format_value_for_docs(value)

        table.insert(preview_lines, "- **" .. formatted_key .. ":** " .. formatted_value)
        attr_count = attr_count + 1
      end
    end

    if attr_count == 0 then table.insert(preview_lines, "No additional attributes") end
  else
    table.insert(preview_lines, "No attributes available")
  end

  -- Device info section
  if entity.device and type(entity.device) == "table" then
    table.insert(preview_lines, "")
    table.insert(preview_lines, "## Device")

    local device_count = 0
    for key, value in pairs(entity.device) do
      if
        not key:match "^_"
        and key ~= "device_name"
        and key ~= "device_id"
        and key ~= "id"
        and key ~= "config_entries"
        and key ~= "config_entries_subentries"
        and key ~= "primary_config_entry"
        and key ~= "via_device_id"
        and key ~= "created_at"
        and key ~= "modified_at"
        and key ~= "entry_type"
        and key ~= "disabled_by"
      then
        local formatted_key = key:gsub("_", " "):gsub("^%l", string.upper)
        local formatted_value = M.format_value_for_docs(value)

        table.insert(preview_lines, "- **" .. formatted_key .. ":** " .. formatted_value)
        device_count = device_count + 1
      end
    end

    if device_count == 0 then table.insert(preview_lines, "No additional device information") end
  end

  if entity.last_changed or entity.last_updated then
    table.insert(preview_lines, "")
    table.insert(preview_lines, "## Timeline")
    if entity.last_changed then table.insert(preview_lines, "- **Last Changed:** " .. entity.last_changed) end
    if entity.last_updated then table.insert(preview_lines, "- **Last Updated:** " .. entity.last_updated) end
  end

  return {
    text = table.concat(preview_lines, "\n"),
    ft = "markdown",
  }
end

---Format entity documentation with rich markdown formatting
---@param entity table Home Assistant entity data
---@return string Formatted markdown documentation
function M.format_entity_documentation(entity)
  local docs = {}

  -- Always show entity ID first
  table.insert(docs, "**Entity:** `" .. entity.entity_id .. "`")

  -- Show current state
  table.insert(docs, "**State:** `" .. tostring(entity.state) .. "`")

  -- Show all attributes in a clean format
  if entity.attributes and type(entity.attributes) == "table" then
    for key, value in pairs(entity.attributes) do
      -- Skip internal/technical attributes and format user-friendly ones
      if not key:match "^_" and key ~= "icon" and key ~= "entity_picture" then
        local formatted_key = key:gsub("_", " "):gsub("^%l", string.upper)
        local formatted_value = M.format_value_for_docs(value)

        table.insert(docs, "**" .. formatted_key .. ":** " .. formatted_value)
      end
    end
  end

  return table.concat(docs, "\n")
end

---Format entity documentation with enhanced device and area information
---@param entity table Home Assistant entity data
---@param callback function Callback with formatted documentation
function M.format_entity_documentation_enhanced(entity, callback)
  -- Start with basic formatting
  local basic_docs = M.format_entity_documentation(entity)

  -- Try to get registry information
  local registry = require "ha.utils.registry"
  registry.get_entity_relationships(entity.entity_id, function(relationships)
    if not relationships then
      -- Fallback to basic documentation
      callback(basic_docs)
      return
    end

    local docs = {}

    -- Always show entity ID first
    table.insert(docs, "**Entity:** `" .. entity.entity_id .. "`")

    -- Show current state
    table.insert(docs, "**State:** `" .. tostring(entity.state) .. "`")

    -- Show device information if available
    if relationships.device_name then table.insert(docs, "**Device:** `" .. relationships.device_name .. "`") end

    -- Show location information if available
    if relationships.area_name then table.insert(docs, "**Location:** `" .. relationships.area_name .. "`") end

    -- Extract domain from entity_id
    local domain = entity.entity_id:match "^([^%.]+)%."
    if domain then table.insert(docs, "**Domain:** `" .. domain .. "`") end
    table.insert(docs, "----------------------------------------------")

    -- Show all attributes in a clean format
    if entity.attributes and type(entity.attributes) == "table" then
      for key, value in pairs(entity.attributes) do
        -- Skip internal/technical attributes and format user-friendly ones
        if not key:match "^_" and key ~= "icon" and key ~= "entity_picture" then
          local formatted_key = key:gsub("_", " "):gsub("^%l", string.upper)
          local formatted_value = M.format_value_for_docs(value)

          table.insert(docs, "**" .. formatted_key .. ":** " .. formatted_value)
        end
      end
    end

    callback(table.concat(docs, "\n"))
  end)
end

---Format entity preview with enhanced information (sync version with async enhancement)
---@param entity table Home Assistant entity data
---@param callback function Callback with formatted preview
function M.format_entity_preview_enhanced(entity, callback)
  -- Return immediate basic preview
  local immediate_preview = M.format_entity_documentation(entity)

  -- Then enhance with registry data
  M.format_entity_documentation_enhanced(entity, callback)

  return immediate_preview
end

---Format device information
---@param device_name string Device name
---@param device_id string Device ID (optional)
---@return string Formatted device info
function M.format_device_info(device_name, device_id)
  if device_id then
    return "`" .. device_name .. "` (ID: `" .. device_id .. "`)"
  else
    return "`" .. device_name .. "`"
  end
end

---Format area information
---@param area_name string Area name
---Format a value for display without truncation (for service documentation)
---@param value any The value to format
---@param indent number Indentation level (default: 0)
---@param max_depth number Maximum recursion depth (default: 3)
---@return string Formatted value
function M.format_value_for_services(value, indent, max_depth)
  indent = indent or 0
  max_depth = max_depth or 3

  if indent > max_depth then return "..." end

  local indent_str = string.rep("  ", indent)

  -- Handle vim.NIL first
  if value == vim.NIL then return "*not set*" end

  if type(value) == "table" then
    -- Check if table is empty first
    local has_content = false
    for _ in pairs(value) do
      has_content = true
      break
    end

    if not has_content then return "*empty*" end

    -- Check if it's an array-like table
    local is_array = true
    local count = 0
    for k, _ in pairs(value) do
      count = count + 1
      if type(k) ~= "number" or k ~= count then
        is_array = false
        break
      end
    end

    if is_array and count > 0 then
      -- Check if this looks like a key-value pair array (Home Assistant style)
      local is_kv_pairs = count > 0 and type(value[1]) == "table" and #value[1] == 2

      if is_kv_pairs then
        -- Format as key-value pairs (no truncation for services)
        local items = {}
        for i, pair in ipairs(value) do
          if type(pair) == "table" and #pair >= 2 then
            table.insert(items, indent_str .. "  `" .. tostring(pair[1]) .. "`: `" .. tostring(pair[2]) .. "`")
          else
            -- Fallback to regular array formatting for malformed pairs
            local formatted_item = M.format_value_for_services(pair, indent + 1, max_depth)
            table.insert(items, indent_str .. "  - " .. formatted_item)
          end
        end
        return "\n" .. table.concat(items, "\n")
      else
        -- Format as regular array (no truncation for services)
        local items = {}
        for i, v in ipairs(value) do
          if v == vim.NIL then
            table.insert(items, indent_str .. "  - *not set*")
          else
            local formatted_item = M.format_value_for_services(v, indent + 1, max_depth)
            table.insert(items, indent_str .. "  - " .. formatted_item)
          end
        end
        return "\n" .. table.concat(items, "\n")
      end
    else
      -- Format as object (no truncation for services)
      local items = {}
      for k, v in pairs(value) do
        local formatted_value = M.format_value_for_services(v, indent + 1, max_depth)
        table.insert(items, indent_str .. "  **" .. tostring(k) .. ":** " .. formatted_value)
      end
      return "\n" .. table.concat(items, "\n")
    end
  elseif type(value) == "string" then
    return "`" .. value .. "`"
  elseif type(value) == "number" then
    return "`" .. tostring(value) .. "`"
  elseif type(value) == "boolean" then
    return "`" .. tostring(value) .. "`"
  elseif value == nil then
    return "*not available*"
  else
    -- Handle any other special cases
    local str_value = tostring(value)
    if str_value == "vim.NIL" then
      return "*not set*"
    else
      return "`" .. str_value .. "`"
    end
  end
end

---Format a Home Assistant service field selector type for display
---@param selector any The selector value to format
---@return string Formatted selector type description
function M.format_selector_type(selector)
  if selector == nil or selector == vim.NIL then
    return "*any*"
  end

  if type(selector) == "string" then
    return "`" .. selector .. "`"
  end

  if type(selector) ~= "table" then
    return "`" .. type(selector) .. "`"
  end

  -- For service selectors, we mainly want to identify the type and show configuration
  -- Let's reuse the existing formatting but be more concise about type detection
  
  -- Find the first non-NIL key to determine selector type
  local selector_type = nil
  local selector_config = nil
  
  for key, value in pairs(selector) do
    if value ~= vim.NIL then
      selector_type = key
      selector_config = value
      break
    elseif value == vim.NIL then
      -- If all we have is vim.NIL values, still use the key to identify type
      selector_type = selector_type or key
    end
  end
  
  if not selector_type then
    return "`object`"
  end
  
  -- Format the base type
  local type_name = selector_type
  
  -- Add configuration details for common types
  if selector_type == "text" and type(selector_config) == "table" then
    if selector_config.type then
      type_name = selector_config.type
    end
    if selector_config.multiline then
      type_name = type_name .. " (multiline)"
    end
  elseif selector_type == "number" and type(selector_config) == "table" then
    local details = {}
    if selector_config.min then table.insert(details, "min: " .. selector_config.min) end
    if selector_config.max then table.insert(details, "max: " .. selector_config.max) end
    if selector_config.unit_of_measurement then 
      table.insert(details, "unit: " .. selector_config.unit_of_measurement) 
    end
    if #details > 0 then
      type_name = type_name .. " (" .. table.concat(details, ", ") .. ")"
    end
  elseif selector_type == "select" and type(selector_config) == "table" and selector_config.options then
    -- Show all options for select fields, not truncated
    local options_display = M.format_value_for_services(selector_config.options)
    return "`" .. type_name .. "` - Options:" .. options_display
  elseif selector_type == "entity" and type(selector_config) == "table" and selector_config.domain then
    local domain_display = M.format_value_for_services(selector_config.domain)
    return "`" .. type_name .. "` - Domains:" .. domain_display
  end
  
  return "`" .. type_name .. "`"
end

---Format Home Assistant service target information for user display
---@param target any The target configuration
---@return string|nil Formatted target description or nil if not meaningful
function M.format_service_target(target)
  if not target or target == vim.NIL then
    return nil
  end
  
  if type(target) ~= "table" then
    return tostring(target)
  end
  
  -- Extract meaningful information from target configuration
  local target_parts = {}
  
  -- Handle entity targets
  if target.entity then
    if type(target.entity) == "table" then
      local entity_info = target.entity
      if entity_info.domain then
        local domains = entity_info.domain
        if type(domains) == "table" then
          table.insert(target_parts, "entities in domains: " .. table.concat(domains, ", "))
        else
          table.insert(target_parts, "entities in domain: " .. domains)
        end
      else
        table.insert(target_parts, "any entities")
      end
      
      -- Add feature requirements if specified
      if entity_info.supported_features then
        table.insert(target_parts, "with specific features")
      end
    else
      table.insert(target_parts, "entities")
    end
  end
  
  -- Handle device targets
  if target.device then
    table.insert(target_parts, "devices")
  end
  
  -- Handle area targets
  if target.area then
    table.insert(target_parts, "areas")
  end
  
  if #target_parts > 0 then
    return "Applies to " .. table.concat(target_parts, " or ")
  end
  
  return nil
end

---Format Home Assistant service response information for user display
---@param response any The response configuration
---@return string|nil Formatted response description or nil if not meaningful
function M.format_service_response(response)
  if not response or response == vim.NIL then
    return nil
  end
  
  if type(response) == "table" and response.optional ~= nil then
    if response.optional then
      return "May return response data"
    else
      return "Returns response data"
    end
  end
  
  return "Returns data"
end

---Format area info with optional area ID
---@param area_name string Area name 
---@param area_id string Area ID (optional)
---@return string Formatted area info
function M.format_area_info(area_name, area_id)
  if area_id then
    return "`" .. area_name .. "` (ID: `" .. area_id .. "`)"
  else
    return "`" .. area_name .. "`"
  end
end

return M
