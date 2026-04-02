-- Home Assistant service completion source for blink.cmp

local config = require "ha.config"
local auth = require "ha.auth"
local api = require "ha.api"
local utils = require "ha.utils"

local M = {}

-- Create cache for service data
local _cache = utils.cache.create_cache("ha_services", 30000) -- 30 seconds

---Create new source instance
function M.new() return setmetatable({}, { __index = M }) end

---Check if this source should be enabled
function M:enabled() return auth.has_credentials() and utils.workspace.is_ha_file() and self:_is_service_context() end

---Get completion items (Enhanced with domain-based filtering)
function M:get_completions(context, callback)
  if not self:enabled() then
    callback { items = {} }
    return
  end

  -- Extract domain filter from context if typing after a domain prefix
  local domain_filter = self:_extract_service_domain_from_context(context)

  self:_get_services(function(services)
    local items = {}

    for domain, domain_services in pairs(services) do
      -- If we have a domain filter, only include services from that domain
      local should_include_domain = true
      if domain_filter and domain ~= domain_filter then
        should_include_domain = false
      end
      
      if should_include_domain then
        for service_name, service_info in pairs(domain_services) do
          local full_service = domain .. "." .. service_name

          local item = {
            label = full_service,
            kind = require("blink.cmp.types").CompletionItemKind.Function,
            detail = service_info.description or "Home Assistant Service",
            documentation = {
              kind = "markdown",
              value = self:_format_service_documentation(domain, service_name, service_info),
            },
            insertText = full_service,
            filterText = full_service .. " " .. (service_info.description or ""),
            sortText = full_service,
            data = {
              source = "ha_services",
              domain = domain,
              service = service_name,
              info = service_info,
            },
          }
          table.insert(items, item)
        end
      end
    end

    callback { items = items }
  end)
end

---Resolve completion item
function M:resolve(item, callback) callback(item) end

---Get trigger characters
function M:get_trigger_characters() return {} end

---Extract service domain from current context
---@param context table Completion context
---@return string|nil Domain name if found
function M:_extract_service_domain_from_context(context)
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2]
  
  -- Get text before cursor
  local text_before_cursor = line:sub(1, col)
  
  -- Match domain pattern like: homeassistant., light., etc.
  local domain_pattern = "(%w+)%.$"
  local domain_match = text_before_cursor:match(domain_pattern)
  
  if domain_match then
    return domain_match  
  end
  
  -- Match partial service pattern like: homeassistant.relo
  local partial_service_pattern = "(%w+)%.[%w_]+$"
  local partial_domain = text_before_cursor:match(partial_service_pattern)
  
  return partial_domain
end

---Check if the given string is a valid Home Assistant service domain
---@param domain string Domain to check  
---@return boolean True if it's a valid HA service domain
function M:_is_valid_service_domain(domain)
  return utils.workspace.is_valid_service_domain(domain)
end

-- Removed _is_ha_file() - now using utils.file.is_ha_file()

---Check if cursor is in a service call context
function M:_is_service_context()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2]

  -- Check if we're on a service line
  local before_cursor = line:sub(1, col)

  -- Look for service: or action: keywords
  local service_patterns = {
    "service:%s*$",
    "action:%s*$",
    "service:%s*[%w%.]*$",
    "action:%s*[%w%.]*$",
  }

  for _, pattern in ipairs(service_patterns) do
    if before_cursor:match(pattern) then return true end
  end

  -- Also trigger when there's a domain pattern for services (like "homeassistant.")
  local domain_pattern = "(%w+)%.$"
  local domain_match = before_cursor:match(domain_pattern)
  
  if domain_match then
    -- Check if it's a valid service domain (more restrictive than entity domains)
    return self:_is_valid_service_domain(domain_match)
  end
  
  -- Also trigger for partial service patterns like "homeassistant.relo"
  local partial_service_pattern = "(%w+)%.[%w_]+$" 
  local partial_domain = before_cursor:match(partial_service_pattern)
  
  if partial_domain then
    return self:_is_valid_service_domain(partial_domain)
  end

  return false
end

---Get services with caching
function M:_get_services(callback)
  utils.cache.fetch_with_cache(_cache, function(fetch_callback)
    -- Fetch from API
    api.get_services(function(success, result)
      if success and result then
        fetch_callback(result)
      else
        -- Return cached data even if stale, or empty map
        local cached_data = _cache:get(300000) -- Try stale cache up to 5 minutes
        fetch_callback(cached_data or {})
      end
    end)
  end, callback)
end

---Format service documentation
function M:_format_service_documentation(domain, service, info)
  local docs = {}

  table.insert(docs, "**Service:** `" .. domain .. "." .. service .. "`")

  if info.description then table.insert(docs, "**Description:** " .. info.description) end

  -- Add service fields if available
  if info.fields then
    table.insert(docs, "**Fields:**")
    for field_name, field_info in pairs(info.fields) do
      local field_desc = field_info.description or "No description"
      table.insert(docs, "- `" .. field_name .. "`: " .. field_desc)
    end
  end

  return table.concat(docs, "\n")
end

return M