-- ha.nvim diagnostics integration
-- Validates entity_ids and service calls against the registry

local M = {}

local config = require "ha.config"
local utils = require "ha.utils"
local registry = require "ha.utils.registry"

-- Diagnostic namespace
local NAMESPACE = vim.api.nvim_create_namespace "ha_diagnostics"

-- Diagnostic source name
local SOURCE_NAME = "ha.nvim"

-- Cache for debouncing
local _debounce_timers = {}

-- Patterns for matching HA references in YAML
local PATTERNS = {
  -- entity_id: sensor.temperature or entity_id: "sensor.temperature"
  entity_id_value = 'entity_id:%s*["\']?([%w_]+%.[%w_]+)["\']?',
  -- entity_id in lists: - sensor.temperature
  entity_id_list = '-%s*["\']?([%w_]+%.[%w_]+)["\']?%s*$',
  -- service calls: service: light.turn_on
  service_call = 'service:%s*["\']?([%w_]+%.[%w_]+)["\']?',
  -- action shorthand: light.turn_on:
  action_shorthand = '^%s*([%w_]+%.[%w_]+):',
  -- target entity_id in nested structure
  target_entity = 'entity_id:%s*["\']?([%w_]+%.[%w_]+)["\']?',
  -- condition entity_id
  condition_entity = 'entity_id:%s*["\']?([%w_]+%.[%w_]+)["\']?',
  -- Generic entity reference (domain.name pattern in value position)
  generic_entity = ':%s*["\']?([%w_]+%.[%w_]+)["\']?%s*$',
}

-- Known HA domains that are valid but might not have entities
local SPECIAL_DOMAINS = {
  "homeassistant",
  "persistent_notification",
  "system_log",
  "logger",
  "recorder",
  "frontend",
  "config",
  "hassio",
  "cloud",
}

-- File extensions that should not be treated as entity domains
local FILE_EXTENSIONS = {
  "js", "css", "html", "json", "yaml", "yml", "png", "jpg", "jpeg", "gif", "svg", "ico", "woff", "woff2", "ttf", "eot",
}

---Check if a domain is a special/system domain
---@param domain string
---@return boolean
local function is_special_domain(domain)
  return vim.tbl_contains(SPECIAL_DOMAINS, domain)
end

---Check if a value looks like a file path or URL (not an entity)
---@param value string
---@return boolean
local function is_file_or_url(value)
  -- Check for file extensions
  local ext = value:match("%.([%w]+)$")
  if ext and vim.tbl_contains(FILE_EXTENSIONS, ext:lower()) then
    return true
  end
  -- Check for URL-like patterns (anywhere in the string)
  if value:match("/") or value:match("^http") or value:match("hacsfiles") then
    return true
  end
  -- Check for common lovelace/resource keys that contain file paths
  if value:match("^%s*url:") or value:match("^%s*filename:") or value:match("^%s*path:") or value:match("^%s*type:%s*module") then
    return true
  end
  return false
end

---Extract entity_id references from a line
---@param line string
---@param line_num number 0-indexed line number
---@return table Array of {entity_id, col_start, col_end}
local function extract_entity_refs(line, line_num)
  local refs = {}
  
  -- Try each pattern
  for pattern_name, pattern in pairs(PATTERNS) do
    if pattern_name:match("entity") or pattern_name == "generic_entity" then
      local start_pos = 1
      while true do
        local match_start, match_end, entity_id = line:find(pattern, start_pos)
        if not match_start then break end
        
        -- Verify it looks like an entity_id (domain.name), skip numeric values like 0.234
        local domain = entity_id:match("^([%w_]+)%.")
        if domain and not is_special_domain(domain) and not domain:match("^%d+$") and not is_file_or_url(entity_id) and not is_file_or_url(line) then
          -- Find the actual position of the entity_id in the match
          local entity_start = line:find(entity_id, match_start, true)
          if entity_start then
            table.insert(refs, {
              entity_id = entity_id,
              col_start = entity_start - 1, -- 0-indexed
              col_end = entity_start - 1 + #entity_id,
              line = line_num,
            })
          end
        end
        
        start_pos = match_end + 1
      end
    end
  end
  
  return refs
