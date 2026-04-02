-- Integration picker with enhanced preview and C-s functionality
local M = {}

local core = require "ha.ui.picker.core"
local actions = require "ha.ui.picker.actions"

---Create integration picker items
---@param integrations table List of integrations (manifests or admin data)
---@return table Formatted picker items
local function create_integration_picker_items(integrations)
  local items = {}

  for i, integration in ipairs(integrations) do
    local display_text = integration.domain or "unknown"
    local description = integration.name or "No name"

    -- Add type/source indicators based on data source
    if integration._source == "admin_api" then
      if integration.integration_type == "virtual" then
        description = description .. " [Virtual]"
      elseif integration.integration_type then
        description = description .. " [" .. integration.integration_type:gsub("^%l", string.upper) .. "]"
      end
    else
      -- Built-in indicator for manifest API
      if integration.is_built_in == false then description = description .. " [Custom]" end
    end

    table.insert(items, {
      idx = i,
      text = display_text,
      description = description,
      integration_data = integration,
    })
  end

  return items
end

---Generate integration preview content
---@param item table Picker item containing integration data
---@return table Preview data with text and filetype
local function generate_integration_preview(item)
  local integration = item.integration_data
  local lines = {}

  -- Header
  table.insert(lines, "# " .. (integration.name or "Unknown Integration"))
  table.insert(lines, "")

  -- Basic Information
  table.insert(lines, "**Domain:** " .. (integration.domain or "unknown"))

  if integration.version then table.insert(lines, "**Version:** " .. integration.version) end

  -- Data Source and Type Information
  if integration._source == "admin_api" then
    table.insert(lines, "**API:** Admin (enhanced data)")

    if integration.integration_type then
      table.insert(lines, "**Type:** " .. integration.integration_type:gsub("_", " "):gsub("^%l", string.upper))
    end

    if integration.iot_class then
      table.insert(lines, "**IoT Class:** " .. integration.iot_class:gsub("_", " "):gsub("^%l", string.upper))
    end
  elseif integration._source == "manifest_api" then
    table.insert(lines, "**API:** Basic (manifest)")
  end

  -- Admin API specific data
  if integration._source == "admin_api" then
    -- Configuration and features
    if integration.config_flow ~= nil then
      table.insert(lines, "")
      table.insert(lines, "**Config Flow:** " .. (integration.config_flow and "✓ Supported" or "✗ Manual only"))
    end

    if integration.single_config_entry ~= nil then
      table.insert(
        lines,
        "**Multi-Instance:** " .. (integration.single_config_entry and "✗ Single only" or "✓ Supported")
      )
    end

    if integration.supported_by then table.insert(lines, "**Supported By:** " .. integration.supported_by) end

    if integration.quality_scale then table.insert(lines, "**Quality Scale:** " .. integration.quality_scale) end

    -- Technical details
    if integration.documentation then
      table.insert(lines, "")
      table.insert(lines, "**Documentation:** " .. integration.documentation)
    end

    if integration.requirements and #integration.requirements > 0 then
      table.insert(lines, "")
      table.insert(lines, "**Requirements:**")
      for _, req in ipairs(integration.requirements) do
        table.insert(lines, "  • " .. req)
      end
    end

    if integration.dependencies and #integration.dependencies > 0 then
      table.insert(lines, "")
      table.insert(lines, "**Dependencies:**")
      for _, dep in ipairs(integration.dependencies) do
        table.insert(lines, "  • " .. dep)
      end
    end

    if integration.iot_standards and #integration.iot_standards > 0 then
      table.insert(lines, "")
      table.insert(lines, "**IoT Standards:**")
      for _, standard in ipairs(integration.iot_standards) do
        table.insert(lines, "  • " .. standard)
      end
    end

  -- Manifest API specific data
  elseif integration.manifest then
    if integration.manifest.name then table.insert(lines, "**Display Name:** " .. integration.manifest.name) end

    if integration.manifest.documentation then
      table.insert(lines, "**Documentation:** " .. integration.manifest.documentation)
    end

    if integration.manifest.requirements and #integration.manifest.requirements > 0 then
      table.insert(lines, "")
      table.insert(lines, "**Requirements:**")
      for _, req in ipairs(integration.manifest.requirements) do
        table.insert(lines, "  • " .. req)
      end
    end

    if integration.manifest.dependencies and #integration.manifest.dependencies > 0 then
      table.insert(lines, "")
      table.insert(lines, "**Dependencies:**")
      for _, dep in ipairs(integration.manifest.dependencies) do
        table.insert(lines, "  • " .. dep)
      end
    end

    if integration.manifest.config_flow ~= nil then
      table.insert(lines, "")
      table.insert(
        lines,
        "**Config Flow:** " .. (integration.manifest.config_flow and "✓ Supported" or "✗ Manual only")
      )
    end

    if integration.manifest.quality_scale then
      table.insert(lines, "**Quality Scale:** " .. integration.manifest.quality_scale)
    end
  end

  -- Integration Type
  if integration.is_built_in ~= nil then
    table.insert(lines, "")
    table.insert(lines, "**Type:** " .. (integration.is_built_in and "Built-in" or "Custom"))
  end

  return {
    text = table.concat(lines, "\n"),
    ft = "markdown",
  }
end

---Show integration picker with enhanced preview and C-s functionality
---@param integrations table List of integrations
---@param callback function Selection callback
function M.show_integration_picker(integrations, callback)
  local items = create_integration_picker_items(integrations)

  local picker_config = {
    source = "home_assistant_integrations",
    items = items,
    title = "Select Integration (" .. #items .. " available)",
    preview = core.create_preview_function(generate_integration_preview),
    format = core.create_format_function("text", "description"),
    confirm = core.create_confirm_function("integration_data", callback),
    actions = actions.create_actions_with_insertion("integration"),
    win = {
      input = {
        keys = actions.create_keybindings_with_insertion("integration"),
      },
      list = {
        keys = actions.create_keybindings_with_insertion("integration"),
      },
    },
  }

  core.show_picker(picker_config)
end

return M
