-- Streamlined ha.nvim command system
-- Eliminates duplication and focuses on essential functionality

local M = {}

local config = require "ha.config"
local auth = require "ha.auth"
local api = require "ha.api"
local ui = require "ha.ui"

-- Unified command tree structure
local commands_tree = {
  description = "Home Assistant Commands",
  children = {
    auth = {
      description = "Authentication & credential management",
      children = {
        setup = {
          description = "Setup credentials interactively",
          callback = function() M.auth_setup() end,
        },
        test = {
          description = "Test current connection",
          callback = function() M.auth_test() end,
        },
        clear = {
          description = "Clear stored credentials",
          callback = function() M.auth_clear() end,
        },
        show = {
          description = "Show current authentication details",
          callback = function() M.auth_show() end,
        },
      },
    },
    entities = {
      description = "Browse entities (auto-detects entity under cursor or use explicit argument)",
      callback = function(args)
        local entity_id = nil

        -- Check for explicit argument first
        if args and args[1] and args[1] ~= "" then
          entity_id = args[1]
        else
          -- Try to detect entity under cursor
          entity_id = M.get_entity_under_cursor()
        end

        M.entity_picker(entity_id)
      end,
    },
    services = {
      description = "Browse and call Home Assistant services",
      callback = function() M.service_picker() end,
    },
    integrations = {
      description = "Browse installed Home Assistant integrations",
      callback = function() M.integration_picker() end,
    },
    reload = {
      description = "Reload Home Assistant configurations",
      children = {
        lovelace = {
          description = "Refresh Lovelace UI configuration",
          callback = function() M.reload_lovelace() end,
        },
        all = {
          description = "Reload all configurations (homeassistant.reload_all)",
          callback = function() M.reload_all() end,
        },
        automations = {
          description = "Reload automation configurations",
          callback = function() M.reload_automations() end,
        },
        scripts = {
          description = "Reload script configurations",
          callback = function() M.reload_scripts() end,
        },
        scenes = {
          description = "Reload scene configurations",
          callback = function() M.reload_scenes() end,
        },
        groups = {
          description = "Reload group configurations",
          callback = function() M.reload_groups() end,
        },
        themes = {
          description = "Reload theme configurations",
          callback = function() M.reload_themes() end,
        },
        core_config = {
          description = "Reload core Home Assistant configuration",
          callback = function() M.reload_core_config() end,
        },
        input = {
          description = "Reload all input helper configurations",
          callback = function() M.reload_input_helpers() end,
        },
      },
    },
    call = {
      description = "Call Home Assistant service directly (domain.service)",
      callback = function() M.call_service_direct() end,
    },
    template = {
      description = "Home Assistant template rendering",
      children = {
        render = {
          description = "Render template from selection or prompt",
          callback = function() M.render_template() end,
        },
        toggle = {
          description = "Toggle template result window",
          callback = function() M.toggle_template_channel() end,
        },
        help = {
          description = "Show template functions reference",
          callback = function() M.show_template_help() end,
        },
      },
    },
    restart = {
      description = "Restart Home Assistant server",
      callback = function() M.restart_homeassistant() end,
    },
    status = {
      description = "Show Home Assistant connection status",
      callback = function() M.show_status() end,
    },
    log = {
      description = "Show Home Assistant error log",
      callback = function() M.show_error_log() end,
    },
    open = {
      description = "Open Home Assistant in browser",
      callback = function() M.open_in_browser() end,
    },
    diagnostics = {
      description = "HA diagnostics commands",
      children = {
        run = {
          description = "Run diagnostics on current buffer",
          callback = function() M.run_diagnostics() end,
        },
        clear = {
          description = "Clear diagnostics from current buffer",
          callback = function() M.clear_diagnostics() end,
        },
        refresh = {
          description = "Refresh diagnostics for all HA buffers",
          callback = function() M.refresh_diagnostics() end,
        },
        stats = {
          description = "Show diagnostics statistics",
          callback = function() M.show_diagnostics_stats() end,
        },
      },
    },
    lsp = {
      description = "HA Language Server commands",
      children = {
        toggle = {
          description = "Toggle HA LSP on/off",
          callback = function() M.toggle_lsp() end,
        },
        stop = {
          description = "Stop HA LSP",
          callback = function() M.stop_lsp() end,
        },
        start = {
          description = "Start HA LSP",
          callback = function() M.start_lsp() end,
        },
        restart = {
          description = "Restart HA LSP",
          callback = function() M.restart_lsp() end,
        },
        status = {
          description = "Show HA LSP status",
          callback = function() M.lsp_status() end,
        },
      },
    },
  },
}