end

---Extract service references from a line
---@param line string
---@param line_num number 0-indexed line number
---@return table Array of {service, col_start, col_end}
local function extract_service_refs(line, line_num)
  local refs = {}
  
  -- Service call pattern
  local service_patterns = {
    'service:%s*["\']?([%w_]+%.[%w_]+)["\']?',
    '^%s*([%w_]+%.[%w_]+):%s*$', -- Action shorthand
  }
  
  for _, pattern in ipairs(service_patterns) do
    local start_pos = 1
    while true do
      local match_start, match_end, service = line:find(pattern, start_pos)
      if not match_start then break end
      
      -- Find the actual position of the service in the match
      local service_start = line:find(service, match_start, true)
      if service_start then
        table.insert(refs, {
          service = service,
          col_start = service_start - 1, -- 0-indexed
          col_end = service_start - 1 + #service,
          line = line_num,
        })
      end
      
      start_pos = match_end + 1
    end
  end
  
  return refs
end

---Validate entity_id against registry
---@param entity_id string
---@return boolean, string? is_valid, error_message
local function validate_entity(entity_id)
  if not registry.get_stats().initialized then
    return true, nil -- Can't validate without registry
  end
  
  local entity = registry.get_entity(entity_id)
  if entity then
    return true, nil
  end
  
  -- Check if domain exists at all
  local domain = entity_id:match("^([%w_]+)%.")
  local available_domains = registry.get_available_domains()
  
  if not vim.tbl_contains(available_domains, domain) and not is_special_domain(domain) then
    return false, string.format("Unknown domain '%s'", domain)
  end
  
  return false, string.format("Entity '%s' not found in registry", entity_id)
end

---Validate service against registry
---@param service string domain.service format
---@return boolean, string? is_valid, error_message
local function validate_service(service)
  if not registry.get_stats().initialized then
    return true, nil -- Can't validate without registry
  end
  
  local domain, service_name = service:match("^([%w_]+)%.([%w_]+)$")
  if not domain or not service_name then
    return false, "Invalid service format"
  end
  
  -- Special domains are always valid
  if is_special_domain(domain) then
    return true, nil
  end
  
  -- Check against the service registry
  local services = registry.get_services()
  if not services or not next(services) then
    return true, nil -- No service data available, can't validate
  end
  
  -- Check if domain exists in service registry
  if not registry.has_service_domain(domain) then
    return false, string.format("Unknown service domain '%s'", domain)
  end
  
  -- Check if the specific service exists under the domain
  local service_info = registry.get_service(domain, service_name)
  if not service_info then
    return false, string.format("Service '%s.%s' not found in registry", domain, service_name)
  end
  
  return true, nil
end

