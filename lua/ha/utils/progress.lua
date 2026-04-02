---@class TrackedRequest
---@field id string Unique request identifier
---@field description string Human-readable description
---@field notify_on_completion boolean Whether to show completion notification
---@field started_at number Timestamp when request started
---@field status "pending"|"completed"|"failed" Request status

---@class ProgressState
---@field active_count number Number of active requests
---@field completed_count number Number of completed requests  
---@field total_count number Total requests in current batch
---@field descriptions string[] Current request descriptions
---@field has_failures boolean Whether any requests failed

---@class ProgressObserver
---@field on_progress_changed fun(state: ProgressState): nil Callback for progress changes

local utils = require("ha.utils")

---@class ProgressTracker
local M = {}

-- Private state
local _active_requests = {} ---@type table<string, TrackedRequest>
local _completed_count = 0
local _observers = {} ---@type ProgressObserver[]
local _request_counter = 0
local _cleanup_timer = nil

---Start automatic cleanup timer for timed-out requests
local function start_cleanup_timer()
    if _cleanup_timer then return end
    
    _cleanup_timer = vim.loop.new_timer()
    _cleanup_timer:start(60000, 60000, function() -- Check every 60 seconds
        vim.schedule(function()
            M.cleanup_timed_out_requests(120000) -- Timeout after 2 minutes
        end)
    end)
end

---Stop automatic cleanup timer
local function stop_cleanup_timer()
    if _cleanup_timer then
        _cleanup_timer:stop()
        _cleanup_timer:close()
        _cleanup_timer = nil
    end
end

---Generate unique request ID
---@return string
local function generate_request_id()
    _request_counter = _request_counter + 1
    return string.format("req_%d_%d", os.time(), _request_counter)
end

---Get current progress state
---@return ProgressState
local function get_progress_state()
    local active_count = vim.tbl_count(_active_requests)
    local descriptions = {}
    local has_failures = false
    
    -- Sort active requests by start time (oldest first) for consistent display
    local sorted_requests = {}
    for _, request in pairs(_active_requests) do
        table.insert(sorted_requests, request)
        if request.status == "failed" then
            has_failures = true
        end
    end
    
    -- Sort by started_at timestamp (oldest first)
    table.sort(sorted_requests, function(a, b)
        return a.started_at < b.started_at
    end)
    
    -- Extract descriptions in chronological order
    for _, request in ipairs(sorted_requests) do
        table.insert(descriptions, request.description)
    end
    
    return {
        active_count = active_count,
        completed_count = _completed_count,
        total_count = active_count + _completed_count,
        descriptions = descriptions,
        has_failures = has_failures
    }
end

---Notify all observers of progress changes
---@param state ProgressState
local function notify_observers(state)
    vim.schedule(function()
        for _, observer in ipairs(_observers) do
            if observer.on_progress_changed then
                local ok, err = pcall(observer.on_progress_changed, state)
                if not ok then
                    utils.logger.error("Progress observer error: " .. tostring(err))
                end
            end
        end
        
        -- Stop cleanup timer when no active requests
        if state.active_count == 0 then
            stop_cleanup_timer()
        end
    end)
end

---Add a background operation (no completion notification)
---@param description string Human-readable description
---@return string request_id Unique request identifier
function M.add_background(description)
    return M.add_request(nil, description, false)
end

---Add a user-initiated operation (with completion notification)
---@param description string Human-readable description  
---@return string request_id Unique request identifier
function M.add_user_action(description)
    return M.add_request(nil, description, true)
end

