-- Service picker with enhanced preview and C-s functionality
local M = {}

local formatting = require "ha.ui.formatting"
local core = require "ha.ui.picker.core"
local actions = require "ha.ui.picker.actions"

---Generate dynamic preview content for a service
---@param item table Picker item containing service data
---@return table Preview content
local function generate_service_preview(item)
  local service_data = item.service_data
  
  if not service_data or not service_data.domain or not service_data.service then
    return {
      text = "# No Service Data\n\nService information not available.",
      ft = "markdown",
    }
  end

  local preview_lines = {}
  local domain = service_data.domain
  local service_name = service_data.service
  local service_info = service_data.info or {}

  -- Header with service name
  table.insert(preview_lines, "# " .. domain .. "." .. service_name)
  table.insert(preview_lines, "")

  -- Service description
  if service_info.description and service_info.description ~= "" then
    table.insert(preview_lines, service_info.description)
    table.insert(preview_lines, "")
  end

  -- Service fields with enhanced formatting
  if service_info.fields and next(service_info.fields) then
    table.insert(preview_lines, "## Fields")
    table.insert(preview_lines, "")

    -- Sort fields to show required fields first
    local field_entries = {}
    for field_name, field_info in pairs(service_info.fields) do
      table.insert(field_entries, {
        name = field_name,
        info = field_info,
        required = field_info.required or false,
      })
    end

    table.sort(field_entries, function(a, b)
      if a.required ~= b.required then return a.required and not b.required end
      return a.name < b.name
    end)

    for _, field_entry in ipairs(field_entries) do
      local field_name = field_entry.name
      local field_info = field_entry.info

      table.insert(preview_lines, "### " .. field_name)

      -- Field description
      local field_desc = field_info.description or "No description available"
      table.insert(preview_lines, field_desc)

      -- Field metadata in a structured way
      local metadata_parts = {}

      -- Required status
      if field_info.required then
        table.insert(metadata_parts, "**Required:** Yes")
      else
        table.insert(metadata_parts, "**Required:** No")
      end

      -- Type information from selector
      if field_info.selector then
        local type_info = formatting.format_selector_type(field_info.selector)
        if type_info and type_info ~= "" then table.insert(metadata_parts, "**Type:** " .. type_info) end
      end

      -- Default value if provided
      if field_info.default ~= nil then
        local default_value = formatting.format_value_for_services(field_info.default)
        table.insert(metadata_parts, "**Default:** " .. default_value)
      end

      -- Example value if provided
      if field_info.example ~= nil then
        local example_value = formatting.format_value_for_services(field_info.example)
        table.insert(metadata_parts, "**Example:** " .. example_value)
      end

      -- Add formatted metadata
      if #metadata_parts > 0 then
        table.insert(preview_lines, "")
        for _, part in ipairs(metadata_parts) do
          table.insert(preview_lines, part)
        end
      end

      table.insert(preview_lines, "")
    end
  else
    table.insert(preview_lines, "## Fields")
    table.insert(preview_lines, "")
    table.insert(preview_lines, "No additional fields required.")
    table.insert(preview_lines, "")
  end

  -- Additional service metadata if available
  local has_additional_info = false
  local additional_lines = {}

  if service_info.target then
    local target_info = formatting.format_service_target(service_info.target)
    if target_info and target_info ~= "" then
      table.insert(additional_lines, "**Target:** " .. target_info)
      has_additional_info = true
    end
  end

  if service_info.response then
    local response_info = formatting.format_service_response(service_info.response)
    if response_info and response_info ~= "" then
      table.insert(additional_lines, "**Response:** " .. response_info)
      has_additional_info = true
    end
  end

  if has_additional_info then
    table.insert(preview_lines, "## Additional Information")
    table.insert(preview_lines, "")
    for _, line in ipairs(additional_lines) do
      table.insert(preview_lines, line)
    end
  end

  return {
    text = table.concat(preview_lines, "\n"),
    ft = "markdown",
  }
end

---Create lightweight picker items from services
---@param services table Services data structure
---@return table List of picker items
local function create_service_picker_items(services)
  local items = {}
  local i = 0

  for domain, domain_services in pairs(services) do
    for service_name, service_info in pairs(domain_services) do
      i = i + 1

      table.insert(items, {
        idx = i,
        text = domain .. "." .. service_name,
        description = service_info.description or "",
        service_data = {
          domain = domain,
          service = service_name,
          info = service_info,
        },
      })
    end
  end

  table.sort(items, function(a, b) return a.text < b.text end)
  return items
end

---Show service picker with enhanced preview and C-s functionality
---@param services table List of services
---@param callback function Selection callback
function M.show_service_picker(services, callback)
  local items = create_service_picker_items(services)

  local picker_config = {
    source = "home_assistant_services",
    items = items,
    title = "Select Service (" .. #items .. " available)",
    preview = core.create_preview_function(generate_service_preview),
    format = core.create_format_function("text", "description"),
    confirm = core.create_confirm_function("service_data", callback),
    actions = actions.create_actions_with_insertion("service"),
    win = {
      input = {
        keys = actions.create_keybindings_with_insertion("service"),
      },
      list = {
        keys = actions.create_keybindings_with_insertion("service"),
      },
    },
  }

  core.show_picker(picker_config)
end

return M
