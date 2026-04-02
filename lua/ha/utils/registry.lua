-- Registry processing module for Home Assistant entities
-- Handles caching, relationship resolution, and real-time updates via WebSocket

local M = {}

-- Note: api module is required dynamically to avoid circular dependencies
local logger = require "ha.utils.logger"

-- In-memory registry data
local _registries = {
  areas = {},
  devices = {},
  entities = {},
  integrations = {},
  services = {},
  initialized = false,
  last_updated = 0,
}

-- In-memory state data
local _states = {}

-- Available domains set for completion
local _available_domains = {}

-- Initialization guard
local _initializing = false
local _pending_callbacks = {}

-- WebSocket subscription IDs for registry and state changes
local _subscription_ids = {}

---Extract domains from entities and populate domain set
---@param entities table Indexed entities table
local function extract_domains_from_entities(entities)
  for entity_id, _ in pairs(entities) do
    local domain = entity_id:match("^([^%.]+)%.")
    if domain then
      _available_domains[domain] = true
    end
  end
end

---Index array by ID field
---@param items table Array of items
---@param id_field string Field name to use as key
---@return table Indexed table
local function index_by_id(items, id_field)
  local indexed = {}
  if type(items) ~= "table" then
    logger.debug("Invalid items type for indexing: " .. type(items))
    return indexed
  end

  for _, item in ipairs(items) do
    if type(item) == "table" and item[id_field] then
      indexed[item[id_field]] = item
    else
      logger.debug("Skipping invalid item in registry: " .. vim.inspect(item))
    end
  end
  return indexed
end

---Enrich entity data with device_name, resolved area_id, and current state
---@param entity table Entity data to enrich
---@param devices table Device registry
local function enrich_entity(entity, devices)
  if not entity then return end

  -- Add device_name if entity has a device
  if entity.device_id then
    local device = devices[entity.device_id]
    if device then
      entity.device_name = device.name or device.name_by_user

      -- If entity doesn't have direct area assignment, use device's area
      if not entity.area_id or entity.area_id == vim.NIL then
        if device.area_id and device.area_id ~= vim.NIL then entity.area_id = device.area_id end
      end
      entity.device = device
    else
      entity.device_name = nil
      entity.device = nil
    end
  else
    entity.device_name = nil
    entity.device = nil
  end

  -- Ensure area_id is nil instead of vim.NIL for consistency
  if entity.area_id == vim.NIL then entity.area_id = nil end

  -- Add current state and attributes if available
  local state_data = _states[entity.entity_id]
  if state_data then
    entity.state = state_data.state
    entity.attributes = state_data.attributes or {}
    entity.last_changed = state_data.last_changed
    entity.last_updated = state_data.last_updated
    entity.context = state_data.context
  else
    -- Set defaults if no state data available
    entity.state = nil
    entity.attributes = {}
    entity.last_changed = nil
    entity.last_updated = nil
    entity.context = nil
  end
end

---Enrich all entities with device and area information
local function enrich_all_entities()
  logger.debug "Enriching all entities with device, area, and state information"

  for entity_id, entity in pairs(_registries.entities) do
    enrich_entity(entity, _registries.devices)
  end

  logger.debug("Enriched " .. vim.tbl_count(_registries.entities) .. " entities")
end

---Update entities affected by device changes
---@param device_id string Device ID that changed
local function update_entities_for_device(device_id)
  logger.debug("Updating entities for device: " .. device_id)

  -- Find all entities that belong to this device and re-enrich them
  for entity_id, entity in pairs(_registries.entities) do
    if entity.device_id == device_id then enrich_entity(entity, _registries.devices) end
  end
end

---Update entities affected by area changes
---@param area_id string Area ID that changed
local function update_entities_for_area(area_id)
  logger.debug("Updating entities for area: " .. area_id)

  -- Find all entities directly assigned to this area and re-enrich them
  for entity_id, entity in pairs(_registries.entities) do
    if entity.area_id == area_id then enrich_entity(entity, _registries.devices) end
  end

  -- Also update entities whose devices belong to this area
  for device_id, device in pairs(_registries.devices) do
    if device.area_id == area_id then update_entities_for_device(device_id) end
  end
end

