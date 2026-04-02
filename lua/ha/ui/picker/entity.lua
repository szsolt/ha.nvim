-- Entity picker with filtering capabilities
local M = {}

local utils = require "ha.utils"
local formatting = require "ha.ui.formatting"
local registry = require "ha.utils.registry"
local core = require "ha.ui.picker.core"
local actions = require "ha.ui.picker.actions"

---Get available domains from entities
---@param entities table List of entities
---@return table List of unique domains with counts
local function get_available_domains(entities)
  local domain_counts = {}

  for _, entity in ipairs(entities) do
    if entity and entity.entity_id then
      local domain = entity.entity_id:match "^([^%.]+)%."
      if domain then domain_counts[domain] = (domain_counts[domain] or 0) + 1 end
    end
  end

  local domains = {}
  for domain, count in pairs(domain_counts) do
    table.insert(domains, { name = domain, count = count })
  end

  table.sort(domains, function(a, b) return a.name < b.name end)
  return domains
end

---Get available device classes from entities
---@param entities table List of entities
---@return table List of device classes with counts
local function get_available_device_classes(entities)
  local device_class_counts = {}

  for _, entity in ipairs(entities) do
    if entity.attributes and entity.attributes.device_class then
      local device_class = entity.attributes.device_class
      device_class_counts[device_class] = (device_class_counts[device_class] or 0) + 1
    end
  end

  local device_class_list = {}
  for device_class, count in pairs(device_class_counts) do
    table.insert(device_class_list, {
      name = device_class,
      count = count,
    })
  end

  table.sort(device_class_list, function(a, b)
    if a.count == b.count then return a.name < b.name end
    return a.count > b.count
  end)

  return device_class_list
end

---Get available platforms from entities
---@param entities table List of entities
---@return table List of platforms with counts
local function get_available_platforms(entities)
  local platform_counts = {}

  for _, entity in ipairs(entities) do
    if entity.platform then platform_counts[entity.platform] = (platform_counts[entity.platform] or 0) + 1 end
  end

  local platforms = {}
  for platform, count in pairs(platform_counts) do
    table.insert(platforms, { name = platform, count = count })
  end

  table.sort(platforms, function(a, b) return a.name < b.name end)
  return platforms
end

---Get available areas from entities
---@param entities table List of entities
---@return table List of areas with entity counts
local function get_available_areas(entities)
  local area_counts = {}
  local areas = registry.get_areas()

  for _, entity in ipairs(entities) do
    if entity and entity.area_id then area_counts[entity.area_id] = (area_counts[entity.area_id] or 0) + 1 end
  end

  local area_list = {}
  for area_id, count in pairs(area_counts) do
    local area = areas[area_id]
    local area_name = area and area.name or area_id
    table.insert(area_list, {
      id = area_id,
      name = area_name,
      count = count,
    })
  end

  table.sort(area_list, function(a, b) return a.name < b.name end)
  return area_list
end

---Check if entity is available (not unknown/unavailable)
---@param entity table Entity to check
---@return boolean True if entity is available
local function is_entity_available(entity)
  if not entity or not entity.state then return false end
  local state = tostring(entity.state):lower()
  return state ~= "unknown" and state ~= "unavailable"
end

---Check if picker item entity is available
---@param item table Picker item
---@return boolean True if entity is available
local function is_picker_item_available(item) return item.entity and is_entity_available(item.entity) end
---Filter entities by criteria
---@param entities table List of entities
---@param filters table Filter criteria
---@return table Filtered entities
local function filter_entities(entities, filters)
  local filtered = {}

  for _, entity in ipairs(entities) do
    local include = true

    -- Domain filter
    if filters.domain then
      local domain = entity.entity_id:match "^([^%.]+)%."
      if domain ~= filters.domain then include = false end
    end

    -- Area filter
    if filters.area_id and entity.area_id ~= filters.area_id then include = false end

    -- Device class filter
    if filters.device_class then
      local entity_device_class = entity.attributes and entity.attributes.device_class
      if entity_device_class ~= filters.device_class then include = false end
    end

    -- Platform filter
    if filters.platform and entity.platform ~= filters.platform then include = false end

    -- Availability filter (hide unavailable entities by default)
    if filters.hide_unavailable ~= false and not is_entity_available(entity) then include = false end

    if include then table.insert(filtered, entity) end
  end

  return filtered
end

