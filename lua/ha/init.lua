-- ha.nvim - Home Assistant plugin for Neovim
-- Main entry point

local M = {}

local api = require "ha.api"
local config = require "ha.config"
local auth = require "ha.auth"
local lsp = require "ha.lsp"
local commands = require "ha.commands"
local ui = require "ha.ui"
local utils = require "ha.utils"
local completion = require "ha.completion"
local diagnostics = require "ha.diagnostics"

-- Plugin state
M._state = {
  initialized = false,
  lsp_client = nil,
  connection_status = "disconnected",
}

---Register the custom Mason registry for Home Assistant Language Server
local function setup_mason_registry()
  local ok, mason = pcall(require, "mason")
  if not ok then
    utils.logger.debug "Mason not available, skipping registry setup"
    return
  end

  -- Get current mason settings
  local mason_settings = require("mason.settings")
  local current = mason_settings.current or {}
  local registries = current.registries or { "github:mason-org/mason-registry" }

  -- Add our registry if not already present
  local ha_registry = "lua:ha.mason-registry"
  local found = false
  for _, reg in ipairs(registries) do
    if reg == ha_registry then
      found = true
      break
    end
  end

  if not found then
    table.insert(registries, 1, ha_registry)
    mason.setup({ registries = registries })
    utils.logger.info "Registered ha.mason-registry with Mason"
  end
end

---Initialize the Home Assistant plugin
---@param opts? table User configuration options
function M.setup(opts)
  if M._state.initialized then return end

  -- Merge user config with defaults
  config.setup(opts or {})

  -- Setup Mason registry for HA Language Server
  setup_mason_registry()

  -- Initialize logging
  utils.logger.setup(config.get().log_level)
  utils.logger.info "Initializing ha.nvim"

  -- Setup workspace detection with caching
  utils.workspace.setup()

  -- Setup authentication
  auth.setup()

  -- Setup UI components
  ui.setup()

  -- Setup progress system (after UI is initialized)
  ui.progress_renderer.setup()

  -- Setup completion sources
  completion.setup()

  -- Register commands
  commands.setup()

  -- Setup diagnostics
  diagnostics.setup()

  -- Auto-detect Home Assistant workspace and setup LSP if found
  vim.schedule(function()
    if utils.workspace.is_home_assistant_workspace() then
      utils.logger.info "Home Assistant workspace detected"
      M.setup_lsp()

      -- Auto-migrate credentials if needed
      auth.migrate_from_vscode()

      -- Check connection status and preload registry
      M.check_connection(true) -- Enable registry preloading
    else
      utils.logger.debug "No Home Assistant workspace detected"
    end
  end)

  -- Setup buffer-aware activation for HA files
  M.setup_buffer_activation()

  M._state.initialized = true
  utils.logger.info "ha.nvim initialized successfully"
end

---Setup buffer-aware activation that works regardless of CWD
function M.setup_buffer_activation()
  local augroup = vim.api.nvim_create_augroup("ha_buffer_activation", { clear = true })

  vim.api.nvim_create_autocmd({ "BufEnter", "BufReadPost" }, {
    group = augroup,
    callback = function(args)
      local bufnr = args.buf

      -- Check if this is an HA file
      if utils.workspace.is_ha_file(bufnr) then
        local ha_root = utils.workspace.get_buffer_ha_root(bufnr)
        if ha_root then
          utils.logger.debug("HA file activated: " .. vim.api.nvim_buf_get_name(bufnr))

          -- Ensure credentials are migrated
          if not auth.has_credentials() then auth.migrate_from_vscode() end

          -- Check connection if not already connected
          if M._state.connection_status == "disconnected" then
            M.check_connection(true) -- Enable registry preloading
          end

          -- Update UI to reflect HA environment
          ui.status.update(M._state.connection_status)
        end
      end
    end,
    desc = "Activate HA environment when entering HA buffers",
  })
end

---Setup LSP client for Home Assistant
function M.setup_lsp()
  if M._state.lsp_client then
    utils.logger.debug "LSP client already initialized"
    return
  end

  local client_id = lsp.setup()
  if client_id then
    M._state.lsp_client = vim.lsp.get_client_by_id(client_id)
    utils.logger.info "Home Assistant LSP client started"

    -- Update status
    M._state.connection_status = "connecting"
    ui.status.update "connecting"
  else
    utils.logger.error "Failed to start Home Assistant LSP client"
  end
end

