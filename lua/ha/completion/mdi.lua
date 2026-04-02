-- Home Assistant MDI (Material Design Icons) completion source for blink.cmp
-- Enhanced version using proper material_icons.lua API with family-based structure

local config = require "ha.config"
local auth = require "ha.auth"
local utils = require "ha.utils"
local material_icons = require "material_icons"

local M = {}

-- Create cache for MDI completion data
local _cache = utils.cache.create_cache("mdi_completion", 300000) -- 5 minutes (icons don't change often)

-- Common Home Assistant icon categories for better sorting
local HA_CATEGORIES = {
  home = { "home", "house", "room", "sofa", "bed", "kitchen", "bathroom", "garage", "office" },
  lighting = { "lightbulb", "light", "lamp", "ceiling", "floor", "desk", "switch", "power", "plug" },
  appliances = { "washing", "machine", "dryer", "dishwasher", "fridge", "microwave", "oven", "vacuum", "robot", "printer" },
  climate = { "thermometer", "thermostat", "air", "conditioner", "fan", "humidity", "temperature", "heat", "cool", "fire", "snowflake" },
  security = { "lock", "key", "shield", "camera", "cctv", "motion", "sensor", "smoke", "detector", "security" },
  openings = { "window", "door", "garage", "gate" },
  weather = { "weather", "sunny", "cloudy", "rainy", "snowy", "windy", "umbrella", "storm" },
  media = { "television", "tv", "speaker", "volume", "play", "pause", "stop", "music", "radio", "cast" },
  sensors = { "eye", "motion", "run", "water", "car", "account", "person", "phone", "device", "tracker" },
  energy = { "battery", "charging", "lightning", "bolt", "electricity", "solar", "panel", "flash", "energy" },
  tech = { "router", "wireless", "wifi", "bluetooth", "cast", "server", "nas", "network" },
  navigation = { "arrow", "menu", "dots", "cog", "settings", "navigation" },
  status = { "check", "close", "alert", "information", "help", "bell", "notification", "warning", "error" },
  garden = { "sprinkler", "flower", "plant", "garden", "tree", "pool", "fence", "outdoor" },
}

---Create new source instance
function M.new() return setmetatable({}, { __index = M }) end

---Check if this source should be enabled
function M:enabled() return utils.workspace.is_ha_file() and self:_should_trigger_mdi_completion() end

---Get completion items
function M:get_completions(context, callback)
  if not self:enabled() then
    callback { items = {} }
    return
  end

  self:_get_mdi_completion_data(function(completion_data)
    local items = {}
    local cursor_text = self:_get_text_before_cursor()
    local filter_text = self:_extract_filter_from_cursor(cursor_text)

    for _, icon_data in ipairs(completion_data) do
      -- Apply filtering if there's partial text after "mdi:"
      if self:_matches_filter(icon_data, filter_text) then
        local display_icon = icon_data.icon or ""

        local item = {
          label = display_icon .. " " .. icon_data.ha_name, -- Use HA-compatible name
          kind = require("blink.cmp.types").CompletionItemKind.Value,
          detail = icon_data.description or "Material Design Icon",
          documentation = {
            kind = "markdown",
            value = self:_format_icon_documentation(icon_data),
          },
          insertText = icon_data.ha_name, -- Insert HA-compatible name
          filterText = icon_data.ha_name .. " " .. (icon_data.description or "") .. " " .. (icon_data.category or ""),
          sortText = self:_get_sort_text(icon_data),
          data = {
            source = "ha_mdi_icons",
            icon = icon_data,
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
function M:get_trigger_characters() return { ":" } end

---Check if we should trigger MDI completion
function M:_should_trigger_mdi_completion()
  local cursor_text = self:_get_text_before_cursor()
  return cursor_text:match("mdi:[%w%-_]*$") or cursor_text:match("mdi:$")
end

---Get text before cursor
function M:_get_text_before_cursor()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2]
  return line:sub(1, col)
end

---Extract filter text from cursor position
function M:_extract_filter_from_cursor(cursor_text)
  local filter = cursor_text:match("mdi:([%w%-_]*)$")
  return filter or ""
end

---Check if icon matches the current filter
function M:_matches_filter(icon_data, filter_text)
  if not filter_text or filter_text == "" then
    return true
  end

  local filter_lower = filter_text:lower()
  
  -- Check HA name match (kebab-case)
  if icon_data.ha_name:lower():find(filter_lower, 1, true) then
    return true
  end
  
  -- Check original name match (snake_case) for backward compatibility
  if icon_data.name:lower():find(filter_lower, 1, true) then
    return true
  end
  
  -- Check description match
  if icon_data.description and icon_data.description:lower():find(filter_lower, 1, true) then
    return true
  end
  
  -- Check category match
  if icon_data.category and icon_data.category:lower():find(filter_lower, 1, true) then
    return true
  end
  
  return false
end

---Get MDI completion data with caching
function M:_get_mdi_completion_data(callback)
  utils.cache.fetch_with_cache(_cache, function(fetch_callback)
    local completion_data = self:_generate_completion_data_from_material_icons()
    fetch_callback(completion_data)
  end, callback)
end

---Generate completion data using the new material_icons.all() method
function M:_generate_completion_data_from_material_icons()
  local completion_data = {}
  
  -- Use the new all() method to get ALL MDI icons without any filtering
  local all_icons = material_icons.all("mdi") -- Get all icons, no limit
  
  -- Convert to our completion data format
  for _, icon_result in ipairs(all_icons) do
    -- Convert snake_case to kebab-case for Home Assistant compatibility
    local ha_name = icon_result.name:gsub("_", "-")
    
    local icon_data = {
      name = icon_result.name,        -- Original name from JSON (snake_case)
      ha_name = ha_name,              -- HA-compatible name (kebab-case)
      icon = icon_result.icon,
      unicode = icon_result.unicode,
      description = self:_generate_description(ha_name), -- Use HA name for description
      category = self:_determine_category(ha_name),       -- Use HA name for categorization
    }
    table.insert(completion_data, icon_data)
  end

  -- Sort by relevance for Home Assistant
  table.sort(completion_data, function(a, b)
    return self:_get_sort_priority(a) > self:_get_sort_priority(b)
  end)

  return completion_data
end

---Generate human-readable description from icon name
function M:_generate_description(icon_name)
  -- Convert kebab-case to human readable
  local description = icon_name:gsub("%-", " "):gsub("_", " ")
  
  -- Capitalize first letter of each word
  description = description:gsub("(%w)(%w*)", function(first, rest)
    return first:upper() .. rest:lower()
  end)
  
  return description
end

---Determine category based on icon name
function M:_determine_category(icon_name)
  local name_lower = icon_name:lower()
  
  for category, keywords in pairs(HA_CATEGORIES) do
    for _, keyword in ipairs(keywords) do
      if name_lower:find(keyword, 1, true) then
        return category
      end
    end
  end
  
  return "other"
end

---Get sort priority for Home Assistant relevance
function M:_get_sort_priority(icon_data)
  local category_priority = {
    home = 10,
    lighting = 9,
    climate = 8,
    security = 7,
    appliances = 6,  -- Moved printer category higher
    openings = 5,
    weather = 4,
    media = 4,
    sensors = 4,
    energy = 3,
    tech = 2,
    navigation = 1,
    status = 1,
    garden = 2,
    other = 0,
  }
  
  return category_priority[icon_data.category] or 0
end

---Get sort text with category-based priority
function M:_get_sort_text(icon_data)
  local priority = self:_get_sort_priority(icon_data)
  -- Use zero-padded priority as prefix for consistent sorting
  return string.format("%02d_%s", 99 - priority, icon_data.ha_name)
end

---Format icon documentation with proper preview
function M:_format_icon_documentation(icon_data)
  local docs = {}

  table.insert(docs, "**Icon:** `mdi:" .. icon_data.ha_name .. "`") -- Use HA name

  if icon_data.description then
    table.insert(docs, "**Description:** " .. icon_data.description)
  end

  if icon_data.category and icon_data.category ~= "other" then
    table.insert(docs, "**Category:** " .. icon_data.category:gsub("^%l", string.upper))
  end

  -- Show actual icon character if available
  local icon_char = icon_data.icon or ""
  if icon_char ~= "" then
    table.insert(docs, "**Preview:** " .. icon_char .. " (requires Material Design Icons font)")
  end
  
  if icon_data.unicode then
    table.insert(docs, "**Unicode:** U+" .. icon_data.unicode:upper())
  end
  
  -- Show original name if different from HA name
  if icon_data.name ~= icon_data.ha_name then
    table.insert(docs, "**Source:** " .. icon_data.name .. " (converted to kebab-case)")
  end

  table.insert(docs, "*Material Design Icons for Home Assistant*")

  return table.concat(docs, "\n")
end

return M
