-- Logger utility module
local M = {}

-- Log levels
local LOG_LEVELS = {
  TRACE = 0,
  DEBUG = 1,
  INFO = 2,
  WARN = 3,
  ERROR = 4,
  FATAL = 5,
}

-- Current log level
local _log_level = LOG_LEVELS.INFO

-- Log file path
local _log_file = nil

---Setup logger
---@param level string Log level ('trace', 'debug', 'info', 'warn', 'error', 'fatal')
function M.setup(level)
  _log_level = LOG_LEVELS[level:upper()] or LOG_LEVELS.INFO
  _log_file = vim.fn.stdpath "data" .. "/ha.nvim.log"

  -- Create log file if it doesn't exist
  if vim.fn.filereadable(_log_file) == 0 then vim.fn.writefile({}, _log_file) end

  M.info("Logger initialized with level: " .. level)
end

---Log a message
---@param level number Log level number
---@param level_name string Log level name
---@param message string Log message
local function log(level, level_name, message)
  if level < _log_level then return end

  local timestamp = os.date "%Y-%m-%d %H:%M:%S"
  local log_entry = string.format("[%s] [%s] [ha.nvim] %s", timestamp, level_name, message)

  -- Write to log file if configured
  if _log_file then
    local file = io.open(_log_file, "a")
    if file then
      file:write(log_entry .. "\n")
      file:close()
    end
  end

  -- Also output to console for debug/error levels
  -- if level >= LOG_LEVELS.DEBUG then print(log_entry) end
end

---Log trace message
---@param message string Message to log
function M.trace(message) log(LOG_LEVELS.TRACE, "TRACE", message) end

---Log debug message
---@param message string Message to log
function M.debug(message) log(LOG_LEVELS.DEBUG, "DEBUG", message) end

---Log info message
---@param message string Message to log
function M.info(message) log(LOG_LEVELS.INFO, "INFO", message) end

---Log warning message
---@param message string Message to log
function M.warn(message) log(LOG_LEVELS.WARN, "WARN", message) end

---Log error message
---@param message string Message to log
function M.error(message) log(LOG_LEVELS.ERROR, "ERROR", message) end

return M