---Check Home Assistant connection status and optionally preload registry
---@param preload_registry? boolean Whether to preload registry data
function M.check_connection(preload_registry)
  api.test_connection_and_auth(function(success, result)
    if success then
      M._state.connection_status = "connected"
      ui.status.update("connected", result)
      utils.logger.info("Connected to Home Assistant: " .. (result.name or "Unknown"))

      -- Preload registry if requested and connection is successful
      if preload_registry then vim.schedule(function() M.preload_registry() end) end
    else
      M._state.connection_status = "error"
      ui.status.update "error"
      utils.logger.warn("Failed to connect to Home Assistant: " .. (result.error or "Unknown error"))
    end
  end)
end

---Preload registry data in background for better UX
function M.preload_registry()
  local registry = utils.registry

  -- Only preload if not already initialized
  if registry.get_stats().initialized then
    utils.logger.debug "Registry already initialized, skipping preload"
    return
  end

  utils.logger.info "Preloading registry data for better user experience..."

  registry.initialize(function(success, error)
    if success then
      local stats = registry.get_stats()
      utils.logger.info(
        string.format(
          "Registry preloaded: %d areas, %d devices, %d entities",
          stats.areas_count,
          stats.devices_count,
          stats.entities_count
        )
      )
    else
      utils.logger.warn("Registry preload failed: " .. tostring(error))
    end
  end)
end

---Get current plugin state
---@return table Current state
function M.get_state() return vim.deepcopy(M._state) end

---Stop the plugin and cleanup resources
function M.stop()
  if M._state.lsp_client then
    M._state.lsp_client:stop()
    M._state.lsp_client = nil
  end

  ui.cleanup()
  M._state.initialized = false
  utils.logger.info "ha.nvim stopped"
end

-- Health check function for :checkhealth
function M.check()
  local health = vim.health

  health.start "ha.nvim"

  -- Check if plugin is initialized
  if M._state.initialized then
    health.ok "Plugin initialized"
  else
    health.error("Plugin not initialized", "Run require('ha').setup()")
    return
  end

  -- Check workspace
  if utils.workspace.is_home_assistant_workspace() then
    health.ok "Home Assistant workspace detected"
  else
    health.warn "Not in a Home Assistant workspace"
  end

  -- Check authentication
  local has_creds = auth.has_credentials()
  if has_creds then
    health.ok "Credentials configured"
  else
    health.error("No credentials found", "Run :Ha auth setup")
  end

  -- Check LSP
  if M._state.lsp_client and M._state.lsp_client.is_stopped() == false then
    health.ok "LSP client running"
  else
    health.warn "LSP client not running"
  end

  -- Check connection
  if M._state.connection_status == "connected" then
    health.ok "Connected to Home Assistant"
  elseif M._state.connection_status == "connecting" then
    health.info "Connecting to Home Assistant..."
  else
    health.error "Not connected to Home Assistant"
  end

  -- Check registry system
  local registry_ok, registry = pcall(require, "ha.utils.registry")
  if registry_ok then
    health.ok "Registry system available"

    -- Check registry status
    local stats = registry.get_stats()
    if stats.initialized then
      health.ok(
        string.format(
          "Registry active (%d areas, %d devices, %d entities)",
          stats.areas_count,
          stats.devices_count,
          stats.entities_count
        )
      )
    else
      health.info "Registry not initialized (will populate on first use)"
    end

    -- Validate registry data if available
    local validation = registry.validate()
    if validation.valid then
      health.ok "Registry data structure valid"
    elseif #validation.errors > 0 then
      health.error("Registry data validation failed: " .. table.concat(validation.errors, ", "))
    end

    if #validation.warnings > 0 then
      health.warn("Registry data warnings: " .. table.concat(validation.warnings, ", "))
    end
  else
    health.error("Registry system failed to load: " .. tostring(registry))
  end

  -- Check diagnostics system
  local diag_ok, diag = pcall(require, "ha.diagnostics")
  if diag_ok then
    health.ok "Diagnostics system available"
    local diag_stats = diag.get_stats()
    if diag_stats.total_diagnostics > 0 then
      health.info(string.format(
        "Diagnostics: %d issues in %d buffers",
        diag_stats.total_diagnostics,
        diag_stats.buffers_with_diagnostics
      ))
    else
      health.ok "No diagnostic issues found"
    end
  else
    health.warn("Diagnostics system failed to load: " .. tostring(diag))
  end

  -- Check dependencies
  local deps = {
    { "plenary.nvim", "plenary" },
    { "blink.cmp", "blink.cmp" },
    { "snacks.nvim", "snacks" },
    { "utf8.nvim", "utf8" },
  }

  for _, dep in ipairs(deps) do
    local ok, _ = pcall(require, dep[2])
    if ok then
      health.ok(dep[1] .. " available")
    else
      health.warn(dep[1] .. " not found", "Install " .. dep[1] .. " for full functionality")
    end
  end
end

return M
