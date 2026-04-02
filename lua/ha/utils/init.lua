-- ha.nvim utility modules
local M = {}

-- Export utility modules
M.logger = require "ha.utils.logger"
M.workspace = require "ha.utils.workspace"
M.cache = require "ha.utils.cache"

-- Lazy load registry to avoid circular dependencies
local _registry = nil
function M.get_registry()
  if not _registry then
    _registry = require "ha.utils.registry"
  end
  return _registry
end

-- For compatibility, provide registry as a property that lazy loads
local registry_mt = {
  __index = function(_, key)
    return M.get_registry()[key]
  end
}
M.registry = setmetatable({}, registry_mt)

---Find VS Code settings for migration
---@return table? VS Code settings or nil
function M.find_vscode_settings()
  local possible_paths = {
    vim.fn.expand "~/.config/Code/User/settings.json",
    vim.fn.expand "~/.config/Code - OSS/User/settings.json",
    vim.fn.expand "~/Library/Application Support/Code/User/settings.json",
    vim.fn.expand "%APPDATA%/Code/User/settings.json":gsub("%%APPDATA%%", os.getenv "APPDATA" or ""),
  }

  for _, path in ipairs(possible_paths) do
    if vim.fn.filereadable(path) == 1 then
      local content = vim.fn.readfile(path)
      if content then
        local json_str = table.concat(content, "\n")
        local ok, settings = pcall(vim.fn.json_decode, json_str)
        if ok and settings then
          M.logger.debug("Found VS Code settings at: " .. path)
          return settings
        end
      end
    end
  end

  M.logger.debug "No VS Code settings found"
  return nil
end

---Check if command exists
---@param cmd string Command to check
---@return boolean True if command exists
function M.command_exists(cmd) return vim.fn.executable(cmd) == 1 end

---Debounce function calls
---@param func function Function to debounce
---@param delay number Delay in milliseconds
---@return function Debounced function
function M.debounce(func, delay)
  local timer = nil
  return function(...)
    local args = { ... }
    if timer then timer:stop() end
    timer = vim.defer_fn(function() func(unpack(args)) end, delay)
  end
end

return M