---Handle registry change events
---@param registry_type string Type of registry that changed
---@param event table Event data
local function handle_registry_change(registry_type, event)
  logger.debug("Registry change event: " .. registry_type .. " - " .. vim.inspect(event))

  if not event or not event.data then
    logger.warn "Invalid registry change event"
    return
  end

  local action = event.data.action
  local item = event.data[registry_type:sub(1, -2)] -- Remove 's' from 'areas', 'devices', 'entities'

  if not item then
    logger.warn "No item data in registry change event"
    return
  end

  if registry_type == "areas" then
    local area_id = item.area_id
    if action == "create" or action == "update" then
      _registries.areas[area_id] = item
      update_entities_for_area(area_id)
    elseif action == "remove" then
      _registries.areas[area_id] = nil
      update_entities_for_area(area_id)
    end
  elseif registry_type == "devices" then
    local device_id = item.id
    if action == "create" or action == "update" then
      _registries.devices[device_id] = item
      update_entities_for_device(device_id)
    elseif action == "remove" then
      _registries.devices[device_id] = nil
      update_entities_for_device(device_id)
    end
  elseif registry_type == "entities" then
    local entity_id = item.entity_id
    if action == "create" or action == "update" then
      _registries.entities[entity_id] = item
      enrich_entity(item, _registries.devices)
      
      -- Add domain if new
      local domain = entity_id:match("^([^%.]+)%.")
      if domain and not _available_domains[domain] then
        _available_domains[domain] = true
        logger.debug("New domain discovered: " .. domain)
      end
    elseif action == "remove" then
      _registries.entities[entity_id] = nil
      _states[entity_id] = nil -- Also remove state data
    end
  elseif registry_type == "integrations" then
    local domain = item.domain
    if action == "create" or action == "update" then
      _registries.integrations[domain] = item
      logger.debug("Integration updated: " .. (domain or "unknown"))
    elseif action == "remove" then
      _registries.integrations[domain] = nil
      logger.debug("Integration removed: " .. (domain or "unknown"))
    end
  end

  _registries.last_updated = os.time()
end

---Handle state change events
---@param event table State change event data
local function handle_state_change(event)
  if not event or not event.data then
    logger.warn "Invalid state change event"
    return
  end

  local entity_id = event.data.entity_id
  local new_state = event.data.new_state

  if not entity_id or not new_state then
    logger.warn "Invalid state change event data"
    return
  end

  logger.trace("State change for entity: " .. entity_id)

  -- Update cached state
  _states[entity_id] = new_state

  -- Re-enrich the entity if it exists in registry
  local entity = _registries.entities[entity_id]
  if entity then enrich_entity(entity, _registries.devices) end
end

---Initialize registry data and set up WebSocket subscriptions
---@param callback function Callback with (success, error)
function M.initialize(callback)
  -- Already initialized - callback immediately
  if _registries.initialized then
    callback(true, nil)
    return
  end

  -- Currently initializing - queue callback
  if _initializing then
    table.insert(_pending_callbacks, callback)
    logger.debug("Registry initialization in progress, queueing callback")
    return
  end

  -- Start initialization
  _initializing = true
  _pending_callbacks = { callback }
  
  logger.info "Initializing registry processor..."

  -- Function to complete all pending callbacks
  local function complete_all_callbacks(success, error)
    _initializing = false
    local callbacks = _pending_callbacks
    _pending_callbacks = {}
    
    for _, cb in ipairs(callbacks) do
      vim.schedule(function() cb(success, error) end)
    end
  end

  -- Fetch all registries initially (API will handle progress display)
  local api = require "ha.api"
  api.get_all_registries(function(success, result)
    if not success then
      logger.error("Failed to fetch initial registries: " .. vim.inspect(result))
      complete_all_callbacks(false, result)
      return
    end

    -- Validate result structure
    if type(result) ~= "table" then
      logger.warn("Registry API returned invalid data type: " .. type(result))
      result = {}
    end

    -- Process and store registry data
    _registries.areas = index_by_id(result.areas or {}, "area_id")
    _registries.devices = index_by_id(result.devices or {}, "id")
    _registries.entities = index_by_id(result.entities or {}, "entity_id")
    _registries.integrations = index_by_id(result.integrations or {}, "domain")

    -- Store service data (keyed by domain -> service_name -> info)
    _registries.services = result.services or {}

    -- Extract initial domains from entities
    extract_domains_from_entities(_registries.entities)

    local areas_count = vim.tbl_count(_registries.areas)
    local devices_count = vim.tbl_count(_registries.devices)
    local entities_count = vim.tbl_count(_registries.entities)
    local integrations_count = vim.tbl_count(_registries.integrations)

    -- Fetch initial states (pass nil to get all states)
    api.get_states(nil, function(states_success, states_result)
      if states_success and states_result then
        -- Index states by entity_id
        for _, state in ipairs(states_result) do
          if state.entity_id then _states[state.entity_id] = state end
        end
        logger.info("Loaded states for " .. vim.tbl_count(_states) .. " entities")
      end

      _registries.initialized = true
      _registries.last_updated = os.time()

      -- Build initial enriched entity data
      enrich_all_entities()

      -- Log statistics
      logger.info(
        "Registry initialized: "
          .. areas_count
          .. " areas, "
          .. devices_count
          .. " devices, "
          .. entities_count
          .. " entities, "
          .. integrations_count
          .. " integrations with states"
      )

      -- Set up WebSocket subscriptions for real-time updates
      logger.info "Setting up WebSocket subscriptions..."

      _subscription_ids.registry = api.subscribe_registry_changes(handle_registry_change)
      _subscription_ids.states = api.subscribe_events("state_changed", handle_state_change)

      logger.info "Registry and state WebSocket subscriptions established"

      -- Complete all pending callbacks
      complete_all_callbacks(true, nil)
    end)
  end)
