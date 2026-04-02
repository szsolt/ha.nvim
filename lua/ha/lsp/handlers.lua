-- LSP handlers module - Corrected version
local M = {}

local ui = require "ha.ui"
local utils = require "ha.utils"

---Get custom LSP handlers
---@return table LSP handlers
function M.get_handlers()
  return {
    -- Home Assistant specific notifications
    ["ha_connected"] = M.handle_ha_connected,
    ["ha_connection_error"] = M.handle_ha_connection_error,
    ["no-config"] = M.handle_no_config,
    ["configuration_check_completed"] = M.handle_config_check_completed,
    ["get_error_log_completed"] = M.handle_error_log_completed,
    ["render_template_completed"] = M.handle_template_completed,

    -- Override default handlers with proper nil checking
    ["textDocument/publishDiagnostics"] = M.handle_diagnostics,
    ["window/showMessage"] = M.handle_show_message,

    -- CRITICAL: Fix configuration change handler to prevent crashes
    ["workspace/didChangeConfiguration"] = M.handle_configuration_change,

    -- Add completion handler to ensure proper completion handling
    ["textDocument/completion"] = M.handle_completion,
  }
end

---Handle Home Assistant connection established
---@param result table Connection result
function M.handle_ha_connected(result)
  -- Add nil check
  if not result then
    utils.logger.warn "HA connected notification with nil result"
    return
  end

  utils.logger.info("Home Assistant connected: " .. vim.inspect(result))

  local ha = require "ha"
  ha._state.connection_status = "connected"

  ui.status.update("connected", result)

  if result.name then vim.notify("Connected to " .. result.name, vim.log.levels.INFO) end
end

---Handle Home Assistant connection error
---@param result table Error result
function M.handle_ha_connection_error(result)
  -- Add nil check
  if not result then
    utils.logger.warn "HA connection error notification with nil result"
    return
  end

  utils.logger.warn("Home Assistant connection error: " .. vim.inspect(result))

  local ha = require "ha"
  ha._state.connection_status = "error"

  ui.status.update "error"

  if result.error then vim.notify("Home Assistant connection error: " .. result.error, vim.log.levels.ERROR) end
end

---Handle no config notification
---@param result table Result data
function M.handle_no_config(result)
  utils.logger.warn "No Home Assistant configuration"

  local auth = require "ha.auth"
  if auth.has_credentials() then
    utils.logger.debug "Credentials found, ignoring no-config notification"
    return
  end

  vim.notify("No Home Assistant authentication found. Run :Ha auth setup", vim.log.levels.WARN)
end

---Handle configuration check completed
---@param result table Check result
function M.handle_config_check_completed(result)
  -- Add nil check - this was likely causing the error at line 38
  if not result then
    utils.logger.warn "Configuration check completed with nil result"
    vim.notify("Configuration check completed with unknown result", vim.log.levels.WARN)
    return
  end

  if result.result == "valid" then
    vim.notify("Home Assistant Configuration: Valid!", vim.log.levels.INFO)
  else
    vim.notify("Configuration error: " .. (result.error or "Unknown error"), vim.log.levels.ERROR)
  end
end

---Handle error log completed
---@param result string Error log content
function M.handle_error_log_completed(result)
  if not result then
    utils.logger.warn "Error log completed with nil result"
    return
  end
  ui.show_error_log(result)
end

---Handle template render completed
---@param result string Template result
function M.handle_template_completed(result)
  if not result then
    utils.logger.warn "Template completed with nil result"
    return
  end
  ui.show_template_result(result)
end

---Handle completion with proper nil checking
---@param err table Error object
---@param result table Completion result
---@param ctx table LSP context
---@param config table LSP config
function M.handle_completion(err, result, ctx, config)
  -- Handle errors
  if err then
    utils.logger.error("Completion error: " .. vim.inspect(err))
    return
  end

  -- Handle nil result (no completions available)
  if not result then
    utils.logger.debug "No completion results available"
    return
  end

  -- Handle empty results
  if type(result) == "table" and vim.tbl_isempty(result) then
    utils.logger.debug "Empty completion results"
    return
  end

  -- If result has items array, check if it's empty
  if result.items and vim.tbl_isempty(result.items) then
    utils.logger.debug "No completion items available"
    return
  end

  -- Process the completion results
  local items_count = result.items and #result.items or (type(result) == "table" and #result or 0)
  utils.logger.debug("Processing " .. items_count .. " completion items")

  -- Call the default handler with proper error checking
  return vim.lsp.handlers["textDocument/completion"](err, result, ctx, config)
end

---Handle diagnostics with custom formatting
---@param err table Error object
---@param result table Diagnostic result
---@param ctx table LSP context
---@param config table LSP config
function M.handle_diagnostics(err, result, ctx, config)
  -- Add nil check
  if err then
    utils.logger.error("Diagnostics error: " .. vim.inspect(err))
    return
  end

  if not result then
    utils.logger.debug "No diagnostic results"
    return
  end

  -- Use default handler but with custom processing
  vim.lsp.handlers["textDocument/publishDiagnostics"](err, result, ctx, config)

  -- Log diagnostics for debugging
  if result.diagnostics then
    utils.logger.debug(string.format("Received %d diagnostics for %s", #result.diagnostics, result.uri or "unknown"))
  end
end

---Handle show message with custom formatting
---@param err table Error object
---@param result table Message result
---@param ctx table LSP context
---@param config table LSP config
function M.handle_show_message(err, result, ctx, config)
  -- Add nil check
  if not result then
    utils.logger.warn "Show message with nil result"
    return
  end

  local level = vim.log.levels.INFO
  if result.type == 1 then -- Error
    level = vim.log.levels.ERROR
  elseif result.type == 2 then -- Warning
    level = vim.log.levels.WARN
  elseif result.type == 3 then -- Info
    level = vim.log.levels.INFO
  elseif result.type == 4 then -- Log
    level = vim.log.levels.DEBUG
  end

  vim.notify("[HA LSP] " .. (result.message or "Unknown message"), level)
end

---Handle workspace configuration changes to prevent crashes
---@param err table Error object
---@param result table Configuration change result
---@param ctx table LSP context
---@param config table LSP config
function M.handle_configuration_change(err, result, ctx, config)
  utils.logger.debug "Intercepted workspace/didChangeConfiguration"

  -- The Home Assistant language server expects config.settings but Neovim sends different format
  -- Simply ignore configuration changes to prevent crashes
  -- The server already has the correct configuration from initialization

  -- Add proper nil check - this was likely the source of your error
  if result then
    utils.logger.debug("Configuration change ignored to prevent crash: " .. vim.inspect(result))
  else
    utils.logger.debug "Configuration change with nil result ignored"
  end

  -- Don't forward to the server - just return true to indicate handled
  return true
end

return M
