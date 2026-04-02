-- WebSocket client using websocat over stdio with progress indicators
local M = {}

local utils = require "ha.utils"
local progress = require "ha.utils.progress"
local curl = require "plenary.curl"

-- Process management
local websocket_process = nil
local stdin_pipe = nil
local stdout_pipe = nil
local stderr_pipe = nil

-- State management
local connection_state = "disconnected"
local authenticated = false
local message_id = 0
local pending_requests = {}

-- Connection queue management - Fix for concurrency issues
local connection_queue = {}
local is_connecting = false

-- Auto-reconnect state
local _reconnect_attempts = 0
local _max_reconnect_attempts = 10
local _reconnect_timer = nil
local _manual_disconnect = false

-- Connection progress tracking
local _connection_progress_id = nil

-- Event subscription management
local subscriptions = {}

-- Message queue for when not connected
local message_queue = {}

-- Buffer for handling chunked messages
local message_buffer = ""

---Add callback to connection queue with timestamp
---@param callback function
local function queue_connection_callback(callback)
  table.insert(connection_queue, {
    callback = callback,
    timestamp = os.time(),
  })
end

---Process all queued connection callbacks
---@param success boolean
---@param result any
local function process_connection_queue(success, result)
  local callbacks = connection_queue
  connection_queue = {}
  is_connecting = false

  for _, entry in ipairs(callbacks) do
    vim.schedule(function() entry.callback(success, result) end)
  end
end

---Clean up old connection queue entries (prevent memory leaks)
local function cleanup_connection_queue()
  local current_time = os.time()
  local cleaned_queue = {}

  for _, entry in ipairs(connection_queue) do
    if current_time - entry.timestamp < 60 then -- 60 second timeout
      table.insert(cleaned_queue, entry)
    else
      utils.logger.warn "Connection queue entry timed out"
      vim.schedule(function() entry.callback(false, { error = "Connection queue timeout" }) end)
    end
  end

  connection_queue = cleaned_queue
end

---Generate unique message ID
---@return number
local function next_message_id()
  message_id = message_id + 1
  return message_id
end

---Send raw data to websocat process
---@param data string
local function send_raw(data)
  if not stdin_pipe then
    utils.logger.error "Cannot send data: WebSocket process not running"
    return false
  end

  utils.logger.debug("Sending: " .. data)
  stdin_pipe:write(data .. "\n")
  return true
end

---Send WebSocket message
---@param message table
local function send_message(message)
  local json_data = vim.json.encode(message)
  return send_raw(json_data)
end

