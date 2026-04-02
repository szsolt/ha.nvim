-- ha.nvim LSP integration (Modernized for Neovim 0.11+)
local M = {}

local auth = require "ha.auth"
local config = require "ha.config"
local utils = require "ha.utils"

-- LSP client state
local _client_id = nil

---Check if current buffer is in a Home Assistant project
---@param bufnr number? Buffer number (default: current buffer)
---@return boolean True if in HA project
function M.is_home_assistant_project(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local buffer_path = vim.api.nvim_buf_get_name(bufnr)

  if buffer_path == "" then return false end

  -- Check if we can find Home Assistant markers
  local root = vim.fs.root(buffer_path, { "configuration.yaml", ".homeassistant" })

  if root then
    utils.logger.debug("Found Home Assistant project root: " .. root)
    return true
  end

  return false
end

---Setup Home Assistant language server using Neovim 0.11+ native LSP
---@return number? LSP client ID
function M.setup()
  if not config.get_value("lsp.enabled", true) then
    utils.logger.debug "LSP disabled in configuration"
    return nil
  end

  local server_path = M.find_server_path()
  if not server_path then
    utils.logger.error "Home Assistant language server not found"
    return nil
  end

  -- Validate Node.js is available
  if vim.fn.executable "node" ~= 1 then
    utils.logger.error "Node.js not found. Home Assistant language server requires Node.js"
    return nil
  end

  -- Setup LSP config using the new Neovim 0.11+ native API
  vim.lsp.config["home-assistant"] = {
    cmd = { "node", server_path, "--stdio" },
    filetypes = { "yaml", "home-assistant" },
    -- Only activate in Home Assistant projects
    root_markers = { "configuration.yaml", ".homeassistant" },
    -- Custom root_dir function for strict HA project detection
    root_dir = function(bufnr, on_dir)
      local buffer_path = vim.api.nvim_buf_get_name(bufnr)
      if buffer_path == "" then
        on_dir(nil) -- Don't activate for unnamed buffers
        return
      end

      -- Only activate if we find HA-specific markers
      local root = vim.fs.root(buffer_path, { "configuration.yaml", ".homeassistant" })
      if root then
        utils.logger.debug("Activating Home Assistant LSP for: " .. buffer_path)
        on_dir(root)
      else
        utils.logger.debug "Not a Home Assistant project, skipping LSP activation"
        on_dir(nil) -- Don't activate LSP
      end
    end,
    settings = M.get_settings(),
    capabilities = M.get_capabilities(),
  }

  -- Log the command being executed
  utils.logger.debug("Starting HA LSP with command: node " .. server_path .. " --stdio")

  -- Enable the LSP
  vim.lsp.enable "home-assistant"

  -- Setup LspAttach autocmd for this specific LSP
  vim.api.nvim_create_autocmd("LspAttach", {
    group = vim.api.nvim_create_augroup("HALspAttach", { clear = true }),
    callback = function(args)
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      if client and client.name == "home-assistant" then
        _client_id = args.data.client_id
        utils.logger.info("Home Assistant LSP client attached with ID: " .. _client_id)

        M.on_attach(client, args.buf)

        -- Send initial auth after attachment (simplified approach)
        vim.schedule(function() M.send_auth_update(client) end)
      end
    end,
  })

  return _client_id
end

---Send authentication update to the server (Cleaned up)
---@param client table LSP client
function M.send_auth_update(client)
  local token = auth.get_token()
  local url = auth.get_url()

  if not token or not url then
    utils.logger.debug "No auth available for LSP server"
    return
  end

  utils.logger.debug "Sending auth update to HA LSP server"

  -- Use workspace/didChangeConfiguration with proper format
  local settings = {
    ["vscode-home-assistant"] = {
      longLivedAccessToken = token,
      hostUrl = url,
      ignoreCertificates = config.get_value("lsp.settings.vscode-home-assistant.ignoreCertificates", false),
      configTimestamp = os.time(),
    },
  }

  -- Send configuration update
  client.notify("workspace/didChangeConfiguration", { settings = settings })
end

---Find Home Assistant language server path using Mason registry
---@return string? Path to language server
function M.find_server_path()
  -- First priority: User configured static path (backward compatibility)
  local configured_path = config.get_value "lsp.server_path"
  if configured_path and vim.fn.executable "node" == 1 and vim.fn.filereadable(configured_path) == 1 then
    utils.logger.debug("Using configured static path: " .. configured_path)
    return configured_path
  end

  -- Second priority: Mason installation (dynamic)
  local mason_path = M.get_mason_server_path()
  if mason_path then return mason_path end

  -- Third priority: Legacy paths for existing installations
  local legacy_path = M.find_legacy_server_path()
  if legacy_path then return legacy_path end

  -- If nothing found, attempt auto-installation via Mason
  if config.get_value("lsp.dynamic.enabled", true) then
    utils.logger.info "Home Assistant language server not found - attempting auto-installation..."
    M.auto_install_via_mason()
    -- Return nil for now - user will need to restart or we'll retry on next call
    return nil
  end

  utils.logger.error "Home Assistant language server not found and auto-installation disabled"
  return nil
end

---Get Home Assistant language server path from Mason registry
---@return string? Path to language server
function M.get_mason_server_path()
  local mason_registry = require "mason-registry"
  local pkg_name = "home-assistant-language-server"

  -- Check if Home Assistant language server is installed via Mason
  if not mason_registry.is_installed(pkg_name) then
    utils.logger.debug "Home Assistant language server not installed via Mason"
    return nil
  end

  local InstallLocation = require "mason-core.installer.InstallLocation"
  local install_path = InstallLocation.global():package(pkg_name)
  local server_path = install_path .. "/out/server/server.js"

  if vim.fn.filereadable(server_path) == 1 then
    utils.logger.debug("Found HA language server via Mason: " .. server_path)

    -- Verify schema files exist (optional validation)
    local schema_path = install_path .. "/out/language-service/src/schemas/json/blueprint-automation.json"
    if vim.fn.filereadable(schema_path) == 1 then
      utils.logger.debug "Schema files verified in Mason installation"
    else
      utils.logger.warn "Schema files missing in Mason installation - language server may have limited functionality"
    end

    return server_path
  else
    utils.logger.warn("Mason reports HA language server installed but server.js not found: " .. server_path)
    return nil
  end
end

---Auto-install Home Assistant language server via Mason
function M.auto_install_via_mason()
  local ok, mason_registry = pcall(require, "mason-registry")
  if not ok then
    utils.logger.error "Mason registry not available for auto-installation"
    return
  end

  if not mason_registry.has_package "home-assistant-language-server" then
    utils.logger.error "Home Assistant language server not available in Mason registry"
    utils.logger.error "Please check your Mason configuration includes the ha-mason-registry"
    return
  end

  local pkg = mason_registry.get_package "home-assistant-language-server"
  if pkg:is_installed() then
    utils.logger.debug "Home Assistant language server already installed via Mason"
    return
  end

  utils.logger.info "Installing Home Assistant language server via Mason..."

  -- Add progress tracking
  local progress = require "ha.utils.progress"
  local install_progress_id = progress.add_background "Installing Home Assistant Language Server"

  pkg:install({}, function(success, result)
    if success then
      utils.logger.info "✓ Home Assistant language server installed successfully via Mason"
      progress.complete_request(install_progress_id, true)

      -- Restart LSP with new installation
      vim.schedule(function()
        utils.logger.info "Restarting Home Assistant LSP with new installation..."
        M.restart()
      end)
    else
      utils.logger.error("✗ Failed to install Home Assistant language server via Mason: " .. tostring(result))
      progress.fail_request(install_progress_id, "Installation failed: " .. tostring(result))
    end
  end)
end

---Find Home Assistant language server in legacy locations (backward compatibility)
---@return string? Path to language server
function M.find_legacy_server_path()
  utils.logger.debug "Checking legacy installation paths..."

  -- Check for local cloned vscode-home-assistant repository
  local local_paths = {
    -- User's local clone
    "/home/zsolt/code-other/vscode-home-assistant/out/server/server.js",
    -- Alternative common clone locations
    vim.fn.expand "~/code/vscode-home-assistant/out/server/server.js",
    vim.fn.expand "~/projects/vscode-home-assistant/out/server/server.js",
    vim.fn.expand "~/dev/vscode-home-assistant/out/server/server.js",
  }

  -- Check local cloned repository paths first (higher priority)
  for _, path in ipairs(local_paths) do
    if vim.fn.executable "node" == 1 and vim.fn.filereadable(path) == 1 then
      -- Verify schema files exist
      local base_dir = vim.fn.fnamemodify(path, ":h:h") -- Go up two levels from server.js
      local schema_path = base_dir .. "/language-service/src/schemas/json/blueprint-automation.json"

      if vim.fn.filereadable(schema_path) == 1 then
        utils.logger.debug("Found HA language server at local clone: " .. path)
        utils.logger.debug("Schema files verified at: " .. vim.fn.fnamemodify(schema_path, ":h"))
        return path
      else
        utils.logger.warn("Server found but schema files missing: " .. schema_path)
        -- Try to ensure schema files are present
        M.ensure_schema_files(base_dir)
        if vim.fn.filereadable(schema_path) == 1 then
          utils.logger.info("Schema files restored, using server: " .. path)
          return path
        end
      end
    end
  end

  -- Fallback to global npm/yarn installations
  local fallback_paths = {
    -- npm global install
    vim.fn.expand "~/.npm-global/lib/node_modules/@home-assistant/language-server/out/server/server.js",
    -- yarn global install
    vim.fn.expand "~/.yarn/global/node_modules/@home-assistant/language-server/out/server/server.js",
    -- System install
    "/usr/local/lib/node_modules/@home-assistant/language-server/out/server/server.js",
    -- VS Code extension path (fallback)
    vim.fn.expand "~/.vscode/extensions/keesschollaart.vscode-home-assistant-*/out/server/server.js",
  }

  for _, path in ipairs(fallback_paths) do
    if vim.fn.glob(path) ~= "" then
      local expanded = vim.fn.glob(path)
      if vim.fn.executable "node" == 1 and vim.fn.filereadable(expanded) == 1 then
        utils.logger.debug("Found HA language server at legacy path: " .. expanded)
        return expanded
      end
    end
  end

  utils.logger.debug "No legacy Home Assistant language server installations found"
  return nil
end

---Ensure schema files are present in the out directory
---@param base_dir string Base directory of the vscode-home-assistant repo
function M.ensure_schema_files(base_dir)
  local src_schema_dir = base_dir .. "/src/language-service/src/schemas/json"
  local out_schema_dir = base_dir .. "/out/language-service/src/schemas/json"

  -- Check if source schemas exist
  if vim.fn.isdirectory(src_schema_dir) ~= 1 then
    utils.logger.error("Source schema directory not found: " .. src_schema_dir)
    return false
  end

  -- Create output schema directory if it doesn't exist
  if vim.fn.isdirectory(out_schema_dir) ~= 1 then
    vim.fn.mkdir(out_schema_dir, "p")
    utils.logger.info("Created schema output directory: " .. out_schema_dir)
  end

  -- Copy missing schema files
  local schema_files = { "blueprint-automation.json", "blueprint-script.json" }
  local files_copied = 0

  for _, file in ipairs(schema_files) do
    local src_file = src_schema_dir .. "/" .. file
    local dst_file = out_schema_dir .. "/" .. file

    if vim.fn.filereadable(src_file) == 1 and vim.fn.filereadable(dst_file) ~= 1 then
      -- Use Lua to copy the file (cross-platform)
      local src_content = vim.fn.readfile(src_file)
      if vim.fn.writefile(src_content, dst_file) == 0 then
        files_copied = files_copied + 1
        utils.logger.debug("Copied schema file: " .. file)
      else
        utils.logger.error("Failed to copy schema file: " .. file)
      end
    end
  end

  if files_copied > 0 then
    utils.logger.info(string.format("Copied %d missing schema files", files_copied))
    return true
  end

  return false
end

---Get LSP settings (Fixed based on server analysis)
---@return table LSP settings
function M.get_settings()
  local token = auth.get_token()
  local url = auth.get_url()

  -- Complete configuration structure as expected by the server
  return {
    ["vscode-home-assistant"] = {
      longLivedAccessToken = token or "",
      hostUrl = url or "",
      ignoreCertificates = config.get_value("lsp.settings.vscode-home-assistant.ignoreCertificates", false),
      disableAutomaticFileAssociation = config.get_value(
        "lsp.settings.vscode-home-assistant.disableAutomaticFileAssociation",
        false
      ),
      autoRenderTemplates = config.get_value("lsp.settings.vscode-home-assistant.autoRenderTemplates", true),
      configTimestamp = os.time(),
    },
  }
end

---Get LSP capabilities (Enhanced for better completion integration)
---@return table LSP capabilities
function M.get_capabilities()
  local capabilities = vim.lsp.protocol.make_client_capabilities()

  -- Only disable the most problematic capabilities
  if capabilities.workspace then
    capabilities.workspace.didChangeConfiguration = {
      dynamicRegistration = false,
    }
  end

  -- Enhanced completion capabilities
  if capabilities.textDocument and capabilities.textDocument.completion then
    capabilities.textDocument.completion.completionItem = {
      documentationFormat = { "markdown", "plaintext" },
      snippetSupport = true,
      preselectSupport = true,
      insertReplaceSupport = true,
      labelDetailsSupport = true,
      deprecatedSupport = true,
      commitCharactersSupport = true,
      tagSupport = { valueSet = { 1 } },
      resolveSupport = {
        properties = { "documentation", "detail", "additionalTextEdits" },
      },
    }
    capabilities.textDocument.completion.contextSupport = true
  end

  -- Add cmp-nvim-lsp capabilities if available (for nvim-cmp users)
  local ok, cmp_nvim_lsp = pcall(require, "cmp_nvim_lsp")
  if ok then
    capabilities = cmp_nvim_lsp.default_capabilities(capabilities)
    utils.logger.debug "Enhanced capabilities with cmp_nvim_lsp"
  end

  -- Add blink.cmp capabilities if available
  local ok_blink, blink = pcall(require, "blink.cmp")
  if ok_blink and blink.get_lsp_capabilities then
    capabilities = blink.get_lsp_capabilities(capabilities)
    utils.logger.debug "Enhanced capabilities with blink.cmp"
  end

  return capabilities
end

---LSP on_attach handler (Optimized for better completion UX)
---@param client table LSP client
---@param bufnr number Buffer number
function M.on_attach(client, bufnr)
  utils.logger.debug(string.format("LSP attached to buffer %d", bufnr))

  -- Debug completion capabilities
  if client.server_capabilities.completionProvider then
    utils.logger.info "✓ Home Assistant LSP supports completion"
    utils.logger.debug("Completion capabilities: " .. vim.inspect(client.server_capabilities.completionProvider))

    -- Check for blink.cmp first
    local ok_blink, blink = pcall(require, "blink.cmp")
    if ok_blink then
      utils.logger.info "✓ blink.cmp detected - letting blink handle completion"

      -- Optional: Enhance trigger characters for better UX
      -- You can uncomment this if you want more aggressive triggering
      -- if client.server_capabilities.completionProvider.triggerCharacters then
      --   -- Add more trigger characters for better UX
      --   local triggers = client.server_capabilities.completionProvider.triggerCharacters
      --   table.insert(triggers, ":")  -- Trigger after colons
      --   table.insert(triggers, ".")  -- Trigger after dots
      --   utils.logger.debug("Enhanced trigger characters: " .. vim.inspect(triggers))
      -- end
    else
      -- Only enable native completion if blink is not available
      if vim.lsp.completion and vim.lsp.completion.enable then
        vim.lsp.completion.enable(true, client.id, bufnr, {
          autotrigger = true,
          convert = function(item)
            utils.logger.debug("Converting completion item: " .. (item.label or "no label"))
            return item
          end,
        })
        utils.logger.info "✓ Enabled native LSP completion (no blink.cmp found)"
      else
        -- Fallback for older versions
        vim.bo[bufnr].omnifunc = "v:lua.vim.lsp.omnifunc"
        utils.logger.info "✓ Enabled omnifunc completion fallback"
      end
    end
  else
    utils.logger.warn "✗ Home Assistant LSP does not support completion"
  end

  -- Setup buffer-local keymaps
  -- M.setup_keymaps(bufnr)

  -- Enable document formatting if available
  if client.server_capabilities.documentFormattingProvider then
    vim.bo[bufnr].formatexpr = "v:lua.vim.lsp.formatexpr()"
    utils.logger.debug "✓ Enabled document formatting"
  end

  -- Setup simple document highlighting without custom handlers
  if client.server_capabilities.documentHighlightProvider then
    local group = vim.api.nvim_create_augroup("HALspDocumentHighlight", { clear = false })
    vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
      group = group,
      buffer = bufnr,
      callback = vim.lsp.buf.document_highlight,
    })
    vim.api.nvim_create_autocmd("CursorMoved", {
      group = group,
      buffer = bufnr,
      callback = vim.lsp.buf.clear_references,
    })
    utils.logger.debug "✓ Enabled document highlighting"
  end