---Create title with filter info
---@param total_count number Total entity count
---@param filtered_count number Filtered entity count
---@param filters table Current filters
---@return string Title string
local function create_title(total_count, filtered_count, filters)
  local title_parts = { "Select Entity" }

  local filter_parts = {}
  if filters.domain then table.insert(filter_parts, "domain:" .. filters.domain) end
  if filters.area_id then
    local areas = registry.get_areas()
    local area = areas[filters.area_id]
    local area_name = area and area.name or filters.area_id
    table.insert(filter_parts, "area:" .. area_name)
  end
  if filters.device_class then table.insert(filter_parts, "class:" .. filters.device_class) end
  if filters.platform then table.insert(filter_parts, "platform:" .. filters.platform) end
  if filters.hide_unavailable ~= false then
    table.insert(filter_parts, "available")
  else
    table.insert(filter_parts, "all")
  end

  if #filter_parts > 0 then table.insert(title_parts, "[" .. table.concat(filter_parts, ", ") .. "]") end

  table.insert(title_parts, "(" .. filtered_count .. "/" .. total_count .. ")")

  return table.concat(title_parts, " ")
end

---Create lightweight picker items from entities
---@param entities table List of entities to convert
---@return table List of picker items
local function create_picker_items(entities)
  local items = {}
  for i, entity in ipairs(entities) do
    if entity and entity.entity_id then
      local friendly_name = entity.attributes and entity.attributes.friendly_name or ""

      table.insert(items, {
        idx = i,
        text = entity.entity_id,
        friendly_name = friendly_name,
        entity = entity,
      })
    end
  end
  return items
end

---Generate dynamic preview content for an entity
---@param item table Picker item containing entity data
---@return table Preview content
local function generate_entity_preview(item)
  local entity = item.entity

  if not entity or not entity.entity_id then
    return {
      text = "# No Entity Data\n\nEntity information not available.",
      ft = "markdown",
    }
  end

  local preview_lines = {}

  table.insert(preview_lines, "# " .. entity.entity_id)
  table.insert(preview_lines, "")

  local friendly_name = entity.attributes and entity.attributes.friendly_name or ""
  if friendly_name and friendly_name ~= "" then table.insert(preview_lines, "**Name:** " .. friendly_name) end

  table.insert(preview_lines, "**State:** `" .. tostring(entity.state or "unknown") .. "`")

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
        local formatted_value = formatting.format_value_for_docs(value)

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
      if not key:match "^_" and key ~= "device_name" and key ~= "device_id" then
        local formatted_key = key:gsub("_", " "):gsub("^%l", string.upper)
        local formatted_value = formatting.format_value_for_docs(value)

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

