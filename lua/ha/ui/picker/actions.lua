-- Reusable picker actions, including the C-s insertion functionality
local M = {}

---Create a generic insertion action for pickers
---@param config table Configuration for the insertion action
---  - extract_fn: function(item) -> string - Function to extract identifier from picker item
---  - format_fn: function(identifiers) -> string - Optional function to format list of identifiers
---  - notification_name: string - Name to use in success notifications (e.g., "entities", "services")
---@return table Action configuration for snacks.picker
function M.create_insertion_action(config)
  local extract_fn = config.extract_fn
  local format_fn = config.format_fn or function(identifiers)
    return #identifiers == 1 and identifiers[1] or table.concat(identifiers, "\n")
  end
  local notification_name = config.notification_name or "items"

  return {
    action = function(picker, item)
      local selected_items = picker:selected { fallback = true }
      picker:close()

      vim.schedule(function()
        local buf = vim.api.nvim_get_current_buf()
        local cursor = vim.api.nvim_win_get_cursor(0)
        local row = cursor[1] - 1
        local col = cursor[2]

        -- Extract identifiers using the provided function
        local identifiers = {}
        for _, selected_item in ipairs(selected_items) do
          local identifier = extract_fn(selected_item)
          if identifier and identifier ~= "" then
            table.insert(identifiers, identifier)
          end
        end

        if #identifiers == 0 then
          vim.notify("No " .. notification_name .. " to insert", vim.log.levels.WARN)
          return
        end

        -- Format the text to insert
        local text_to_insert = format_fn(identifiers)
        local lines = vim.split(text_to_insert, "\n", { plain = true })
        local current_line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""

        if #lines == 1 then
          -- Single line insertion
          local new_line = current_line:sub(1, col) .. lines[1] .. current_line:sub(col + 1)
          vim.api.nvim_buf_set_lines(buf, row, row + 1, false, { new_line })
          vim.api.nvim_win_set_cursor(0, { row + 1, col + #lines[1] })
        else
          -- Multi-line insertion
          local first_line = current_line:sub(1, col) .. lines[1]
          local last_line = lines[#lines] .. current_line:sub(col + 1)

          local insert_lines = { first_line }
          for i = 2, #lines - 1 do
            table.insert(insert_lines, lines[i])
          end
          table.insert(insert_lines, last_line)

          vim.api.nvim_buf_set_lines(buf, row, row + 1, false, insert_lines)
          vim.api.nvim_win_set_cursor(0, { row + #lines, #lines[#lines] + (#lines > 1 and 0 or col) })
        end

        -- Success notification
        local count_msg = #identifiers == 1 and (notification_name:gsub("s$", "")) or (#identifiers .. " " .. notification_name)
        vim.notify("Inserted " .. count_msg .. " into buffer", vim.log.levels.INFO)
      end)
    end,
  }
end

---Standard extraction functions for different picker types
M.extractors = {
  entity = function(item)
    return item.entity and item.entity.entity_id or nil
  end,
  
  service = function(item)
    local service_data = item.service_data
    if service_data and service_data.domain and service_data.service then
      return service_data.domain .. "." .. service_data.service
    end
    return nil
  end,
  
  integration = function(item)
    return item.integration_data and item.integration_data.domain or nil
  end,
  
  area = function(item)
    -- Prefer area name over area_id for readability
    if item.area and item.area.name then
      return item.area.name
    end
    return item.area_id or nil
  end,
  
  reload_option = function(item)
    return item.option and item.option.name or nil
  end,
}

---Create standard insertion actions for common picker types
---@param picker_type string Type of picker ("entity", "service", "integration", "area", "reload_option")
---@return table Action configuration
function M.create_standard_insertion_action(picker_type)
  local extractor = M.extractors[picker_type]
  
  if not extractor then
    error("Unknown picker type: " .. picker_type)
  end
  
  -- Convert picker_type to proper notification name
  local notification_names = {
    entity = "entities",
    service = "services", 
    integration = "integrations",
    area = "areas",
    reload_option = "reload options",
  }
  
  return M.create_insertion_action({
    extract_fn = extractor,
    notification_name = notification_names[picker_type] or picker_type .. "s",
  })
end

---Create keybinding configuration that includes C-s insertion action
---@param picker_type string Type of picker for standard insertion action
---@param custom_keys table|nil Additional custom keybindings
---@return table Keybinding configuration
function M.create_keybindings_with_insertion(picker_type, custom_keys)
  local keys = custom_keys or {}
  
  -- Add the standard C-s insertion action
  keys["<C-s>"] = {
    "insert_items",
    desc = "Insert selected " .. picker_type .. "s into buffer", 
    mode = { "n", "i" },
  }
  
  return keys
end

---Create actions table that includes insertion action
---@param picker_type string Type of picker for standard insertion action
---@param custom_actions table|nil Additional custom actions
---@return table Actions configuration
function M.create_actions_with_insertion(picker_type, custom_actions)
  local actions = custom_actions or {}
  
  -- Add the standard insertion action
  actions.insert_items = M.create_standard_insertion_action(picker_type)
  
  return actions
end

return M