---Add a request to the progress tracker
---@param request_id string|nil Optional custom request ID
---@param description string Human-readable description
---@param notify_on_completion boolean Whether to show completion notification
---@return string request_id The request identifier
function M.add_request(request_id, description, notify_on_completion)
    request_id = request_id or generate_request_id()
    
    local was_empty = vim.tbl_isempty(_active_requests)
    
    _active_requests[request_id] = {
        id = request_id,
        description = description,
        notify_on_completion = notify_on_completion or false,
        started_at = vim.loop.now(),
        status = "pending"
    }
    
    -- If we went from 0 to 1+ requests, reset completed count and start cleanup timer
    if was_empty then
        _completed_count = 0
        start_cleanup_timer()
    end
    
    local state = get_progress_state()
    utils.logger.debug(string.format("Added request: %s - %s", request_id, description))
    notify_observers(state)
    
    return request_id
end

---Mark a request as completed
---@param request_id string Request identifier
---@param success boolean Whether the request succeeded
---@param error_message string|nil Optional error message for failures
function M.complete_request(request_id, success, error_message)
    local request = _active_requests[request_id]
    if not request then
        utils.logger.warn("Attempted to complete unknown request: " .. tostring(request_id))
        return
    end
    
    -- Update request status
    request.status = success and "completed" or "failed"
    _completed_count = _completed_count + 1
    
    -- Remove from active requests
    _active_requests[request_id] = nil
    
    -- Show completion notification if requested
    if request.notify_on_completion then
        local icon = success and "✓" or "✗"
        local message = success and request.description or 
                       (request.description .. (error_message and (" - " .. error_message) or " - Failed"))
        vim.schedule(function()
            vim.notify(icon .. " " .. message, success and vim.log.levels.INFO or vim.log.levels.ERROR)
        end)
    end
    
    local state = get_progress_state()
    local duration = vim.loop.now() - request.started_at
    utils.logger.debug(string.format(
        "Completed request: %s - %s (%dms)", 
        request_id, success and "success" or "failed", duration
    ))
    
    notify_observers(state)
end

---Mark a request as failed (convenience wrapper)
---@param request_id string Request identifier
---@param error_message string|nil Optional error message
function M.fail_request(request_id, error_message)
    M.complete_request(request_id, false, error_message)
end

---Check for timed-out requests and mark them as failed
---@param timeout_ms number Timeout in milliseconds (default: 30000)
function M.cleanup_timed_out_requests(timeout_ms)
    timeout_ms = timeout_ms or 30000
    local now = vim.loop.now()
    local timed_out = {}
    
    for request_id, request in pairs(_active_requests) do
        if now - request.started_at > timeout_ms then
            table.insert(timed_out, request_id)
        end
    end
    
    for _, request_id in ipairs(timed_out) do
        utils.logger.warn("Request timed out: " .. _active_requests[request_id].description)
        M.fail_request(request_id, "Request timed out")
    end
end

---Get current progress state
---@return ProgressState
function M.get_state()
    return get_progress_state()
end

---Check if there are active requests
---@return boolean
function M.has_active_requests()
    return not vim.tbl_isempty(_active_requests)
end

---Register an observer for progress changes
---@param observer ProgressObserver Observer with on_progress_changed callback
function M.add_observer(observer)
    table.insert(_observers, observer)
end

---Remove an observer
---@param observer ProgressObserver Observer to remove
function M.remove_observer(observer)
    for i, obs in ipairs(_observers) do
        if obs == observer then
            table.remove(_observers, i)
            break
        end
    end
end

---Clear all active requests (emergency cleanup)
function M.clear_all_requests()
    local count = vim.tbl_count(_active_requests)
    if count > 0 then
        utils.logger.warn(string.format("Clearing %d active requests", count))
        _active_requests = {}
        _completed_count = 0
        notify_observers(get_progress_state())
    end
end

---Get debug information
---@return table Debug info about active requests
function M.get_debug_info()
    return {
        active_requests = vim.tbl_count(_active_requests),
        completed_count = _completed_count,
        observers = #_observers,
        request_details = vim.tbl_map(function(req)
            return {
                id = req.id,
                description = req.description,
                status = req.status,
                age_ms = vim.loop.now() - req.started_at
            }
        end, _active_requests)
    }
end

return M