end

---Get entity by ID with enriched data (device_name, resolved area_id, and current state)
---@param entity_id string Entity ID to look up
---@return table|nil Entity data with device_name, area_id, state, and attributes
function M.get_entity(entity_id)
  if not _registries.initialized then
    logger.warn "Registry not initialized, call M.initialize() first"
    return nil
  end

  if not entity_id or type(entity_id) ~= "string" then
    logger.debug("Invalid entity_id: " .. tostring(entity_id))
    return nil
  end

  return _registries.entities[entity_id]
end

---Get all entities as an array (perfect for pickers)
---@return table Array of enriched entities with states
function M.get_all_entities()
  if not _registries.initialized then
    logger.warn "Registry not initialized, call M.initialize() first"
    return {}
  end

  local results = {}
  for entity_id, entity in pairs(_registries.entities) do
    table.insert(results, entity)
  end

  return results
end

---Get all entities with enriched data, optionally filtered by area
---@param area_id string|nil Area ID to filter by (nil for all)
---@return table Array of enriched entities with states
function M.get_entities_by_area(area_id)
  if not _registries.initialized then
    logger.warn "Registry not initialized, call M.initialize() first"
    return {}
  end

  if not area_id then return M.get_all_entities() end

  local results = {}
  for entity_id, entity in pairs(_registries.entities) do
    if entity.area_id == area_id then table.insert(results, entity) end
  end

  return results
end

---Get current state for an entity (for backward compatibility)
---@param entity_id string Entity ID
---@return table|nil State data
function M.get_entity_state(entity_id)
  if not _registries.initialized then
    logger.warn "Registry not initialized, call M.initialize() first"
    return nil
  end

  return _states[entity_id]
end

---Get all areas
---@return table Indexed areas
function M.get_areas()
  if not _registries.initialized then
    logger.warn "Registry not initialized, call M.initialize() first"
    return {}
  end

  return _registries.areas
end

---Get all devices
---@return table Indexed devices
function M.get_devices()
  if not _registries.initialized then
    logger.warn "Registry not initialized, call M.initialize() first"
    return {}
  end

  return _registries.devices
end

---Get all entities (registry data, not relationships)
---@return table Indexed entities
function M.get_entities()
  if not _registries.initialized then
    logger.warn "Registry not initialized, call M.initialize() first"
    return {}
  end

  return _registries.entities
end

---Get all integrations as an array (perfect for pickers)
---@return table Array of integration data
function M.get_all_integrations()
  if not _registries.initialized then
    logger.warn "Registry not initialized, call M.initialize() first"
    return {}
  end

  local results = {}
  for entry_id, integration in pairs(_registries.integrations) do
    table.insert(results, integration)
  end

  -- Sort by domain name for consistent ordering
  table.sort(results, function(a, b) return (a.domain or "") < (b.domain or "") end)

  return results
end

