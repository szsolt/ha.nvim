-- Cache management utilities for Home Assistant modules
local M = {}

-- Direct require to avoid circular dependency
local logger = require "ha.utils.logger"

---Create a new cache instance with TTL support
---@param name string Cache name for debugging
---@param default_ttl number Default TTL in milliseconds
---@return table Cache object
function M.create_cache(name, default_ttl)
  local cache = {
    _name = name,
    _data = {},
    _last_updated = 0,
    _default_ttl = default_ttl or 30000, -- 30 seconds default
  }
  
  ---Check if cache is valid and not expired
  ---@param ttl? number Custom TTL in milliseconds
  ---@return boolean True if cache is valid
  function cache:is_valid(ttl)
    local cache_ttl = ttl or self._default_ttl
    local now = vim.loop and vim.loop.now() or (os.time() * 1000)
    
    -- Ensure both values are numbers
    local last_updated = tonumber(self._last_updated) or 0
    local ttl_num = tonumber(cache_ttl) or 30000
    local now_num = tonumber(now) or 0
    
    return (now_num - last_updated) < ttl_num and next(self._data) ~= nil
  end
  
  ---Get cached data if valid
  ---@param ttl? number Custom TTL in milliseconds
  ---@return any|nil Cached data or nil if expired/empty
  function cache:get(ttl)
    if self:is_valid(ttl) then
      logger.debug("Cache hit for " .. self._name)
      return self._data
    end
    
    logger.debug("Cache miss for " .. self._name)
    return nil
  end
  
  ---Set cache data
  ---@param data any Data to cache
  function cache:set(data)
    self._data = data
    self._last_updated = tonumber(vim.loop and vim.loop.now() or (os.time() * 1000))
    logger.debug("Cache updated for " .. self._name)
  end
  
  ---Clear cache data
  function cache:clear()
    self._data = {}
    self._last_updated = 0
    logger.debug("Cache cleared for " .. self._name)
  end
  
  ---Get cache statistics
  ---@return table Cache stats
  function cache:stats()
    local now = vim.loop and vim.loop.now() or (os.time() * 1000)
    return {
      name = self._name,
      has_data = next(self._data) ~= nil,
      last_updated = self._last_updated,
      age_ms = now - self._last_updated,
      ttl_ms = self._default_ttl,
      is_valid = self:is_valid(),
    }
  end
  
  return cache
end

---Create a cache manager for multiple related caches
---@param prefix string Prefix for cache names
---@return table Cache manager
function M.create_cache_manager(prefix)
  local manager = {
    _prefix = prefix,
    _caches = {},
  }
  
  ---Get or create a cache
  ---@param name string Cache name (will be prefixed)
  ---@param ttl? number TTL in milliseconds
  ---@return table Cache object
  function manager:get_cache(name, ttl)
    local cache_name = self._prefix .. "_" .. name
    
    if not self._caches[cache_name] then
      self._caches[cache_name] = M.create_cache(cache_name, ttl)
    end
    
    return self._caches[cache_name]
  end
  
  ---Clear all managed caches
  function manager:clear_all()
    for _, cache in pairs(self._caches) do
      cache:clear()
    end
    logger.debug("All caches cleared for " .. self._prefix)
  end
  
  ---Get stats for all managed caches
  ---@return table Array of cache stats
  function manager:get_all_stats()
    local stats = {}
    for _, cache in pairs(self._caches) do
      table.insert(stats, cache:stats())
    end
    return stats
  end
  
  return manager
end

---Utility function for async data fetching with caching
---@param cache table Cache object
---@param fetch_fn function Function to fetch data, should accept callback(data)
---@param callback function Callback to receive data
---@param ttl? number Custom TTL
function M.fetch_with_cache(cache, fetch_fn, callback, ttl)
  -- Try cache first
  local cached_data = cache:get(ttl)
  if cached_data then
    callback(cached_data)
    return
  end
  
  -- Cache miss, fetch new data
  fetch_fn(function(data)
    if data then
      cache:set(data)
    end
    callback(data)
  end)
end

---Create a simple memoization cache for synchronous functions
---@param fn function Function to memoize
---@param ttl? number TTL in milliseconds (default: 5 minutes)
---@param key_fn? function Optional function to generate cache key from args
---@return function Memoized function
function M.memoize(fn, ttl, key_fn)
  local cache = M.create_cache("memoized", ttl or 300000) -- 5 minutes default
  local memo_cache = {}
  
  return function(...)
    local args = {...}
    local key = key_fn and key_fn(args) or table.concat(vim.tbl_map(tostring, args), "_")
    
    -- Check if we have a cached result for this key
    if memo_cache[key] then
      local cached_entry = memo_cache[key]
      local now = vim.loop and vim.loop.now() or (os.time() * 1000)
      
      if (now - cached_entry.timestamp) < (ttl or 300000) then
        return cached_entry.result
      end
    end
    
    -- Cache miss, compute result
    local result = fn(...)
    memo_cache[key] = {
      result = result,
      timestamp = vim.loop and vim.loop.now() or (os.time() * 1000)
    }
    
    return result
  end
end

return M