end

---Get current LSP client
---@return table? LSP client
function M.get_client()
  if _client_id then return vim.lsp.get_client_by_id(_client_id) end

  -- Fallback: search for the home-assistant client
  for _, client in pairs(vim.lsp.get_clients()) do
    if client.name == "home-assistant" then
      _client_id = client.id
      return client
    end
  end

  return nil
end

---Update authentication credentials
---@param token string? Access token
---@param url string? Home Assistant URL
function M.update_auth(token, url)
  local client = M.get_client()
  if not client then
    utils.logger.warn "No Home Assistant LSP client available for auth update"
    return
  end

  utils.logger.info "Updating Home Assistant LSP authentication"

  -- Update the stored credentials if both are provided
  if token and url then
    auth.save_credentials(token, url)
  end

  -- Send updated configuration to server
  M.send_auth_update(client)
end

---Stop LSP client
function M.stop()
  if _client_id then
    local client = vim.lsp.get_client_by_id(_client_id)
    if client then client:stop() end
    _client_id = nil
    utils.logger.info "Home Assistant LSP client stopped"
  else
    -- Stop by name if client_id is not available
    for _, client in pairs(vim.lsp.get_clients()) do
      if client.name == "home-assistant" then
        client:stop()
        utils.logger.info "Home Assistant LSP client stopped"
        break
      end
    end
  end