---Get all available domains as a sorted array (for completion)
---@return table Array of domain names
function M.get_available_domains()
  if not _registries.initialized then
    logger.warn "Registry not initialized, call M.initialize() first"
    return {}
  end

  local domains = {}
  for domain, _ in pairs(_available_domains) do
    table.insert(domains, domain)
  end

  -- Sort alphabetically for consistent completion ordering
  table.sort(domains)
  return domains
end

---Get integration by domain
---@param domain string Integration domain
---@return table|nil Integration data
function M.get_integration(domain)
  if not _registries.initialized then
    logger.warn "Registry not initialized, call M.initialize() first"
    return nil
  end

  if not domain or type(domain) ~= "string" then
    logger.debug("Invalid domain: " .. tostring(domain))
    return nil
  end

  return _registries.integrations[domain]
end

---Get integration by domain (alias for get_integration for backward compatibility)
---@param domain string Integration domain
---@return table|nil Integration data
function M.get_integration_by_domain(domain) return M.get_integration(domain) end

---Get all integrations indexed by domain
---@return table Indexed integrations
function M.get_integrations()
  if not _registries.initialized then
    logger.warn "Registry not initialized, call M.initialize() first"
    return {}
  end

  return _registries.integrations
end

---Get all services (keyed by domain -> service_name -> info)
---@return table Services data
function M.get_services()
  if not _registries.initialized then
    logger.warn "Registry not initialized, call M.initialize() first"
    return {}
  end

  return _registries.services
end

---Get a specific service by domain.service_name
---@param domain string Service domain
---@param service_name string Service name
---@return table|nil Service info
function M.get_service(domain, service_name)
  if not _registries.initialized then
    logger.warn "Registry not initialized, call M.initialize() first"
    return nil
  end

  local domain_services = _registries.services[domain]
  if not domain_services then return nil end

  return domain_services[service_name]
end

---Check if a service domain exists in the service registry
---@param domain string Service domain
---@return boolean True if domain has registered services
function M.has_service_domain(domain)
  if not _registries.initialized then return false end
  return _registries.services[domain] ~= nil
end

---Get registry statistics
---@return table Statistics
function M.get_stats()
  local services_count = 0
  for _, domain_services in pairs(_registries.services) do
    if type(domain_services) == "table" then
      services_count = services_count + vim.tbl_count(domain_services)
    end
  end

  return {
    initialized = _registries.initialized,
    last_updated = _registries.last_updated,
    areas_count = vim.tbl_count(_registries.areas),
    devices_count = vim.tbl_count(_registries.devices),
    entities_count = vim.tbl_count(_registries.entities),
    integrations_count = vim.tbl_count(_registries.integrations),
    services_count = services_count,
    states_count = vim.tbl_count(_states),
    subscription_ids = _subscription_ids,
  }
end

---Force refresh of all registry data
---@param callback function Callback with (success, error)
function M.refresh(callback)
  logger.info "Force refreshing registry data..."

  -- Fetch all registries (API will handle progress display)
  local api = require "ha.api"
  api.get_all_registries(function(success, result)
    if not success then
      logger.error("Failed to refresh registries: " .. vim.inspect(result))
      callback(false, result)
      return
    end

    if type(result) ~= "table" then
      logger.warn("Registry API returned invalid data type: " .. type(result))
      result = {}
    end

    _registries.areas = index_by_id(result.areas or {}, "area_id")
    _registries.devices = index_by_id(result.devices or {}, "id")
    _registries.entities = index_by_id(result.entities or {}, "entity_id")
    _registries.integrations = index_by_id(result.integrations or {}, "domain")
    _registries.services = result.services or {}

    -- Extract domains from entities (refresh scenario)
    _available_domains = {}
    extract_domains_from_entities(_registries.entities)

    -- Also refresh states
    api.get_states(nil, function(states_success, states_result)
      if states_success and states_result then
        _states = {}
        for _, state in ipairs(states_result) do
          if state.entity_id then _states[state.entity_id] = state end
        end
      end

      _registries.last_updated = os.time()
      enrich_all_entities()

      logger.info "Registry and states refreshed successfully"
      callback(true, nil)
    end)
  end)
end