---Run diagnostics on a buffer
---@param bufnr number Buffer number
function M.diagnose_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  
  -- Check if diagnostics are enabled
  if not config.get_value("diagnostics.enabled", true) then
    return
  end
  
  -- Check if this is an HA file
  if not utils.workspace.is_ha_file(bufnr) then
    vim.diagnostic.reset(NAMESPACE, bufnr)
    return
  end
  
  -- Check if registry is initialized
  if not registry.get_stats().initialized then
    -- Try to initialize registry
    registry.initialize(function(success)
      if success then
        -- Retry diagnostics after registry is ready
        vim.schedule(function()
          M.diagnose_buffer(bufnr)
        end)
      end
    end)
    return
  end
  
  local diagnostics = {}
  local seen = {} -- Track seen diagnostics by line:col:message to avoid duplicates
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  
  ---Add diagnostic if not already seen
  ---@param diag table Diagnostic entry
  local function add_diagnostic(diag)
    local key = string.format("%d:%d:%s", diag.lnum, diag.col, diag.message)
    if not seen[key] then
      seen[key] = true
      table.insert(diagnostics, diag)
    end
  end
  
  for line_num, line in ipairs(lines) do
    local line_idx = line_num - 1 -- 0-indexed
    
    -- Skip comments
    if line:match("^%s*#") then
      goto continue
    end
    
    -- Check entity references
    local entity_refs = extract_entity_refs(line, line_idx)
    for _, ref in ipairs(entity_refs) do
      local is_valid, error_msg = validate_entity(ref.entity_id)
      if not is_valid then
        add_diagnostic({
          lnum = ref.line,
          col = ref.col_start,
          end_col = ref.col_end,
          message = error_msg,
          severity = vim.diagnostic.severity.WARN,
          source = SOURCE_NAME,
        })
      end
    end
    
    -- Check service references
    local service_refs = extract_service_refs(line, line_idx)
    for _, ref in ipairs(service_refs) do
      local is_valid, error_msg = validate_service(ref.service)
      if not is_valid then
        add_diagnostic({
          lnum = ref.line,
          col = ref.col_start,
          end_col = ref.col_end,
          message = error_msg,
          severity = vim.diagnostic.severity.WARN,
          source = SOURCE_NAME,
        })
      end
    end
    
    ::continue::
  end
  
  -- Set diagnostics
  vim.diagnostic.set(NAMESPACE, bufnr, diagnostics)
  
  if #diagnostics > 0 then
    utils.logger.debug(string.format("HA Diagnostics: Found %d issues in buffer %d", #diagnostics, bufnr))
  end
end

---Debounced version of diagnose_buffer
---@param bufnr number Buffer number
---@param delay number? Delay in milliseconds (default: 500)
function M.diagnose_buffer_debounced(bufnr, delay)
  delay = delay or 500
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  
  -- Cancel existing timer for this buffer
  if _debounce_timers[bufnr] then
    _debounce_timers[bufnr]:stop()
  end
  
  -- Create new timer
  _debounce_timers[bufnr] = vim.defer_fn(function()
    M.diagnose_buffer(bufnr)
    _debounce_timers[bufnr] = nil
  end, delay)
end

---Clear diagnostics for a buffer
---@param bufnr number? Buffer number (default: current)
function M.clear(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  vim.diagnostic.reset(NAMESPACE, bufnr)
end

---Setup diagnostics autocommands
function M.setup()
  if not config.get_value("diagnostics.enabled", true) then
    utils.logger.debug "HA Diagnostics disabled in configuration"
    return
  end
  
  local augroup = vim.api.nvim_create_augroup("ha_diagnostics", { clear = true })
  
  -- Run diagnostics on buffer enter and write
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
    group = augroup,
    pattern = { "*.yaml", "*.yml" },
    callback = function(args)
      -- Small delay to let registry initialize if needed
      vim.defer_fn(function()
        M.diagnose_buffer(args.buf)
      end, 100)
    end,
    desc = "Run HA diagnostics on YAML files",
  })
  
  -- Run diagnostics on text change (debounced)
  if config.get_value("diagnostics.on_change", true) then
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
      group = augroup,
      pattern = { "*.yaml", "*.yml" },
      callback = function(args)
        M.diagnose_buffer_debounced(args.buf, config.get_value("diagnostics.debounce_ms", 1000))
      end,
      desc = "Run HA diagnostics on text change (debounced)",
    })
  end
  
  utils.logger.info "HA Diagnostics setup complete"
end

---Refresh diagnostics for all HA buffers
function M.refresh_all()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local bufname = vim.api.nvim_buf_get_name(bufnr)
      if bufname:match("%.ya?ml$") then
        M.diagnose_buffer(bufnr)
      end
    end
  end
end

---Get diagnostic statistics
---@return table Statistics
function M.get_stats()
  local stats = {
    namespace = NAMESPACE,
    source = SOURCE_NAME,
    buffers_with_diagnostics = 0,
    total_diagnostics = 0,
  }
  
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local diags = vim.diagnostic.get(bufnr, { namespace = NAMESPACE })
      if #diags > 0 then
        stats.buffers_with_diagnostics = stats.buffers_with_diagnostics + 1
        stats.total_diagnostics = stats.total_diagnostics + #diags
      end
    end
  end
  
  return stats
end

return M
