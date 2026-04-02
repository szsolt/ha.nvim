-- Core picker utilities and common functionality
local M = {}

local snacks = require "snacks"

---Create standardized preview function for markdown content
---@param preview_generator function Function that generates preview data for an item
---@return function Preview function compatible with snacks.picker
function M.create_preview_function(preview_generator)
  return function(ctx)
    ctx.preview:reset()

    if not ctx.item then
      local lines = vim.split("# No Item Selected\n\nNo information available.", "\n")
      ctx.preview:set_lines(lines)
      ctx.preview:highlight { ft = "markdown" }
      return
    end

    local preview_data = preview_generator(ctx.item)
    local lines = vim.split(preview_data.text, "\n")
    ctx.preview:set_lines(lines)
    ctx.preview:highlight { ft = preview_data.ft or "markdown" }
  end
end

---Create standardized picker configuration
---@param config table Picker configuration
---@return table Complete snacks.picker configuration
function M.create_picker_config(config)
  local picker_config = {
    source = config.source,
    items = config.items,
    title = config.title,
    preview = config.preview,
    format = config.format,
    confirm = config.confirm,
    actions = config.actions or {},
    on_show = config.on_show,
    win = {
      preview = {
        wo = {
          conceallevel = 2,
          concealcursor = "",
        },
      },
    },
  }

  -- Merge custom window configuration
  if config.win then picker_config.win = vim.tbl_deep_extend("force", picker_config.win, config.win) end

  return picker_config
end

---Create standardized format function for picker items
---@param label_key string Key to use for the main label (e.g., "text", "name")
---@param description_key string|nil Optional key for description text
---@param availability_check function|nil Optional function to check if item is available
---@return function Format function compatible with snacks.picker
function M.create_format_function(label_key, description_key, availability_check)
  return function(item, _)
    local ret = {}
    local is_available = availability_check and availability_check(item) or true
    local label_hl = is_available and "SnacksPickerLabel" or "Comment"
    local comment_hl = is_available and "SnacksPickerComment" or "Comment"

    -- Main label
    local label_text = item[label_key] or "unknown"
    ret[#ret + 1] = { label_text, label_hl }

    -- Description if provided
    if description_key and item[description_key] and item[description_key] ~= "" then
      ret[#ret + 1] = { " - ", comment_hl }
      ret[#ret + 1] = { item[description_key], comment_hl }
    end

    -- Additional status info for unavailable items
    if availability_check and not is_available and item.entity and item.entity.state then
      ret[#ret + 1] = { " ", comment_hl }
      ret[#ret + 1] = { "(" .. tostring(item.entity.state) .. ")", comment_hl }
    end

    return ret
  end
end

---Create standardized confirm function
---@param data_key string Key to extract data from selected item
---@param callback function Callback to invoke with selected data
---@return function Confirm function compatible with snacks.picker
function M.create_confirm_function(data_key, callback)
  return function(picker, item)
    picker:close()
    if callback and item and item[data_key] then callback(item[data_key]) end
  end
end

---Show a generic picker with the provided configuration
---@param config table Picker configuration
function M.show_picker(config)
  local picker_config = M.create_picker_config(config)
  snacks.picker.pick(picker_config)
end

return M