end

---Restart LSP client
function M.restart()
  M.stop()
  vim.schedule(function() M.setup() end)
end

---Debug completion status for troubleshooting
---@param bufnr number Buffer number
function M.debug_completion_status(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local lines = { "=== Home Assistant LSP Completion Debug ===" }

  local ha_client = M.get_client()
  if not ha_client then
    table.insert(lines, "❌ No Home Assistant LSP client found")
    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
    return
  end

  table.insert(lines, "✓ Home Assistant LSP client found (ID: " .. ha_client.id .. ")")

  if ha_client.server_capabilities.completionProvider then
    table.insert(lines, "✓ LSP server supports completion")
    table.insert(lines, "  Trigger character is SPACE (' ') - try typing after a space")
  else
    table.insert(lines, "❌ LSP server does not support completion")
  end

  if vim.lsp.completion then
    table.insert(lines, "✓ Native vim.lsp.completion available")
  else
    table.insert(lines, "❌ Native vim.lsp.completion not available (Neovim < 0.11)")
  end

  local omnifunc = vim.bo[bufnr].omnifunc
  table.insert(lines, "Omnifunc: " .. (omnifunc or "not set"))
  table.insert(lines, "Completeopt: " .. vim.o.completeopt)

  table.insert(lines, "")
  table.insert(lines, "=== Completion Sources ===")

  local ok_blink = pcall(require, "blink.cmp")
  if ok_blink then
    table.insert(lines, "✓ blink.cmp detected")
  end

  local ok_cmp = pcall(require, "cmp")
  if ok_cmp then
    table.insert(lines, "✓ nvim-cmp detected")
  end

  if not ok_blink and not ok_cmp then
    table.insert(lines, "Using native LSP completion only")
  end

  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

---Show entity state info in a hover float
---@param entity_id string The entity_id to look up
function M.show_entity_hover(entity_id)
  local registry = require "ha.utils.registry"
  local formatting = require "ha.ui.formatting"

  if not registry.get_stats().initialized then
    vim.notify("Registry not initialized", vim.log.levels.WARN)
    return
  end

  local entity = registry.get_entity(entity_id)
  if not entity then
    vim.notify("Entity '" .. entity_id .. "' not found in registry", vim.log.levels.WARN)
    return
  end

  local lines = {}
  table.insert(lines, "### " .. entity_id)
  table.insert(lines, "")

  local friendly_name = entity.attributes and entity.attributes.friendly_name
  if friendly_name and friendly_name ~= "" then
    table.insert(lines, "**Name:** " .. friendly_name)
  end

  table.insert(lines, "**State:** `" .. tostring(entity.state or "unknown") .. "`")

  if entity.attributes and entity.attributes.unit_of_measurement then
    table.insert(lines, "**Unit:** " .. entity.attributes.unit_of_measurement)
  end

  if entity.area_id then
    local areas = registry.get_areas()
    local area = areas[entity.area_id]
    local area_name = area and area.name or entity.area_id
    table.insert(lines, "**Area:** " .. area_name)
  end

  if entity.device_name then
    table.insert(lines, "**Device:** " .. entity.device_name)
  end

  if entity.platform then
    table.insert(lines, "**Platform:** " .. entity.platform)
  end

  -- Key attributes
  if entity.attributes and type(entity.attributes) == "table" then
    local skip = { friendly_name = true, icon = true, entity_picture = true, unit_of_measurement = true }
    local attr_lines = {}
    for key, value in pairs(entity.attributes) do
      if not key:match("^_") and not skip[key] then
        local formatted_key = key:gsub("_", " "):gsub("^%l", string.upper)
        local formatted_value = formatting.format_value_for_docs(value)
        table.insert(attr_lines, "- **" .. formatted_key .. ":** " .. formatted_value)
      end
    end
    if #attr_lines > 0 then
      table.insert(lines, "")
      table.insert(lines, "**Attributes:**")
      for _, l in ipairs(attr_lines) do
        table.insert(lines, l)
      end
    end
  end

  if entity.last_changed then
    table.insert(lines, "")
    table.insert(lines, "*Last changed: " .. entity.last_changed .. "*")
  end

  vim.lsp.util.open_floating_preview(lines, "markdown", {
    border = "rounded",
    focus_id = "ha_entity_hover",
    max_width = 80,
  })
end

---Test Home Assistant language server command
---@return boolean True if server starts correctly
function M.test_server_command()
  local server_path = M.find_server_path()
  if not server_path then
    utils.logger.error "Cannot test: Home Assistant language server not found"
    return false
  end

  if vim.fn.executable "node" ~= 1 then
    utils.logger.error "Cannot test: Node.js not found"
    return false
  end

  local cmd = { "node", server_path, "--stdio" }
  utils.logger.info("Testing command: " .. table.concat(cmd, " "))

  utils.logger.info "Command structure is valid. Use ':Ha check connection' to test full LSP functionality."
  return true
end

return M