---Process a complete WebSocket message
---@param message table
local function process_websocket_message(message)
  local msg_type = message.type or "unknown"
  utils.logger.trace("Processing message type: " .. msg_type)

  -- Handle authentication flow
  if message.type == "auth_required" then
    utils.logger.info "Authentication required"

    -- Use local require to avoid circular dependency
    local auth = require "ha.auth"
    local token = auth.get_token()
    if token then
      send_message {
        type = "auth",
        access_token = token,
      }
    else
      utils.logger.error "No authentication token available"
      connection_state = "auth_failed"
      if is_connecting then process_connection_queue(false, { error = "No authentication token" }) end
    end
    return
  end

  if message.type == "auth_ok" then
    authenticated = true
    connection_state = "authenticated"
    utils.logger.info "Authentication successful"

    -- Complete connection progress tracking
    if _connection_progress_id then
      progress.complete_request(_connection_progress_id, true)
      _connection_progress_id = nil
    end

    -- Process queued messages
    for _, queued_msg in ipairs(message_queue) do
      send_message(queued_msg.message)
    end
    message_queue = {}

    -- Process all queued connection callbacks
    if is_connecting then
      vim.schedule(function()
        -- Auto-initialize registry after successful WebSocket connection
        local ok, registry = pcall(require, "ha.utils.registry")
        if ok and not registry.get_stats().initialized then
          utils.logger.info "Auto-initializing registry after WebSocket connection"
          registry.initialize(function(success, error)
            if success then
              local stats = registry.get_stats()
              utils.logger.info(
                string.format(
                  "Registry auto-initialized: %d areas, %d devices, %d entities",
                  stats.areas_count,
                  stats.devices_count,
                  stats.entities_count
                )
              )
            else
              utils.logger.warn("Registry auto-initialization failed: " .. tostring(error))
            end
          end)
        end
      end)
      process_connection_queue(true, nil)
    end
    return
  end

  if message.type == "auth_invalid" then
    authenticated = false
    connection_state = "auth_failed"
    local error_msg = message.message or "Authentication failed"
    utils.logger.error("Authentication failed: " .. error_msg)

    -- Complete connection progress tracking with error
    if _connection_progress_id then
      progress.fail_request(_connection_progress_id, error_msg)
      _connection_progress_id = nil
    end

    if is_connecting then process_connection_queue(false, { error = error_msg }) end
    return
  end

  -- Handle command responses AND subscription confirmations
  if message.type == "result" and message.id then
    -- First check if this is a subscription confirmation
    if subscriptions[message.id] then
      local subscription = subscriptions[message.id]
      if message.success then
        utils.logger.debug("Subscription " .. message.id .. " established successfully")
        subscription.active = true
      else
        utils.logger.error("Subscription " .. message.id .. " failed: " .. vim.inspect(message.error))
        subscriptions[message.id] = nil
      end
      return
    end

    -- Otherwise handle as regular command response
    local request = pending_requests[message.id]
    if request then
      pending_requests[message.id] = nil

      -- Complete progress tracking if request was tracked
      if request.progress_id then
        if message.success then
          progress.complete_request(request.progress_id, true)
        else
          local error_msg = message.error and message.error.message or "Unknown error"
          progress.complete_request(request.progress_id, false, error_msg)
        end
      end

      utils.logger.debug("Received result for message ID: " .. message.id)

      vim.schedule(function()
        if message.success then
          if type(message.result) == "table" and #message.result > 10 then
            utils.logger.debug("Received large result with " .. #message.result .. " items")
          end
          request.callback(true, message.result)
        else
          request.callback(false, message.error or { error = "Unknown error" })
        end
      end)
    else
      utils.logger.warn("Received result for unknown message ID: " .. tostring(message.id))
    end
    return
  end

  -- Handle events (state changes, registry changes, etc.)
  if message.type == "event" then
    if message.id and subscriptions[message.id] then
      local subscription = subscriptions[message.id]
      vim.schedule(function() subscription.callback(message.event) end)
    end
    return
  end

  utils.logger.debug("Unhandled message type: " .. tostring(message.type))
end

---Handle incoming WebSocket message
---@param raw_message string
local function handle_message(raw_message)
  raw_message = raw_message:gsub("^%s*(.-)%s*$", "%1")
  if raw_message == "" then return end

  utils.logger.trace(
    "Received chunk: " .. string.sub(raw_message, 1, 200) .. (string.len(raw_message) > 200 and "..." or "")
  )

  message_buffer = message_buffer .. raw_message

  local start_pos = 1
  while start_pos <= string.len(message_buffer) do
    local json_start = string.find(message_buffer, "{", start_pos)
    if not json_start then break end

    local brace_count = 0
    local in_string = false
    local escaped = false
    local json_end = nil

    for i = json_start, string.len(message_buffer) do
      local char = string.sub(message_buffer, i, i)

      if escaped then
        escaped = false
      elseif char == "\\" then
        escaped = true
      elseif char == '"' and not escaped then
        in_string = not in_string
      elseif not in_string then
        if char == "{" then
          brace_count = brace_count + 1
        elseif char == "}" then
          brace_count = brace_count - 1
          if brace_count == 0 then
            json_end = i
            break
          end
        end
      end
    end

    if json_end then
      local json_str = string.sub(message_buffer, json_start, json_end)

      local ok, message = pcall(vim.json.decode, json_str)
      if ok then
        process_websocket_message(message)
      else
        utils.logger.error("Failed to decode JSON: " .. string.sub(json_str, 1, 500) .. "...")
      end

      start_pos = json_end + 1
    else
      break
    end
  end

  if start_pos > 1 then message_buffer = string.sub(message_buffer, start_pos) end
end

---Start WebSocket connection
---@param callback function Callback(success, error)
local function start_connection(callback)
  if connection_state == "authenticated" then
    callback(true, nil)
    return
  end

  -- Use local require to avoid circular dependency
  local auth = require "ha.auth"
  local url = auth.get_url()
  if not url then
    callback(false, { error = "No URL configured" })
    return
  end

  local ws_url = url
    :gsub("^https?://", function(protocol) return protocol == "https://" and "wss://" or "ws://" end)
    :gsub("/$", "") .. "/api/websocket"

  connection_state = "connecting"

  utils.logger.info("Connecting to: " .. ws_url)

  -- Use new progress system for connection tracking
  local connection_progress_id = progress.add_background "Connecting"

  -- Check for websocat synchronously before spawning
  if vim.fn.executable "websocat" ~= 1 then
    progress.fail_request(connection_progress_id, "websocat not installed")
    utils.logger.error "websocat not found. Install with: cargo install websocat"
    connection_state = "error"
    callback(false, { error = "websocat not installed" })
    return
  end

  stdin_pipe = vim.loop.new_pipe()
  stdout_pipe = vim.loop.new_pipe()
  stderr_pipe = vim.loop.new_pipe()

  websocket_process = vim.loop.spawn("websocat", {
    args = {
      ws_url,
      "--text",
      "-E",
      "-B",
      "2097152",
      "--ping-interval",
      "2",
      "--ping-timeout",
      "4",
    },
    stdio = { stdin_pipe, stdout_pipe, stderr_pipe },
  }, function(code, _)
    utils.logger.info("WebSocket process exited with code: " .. tostring(code))
    local was_auth = authenticated
    connection_state = "disconnected"
    authenticated = false

    -- Notify user that connection was lost (only once, not on every reconnect attempt)
    if was_auth and _reconnect_attempts == 0 then
      vim.schedule(function() vim.notify("HA connection lost", vim.log.levels.WARN) end)
    end

    -- Complete connection progress on disconnect (only if not already completed)
    if _connection_progress_id == connection_progress_id then
      progress.fail_request(connection_progress_id, "Connection lost")
      _connection_progress_id = nil
    end

    -- Reset message ID counters to avoid ID reuse errors on reconnection
    message_id = 0

    -- Collect pending requests before clearing (mutating during pairs() is undefined)
    local orphaned_requests = {}
    for id, request in pairs(pending_requests) do
      table.insert(orphaned_requests, request)
    end
    pending_requests = {}

    -- Fail progress and schedule callbacks for orphaned requests
    for _, request in ipairs(orphaned_requests) do
      -- Fail progress directly (runs in libuv context, but progress state is just Lua tables)
      if request.progress_id then progress.fail_request(request.progress_id, "Connection lost") end
      vim.schedule(function() request.callback(false, { error = "Connection lost" }) end)
    end

    -- Clear subscriptions
    subscriptions = {}

    -- Clean up pipes
    if stdin_pipe then pcall(function() stdin_pipe:close() end) end
    if stdout_pipe then pcall(function() stdout_pipe:close() end) end
    if stderr_pipe then pcall(function() stderr_pipe:close() end) end
    stdin_pipe = nil
    stdout_pipe = nil
    stderr_pipe = nil
    websocket_process = nil

    -- Process any remaining queued callbacks with error
    if is_connecting then process_connection_queue(false, { error = "Process exited unexpectedly" }) end

    -- Clear message buffer to avoid corrupt partial JSON on reconnect
    message_buffer = ""

    -- Auto-reconnect if we were previously authenticated (e.g., HA restarted)
    -- Skip if this was a manual disconnect
    if was_auth and not _manual_disconnect then M._schedule_reconnect() end
    _manual_disconnect = false
  end)

  if not websocket_process then
    progress.fail_request(connection_progress_id, "Failed to start process")
    utils.logger.error "Failed to start websocat process"
    connection_state = "error"
    callback(false, { error = "Failed to start process" })
    return
  end

  stdout_pipe:read_start(function(err, data)
    if err then
      utils.logger.error("stdout error: " .. tostring(err))
      return
    end

    if data then
      for line in data:gmatch "[^\r\n]+" do
        handle_message(line)
      end
    end
  end)

  stderr_pipe:read_start(function(err, data)
    if err then
      utils.logger.error("stderr pipe error: " .. tostring(err))
      return
    end

    if data then
      utils.logger.error("websocat stderr: " .. data)
      if data:match "WebSocket connection closed" or data:match "Connection refused" then
        progress.fail_request(connection_progress_id, "Connection failed: " .. data)
        connection_state = "error"
        callback(false, { error = "Connection failed: " .. data })
      end
    end
  end)

  connection_state = "connected"
  utils.logger.info "WebSocket process started, waiting for auth_required"

  -- Set up authentication timeout with progress completion
  vim.defer_fn(function()
    if not authenticated and is_connecting then
      progress.fail_request(connection_progress_id, "Authentication timeout")
      utils.logger.error "Authentication timeout"
      callback(false, { error = "Authentication timeout" })
    end
  end, 10000)

  -- Store connection progress ID for completion in auth flow
  _connection_progress_id = connection_progress_id
end

---Send WebSocket message with callback
---@param message table
---@param callback function
---@param progress_description string|nil Optional progress description
---@param notify_on_completion boolean|nil If true, use user_action progress (shows notification)
local function send_ws_message(message, callback, progress_description, notify_on_completion)
  if connection_state ~= "authenticated" then
    callback(false, { error = "Not authenticated" })
    return
  end

  local id = next_message_id()
  message.id = id

  -- Add to progress tracker if description provided
  local request_id = nil
  if progress_description then
    if notify_on_completion then
      request_id = progress.add_user_action(progress_description)
    else
      request_id = progress.add_background(progress_description)
    end
  end

  pending_requests[id] = {
    callback = callback,
    timestamp = os.time(),
    progress_id = request_id, -- Track progress ID for completion
  }

  if not send_message(message) then
    pending_requests[id] = nil
    if request_id then progress.fail_request(request_id, "Failed to send message") end
    callback(false, { error = "Failed to send message" })
    return
  end

  -- Clean up old requests (timeout mechanism)
  local current_time = os.time()
  for req_id, request in pairs(pending_requests) do
    if current_time - request.timestamp > 30 then
      utils.logger.warn("Request timeout for message ID: " .. req_id)

      -- Mark progress as failed if tracking
      if request.progress_id then progress.fail_request(request.progress_id, "Request timeout") end

      vim.schedule(function() request.callback(false, { error = "Request timeout" }) end)
      pending_requests[req_id] = nil
    end
  end
end

---Schedule a reconnect attempt with fixed interval
---Called from the exit handler when a previously authenticated connection drops
function M._schedule_reconnect()
  if _reconnect_attempts >= _max_reconnect_attempts then
    vim.schedule(function()
      vim.notify("HA reconnect failed after " .. _max_reconnect_attempts .. " attempts. Use :Ha connect to retry.", vim.log.levels.ERROR)
    end)
    _reconnect_attempts = 0
    return
  end

  _reconnect_attempts = _reconnect_attempts + 1
  local delay = 5000 -- Fixed 5 second interval

  -- Show reconnect progress in status bar
  local reconnect_progress_id = progress.add_background(
    string.format("Reconnecting to HA (%d/%d)", _reconnect_attempts, _max_reconnect_attempts)
  )

  _reconnect_timer = vim.defer_fn(function()
    if connection_state ~= "disconnected" then
      progress.complete_request(reconnect_progress_id, true)
      return
    end

    M.connect(function(success, err)
      if success then
        progress.complete_request(reconnect_progress_id, true)
        _reconnect_attempts = 0
        vim.notify("HA reconnected", vim.log.levels.INFO)

        -- Refresh registry with fresh data from the (possibly restarted) HA instance
        local ok, registry = pcall(require, "ha.utils.registry")
        if ok and registry.get_stats().initialized then
          registry.refresh(function() end)
        end
      else
        progress.fail_request(reconnect_progress_id, "Failed")
        -- Schedule next attempt
        if not _manual_disconnect then M._schedule_reconnect() end
      end
    end)
  end, delay)
end

---Ensure connection is established with proper queuing
---@param callback function
local function ensure_connection(callback)
  if connection_state == "authenticated" then
    callback(true, nil)
    return
  end

  -- Clean up old queue entries periodically
  cleanup_connection_queue()

  -- Queue the callback
  queue_connection_callback(callback)

  -- If already connecting, just wait in queue
  if is_connecting then return end

  -- Start new connection
  is_connecting = true
  start_connection(function(success, result) process_connection_queue(success, result) end)
end

---Public connect function (wraps ensure_connection)
---@param callback function Callback(success, error)
function M.connect(callback) ensure_connection(callback) end

-- Public API functions
function M.call_service(domain, service, service_data, callback)
  ensure_connection(function(success, err)
    if not success then
      callback(false, err)
      return
    end

    local message = {
      type = "call_service",
      domain = domain,
      service = service,
    }

    if service_data and next(service_data) then
      if service_data.entity_id then
        message.target = { entity_id = service_data.entity_id }
        local service_data_copy = vim.deepcopy(service_data)
        service_data_copy.entity_id = nil
        if next(service_data_copy) then message.service_data = service_data_copy end
      else
        message.service_data = service_data
      end
    end

    -- Pass progress description to send_ws_message so progress_id is tracked
    -- in pending_requests and can be cleaned up by the exit handler directly
    local progress_desc = string.format("Calling %s.%s", domain, service)

    send_ws_message(message, callback, progress_desc, false)
  end)
end

function M.get_states(entity_id, callback)
  ensure_connection(function(success, err)
    if not success then
      callback(false, err)
      return
    end

    send_ws_message({ type = "get_states" }, function(success, result)
      if success and result and entity_id then
        for _, state in ipairs(result) do
          if state.entity_id == entity_id then
            callback(true, state)
            return
          end
        end
        callback(false, { error = "Entity not found" })
      else
        callback(success, result)
      end
    end)
  end)
end

-- Registry API functions with dynamic progress tracking
function M.get_area_registry(callback, show_progress)
  ensure_connection(function(success, err)
    if not success then
      callback(false, err)
      return
    end

    send_ws_message({ type = "config/area_registry/list" }, callback, show_progress and "Loading areas" or nil)
  end)
end

function M.get_device_registry(callback, show_progress)
  ensure_connection(function(success, err)
    if not success then
      callback(false, err)
      return
    end

    send_ws_message({ type = "config/device_registry/list" }, callback, show_progress and "Loading devices" or nil)
  end)
end

function M.get_entity_registry(callback, show_progress)
  ensure_connection(function(success, err)
    if not success then
      callback(false, err)
      return
    end

    send_ws_message({ type = "config/entity_registry/list" }, callback, show_progress and "Loading entities" or nil)
  end)
end

function M.get_integration_registry(callback, show_progress)
  ensure_connection(function(success, err)
    if not success then
      callback(false, err)
      return
    end

    -- Create single progress entry for the entire integration operation
    local progress_id = nil
    if show_progress then progress_id = progress.add_background "Loading integrations" end

    -- Wrapper callback that handles progress completion
    local complete_callback = function(success, result)
      if progress_id then
        progress.complete_request(progress_id, success, not success and "Integration API failed" or nil)
      end
      callback(success, result)
    end

    -- Try admin API first (no progress tracking on individual call)
    send_ws_message({ type = "integration/descriptions" }, function(admin_success, admin_result)
      if admin_success and admin_result and admin_result.core and admin_result.core.integration then
        utils.logger.info "Using admin integration API (integration/descriptions)"

        -- Process admin result to extract integration list
        local integrations = {}
        for domain, integration_data in pairs(admin_result.core.integration) do
          table.insert(integrations, {
            domain = domain,
            name = integration_data.name or domain,
            version = integration_data.version,
            is_built_in = true, -- Admin API shows all core integrations
            integration_type = integration_data.integration_type,
            config_flow = integration_data.config_flow,
            iot_class = integration_data.iot_class,
            single_config_entry = integration_data.single_config_entry,
            supported_by = integration_data.supported_by,
            quality_scale = integration_data.quality_scale,
            iot_standards = integration_data.iot_standards,
            documentation = integration_data.documentation,
            requirements = integration_data.requirements,
            dependencies = integration_data.dependencies,
            _source = "admin_api",
          })
        end

        -- Sort by domain name for consistency
        table.sort(integrations, function(a, b) return a.domain < b.domain end)
        utils.logger.info(string.format("Admin API returned %d integrations", #integrations))
        complete_callback(true, integrations)
      else
        -- Admin API failed, fallback to manifest/list
        utils.logger.info "Admin integration API failed, falling back to manifest/list"

        send_ws_message({ type = "manifest/list" }, function(manifest_success, manifest_result)
          if manifest_success and manifest_result then
            -- Add source marker to manifest data
            for _, integration in ipairs(manifest_result) do
              integration._source = "manifest_api"
            end
            utils.logger.info(string.format("Manifest API returned %d integrations", #manifest_result))
            complete_callback(true, manifest_result)
          else
            utils.logger.error "Both integration APIs failed"
            complete_callback(false, manifest_result or admin_result)
          end
        end) -- No progress tracking on fallback call
      end
    end) -- No progress tracking on initial call
  end)
end

-- Services API function (uses WebSocket get_services command)
function M.get_services(callback, show_progress)
  ensure_connection(function(success, err)
    if not success then
      callback(false, err)
      return
    end

    send_ws_message({ type = "get_services" }, callback, show_progress and "Loading services" or nil)
  end)
end

function M.get_all_registries(callback)
  local results = {}
  local completed = 0
  local total = 5 -- areas, devices, entities, integrations, services
  local has_error = false

  -- Track individual progress requests
  local progress_requests = {}

  local data_sources = {
    { key = "areas", name = "Areas", type = "config/area_registry/list" },
    { key = "devices", name = "Devices", type = "config/device_registry/list" },
    { key = "entities", name = "Entities", type = "config/entity_registry/list" },
    { key = "integrations", name = "Integrations", type = "manifest/list" },
    { key = "services", name = "Services", type = "get_services" },
  }

  local function complete_callback(source_info, success, result)
    if has_error then return end

    completed = completed + 1

    if success then
      results[source_info.key] = result
      local count = 0

      -- Calculate count based on data type
      if source_info.key == "services" and type(result) == "table" then
        -- Count services across all domains
        for domain, services in pairs(result) do
          if type(services) == "table" then count = count + vim.tbl_count(services) end
        end
      else
        count = type(result) == "table" and #result or 0
      end

      utils.logger.debug(string.format("Loaded %s: %d items", source_info.name, count))
    else
      has_error = true
      utils.logger.error("Data loading failed for " .. source_info.name .. ": " .. vim.inspect(result))
      callback(false, result)
      return
    end

    if completed == total then
      utils.logger.info "All registry data loaded successfully"
      callback(true, results)
    end
  end

  -- Start loading all data sources with new progress system
  for i, source_info in ipairs(data_sources) do
    vim.defer_fn(function()
      if source_info.key == "areas" then
        M.get_area_registry(function(success, result) complete_callback(source_info, success, result) end, true) -- Enable progress tracking
      elseif source_info.key == "devices" then
        M.get_device_registry(function(success, result) complete_callback(source_info, success, result) end, true) -- Enable progress tracking
      elseif source_info.key == "entities" then
        M.get_entity_registry(function(success, result) complete_callback(source_info, success, result) end, true) -- Enable progress tracking
      elseif source_info.key == "integrations" then
        M.get_integration_registry(function(success, result) complete_callback(source_info, success, result) end, true) -- Enable progress tracking
      elseif source_info.key == "services" then
        M.get_services(function(success, result) complete_callback(source_info, success, result) end, true) -- Enable progress tracking
      end
    end, (i - 1) * 100) -- Small delay between requests for better UX
  end
end

---Generic REST API request handler following DRY principle
---@param endpoint string API endpoint (without base URL, e.g., "/api/config")
---@param callback function Callback function(success, result)
---@param options? table Additional options: { method: string, data: table, timeout: number, parse_json: boolean, url: string, token: string }
local function make_rest_request(endpoint, callback, options)
  options = options or {}

  -- Use local require to avoid circular dependency
  local auth = require "ha.auth"

  -- Use provided credentials or fall back to configured ones
  local token = options.token or auth.get_token()
  local url = options.url or auth.get_url()

  if not token or not url then
    callback(false, { error = "No credentials configured" })
    return
  end

  local api_url = url:gsub("/$", "") .. endpoint
  local method = (options.method or "GET"):lower()

  utils.logger.debug("REST API " .. method:upper() .. " request to: " .. api_url)

  local curl_opts = {
    url = api_url,
    headers = {
      ["Authorization"] = "Bearer " .. token,
      ["Content-Type"] = "application/json",
    },
    timeout = options.timeout or 5000,
    callback = function(response)
      vim.schedule(function()
        if response.status >= 200 and response.status < 300 then
          local result = response.body or ""

          -- Parse JSON if requested (default: true)
          if options.parse_json ~= false then
            local ok, data = pcall(vim.json.decode, vim.trim(result))
            if ok and data then
              result = data
            elseif options.parse_json == true then
              callback(false, { error = "Invalid JSON response" })
              return
            end
          end

          callback(true, result)
        elseif response.status == 401 then
          callback(false, { error = "Authentication failed (401 Unauthorized)" })
        else
          -- Try to extract detailed error information from response body
          local error_details = "HTTP error: " .. response.status .. " " .. (response.status_text or "")

          if response.body and response.body ~= "" then
            -- Try to parse error body as JSON to get detailed message
            local ok, error_data = pcall(vim.json.decode, vim.trim(response.body))
            if ok and error_data then
              if error_data.message then
                error_details = error_details .. "\n" .. error_data.message
              elseif error_data.error then
                error_details = error_details .. "\n" .. error_data.error
              elseif type(error_data) == "string" then
                error_details = error_details .. "\n" .. error_data
              end
            else
              -- If not JSON, include raw body (truncated if too long)
              local body_preview = response.body:sub(1, 200)
              if #response.body > 200 then body_preview = body_preview .. "..." end
              error_details = error_details .. "\n" .. body_preview
            end
          end

          callback(false, { error = error_details })
        end
      end)
    end,
    on_error = function(err)
      vim.schedule(function() callback(false, { error = "Connection error: " .. vim.inspect(err) }) end)
    end,
  }

  -- Add data for POST requests
  if method == "post" and options.data then curl_opts.body = vim.json.encode(options.data) end

  -- Call appropriate curl method
  if method == "post" then
    curl.post(curl_opts)
  else
    curl.get(curl_opts)
  end
end

-- Additional API functions for compatibility

---Check Home Assistant configuration
---@param callback function Callback function(success, result)
function M.check_config(callback)
  ensure_connection(function(success, err)
    if not success then
      callback(false, err)
      return
    end

    send_ws_message({ type = "call_service", domain = "homeassistant", service = "check_config" }, callback)
  end)
end

---Get error log (fallback to REST API since WebSocket doesn't support this)
---@param callback function Callback function(success, result)
function M.get_error_log(callback) make_rest_request("/api/error_log", callback, { parse_json = false }) end

---Render template
---@param template string Template string
---@param callback function Callback function(success, result)
function M.render_template(template, callback)
  make_rest_request("/api/template", function(success, result)
    if success then
      -- REST API returns plain text for templates
      callback(true, { template = template, result = result })
    else
      callback(false, { template = template, error = result.error or "Template render failed" })
    end
  end, {
    method = "POST",
    data = { template = template },
    parse_json = false, -- Template API returns plain text, not JSON
  })
end

---Refresh Lovelace configuration
---@param callback function Callback function(success, result)
function M.refresh_lovelace(callback)
  ensure_connection(function(success, err)
    if not success then
      callback(false, err)
      return
    end

    send_ws_message({
      type = "lovelace/config",
      force = true,
    }, callback)
  end)
end

---Get events information
---@param callback function Callback function(success, result)
function M.get_events(callback)
  ensure_connection(function(success, err)
    if not success then
      callback(false, err)
      return
    end

    -- Get available event types (this returns a list of event types)
    send_ws_message({ type = "get_events" }, callback)
  end)
end

---Get history
---@param start_time? string Start time (ISO format)
---@param end_time? string End time (ISO format)
---@param entity_ids? table List of entity IDs
---@param callback function Callback function(success, result)
function M.get_history(start_time, end_time, entity_ids, callback)
  ensure_connection(function(success, err)
    if not success then
      callback(false, err)
      return
    end

    local message = { type = "history/history_during_period" }
    if start_time then message.start_time = start_time end
    if end_time then message.end_time = end_time end
    if entity_ids then message.entity_ids = entity_ids end

    send_ws_message(message, callback)
  end)
end

---Set state for an entity (uses call_service with input_text or similar)
---@param entity_id string Entity ID
---@param state string New state
---@param attributes? table Entity attributes
---@param callback function Callback function(success, result)
function M.set_state(entity_id, state, attributes, callback)
  -- For WebSocket, we typically use call_service instead of direct state setting
  -- This is a simplified version - in practice you'd need to determine the right service
  local domain = entity_id:match "^([^%.]+)%."

  if domain == "input_text" then
    M.call_service(domain, "set_value", { entity_id = entity_id, value = state }, callback)
  elseif domain == "input_number" then
    M.call_service(domain, "set_value", { entity_id = entity_id, value = tonumber(state) }, callback)
  elseif domain == "input_boolean" then
    local service = state == "on" and "turn_on" or "turn_off"
    M.call_service(domain, service, { entity_id = entity_id }, callback)
  else
    callback(false, { error = "State setting not supported for domain: " .. domain })
  end
end

---@param event_type string|nil Event type to subscribe to (nil for all events)
---@param callback function Callback for events
---@return number|nil Subscription ID
function M.subscribe_events(event_type, callback)
  if connection_state ~= "authenticated" then
    -- If not connected, try to establish connection first
    ensure_connection(function(success, err)
      if success then
        -- Retry subscription after connection established
        M.subscribe_events(event_type, callback)
      else
        callback { error = err }
      end
    end)
    return nil
  end

  local sub_id = next_message_id()
  local message = {
    id = sub_id,
    type = "subscribe_events",
  }

  if event_type then message.event_type = event_type end

  subscriptions[sub_id] = {
    callback = callback,
    event_type = event_type,
    active = false,
  }

  -- Use send_message instead of send_ws_message since this doesn't need a response callback
  if send_message(message) then
    utils.logger.debug("Subscription request sent with ID: " .. sub_id)
    return sub_id
  else
    subscriptions[sub_id] = nil
    callback { error = "Failed to send subscription message" }
    return nil
  end
end

---Subscribe to registry changes
---@param callback function Callback for registry change events
---@return table Subscription IDs for area, device, entity, and integration registries
function M.subscribe_registry_changes(callback)
  local subscription_ids = {}

  -- Subscribe to area registry changes
  subscription_ids.areas = M.subscribe_events("area_registry_updated", function(event) callback("areas", event) end)

  -- Subscribe to device registry changes
  subscription_ids.devices = M.subscribe_events(
    "device_registry_updated",
    function(event) callback("devices", event) end
  )

  -- Subscribe to entity registry changes
  subscription_ids.entities = M.subscribe_events(
    "entity_registry_updated",
    function(event) callback("entities", event) end
  )

  -- Subscribe to integration registry changes
  subscription_ids.integrations = M.subscribe_events(
    "integration_registry_updated",
    function(event) callback("integrations", event) end
  )

  return subscription_ids
end

---Unsubscribe from events
---@param subscription_id number
function M.unsubscribe_events(subscription_id)
  if not subscriptions[subscription_id] then return end

  ensure_connection(function(success, err)
    if not success then return end

    send_ws_message({
      type = "unsubscribe_events",
      subscription = subscription_id,
    }, function(success, result)
      if success then
        subscriptions[subscription_id] = nil
        utils.logger.debug("Unsubscribed from events: " .. subscription_id)
      end
    end)
  end)
end

---Fire an event in Home Assistant
---@param event_type string Event type to fire
---@param event_data table|nil Optional event data
---@param callback function Callback(success, result)
function M.fire_event(event_type, event_data, callback)
  ensure_connection(function(success, err)
    if not success then
      callback(false, err)
      return
    end

    local message = {
      type = "fire_event",
      event_type = event_type,
    }
    if event_data then
      message.event_data = event_data
    end

    send_ws_message(message, callback)
  end)
end

function M.disconnect()
  -- Signal to the exit handler that this is a manual disconnect (no auto-reconnect)
  _manual_disconnect = true

  -- Cancel any pending reconnect timer
  if _reconnect_timer then
    pcall(function() _reconnect_timer:stop() end)
    _reconnect_timer = nil
  end
  _reconnect_attempts = 0

  if websocket_process then
    websocket_process:kill "SIGTERM"
    -- Don't nil websocket_process here — let the exit handler do cleanup
    -- The exit handler will check _manual_disconnect and skip reconnect
  end

  connection_state = "disconnected"
  authenticated = false
  subscriptions = {}

  -- Reset message ID counter to avoid "Identifier values have to increase" errors
  message_id = 0

  -- Clear message buffer
  message_buffer = ""

  -- Clear any pending connection queue
  if is_connecting then process_connection_queue(false, { error = "Connection manually disconnected" }) end
end

function M.get_connection_debug()
  return {
    state = connection_state,
    authenticated = authenticated,
    process_running = websocket_process ~= nil,
    pending_requests = vim.tbl_count(pending_requests),
    queued_messages = #message_queue,
    active_subscriptions = vim.tbl_count(subscriptions),
    connection_queue_size = #connection_queue,
    is_connecting = is_connecting,
    manual_disconnect = _manual_disconnect,
    reconnect_attempts = _reconnect_attempts,
  }
end

---Get Home Assistant instance information using REST API
---@param callback function Callback function(success, info)
function M.get_instance_info(callback) make_rest_request("/api/config", callback) end

---Test connection and authentication to Home Assistant
---This is equivalent to the old test_connection but uses get_instance_info
---@param callback function Callback function(success, result)
function M.test_connection_and_auth(callback)
  M.get_instance_info(function(success, result)
    if success then
      callback(true, {
        name = result.location_name or "Home Assistant",
        version = result.version,
        url = result.url,
        message = "Connection and authentication successful",
      })
    else
      callback(false, result)
    end
  end)
end

function M.setup(opts)
  opts = opts or {}
  utils.logger.info "Home Assistant WebSocket API (websocat) initialized"
end

return M