---Generic filter picker configuration
local filter_configs = {
  domain = {
    key = "<C-d>",
    desc = "Filter by domain",
    title = "Filter by Domain",
    source = "home_assistant_domains",
    get_options = get_available_domains,
    get_filter_key = function(item) return item.name end,
    create_preview = function(item)
      return {
        text = "# Domain: "
          .. item.name
          .. "\n\n**Entities in this domain:** "
          .. item.count
          .. "\n\nThis will filter the entity picker to show only entities in the **"
          .. item.name
          .. "** domain.",
        ft = "markdown",
      }
    end,
  },
  area_id = {
    key = "<C-l>",
    desc = "Filter by location (area)",
    title = "Filter by Area",
    source = "home_assistant_area_filter",
    get_options = get_available_areas,
    get_filter_key = function(item) return item.id end,
    create_preview = function(item)
      return {
        text = "# Area: "
          .. item.name
          .. "\n\n**Entities in this area:** "
          .. item.count
          .. "\n\nThis will filter the entity picker to show only entities located in the **"
          .. item.name
          .. "** area.",
        ft = "markdown",
      }
    end,
  },
  platform = {
    key = "<C-p>",
    desc = "Filter by platform",
    title = "Filter by Platform",
    source = "home_assistant_platforms",
    get_options = get_available_platforms,
    get_filter_key = function(item) return item.name end,
    create_preview = function(item)
      return {
        text = "# Platform: "
          .. item.name
          .. "\n\n**Entities from this platform:** "
          .. item.count
          .. "\n\nThis will filter the entity picker to show only entities from the **"
          .. item.name
          .. "** platform.\n\n**Examples:** MQTT, Z-Wave, Zigbee, local integrations, etc.",
        ft = "markdown",
      }
    end,
  },
  device_class = {
    key = "<C-u>",
    desc = "Filter by device class",
    title = "Filter by Device Class",
    source = "home_assistant_device_classes",
    get_options = get_available_device_classes,
    get_filter_key = function(item) return item.name end,
    create_preview = function(item)
      return {
        text = "# Device Class: "
          .. item.name
          .. "\n\n**Entities with this device class:** "
          .. item.count
          .. "\n\nThis will filter the entity picker to show only entities with the **"
          .. item.name
          .. "** device class.\n\n**Examples:** Temperature sensors, power monitors, battery levels, etc.",
        ft = "markdown",
      }
    end,
  },
}
---Generic filter picker function
---@param filter_type string Type of filter (domain, area_id, platform, device_class)
---@param entities_to_process table Current processed entities
---@param current_filters table Current filter state
---@param callback function Entity selection callback
---@param target_entity_id string|nil Optional entity ID to focus on after filtering
local function show_filter_picker(filter_type, entities_to_process, current_filters, callback, target_entity_id)
  local config = filter_configs[filter_type]

  if not config then
    vim.notify("Unknown filter type: " .. filter_type, vim.log.levels.ERROR)
    return
  end

  local options = config.get_options(entities_to_process)

  if #options == 0 then
    vim.notify("No " .. filter_type .. " options available", vim.log.levels.INFO)
    return
  end

  local items = {}
  for i, option in ipairs(options) do
    table.insert(items, {
      idx = i,
      text = option.name,
      count = tostring(option.count), -- Convert count to string
      filter_value = config.get_filter_key(option),
      preview = config.create_preview(option),
    })
  end

  local picker_config = {
    source = config.source,
    items = items,
    title = config.title,
    preview = "preview",
    format = core.create_format_function("text", "count"),
    confirm = function(picker, item)
      picker:close()
      if item and item.filter_value then
        vim.schedule(function()
          local new_filters = vim.deepcopy(current_filters)
          new_filters[filter_type] = item.filter_value
          M.show_entity_picker_internal(callback, new_filters, target_entity_id)
        end)
      end
    end,
    win = {
      input = {
        keys = {
          ["<Esc>"] = {
            function(picker)
              picker:close()
              M.show_entity_picker_internal(callback, current_filters, target_entity_id)
            end,
            desc = "Cancel filter selection",
            mode = { "n", "i" },
          },
        },
      },
    },
  }

  core.show_picker(picker_config)
end

---Create main entity picker keybindings
---@param entities_to_process table Current processed entities
---@param current_filters table Current filter state
---@param callback function Entity selection callback
---@param target_entity_id string|nil Optional entity ID to focus on
---@return table Keybinding configuration
local function create_main_picker_keybindings(entities_to_process, current_filters, callback, target_entity_id)
  local keys = {}

  -- Filter keybindings (only for main picker)
  for filter_type, config in pairs(filter_configs) do
    keys[config.key] = {
      function(picker)
        picker:close()
        show_filter_picker(filter_type, entities_to_process, current_filters, callback, target_entity_id)
      end,
      desc = config.desc,
      mode = { "n", "i" },
    }
  end

  -- Toggle availability and reset filters
  keys["<C-h>"] = {
    function(picker)
      picker:close()
      vim.schedule(function()
        local new_filters = vim.deepcopy(current_filters)
        new_filters.hide_unavailable = not new_filters.hide_unavailable
        local status = new_filters.hide_unavailable and "hidden" or "shown"
        vim.notify("Unavailable entities " .. status, vim.log.levels.INFO)
        M.show_entity_picker_internal(callback, new_filters, target_entity_id)
      end)
    end,
    desc = "Toggle unavailable entities",
    mode = { "n", "i" },
  }

  keys["<C-r>"] = {
    function(picker)
      picker:close()
      vim.schedule(function() M.show_entity_picker_internal(callback, {}, target_entity_id) end)
    end,
    desc = "Reset filters",
    mode = { "n", "i" },
  }

  -- Add insertion action keybinding
  local insertion_keys = actions.create_keybindings_with_insertion "entity"
  for key, binding in pairs(insertion_keys) do
    keys[key] = binding
  end

  return keys
