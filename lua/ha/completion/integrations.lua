-- Home Assistant Integration completion source for blink.cmp
-- Provides integration domain completion for yaml configuration files

local utils = require "ha.utils"
local auth = require "ha.auth"
local registry = require "ha.utils.registry"

local M = {}

-- Create cache for integration data
local _cache = utils.cache.create_cache("integrations", 300000) -- 5 minute cache

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

  -- Check if we should trigger integration completion based on context
  if not self:_should_trigger_integration_completion(context) then
    callback { items = {} }
    return
  end

  self:_get_integrations(function(integrations)
    local items = {}

    for _, integration in ipairs(integrations) do
      local item = {
        label = integration.domain,
        kind = require("blink.cmp.types").CompletionItemKind.Module,
        detail = integration.name or integration.domain,
        documentation = self:_create_integration_documentation(integration),
        insertText = integration.domain,
        sortText = string.format("%04d_%s", integration._source == "admin_api" and 1 or 2, integration.domain),
      }

      table.insert(items, item)
    end

    -- Sort by domain name
    table.sort(items, function(a, b) return a.label < b.label end)

    callback { items = items }
  end)
end

---Check if we should trigger integration completion
---@param context table Completion context
---@return boolean
function M:_should_trigger_integration_completion(context)
  local line = context.line
  local col = context.cursor[2]

  -- Get text before cursor
  local before_cursor = line:sub(1, col)

  -- Trigger completion in these contexts:
  -- 1. After "platform: " (for platforms)
  -- 2. After "integration: " (for explicit integration references)
  -- 3. In platform lists
  -- 4. After domain names in service calls

  local patterns = {
    "platform:%s*$", -- platform: |
    "integration:%s*$", -- integration: |
    "domain:%s*$", -- domain: |
    "- platform:%s*$", -- - platform: |
    "- integration:%s*$", -- - integration: |
    "%- %s*$", -- - | (in platform lists)
  }

  for _, pattern in ipairs(patterns) do
    if before_cursor:match(pattern) then return true end
  end

  return false
end

---Get integrations from registry with caching
---@param callback function
function M:_get_integrations(callback)
  -- Check cache first
  local cached_integrations = _cache:get()
  if cached_integrations then
    callback(cached_integrations)
    return
  end

  -- Check if registry is initialized
  if not registry.get_stats().initialized then
    -- Registry not ready, return empty for now
    callback {}
    return
  end

  -- Get integrations from registry
  local integrations = registry.get_all_integrations()

  -- Cache the results
  _cache:set(integrations)

  callback(integrations)
end

---Create documentation for integration completion item
---@param integration table Integration data
---@return table Documentation
function M:_create_integration_documentation(integration)
  local lines = {}

  -- Basic info
  table.insert(lines, "**" .. (integration.name or integration.domain) .. "**")
  table.insert(lines, "")
  table.insert(lines, "Domain: `" .. integration.domain .. "`")

  -- Admin API data
  if integration._source == "admin_api" then
    if integration.integration_type then
      table.insert(lines, "Type: " .. integration.integration_type:gsub("_", " "):gsub("^%l", string.upper))
    end

    if integration.iot_class then
      table.insert(lines, "IoT Class: " .. integration.iot_class:gsub("_", " "):gsub("^%l", string.upper))
    end

    if integration.config_flow ~= nil then
      table.insert(lines, "Config Flow: " .. (integration.config_flow and "✓" or "✗"))
    end

    if integration.supported_by then table.insert(lines, "Supported by: " .. integration.supported_by) end
  end

  -- Manifest API data
  if integration.manifest and integration.manifest.name then
    table.insert(lines, "Display Name: " .. integration.manifest.name)
  end

  return {
    kind = "markdown",
    value = table.concat(lines, "\n"),
  }
end

return M