---Setup unified command system
function M.setup()
  if config.get_value("commands.create_user_commands", true) then M.create_user_commands() end
end

---Create user commands with streamlined interface
function M.create_user_commands()
  local prefix = config.get_value("commands.prefix", "ha")
  local cmd_name = string.upper(prefix:sub(1, 1)) .. prefix:sub(2)

  vim.api.nvim_create_user_command(cmd_name, function(cmd)
    local command, args = M.parse(cmd.args)
    M.dispatch(command, args)
  end, {
    nargs = "?",
    desc = "Home Assistant commands",
    complete = function(_, line)
      local command, args = M.parse(line)
      
      -- Special case: entity ID completion for entities command
      if command == "entities" and #args > 0 then
        return M.get_entity_completions(args[#args])
      end
      
      -- Default tree-based completion
      if #args > 0 then return M.get_completions_at_path(command == "" and {} or { command }, args[#args]) end
      return M.get_completions_at_path({}, command)
    end,
  })
end

---Parse command arguments
function M.parse(args)
  local parts = vim.split(vim.trim(args), "%s+")
  local prefix = config.get_value("commands.prefix", "ha")
  local cmd_name = string.upper(prefix:sub(1, 1)) .. prefix:sub(2)

  if vim.startswith(cmd_name, parts[1]) then table.remove(parts, 1) end
  if args:sub(-1) == " " then parts[#parts + 1] = "" end
  return table.remove(parts, 1) or "", parts
end

---Get completions for tree navigation at given path
function M.get_completions_at_path(path_segments, prefix)
  local node = commands_tree

  -- Navigate to the current level
  for _, segment in ipairs(path_segments) do
    if node.children and node.children[segment] then
      node = node.children[segment]
    else
      return {} -- Invalid path
    end
  end

  -- Return available children at this level
  if node.children then
    local completions = vim.tbl_keys(node.children)
    table.sort(completions)
    if prefix and prefix ~= "" then
      return vim.tbl_filter(function(key) return key:find(prefix, 1, true) == 1 end, completions)
    end
    return completions
  end

  return {}
end

---Complete arguments using tree structure
function M.complete_args(cmd, prefix)
  local path = cmd == "" and {} or { cmd }
  return M.get_completions_at_path(path, prefix)
end

---Show picker for current tree level
function M.show_level_picker(node, breadcrumb_path)
  if not node.children then
    vim.notify("No subcommands available", vim.log.levels.WARN)
    return
  end

  local items = {}
  for key, child in pairs(node.children) do
    table.insert(items, {
      idx = #items + 1,
      key = key,
      text = key,
      description = child.description,
      node = child,
    })
  end

  -- Sort items by key for consistent ordering
  table.sort(items, function(a, b) return a.key < b.key end)

  local breadcrumb = breadcrumb_path
      and (#breadcrumb_path > 0)
      and ("Home Assistant > " .. table.concat(breadcrumb_path, " > "))
    or "Home Assistant Commands"

  local picker_config = {
    source = "home_assistant_commands",
    items = items,
    title = breadcrumb,
    preview = require("ha.ui.picker.core").create_preview_function(
      function(item)
        return {
          text = "# "
            .. item.text
            .. "\n\n"
            .. item.description
            .. (item.node.callback and "\n\n*Press Enter to execute*" or "\n\n*Press Enter to explore subcommands*"),
          ft = "markdown",
        }
      end
    ),
    format = require("ha.ui.picker.core").create_format_function("text", "description"),
    confirm = function(picker, item)
      picker:close()
      if item and item.node then
        if item.node.callback then
          -- Leaf node - execute
          local ok, err = pcall(item.node.callback)
          if not ok then vim.notify("Command error: " .. err, vim.log.levels.ERROR) end
        else
          -- Branch node - go deeper
          local new_path = vim.deepcopy(breadcrumb_path or {})
          table.insert(new_path, item.key)
          M.show_level_picker(item.node, new_path)
        end
      end
    end,
  }

  local core = require "ha.ui.picker.core"
  core.show_picker(picker_config)
end

---Unified dispatch using tree navigation
function M.dispatch(cmd, args)
  local path = cmd == "" and {} or { cmd, unpack(args) }
  local node = commands_tree
  local traversed_path = {}
  local remaining_args = {}

  -- Navigate the tree following the command path
  for i, segment in ipairs(path) do
    if node.children and node.children[segment] then
      node = node.children[segment]
      table.insert(traversed_path, segment)
    else
      -- Collect remaining segments as arguments for the callback
      for j = i, #path do
        table.insert(remaining_args, path[j])
      end
      break
    end
  end

  -- Execute leaf node or show picker for branch node
  if node.callback then
    -- Leaf node - execute with remaining arguments
    local ok, err = pcall(node.callback, remaining_args)
    if not ok then vim.notify("Command error: " .. err, vim.log.levels.ERROR) end
  elseif node.children then
    -- Branch node - show picker for this level
    M.show_level_picker(node, traversed_path)
  else
    vim.notify("No action defined for: " .. table.concat(path, " "), vim.log.levels.ERROR)
  end
end

---Generate help from command tree
function M.generate_help_from_tree(node, prefix, lines, level)
  prefix = prefix or ""
  lines = lines or {}
  level = level or 0

  if node.children then
    for key, child in pairs(node.children) do
      local cmd_path = prefix == "" and key or (prefix .. " " .. key)
      local indent = string.rep("  ", level)

      if child.callback then
        -- Leaf command
        table.insert(lines, indent .. cmd_path .. " - " .. child.description)
      else
        -- Branch command
        table.insert(lines, indent .. cmd_path .. " - " .. child.description)
        M.generate_help_from_tree(child, cmd_path, lines, level + 1)
      end
    end
  end

  return lines
end

---Show unified help based on command tree
function M.show_help()
  local prefix = config.get_value("commands.prefix", "ha")
  local cmd_name = string.upper(prefix:sub(1, 1)) .. prefix:sub(2)

  local lines = {
    "🏠 Home Assistant Commands",
    "",
    "Usage: " .. cmd_name .. " <command> [subcommand] [args...]",
    "       " .. cmd_name .. "            - Show command picker",
    "       " .. cmd_name .. " <command>  - Show subcommands or execute",
    "",
    "📖 Available Commands:",
    "",
  }

  -- Generate help from tree structure
  local help_lines = M.generate_help_from_tree(commands_tree, cmd_name, {})
  vim.list_extend(lines, help_lines)

  table.insert(lines, "")
  table.insert(lines, "💡 Tips:")
  table.insert(lines, "  • Use Tab completion to explore commands and entity IDs")
  table.insert(lines, "  • Use Enter without arguments to show pickers")
  table.insert(lines, "  • Entity picker shortcuts: <C-d> domain, <C-l> area, <C-r> reset")
  table.insert(lines, "  • Place cursor on entity_id and run 'entities' for auto-detection")

  ui.show_help(lines)
end

-- ============================================================================
-- STREAMLINED COMMAND IMPLEMENTATIONS
-- ============================================================================

-- Authentication commands (unchanged - these are essential)
function M.auth_setup()
  auth.setup_credentials(function(success, result)
    if success then
      -- Disconnect existing WebSocket so it reconnects with new credentials
      api.disconnect()
      -- Check connection and reload registry (triggers WS reconnect)
      local ha = require "ha"
      ha.check_connection(false)
      vim.schedule(function() utils.registry.refresh(function() end) end)
      -- Update LSP with new credentials if active
      local lsp = require "ha.lsp"
      local lsp_client = lsp.get_client()
      if lsp_client then lsp.send_auth_update(lsp_client) end
    end
  end)
end

function M.auth_test()
  api.test_connection_and_auth(function(success, result)
    if success then
      vim.notify("✓ Connected: " .. (result.name or "Unknown"), vim.log.levels.INFO)
    else
      vim.notify("✗ Failed: " .. (result.error or "Unknown"), vim.log.levels.ERROR)
    end
  end)
end

function M.auth_clear()
  vim.ui.select({ "Yes", "No" }, {
    prompt = "Clear stored credentials?",
  }, function(choice)
    if choice == "Yes" then
      auth.clear_credentials()
      vim.notify("Credentials cleared", vim.log.levels.INFO)
    end
  end)
end

function M.auth_show()
  local details = auth.get_auth_details()
  local source_label = ({ storage = "stored", env = "environment", none = "none" })[details.source] or "unknown"
  local lines = {
    "Authentication Details:",
    "",
    "URL: " .. (details.url or "Not set"),
    "Token: " .. (details.token or "Not set"),
    "Source: " .. source_label,
    "Status: " .. (details.has_credentials and "✓ Configured" or "✗ Not configured"),
  }
  ui.show_info(lines)
end

-- Primary workflow commands
function M.entity_picker(entity_id)
  ui.picker.show_entity_picker(function(selected)
    if selected then
      -- Show entity details in a clean format
      local lines = {
        "🏠 " .. selected.entity_id,
        "",
        "State: " .. tostring(selected.state or "unknown"),
      }

      if selected.attributes and selected.attributes.friendly_name then
        table.insert(lines, "Name: " .. selected.attributes.friendly_name)
      end

      if selected.area_id then
        local registry = require "ha.utils.registry"
        local areas = registry.get_areas()
        local area = areas[selected.area_id]
        if area then table.insert(lines, "Area: " .. area.name) end
      end

      ui.show_info(lines)
    end
  end, entity_id)
end

function M.service_picker()
  api.get_services(function(success, result)
    if success then
      ui.picker.show_service_picker(result, function(selected)
        if selected then M.call_service_interactive(selected) end
      end)
    else
      vim.notify("Failed to get services: " .. (result.error or "Unknown"), vim.log.levels.ERROR)
    end
  end)
end

function M.integration_picker()
  -- Get integrations from registry (should be cached)
  local registry = require "ha.utils.registry"
  local integrations = registry.get_all_integrations()

  if #integrations == 0 then
    vim.notify("No integrations found. Ensure registry is initialized.", vim.log.levels.WARN)
    return
  end

  ui.picker.show_integration_picker(integrations, function(selected)
    if selected then
      -- Show integration details in a clean format
      local lines = {
        "🔌 " .. (selected.name or selected.domain or "Unknown Integration"),
        "",
        "Domain: " .. (selected.domain or "unknown"),
      }

      if selected.version then table.insert(lines, "Version: " .. selected.version) end

      if selected.is_built_in ~= nil then
        table.insert(lines, "Type: " .. (selected.is_built_in and "Built-in" or "Custom"))
      end

      -- Add manifest info
      if selected.manifest then
        if selected.manifest.name then table.insert(lines, "Display Name: " .. selected.manifest.name) end

        if selected.manifest.documentation then
          table.insert(lines, "Documentation: " .. selected.manifest.documentation)
        end

        if selected.manifest.config_flow ~= nil then
          table.insert(
            lines,
            "Config Flow: " .. (selected.manifest.config_flow and "✓ Supported" or "✗ Manual only")
          )
        end
      end

      ui.show_info(lines)
    end
  end)
end

-- Direct action commands
function M.call_service_direct()
  vim.ui.input({
    prompt = "Service (domain.service): ",
  }, function(input)
    if not input then return end

    local domain, service_name = input:match "^([^%.]+)%.(.+)$"
    if not domain or not service_name then
      vim.notify("Invalid format. Use: domain.service", vim.log.levels.ERROR)
      return
    end

    -- For direct calls, prompt for JSON data
    vim.ui.input({
      prompt = "Service data (JSON, optional): ",
    }, function(data_json)
      local service_data = {}

      if data_json and data_json ~= "" then
        local ok, parsed = pcall(vim.fn.json_decode, data_json)
        if ok then
          service_data = parsed
        else
          vim.notify("Invalid JSON", vim.log.levels.ERROR)
          return
        end
      end

      api.call_service(domain, service_name, service_data, function(success, result)
        if success then
          vim.notify("✓ Called: " .. input, vim.log.levels.INFO)
        else
          vim.notify("✗ Failed: " .. (result.error or "Unknown"), vim.log.levels.ERROR)
        end
      end)
    end)
  end)
end

function M.render_template()
  local template = nil

  -- Check for visual selection first (highest priority)
  if vim.fn.mode() == "v" or vim.fn.mode() == "V" then
    local start_line = vim.fn.line "'<"
    local end_line = vim.fn.line "'>"
    local lines = vim.fn.getline(start_line, end_line)
    template = table.concat(lines, "\n")
  else
    -- Try current line if it looks like a template
    local current_line = vim.fn.getline "."
    if current_line and current_line:match "%{%{.*%}%}" then template = current_line end
  end

  -- Only prompt if no template found
  if not template or template == "" then
    vim.ui.input({
      prompt = "Template: ",
      default = "{{ now().strftime('%H:%M:%S') }}",
    }, function(input)
      if input and input ~= "" then
        api.render_template(input, function(success, data) ui.show_template_result(success, data) end)
      end
    end)
    return
  end

  -- We have a template, render it directly
  api.render_template(template, function(success, data) ui.show_template_result(success, data) end)
end

function M.toggle_template_channel() ui.toggle_channel "Home Assistant Template Renderer" end

function M.show_template_help()
  local context_info = {
    "Home Assistant Template Functions:",
    "",
    "🏠 Entity Functions:",
    "  states('entity_id')           - Get entity state",
    "  state_attr('entity_id', 'attr') - Get entity attribute",
    "  is_state('entity_id', 'value') - Check if entity has state",
    "  has_value('entity_id')        - Check if entity has value",
    "",
    "⏰ Time Functions:",
    "  now()                        - Current datetime",
    "  utcnow()                     - Current UTC datetime",
    "  as_timestamp(datetime)       - Convert to timestamp",
    "  strptime(string, format)     - Parse datetime string",
    "",
    "🔧 Utility Functions:",
    "  float(value)                 - Convert to number",
    "  int(value)                   - Convert to integer",
    "  bool(value)                  - Convert to boolean",
    "  max(a, b)                    - Maximum value",
    "  min(a, b)                    - Minimum value",
    "",
    "📖 Usage:",
    "  :Ha template                 - Render template (selection/line/prompt)",
    "  :Ha template toggle          - Toggle result window",
    "  :Ha template help            - Show this help",
    "",
    "💡 In template result window:",
    "  q                           - Close window",
  }

  ui.show_info(context_info)
end

function M.restart_homeassistant()
  vim.ui.select({ "Yes", "No" }, {
    prompt = "Restart Home Assistant?",
  }, function(choice)
    if choice == "Yes" then
      api.call_service("homeassistant", "restart", {}, function(success, result)
        if success then
          vim.notify("🔄 Restart initiated", vim.log.levels.INFO)
        elseif result and result.error == "Connection lost" then
          -- Connection lost is expected when restart succeeds - HA is restarting
          vim.notify("🔄 Restart initiated", vim.log.levels.INFO)
        else
          vim.notify("✗ Restart failed: " .. (result and result.error or "Unknown"), vim.log.levels.ERROR)
        end
      end)
    end
  end)
end

function M.reload_lovelace()
  -- Fire lovelace_updated event to trigger dashboard refresh in all connected browsers
  -- url_path: null = default dashboard, or specify dashboard path like "lovelace-tablet"
  api.fire_event("lovelace_updated", { url_path = vim.NIL, mode = "yaml" }, function(success, result)
    if success then
      vim.notify("🔄 Lovelace dashboard refreshed", vim.log.levels.INFO)
    else
      vim.notify("✗ Refresh failed: " .. (result and result.error or "Unknown"), vim.log.levels.ERROR)
    end
  end)
end

-- Utility commands
function M.show_status()
  local ha = require "ha"
  local state = ha.get_state()
  local auth_details = auth.get_auth_details()

  local lines = {
    "🏠 Home Assistant Status:",
    "",
    "Connection: " .. (state.connection_status == "connected" and "✓ Connected" or "✗ " .. state.connection_status),
    "LSP Client: " .. (state.lsp_client and "✓ Running" or "✗ Stopped"),
    "URL: " .. (auth_details.url or "Not configured"),
  }

  ui.show_info(lines)
end

function M.show_error_log()
  api.get_error_log(function(success, result)
    if success then
      ui.show_error_log(result)
    else
      vim.notify("Failed to get error log: " .. (result.error or "Unknown"), vim.log.levels.ERROR)
    end
  end)
end

function M.open_in_browser()
  local url = auth.get_url()
  if url then
    vim.ui.open(url)
    vim.notify("🌐 Opening Home Assistant", vim.log.levels.INFO)
  else
    vim.notify("URL not configured", vim.log.levels.ERROR)
  end
end

-- ============================================================================
-- INDIVIDUAL RELOAD FUNCTIONS
-- ============================================================================

function M.reload_lovelace() api.refresh_lovelace(M.reload_callback) end

function M.reload_all() api.call_service("homeassistant", "reload_all", {}, M.reload_callback) end

function M.reload_automations() api.call_service("automation", "reload", {}, M.reload_callback) end

function M.reload_scripts() api.call_service("script", "reload", {}, M.reload_callback) end

function M.reload_scenes() api.call_service("scene", "reload", {}, M.reload_callback) end

function M.reload_groups() api.call_service("group", "reload", {}, M.reload_callback) end

function M.reload_themes() api.call_service("frontend", "reload_themes", {}, M.reload_callback) end

function M.reload_core_config() api.call_service("homeassistant", "reload_core_config", {}, M.reload_callback) end

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

---Get entity ID completions based on prefix
---@param prefix string Prefix to filter by
---@return table Array of matching entity IDs
function M.get_entity_completions(prefix)
  local registry = require("ha.utils.registry")
  local entities = registry.get_all_entities()
  
  if not entities or #entities == 0 then
    return {}
  end
  
  local completions = {}
  prefix = prefix or ""
  
  for _, entity in ipairs(entities) do
    if entity.entity_id and (prefix == "" or vim.startswith(entity.entity_id, prefix)) then
      table.insert(completions, entity.entity_id)
    end
  end
  
  -- Sort for consistent ordering
  table.sort(completions)
  return completions
end

---Get entity ID under cursor if valid
---@return string|nil entity_id The entity ID if valid, nil otherwise
function M.get_entity_under_cursor()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1 -- Convert to 1-based indexing
  
  -- Find entity ID pattern around cursor position
  -- Pattern: word_chars.word_chars (allowing underscores and alphanumeric)
  local pattern = '[a-zA-Z_][a-zA-Z0-9_]*%.[a-zA-Z0-9_]+'
  
  -- Search for pattern that contains the cursor position
  for match_start, match_end in line:gmatch('()' .. pattern .. '()') do
    match_end = match_end - 1 -- Adjust for inclusive end
    if col >= match_start and col <= match_end then
      return line:sub(match_start, match_end)
    end
  end
  
  return nil
end

function M.call_service_interactive(service_info)
  local service_data = {}

  if service_info.info.fields and next(service_info.info.fields) then
    local field_names = vim.tbl_keys(service_info.info.fields)
    M.prompt_service_fields(
      field_names,
      service_info.info.fields,
      service_data,
      1,
      function() M.execute_service_call(service_info, service_data) end
    )
  else
    M.execute_service_call(service_info, service_data)
  end
end

function M.prompt_service_fields(field_names, field_definitions, service_data, index, callback)
  if index > #field_names then
    callback()
    return
  end

  local field_name = field_names[index]
  local field_def = field_definitions[field_name]
  local prompt = field_name

  if field_def.description then prompt = prompt .. " (" .. field_def.description .. ")" end

  if field_def.required then
    prompt = "* " .. prompt -- Mark required fields
  end

  vim.ui.input({
    prompt = prompt .. ": ",
  }, function(value)
    if value and value ~= "" then service_data[field_name] = value end
    M.prompt_service_fields(field_names, field_definitions, service_data, index + 1, callback)
  end)
end

function M.execute_service_call(service_info, service_data)
  api.call_service(service_info.domain, service_info.service, service_data, function(success, result)
    if success then
      vim.notify("✓ " .. service_info.domain .. "." .. service_info.service, vim.log.levels.INFO)
    else
      vim.notify("✗ Failed: " .. (result.error or "Unknown"), vim.log.levels.ERROR)
    end
  end)
end

function M.reload_callback(success, result)
  if success then
    vim.notify("✓ Reload completed", vim.log.levels.INFO)
  else
    vim.notify("✗ Reload failed: " .. (result.error or "Unknown"), vim.log.levels.ERROR)
  end
end

function M.reload_input_helpers()
  local domains = { "input_button", "input_boolean", "input_datetime", "input_number", "input_select", "input_text" }
  local completed = 0

  for _, domain in ipairs(domains) do
    api.call_service(domain, "reload", {}, function(success, result)
      completed = completed + 1
      if completed == #domains then vim.notify("✓ Input helpers reloaded", vim.log.levels.INFO) end
    end)
  end
end

-- ============================================================================
-- DIAGNOSTICS COMMANDS
-- ============================================================================

function M.run_diagnostics()
  local diagnostics = require "ha.diagnostics"
  diagnostics.diagnose_buffer()
  vim.notify("✓ HA diagnostics run on current buffer", vim.log.levels.INFO)
end

function M.clear_diagnostics()
  local diagnostics = require "ha.diagnostics"
  diagnostics.clear()
  vim.notify("✓ HA diagnostics cleared", vim.log.levels.INFO)
end

function M.refresh_diagnostics()
  local diagnostics = require "ha.diagnostics"
  diagnostics.refresh_all()
  vim.notify("✓ HA diagnostics refreshed for all buffers", vim.log.levels.INFO)
end

function M.show_diagnostics_stats()
  local diagnostics = require "ha.diagnostics"
  local stats = diagnostics.get_stats()
  
  local lines = {
    "🔍 HA Diagnostics Statistics:",
    "",
    "Buffers with diagnostics: " .. stats.buffers_with_diagnostics,
    "Total diagnostics: " .. stats.total_diagnostics,
  }
  
  ui.show_info(lines)
end

-- ============================================================================
-- LSP COMMANDS
-- ============================================================================

function M.toggle_lsp()
  local lsp = require "ha.lsp"
  local client = lsp.get_client()
  if client and not client:is_stopped() then
    lsp.stop()
    vim.notify("✗ HA LSP stopped", vim.log.levels.INFO)
  else
    lsp.setup()
    vim.notify("✓ HA LSP started", vim.log.levels.INFO)
  end
end

function M.stop_lsp()
  local lsp = require "ha.lsp"
  lsp.stop()
  vim.notify("✗ HA LSP stopped", vim.log.levels.INFO)
end

function M.start_lsp()
  local lsp = require "ha.lsp"
  lsp.setup()
  vim.notify("✓ HA LSP started", vim.log.levels.INFO)
end

function M.restart_lsp()
  local lsp = require "ha.lsp"
  lsp.restart()
  vim.notify("✓ HA LSP restarted", vim.log.levels.INFO)
end

function M.lsp_status()
  local lsp = require "ha.lsp"
  local client = lsp.get_client()

  if client and not client:is_stopped() then
    local lines = {
      "󰟢 HA LSP Status: Running",
      "",
      "Client ID: " .. client.id,
      "Name: " .. client.name,
      "Root dir: " .. (client.config.root_dir or "N/A"),
    }
    ui.show_info(lines)
  else
    vim.notify("HA LSP is not running", vim.log.levels.WARN)
  end
end

return M
