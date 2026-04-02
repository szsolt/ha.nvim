-- Home Assistant Entity completion source for blink.cmp
-- Provides entity completion for yaml configuration files

local utils = require "ha.utils"
local auth = require "ha.auth"
local registry = require "ha.utils.registry"
local formatting = require "ha.ui.formatting"

local M = {}

-- Note: No cache needed - registry maintains current data with real-time updates

---Create new source instance
function M.new() return setmetatable({}, { __index = M }) end

---Check if this source should be enabled
function M:enabled() return auth.has_credentials() and utils.workspace.is_ha_file() end

---Get completion items
function M:get_completions(context, callback)
  if not self:enabled() then
    callback { items = {} }
    return
  end

  -- Check if we should trigger entity completion based on context
  if not self:_should_trigger_entity_completion(context) then
    callback { items = {} }
    return
  end

  -- Extract the domain from context (e.g., "light" from "light.")
  local target_domain = self:_extract_domain_from_context(context)
  if not target_domain then
    callback { items = {} }
    return
  end

  self:_get_entities(function(entities)
    local items = {}

    for _, entity in ipairs(entities) do
      -- Filter entities by domain
      local entity_domain = entity.entity_id:match "^([^%.]+)%."
      if entity_domain == target_domain then
        local item = {
          label = entity.entity_id,
          kind = require("blink.cmp.types").CompletionItemKind.Variable,
          detail = entity.attributes and entity.attributes.friendly_name or entity.entity_id,
          documentation = {
            kind = "markdown",
            value = self:_get_enhanced_documentation(entity),
          },
          insertText = entity.entity_id,
          filterText = entity.entity_id .. " " .. (entity.attributes and entity.attributes.friendly_name or ""),
          sortText = entity.entity_id,
          data = {
            source = "ha_entities",
            entity = entity,
          },
        }
        table.insert(items, item)
      end
    end

    callback { items = items }
  end)
end

---Resolve completion item
function M:resolve(item, callback) callback(item) end

---Get trigger characters
function M:get_trigger_characters() return {} end

---Check if we should trigger entity completion based on context
---@param context table Completion context from blink.cmp
---@return boolean True if entity completion should be triggered
function M:_should_trigger_entity_completion(context)
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2]

  -- Get text before cursor
  local text_before_cursor = line:sub(1, col)

  -- Check if there's a domain pattern before cursor
  -- Match patterns like: sensor., light., binary_sensor., device_tracker., etc.
  local domain_pattern = "([%w_]+)%.$"
  local domain_match = text_before_cursor:match(domain_pattern)

  if domain_match then
    -- Validate it's a known Home Assistant domain
    return self:_is_valid_ha_domain(domain_match)
  end

  -- Also trigger if we're completing after a domain that was already partially typed
  -- Like: sensor.living_room_temp|  (cursor at |)
  local partial_entity_pattern = "([%w_]+)%.[%w_]+$"
  local partial_domain = text_before_cursor:match(partial_entity_pattern)

  if partial_domain then return self:_is_valid_ha_domain(partial_domain) end

  return false
end

---Extract domain from current context
---@param context table Completion context
---@return string|nil Domain name if found
function M:_extract_domain_from_context(context)
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2]

  -- Get text before cursor
  local text_before_cursor = line:sub(1, col)

  -- Match domain pattern like: sensor., light., binary_sensor., device_tracker., etc.
  local domain_pattern = "([%w_]+)%.$"
  local domain_match = text_before_cursor:match(domain_pattern)

  if domain_match then return domain_match end

  -- Match partial entity pattern like: sensor.living_room_, binary_sensor.door_
  local partial_entity_pattern = "([%w_]+)%.[%w_]+$"
  local partial_domain = text_before_cursor:match(partial_entity_pattern)

  return partial_domain
end

---Check if the given string is a valid Home Assistant domain
---@param domain string Domain to check
---@return boolean True if it's a valid HA domain
function M:_is_valid_ha_domain(domain) 
  -- Use registry's dynamic domain list instead of hardcoded list
  local domains = registry.get_available_domains()
  return vim.tbl_contains(domains, domain)
end

-- Removed _is_ha_file() - now using utils.file.is_ha_file()

---Get entities with caching
function M:_get_entities(callback)
  -- Check if registry is initialized
  if not registry.get_stats().initialized then
    -- Registry not ready - try to initialize it
    registry.initialize(function(success, error)
      if success then
        callback(registry.get_all_entities())
      else
        -- Fallback to empty list if registry initialization fails
        utils.logger.warn("Registry initialization failed for entity completion: " .. tostring(error))
        callback({})
      end
    end)
    return
  end

  -- Registry is ready - get entities immediately  
  callback(registry.get_all_entities())
end

---Get enhanced documentation for entity (registry entities are pre-enriched)
---@param entity table Home Assistant entity data from registry (already enriched)
---@return string Formatted documentation
function M:_get_enhanced_documentation(entity)
  local docs = {}

  -- Always show entity ID first
  table.insert(docs, "**Entity:** `" .. entity.entity_id .. "`")

  -- Show current state
  table.insert(docs, "**State:** `" .. tostring(entity.state or "unknown") .. "`")

  -- Show device information if available (registry provides device_name)
  if entity.device_name then 
    table.insert(docs, "**Device:** `" .. entity.device_name .. "`") 
  end

  -- Show location information if available (registry resolves area)
  if entity.area_id then
    local areas = registry.get_areas()
    local area = areas[entity.area_id]
    if area and area.name then
      table.insert(docs, "**Location:** `" .. area.name .. "`")
    end
  end

  -- Extract domain from entity_id
  local domain = entity.entity_id:match("^([^%.]+)%.")
  if domain then 
    table.insert(docs, "**Domain:** `" .. domain .. "`") 
  end

  -- Show all attributes in a clean format
  if entity.attributes and type(entity.attributes) == "table" then
    for key, value in pairs(entity.attributes) do
      -- Skip internal/technical attributes and format user-friendly ones
      if not key:match("^_") and key ~= "icon" and key ~= "entity_picture" then
        local formatted_key = key:gsub("_", " "):gsub("^%l", string.upper)
        local formatted_value = formatting.format_value_for_docs(value)

        table.insert(docs, "**" .. formatted_key .. ":** " .. formatted_value)
      end
    end
  end

  return table.concat(docs, "\n")
end

return M
