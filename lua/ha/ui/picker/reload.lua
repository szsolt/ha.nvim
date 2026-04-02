-- Reload options picker with C-s functionality
local M = {}

local core = require "ha.ui.picker.core"
local actions = require "ha.ui.picker.actions"

---Generate reload option preview content
---@param item table Picker item containing reload option data
---@return table Preview content
local function generate_reload_preview(item)
  local option = item.option
  
  if not option then
    return {
      text = "# No Reload Option Data\n\nReload option information not available.",
      ft = "markdown",
    }
  end

  local preview_text = "# Reload Option: "
    .. option.name
    .. "\n\n**Service:** "
    .. option.description
    .. "\n\nThis will reload the specified Home Assistant component."

  return {
    text = preview_text,
    ft = "markdown",
  }
end

---Show reload options picker with C-s functionality
---@param options table List of reload options
---@param callback function Selection callback
function M.show_reload_options(options, callback)
  local items = {}
  for i, option in ipairs(options) do
    table.insert(items, {
      idx = i,
      text = option.name,
      description = option.description,
      option = option,
    })
  end

  local picker_config = {
    source = "home_assistant_reload",
    items = items,
    title = "Select Integration to Reload",
    preview = core.create_preview_function(generate_reload_preview),
    format = core.create_format_function("text", "description"),
    confirm = core.create_confirm_function("option", callback),
    actions = actions.create_actions_with_insertion("reload_option"),
    win = {
      input = {
        keys = actions.create_keybindings_with_insertion("reload_option"),
      },
    },
  }

  core.show_picker(picker_config)
end

return M
