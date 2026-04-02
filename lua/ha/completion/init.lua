-- Home Assistant completion integration for blink.cmp

local M = {}
local config = require "ha.config"
local utils = require "ha.utils"

---Setup completion integration
function M.setup()
  if not config.get_value("completion.enabled", true) then return end

  local ok, blink = pcall(require, "blink.cmp")
  if not ok then
    utils.logger.warn "blink.cmp not available"
    return
  end

  utils.logger.debug "Home Assistant completion sources setup completed"
end

---Clear completion cache
function M.clear_cache()
  -- Clear caches from completion modules that still use caching
  -- Note: entities now use registry (no cache), domains use registry (no cache)
  local modules = { "services", "integrations", "mdi" }
  
  for _, module_name in ipairs(modules) do
    local ok, module = pcall(require, "ha.completion." .. module_name)
    if ok and module._cache then
      -- New cache system has a clear() method
      if type(module._cache.clear) == "function" then
        module._cache:clear()
      else
        -- Fallback for any remaining old-style caches
        if module._cache.entities then module._cache.entities = {} end
        if module._cache.services then module._cache.services = {} end
        if module._cache.icons then module._cache.icons = {} end
        module._cache.last_updated = 0
      end
    end
  end
  
  utils.logger.info("All completion caches cleared")
end

---Get cache statistics for debugging
---@return table Cache statistics
function M.get_cache_stats()
  local stats = {}
  local modules = { "entities", "services", "integrations", "mdi", "domains" }
  
  for _, module_name in ipairs(modules) do
    local ok, module = pcall(require, "ha.completion." .. module_name)
    if ok then
      if module._cache and type(module._cache.stats) == "function" then
        stats[module_name] = module._cache:stats()
      else
        -- For registry-based modules (entities, domains) show registry status
        if module_name == "entities" or module_name == "domains" then
          local registry = require("ha.utils.registry")
          local registry_stats = registry.get_stats()
          stats[module_name] = {
            name = module_name,
            source = "registry",
            initialized = registry_stats.initialized,
            last_updated = registry_stats.last_updated,
          }
        else
          -- Fallback for old-style cache
          stats[module_name] = {
            name = module_name,
            has_data = module._cache and next(module._cache) ~= nil,
            last_updated = module._cache and module._cache.last_updated or 0,
          }
        end
      end
    end
  end
  
  return stats
end

return M