---Validate registry data integrity
---@return table Validation results
function M.validate()
  local validation = {
    valid = false,
    errors = {},
    warnings = {},
  }

  if not _registries.initialized then
    table.insert(validation.errors, "Registry not initialized")
    return validation
  end

  -- Validate structure
  if type(_registries.areas) ~= "table" then table.insert(validation.errors, "Invalid areas data") end

  if type(_registries.devices) ~= "table" then table.insert(validation.errors, "Invalid devices data") end

  if type(_registries.entities) ~= "table" then table.insert(validation.errors, "Invalid entities data") end

  -- Check for orphaned relationships
  local orphaned_entities = 0
  local orphaned_devices = 0

  for entity_id, entity in pairs(_registries.entities) do
    if entity.device_id and not _registries.devices[entity.device_id] then orphaned_entities = orphaned_entities + 1 end
  end

  for device_id, device in pairs(_registries.devices) do
    if device.area_id and device.area_id ~= vim.NIL and not _registries.areas[device.area_id] then
      orphaned_devices = orphaned_devices + 1
    end
  end

  if orphaned_entities > 0 then
    table.insert(validation.warnings, orphaned_entities .. " entities reference missing devices")
  end

  if orphaned_devices > 0 then
    table.insert(validation.warnings, orphaned_devices .. " devices reference missing areas")
  end

  -- Validate relationship consistency
  local enrichment_errors = 0
  for entity_id, entity in pairs(_registries.entities) do
    -- Check if entity should have device_name but doesn't
    if entity.device_id and _registries.devices[entity.device_id] and not entity.device_name then
      enrichment_errors = enrichment_errors + 1
    end
  end

  if enrichment_errors > 0 then
    table.insert(validation.warnings, enrichment_errors .. " entities missing enrichment data")
  end

  validation.valid = #validation.errors == 0
  return validation
end

---Cleanup resources
function M.cleanup()
  -- Unsubscribe from WebSocket events
  local api = require "ha.api"

  if _subscription_ids.registry then
    for _, sub_id in pairs(_subscription_ids.registry) do
      api.unsubscribe_events(sub_id)
    end
  end
  if _subscription_ids.states then api.unsubscribe_events(_subscription_ids.states) end

  -- Clear data and reset initialization state
  _registries = {
    areas = {},
    devices = {},
    entities = {},
    integrations = {},
    services = {},
    initialized = false,
    last_updated = 0,
  }
  _states = {}
  _available_domains = {}
  _subscription_ids = {}
  _initializing = false
  _pending_callbacks = {}

  logger.info "Registry processor cleaned up"
end

-- Legacy compatibility functions (marked as deprecated)
function M.get_entity_relationships(entity_id)
  logger.warn "get_entity_relationships is deprecated, use M.get_entity() directly - entity data is now enriched"
  local entity = M.get_entity(entity_id)
  if not entity then return nil end

  return {
    entity_id = entity_id,
    device_id = entity.device_id,
    device_name = entity.device_name,
    area_id = entity.area_id,
  }
end

function M.get_entity_relationships_async(entity_id, callback)
  logger.warn "get_entity_relationships_async is deprecated, use M.get_entity() directly"
  if not _registries.initialized then
    M.initialize(function(success, error)
      if success then
        callback(M.get_entity_relationships(entity_id))
      else
        callback(nil)
      end
    end)
    return
  end

  callback(M.get_entity_relationships(entity_id))
end

function M._ensure_registry_cache(callback)
  logger.warn "_ensure_registry_cache is deprecated, use M.initialize() instead"
  M.initialize(function(success, error)
    if success then
      callback(_registries)
    else
      callback(nil)
    end
  end)
end

function M._resolve_relationships(entity_id, registries)
  logger.warn "_resolve_relationships is deprecated, use M.get_entity() instead"
  return M.get_entity_relationships(entity_id)
end

function M.clear_cache()
  logger.warn "clear_cache is deprecated, use M.refresh() instead"
  M.refresh(function() end)
end

function M.get_cache_stats()
  logger.warn "get_cache_stats is deprecated, use M.get_stats() instead"
  local stats = M.get_stats()
  return {
    cached = stats.initialized,
    cache_age = os.time() - stats.last_updated,
    cache_size = stats.entities_count,
    areas_count = stats.areas_count,
    devices_count = stats.devices_count,
    entities_count = stats.entities_count,
  }
end

function M.validate_registry_data()
  logger.warn "validate_registry_data is deprecated, use M.validate() instead"
  return M.validate()
end

return M