end
---Internal function to show entity picker with filters
---@param callback function Selection callback
---@param filters table|nil Current filters
---@param target_entity_id string|nil Optional entity ID to focus on
function M.show_entity_picker_internal(callback, filters, target_entity_id)
  filters = filters or {}

  if filters.hide_unavailable == nil then filters.hide_unavailable = true end

  if not registry.get_stats().initialized then
    utils.logger.warn "Registry not initialized, initializing now..."
    registry.initialize(function(success, error)
      if success then
        M.show_entity_picker_internal(callback, filters, target_entity_id)
      else
        vim.notify("Failed to initialize registry: " .. tostring(error), vim.log.levels.ERROR)
      end
    end)
    return
  end

  local all_entities = registry.get_all_entities()

  if #all_entities == 0 then
    vim.notify("No entities found", vim.log.levels.INFO)
    return
  end

  local entities_to_process = all_entities

  if filters.hide_unavailable ~= false then
    entities_to_process = filter_entities(all_entities, filters)
  else
    local temp_filters = vim.deepcopy(filters)
    temp_filters.hide_unavailable = false
    entities_to_process = filter_entities(all_entities, temp_filters)
  end

  if #entities_to_process == 0 then
    vim.notify("No entities match the current filters", vim.log.levels.INFO)
    return
  end

  local items = create_picker_items(entities_to_process)
  local title = create_title(#all_entities, #entities_to_process, filters)

  local picker_config = {
    source = "home_assistant_entities",
    items = items,
    title = title,
    preview = function(ctx)
      ctx.preview:reset()

      if not ctx.item or not ctx.item.entity then
        local lines = vim.split("# No Entity Selected\n\nNo entity information available.", "\n")
        ctx.preview:set_lines(lines)
        ctx.preview:highlight { ft = "markdown" }
        return
      end

      local entity_id = ctx.item.entity.entity_id
      local fresh_entity = registry.get_entity(entity_id)
      local entity_data = fresh_entity or ctx.item.entity

      -- Update the item with fresh data
      local updated_item = vim.deepcopy(ctx.item)
      updated_item.entity = entity_data

      local preview_data = generate_entity_preview(updated_item)

      local lines = vim.split(preview_data.text, "\n")
      ctx.preview:set_lines(lines)
      ctx.preview:highlight { ft = preview_data.ft or "markdown" }
    end,
    format = core.create_format_function("text", "friendly_name", is_picker_item_available),
    confirm = core.create_confirm_function("entity", callback),
    actions = actions.create_actions_with_insertion "entity",
    on_show = function(picker)
      if target_entity_id then
        -- Validate entity exists first
        local registry_entity = registry.get_entity(target_entity_id)
        if not registry_entity then
          vim.notify("Entity '" .. target_entity_id .. "' not found in registry", vim.log.levels.WARN)
          picker:focus "input"  -- Focus input when entity not found
          picker:show_preview()
          return
        end

        -- Find the item index that matches the entity_id
        local items = picker:items()
        for i, item in ipairs(items) do
          if item.text == target_entity_id or (item.entity and item.entity.entity_id == target_entity_id) then
            -- Use the snacks.nvim internal _move method to position cursor
            picker.list:_move(i, true, true)
            picker:focus "list"
            picker:show_preview()
            return
          end
        end

        -- Entity exists but not in current filtered view
        -- Check if we already have no filters - if so, the entity is unavailable
        local has_filters = filters.domain or filters.area_id or filters.device_class or filters.platform
        if not has_filters and filters.hide_unavailable ~= false then
          -- Try once more with hide_unavailable = false
          vim.notify(
            "Entity '" .. target_entity_id .. "' is unavailable. Showing all entities...",
            vim.log.levels.INFO
          )
          vim.schedule(function() 
            M.show_entity_picker_internal(callback, { hide_unavailable = false }, target_entity_id) 
          end)
          picker:close()
          return
        elseif not has_filters then
          -- Already showing all entities including unavailable - entity just doesn't match
          vim.notify(
            "Entity '" .. target_entity_id .. "' not found in current view.",
            vim.log.levels.WARN
          )
          picker:focus "input"
          picker:show_preview()
          return
        else
          -- Has other filters - reset them
          vim.notify(
            "Entity '" .. target_entity_id .. "' filtered out of current view. Resetting filters...",
            vim.log.levels.INFO
          )
          vim.schedule(function() M.show_entity_picker_internal(callback, {}, target_entity_id) end)
          picker:close()
          return
        end
      end

      -- Normal behavior when no target entity specified - focus input field
      picker:focus "input"
      picker:show_preview()
    end,
    win = {
      input = {
        keys = create_main_picker_keybindings(entities_to_process, filters, callback, target_entity_id),
      },
      list = {
        keys = create_main_picker_keybindings(entities_to_process, filters, callback, target_entity_id),
      },
    },
  }

  core.show_picker(picker_config)
end

---Show entity picker with filtering capabilities
---@param callback function Selection callback
---@param target_entity_id string|nil Optional entity ID to focus on
function M.show_entity_picker(callback, target_entity_id) M.show_entity_picker_internal(callback, {}, target_entity_id) end

return M
