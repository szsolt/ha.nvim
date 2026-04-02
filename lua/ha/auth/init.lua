-- ha.nvim authentication management
local M = {}

local config = require "ha.config"
local utils = require "ha.utils"

-- Authentication state
local _state = {
  token = nil,
  url = nil,
  loaded = false,
}

---Setup authentication system
function M.setup()
  -- Load credentials from storage
  M.load_credentials()
end

---Get storage file path
---@return string Storage file path
local function get_storage_path()
  local filename = config.get_value("auth.storage_file", "ha_credentials")
  return vim.fn.stdpath "data" .. "/" .. filename .. ".json"
end

---Simple XOR encryption (better than plaintext)
---@param data string Data to encrypt
---@param key string Encryption key
---@return string Encrypted data
local function encrypt(data, key)
  -- Use bit library if available (LuaJIT), otherwise fallback
  local bit = bit or bit32
  if bit and bit.bxor then
    local result = {}
    for i = 1, #data do
      local char = data:byte(i)
      local key_char = key:byte((i - 1) % #key + 1)
      local xor_result = bit.bxor(char, key_char)
      table.insert(result, string.char(xor_result))
    end
    return table.concat(result)
  else
    -- Fallback: simple character shifting (not true XOR but better than plaintext)
    local result = {}
    for i = 1, #data do
      local char = data:byte(i)
      local key_char = key:byte((i - 1) % #key + 1)
      local shifted = ((char + key_char - 32) % 95) + 32 -- Keep in printable range
      table.insert(result, string.char(shifted))
    end
    return table.concat(result)
  end
end

---Get encryption key based on Neovim installation
---@return string Encryption key
local function get_encryption_key()
  local nvim_version = vim.version()
  local data_path = vim.fn.stdpath "data"
  return nvim_version.major .. "." .. nvim_version.minor .. data_path
end

---Load credentials from secure storage
function M.load_credentials()
  if _state.loaded then return end

  local filepath = get_storage_path()

  -- Check if file exists
  local file = io.open(filepath, "r")
  if not file then
    _state.token = nil
    _state.url = nil
    _state.loaded = true
    return
  end

  local content = file:read "*all"
  file:close()

  if not content or content == "" then
    _state.token = nil
    _state.url = nil
    _state.loaded = true
    return
  end

  -- Decrypt content
  local key = get_encryption_key()
  local decrypted = encrypt(content, key) -- XOR is symmetric

  -- Parse JSON
  local ok, data = pcall(vim.fn.json_decode, decrypted)
  if not ok or type(data) ~= "table" then
    _state.token = nil
    _state.url = nil
    _state.loaded = true
    return
  end

  _state.token = data.token
  _state.url = data.url
  _state.loaded = true

  utils.logger.debug "Credentials loaded from storage"
end

---Save credentials to secure storage
---@param token string Long-lived access token
---@param url string Home Assistant instance URL
function M.save_credentials(token, url)
  -- Validate inputs
  if not token or token == "" then error "Token cannot be empty" end

  if not url or url == "" then error "URL cannot be empty" end

  -- Validate URL format
  if not url:match "^https?://" then error "URL must start with http:// or https://" end

  local filepath = get_storage_path()

  -- Ensure directory exists
  local dir = vim.fn.fnamemodify(filepath, ":h")
  vim.fn.mkdir(dir, "p")

  -- Encrypt content
  local json = vim.fn.json_encode { token = token, url = url }
  local key = get_encryption_key()
  local encrypted = encrypt(json, key)

  -- Write to file
  local file = io.open(filepath, "w")
  if not file then error("Cannot write to storage file: " .. filepath) end

  file:write(encrypted)
  file:close()

  -- Update state
  _state.token = token
  _state.url = url

  utils.logger.info "Credentials saved successfully"
end

---Get stored token
---@return string? Token or nil if not set
function M.get_token()
  M.load_credentials()
  return _state.token
end

---Get stored URL
---@return string? URL or nil if not set
function M.get_url()
  M.load_credentials()
  return _state.url
end

---Check if credentials are available
---@return boolean True if both token and URL are set
function M.has_credentials()
  local token = M.get_token()
  local url = M.get_url()
  return token ~= nil and url ~= nil
end

---Clear stored credentials
function M.clear_credentials()
  local filepath = get_storage_path()
  vim.fn.delete(filepath)
  _state.token = nil
  _state.url = nil
  utils.logger.info "Credentials cleared"
end

---Setup credentials interactively
---@param callback? function Optional callback when complete
function M.setup_credentials(callback)
  -- Get URL first
  vim.ui.input({
    prompt = "Home Assistant URL: ",
    default = "http://homeassistant.local:8123",
    completion = "file",
  }, function(url)
    if not url then
      if callback then callback(false, "Cancelled") end
      return
    end

    -- Get token
    local token = vim.fn.inputsecret "Home Assistant Token: "
    if not token or token == "" then
      if callback then callback(false, "No token provided") end
      return
    end

    -- Save credentials
    local ok, err = pcall(M.save_credentials, token, url)
    if not ok then
      vim.notify("Error saving credentials: " .. err, vim.log.levels.ERROR)
      if callback then callback(false, err) end
      return
    end

    local api = require "ha.api"

    -- Test connection
    api.test_connection_and_auth(function(success, result)
      if success then
        vim.notify("Connected to Home Assistant: " .. (result.name or "Unknown"), vim.log.levels.INFO)
        if callback then callback(true, result) end
      else
        vim.notify("Failed to connect: " .. (result.error or "Unknown error"), vim.log.levels.ERROR)
        if callback then callback(false, result.error) end
      end
    end)
  end)
end

---Migrate credentials from VS Code settings
function M.migrate_from_vscode()
  if not config.get_value("auth.auto_migrate", true) then return end

  if M.has_credentials() then return end -- Already have credentials

  local vscode_settings = utils.find_vscode_settings()
  if not vscode_settings then return end

  local token = vscode_settings["vscode-home-assistant.longLivedAccessToken"]
  local url = vscode_settings["vscode-home-assistant.hostUrl"]

  if token and url then
    utils.logger.info "Migrating credentials from VS Code settings"
    M.save_credentials(token, url)
    vim.notify("Migrated Home Assistant credentials from VS Code", vim.log.levels.INFO)
  end
end

---Get authentication details for display (with obscured token)
---@return table Auth details with obscured token
function M.get_auth_details()
  local token = M.get_token()
  local url = M.get_url()

  local obscured_token = nil
  if token then
    if #token <= 10 then
      obscured_token = "***"
    else
      obscured_token = token:sub(1, 5) .. "..." .. token:sub(-5)
    end
  end

  return {
    url = url,
    token = obscured_token,
    has_credentials = M.has_credentials(),
  }
end

return M
