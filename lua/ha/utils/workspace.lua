-- Workspace utility module
local M = {}

local config = require "ha.config"
local logger = require "ha.utils.logger"

-- Workspace detection cache
local _workspace_cache = {
  cwd = nil,           -- Last checked working directory
  is_ha_workspace = nil, -- Cached result
  root_dir = nil,      -- Cached root directory
  last_check = 0,      -- Timestamp of last check
}

-- Buffer-level HA state tracking
local _buffer_state = {}

---Set buffer as HA-activated
---@param bufnr number Buffer number
---@param ha_root string HA workspace root
local function set_buffer_ha_state(bufnr, ha_root)
  _buffer_state[bufnr] = {
    is_ha_buffer = true,
    ha_root = ha_root,
    activated_at = vim.loop.now(),
  }
end

---Get buffer HA state
---@param bufnr number Buffer number
---@return table? Buffer state or nil
local function get_buffer_ha_state(bufnr)
  return _buffer_state[bufnr]
end

---Clear buffer HA state when buffer is deleted
local function clear_buffer_state(bufnr)
  _buffer_state[bufnr] = nil
end

---Clear workspace cache (useful for testing or directory changes)
local function clear_cache()
  _workspace_cache.cwd = nil
  _workspace_cache.is_ha_workspace = nil
  _workspace_cache.root_dir = nil
  _workspace_cache.last_check = 0
end

---Check if current workspace is a Home Assistant configuration directory
---@return boolean True if HA workspace
function M.is_home_assistant_workspace()
  if not config.get_value("workspace.auto_detect", true) then return false end

  local current_cwd = vim.fn.getcwd()
  
  -- Check cache validity
  if _workspace_cache.cwd == current_cwd and _workspace_cache.is_ha_workspace ~= nil then
    -- Cache hit - return cached result without logging
    return _workspace_cache.is_ha_workspace
  end
  
  -- Cache miss - need to check workspace indicators
  local workspaces = vim.lsp.buf.list_workspace_folders()

  -- If no workspace folders, check current directory
  if #workspaces == 0 then workspaces = { current_cwd } end

  local is_ha = false
  local root = nil
  
  for _, workspace in ipairs(workspaces) do
    if M._check_workspace_indicators(workspace) then
      logger.debug("Home Assistant workspace detected: " .. workspace)
      is_ha = true
      root = workspace
      break
    end
  end
  
  -- Cache the results
  _workspace_cache.cwd = current_cwd
  _workspace_cache.is_ha_workspace = is_ha
  _workspace_cache.root_dir = root
  _workspace_cache.last_check = vim.loop.now()
  
  return is_ha
end

---Check if we're currently in Home Assistant environment
---This is the main function that should be used for statusline and activation checks
---@param bufnr? number Buffer number (defaults to current buffer)
---@return boolean True if in HA environment (workspace OR buffer-based)
function M.is_in_ha_environment(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  
  -- First check if current buffer is an HA file
  if M.is_ha_file(bufnr) then
    return true
  end
  
  -- Fallback to workspace detection for other cases
  return M.is_home_assistant_workspace()
end

---Get Home Assistant workspace root directory
---Enhanced to work with buffer-based detection
---@param bufnr? number Buffer number (defaults to current buffer) 
---@return string? Root directory path
function M.get_root_dir(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  
  -- First try buffer-based detection
  local buffer_root = M.get_buffer_ha_root(bufnr)
  if buffer_root then return buffer_root end
  
  -- Fallback to workspace detection
  M.is_home_assistant_workspace() -- Ensure cache is populated
  return _workspace_cache.root_dir
end

---Check for Home Assistant indicators in a directory
---@param dir string Directory path
---@return boolean True if HA indicators found
function M._check_workspace_indicators(dir)
  local indicators = config.get_value("workspace.indicators", {
    "configuration.yaml",
    ".storage",
    "home-assistant_v2.db",
    "automations.yaml",
    "scripts.yaml",
    "scenes.yaml",
  })

  -- Check for configuration.yaml first (required)
  local config_path = dir .. "/configuration.yaml"
  if vim.fn.filereadable(config_path) == 0 then return false end

  -- Check for at least one other indicator
  local found_indicators = 0
  for _, indicator in ipairs(indicators) do
    if indicator ~= "configuration.yaml" then
      local path = dir .. "/" .. indicator
      if vim.fn.filereadable(path) == 1 or vim.fn.isdirectory(path) == 1 then found_indicators = found_indicators + 1 end
    end
  end

  -- Need at least one additional indicator besides configuration.yaml
  if found_indicators > 0 then return true end

  -- Additional check: look for 'homeassistant:' key in configuration.yaml
  local content = vim.fn.readfile(config_path, "", 50) -- Read first 50 lines
  if content then
    for _, line in ipairs(content) do
      if line:match "^%s*homeassistant%s*:" then
        logger.debug "Found 'homeassistant:' key in configuration.yaml"
        return true
      end
    end
  end

  return false
end

---Check if file is a Home Assistant configuration file
---@param filepath string File path to check
---@return boolean True if HA config file
function M.is_ha_config_file(filepath)
  local root = M.get_root_dir()
  if not root then return false end

  -- Check if file is within HA workspace
  if not vim.startswith(filepath, root) then return false end

  -- Check file extension
  local ext = filepath:match "%.([^%.]+)$"
  if ext ~= "yaml" and ext ~= "yml" then return false end

  -- Simple rule: any yaml file in HA workspace is a config file
  return true
end

---Get Home Assistant configuration files in workspace
---@return table List of configuration file paths
function M.get_ha_config_files()
  local root = M.get_root_dir()
  if not root then return {} end

  local config_files = {}
  local patterns = {
    "configuration.yaml",
    "automations.yaml",
    "scripts.yaml",
    "scenes.yaml",
    "groups.yaml",
    "customize.yaml",
    "lovelace.yaml",
    "ui-lovelace.yaml",
    "secrets.yaml",
  }

  for _, pattern in ipairs(patterns) do
    local path = root .. "/" .. pattern
    if vim.fn.filereadable(path) == 1 then table.insert(config_files, path) end
  end

  -- Also look for includes
  local include_dirs = { "automations", "scripts", "scenes", "integrations", "packages" }
  for _, dir in ipairs(include_dirs) do
    local dir_path = root .. "/" .. dir
    if vim.fn.isdirectory(dir_path) == 1 then
      local files = vim.fn.glob(dir_path .. "/*.yaml", false, true)
      for _, file in ipairs(files) do
        table.insert(config_files, file)
      end
    end
  end

  return config_files
end

---Find Home Assistant executable
---@return string? Path to Home Assistant executable
function M.find_ha_executable()
  local executables = { "hass", "homeassistant" }

  for _, exe in ipairs(executables) do
    if vim.fn.executable(exe) == 1 then return exe end
  end

  -- Check common installation paths
  local paths = {
    "/usr/local/bin/hass",
    "/opt/homeassistant/bin/hass",
    vim.fn.expand "~/.local/bin/hass",
  }

  for _, path in ipairs(paths) do
    if vim.fn.executable(path) == 1 then return path end
  end

  return nil
end

---Check if a file path is within a Home Assistant configuration directory
---@param filepath string File path to check  
---@return boolean True if file is in HA workspace
---@return string? HA workspace root directory if found
function M.is_ha_file_by_path(filepath)
  if not filepath or filepath == "" then return false, nil end
  
  -- Use vim.fs.root to find HA workspace root from file path
  local root = vim.fs.root(filepath, { "configuration.yaml", ".homeassistant" })
  if root and M._check_workspace_indicators(root) then
    return true, root
  end
  
  return false, nil
end

---Check if current buffer is a Home Assistant configuration file
---Enhanced to work buffer-independently by checking file path
---@param bufnr? number Buffer number (defaults to current buffer)
---@return boolean True if this is a Home Assistant file
function M.is_ha_file(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local filetype = vim.bo[bufnr].filetype
  
  -- Must be a yaml file type
  if not (filetype == "home-assistant" or filetype == "yaml") then
    return false
  end
  
  -- Get buffer file path
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  if filepath == "" then return false end
  
  -- Check if file is in HA workspace (buffer-aware)
  local is_ha_file, _ = M.is_ha_file_by_path(filepath)
  return is_ha_file
end

---Get Home Assistant workspace root for current buffer
---@param bufnr? number Buffer number (defaults to current buffer)
---@return string? HA workspace root if current buffer is HA file
function M.get_buffer_ha_root(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  if filepath == "" then return nil end
  
  local is_ha_file, root = M.is_ha_file_by_path(filepath)
  return is_ha_file and root or nil
end

---Check if domain is a valid HA entity domain
---@param domain string Domain to check
---@return boolean True if valid entity domain
function M.is_valid_entity_domain(domain)
  local common_domains = {
    "sensor", "binary_sensor", "light", "switch", "climate", "fan", "cover",
    "lock", "camera", "media_player", "device_tracker", "automation", "script", 
    "scene", "group", "input_boolean", "input_number", "input_select", "weather"
  }
  return vim.tbl_contains(common_domains, domain)
end

---Check if domain is a valid HA service domain  
---@param domain string Domain to check
---@return boolean True if valid service domain
function M.is_valid_service_domain(domain)
  -- Use registry when available for accurate, dynamic validation
  local ok, registry = pcall(require, "ha.utils.registry")
  if ok and registry.get_stats().initialized then
    return registry.has_service_domain(domain)
  end

  -- Fallback to common domains when registry isn't available
  local service_domains = {
    "homeassistant", "automation", "script", "light", "switch", "climate", 
    "fan", "cover", "media_player", "notify", "tts"
  }
  return vim.tbl_contains(service_domains, domain)
end

---Clear workspace cache (for testing or when directory changes)
function M.clear_cache()
  clear_cache()
  logger.debug("Workspace cache cleared")
end

---Get cache debug information
---@return table Cache state for debugging
function M.get_cache_info()
  return {
    cwd = _workspace_cache.cwd,
    is_ha_workspace = _workspace_cache.is_ha_workspace,
    root_dir = _workspace_cache.root_dir,
    last_check = _workspace_cache.last_check,
    age_ms = _workspace_cache.last_check > 0 and (vim.loop.now() - _workspace_cache.last_check) or 0,
  }
end

---Setup workspace detection with directory change monitoring and buffer activation
function M.setup()
  local augroup = vim.api.nvim_create_augroup("ha_workspace_detection", { clear = true })
  
  -- Clear cache when working directory changes
  vim.api.nvim_create_autocmd("DirChanged", {
    group = augroup,
    callback = function()
      clear_cache()
      logger.debug("Working directory changed, cleared workspace cache")
    end,
    desc = "Clear Home Assistant workspace cache on directory change"
  })
  
  -- Monitor buffer changes for HA file activation
  vim.api.nvim_create_autocmd({ "BufEnter", "BufReadPost" }, {
    group = augroup,
    callback = function(args)
      local bufnr = args.buf
      
      -- Skip if buffer is already tracked as HA
      if get_buffer_ha_state(bufnr) then return end
      
      -- Check if this buffer is an HA file
      local filepath = vim.api.nvim_buf_get_name(bufnr)
      local is_ha_file, ha_root = M.is_ha_file_by_path(filepath)
      
      if is_ha_file and ha_root then
        set_buffer_ha_state(bufnr, ha_root)
        logger.debug("HA buffer detected: " .. filepath .. " (root: " .. ha_root .. ")")
        
        -- Trigger HA environment activation
        vim.schedule(function()
          M.activate_ha_environment(ha_root)
        end)
      end
    end,
    desc = "Detect and activate HA environment for HA files"
  })
  
  -- Clean up buffer state when buffers are deleted
  vim.api.nvim_create_autocmd("BufDelete", {
    group = augroup,
    callback = function(args)
      clear_buffer_state(args.buf)
    end,
    desc = "Clean up HA buffer state on buffer deletion"
  })
  
  logger.debug("Workspace detection setup with directory and buffer monitoring")
end

---Activate HA environment for the given root directory
---@param ha_root string HA workspace root directory
function M.activate_ha_environment(ha_root)
  -- Check if HA plugin is loaded and available
  local ha_ok, ha = pcall(require, "ha")
  if not ha_ok then
    logger.debug("HA plugin not loaded yet, skipping activation")
    return
  end
  
  -- Check if already initialized  
  local state = ha.get_state()
  if state.initialized and state.connection_status ~= "disconnected" then
    logger.debug("HA environment already active")
    return
  end
  
  logger.info("Activating HA environment for root: " .. ha_root)
  
  -- Trigger connection check if HA is initialized
  if state.initialized then
    ha.check_connection(true) -- Enable registry preloading
  else
    logger.debug("HA plugin not initialized yet")
  end
end

return M
