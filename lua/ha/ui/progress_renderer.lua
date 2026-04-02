---@class SpinnerConfig
---@field type "braille"|"wheel"|"ascii"|"none" Spinner animation type
---@field speed number Animation speed in milliseconds
---@field enabled boolean Whether spinner animation is enabled

---@class ProgressRendererState
---@field current_frame number Current animation frame
---@field animation_timer userdata|nil vim.loop timer for animation
---@field last_state ProgressState|nil Last known progress state

local config = require "ha.config"
local utils = require "ha.utils"

---@class ProgressRenderer
local M = {}

-- Spinner character sets
local SPINNERS = {
  braille = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
  wheel = { "◐", "◓", "◑", "◒" },
  ascii = { "|", "/", "-", "\\" },
}

-- Private state
local _state = {
  current_frame = 1,
  animation_timer = nil,
  last_state = nil,
} ---@type ProgressRendererState

---Get spinner configuration
---@return SpinnerConfig
local function get_spinner_config()
  return {
    type = config.get_value("ui.progress.spinner_type", "braille"),
    speed = config.get_value("ui.progress.animation_speed", 100),
    enabled = config.get_value("ui.progress.enabled", true),
  }
end

---Get current spinner character
---@return string
local function get_spinner_char()
  local cfg = get_spinner_config()

  if not cfg.enabled or cfg.type == "none" then return "" end

  local spinner_set = SPINNERS[cfg.type] or SPINNERS.braille
  return spinner_set[_state.current_frame] or spinner_set[1]
end

---Advance animation frame
local function advance_frame()
  local cfg = get_spinner_config()
  local spinner_set = SPINNERS[cfg.type] or SPINNERS.braille

  _state.current_frame = (_state.current_frame % #spinner_set) + 1
end

---Start animation timer
local function start_animation()
  if _state.animation_timer then
    return -- Already running
  end

  local cfg = get_spinner_config()
  if not cfg.enabled then return end

  _state.animation_timer = vim.loop.new_timer()
  _state.animation_timer:start(
    0,
    cfg.speed,
    vim.schedule_wrap(function()
      advance_frame()
      -- Trigger statusline update
      M.update_display()
    end)
  )

  utils.logger.debug "Started progress animation timer"
end

---Stop animation timer
local function stop_animation()
  if _state.animation_timer then
    _state.animation_timer:stop()
    _state.animation_timer:close()
    _state.animation_timer = nil
    _state.current_frame = 1
    utils.logger.debug "Stopped progress animation timer"
  end
end

---Format progress text for display
---@param state ProgressState Progress state to format
---@return string Formatted progress text
function M.format_progress(state)
  if state.active_count == 0 then return "" end

  local spinner = get_spinner_char()
  local spinner_part = spinner ~= "" and (spinner .. " ") or ""

  -- Always show progress as (completed/total) when we have multiple operations
  if state.total_count > 1 then
    -- Show first (oldest) active operation: "⠋ Connecting (2/5)"
    if #state.descriptions > 0 then
      return string.format(
        "%s%s (%d/%d)",
        spinner_part,
        state.descriptions[1], -- First/oldest operation (not latest)
        state.completed_count,
        state.total_count
      )
    else
      return string.format("%s%d/%d operations", spinner_part, state.completed_count, state.total_count)
    end
    -- Single operation: "⠋ Loading entities"
  elseif #state.descriptions == 1 then
    return spinner_part .. state.descriptions[1]
  else
    return spinner_part .. "Working..."
  end
end

---Update the progress display (called by statusline, etc.)
function M.update_display()
  -- This will be called by statusline components
  -- The actual display update is handled by vim's statusline refresh
  vim.cmd.redrawstatus()
end

---Handle progress state changes
---@param state ProgressState New progress state
function M.on_progress_changed(state)
  _state.last_state = state

  if state.active_count > 0 then
    -- Start animation if we have active requests
    start_animation()
  else
    -- Stop animation when no active requests
    stop_animation()
    -- Trigger final display update
    M.update_display()
  end
end

---Get current progress display text (for statusline integration)
---@return string Progress text for display
function M.get_display_text()
  if not _state.last_state or _state.last_state.active_count == 0 then return "" end

  return M.format_progress(_state.last_state)
end

---Check if progress is active
---@return boolean
function M.is_active() return _state.last_state and _state.last_state.active_count > 0 or false end

---Get debug information
---@return table Debug info about renderer state
function M.get_debug_info()
  local cfg = get_spinner_config()
  return {
    animation_active = _state.animation_timer ~= nil,
    current_frame = _state.current_frame,
    spinner_config = cfg,
    current_spinner = get_spinner_char(),
    last_state = _state.last_state,
  }
end

---Setup progress renderer (call during plugin initialization)
function M.setup()
  local progress = require "ha.utils.progress"

  -- Register as observer for progress changes
  progress.add_observer {
    on_progress_changed = M.on_progress_changed,
  }

  utils.logger.debug "Progress renderer initialized"
end

---Cleanup (call during plugin teardown)
function M.cleanup()
  stop_animation()
  _state.last_state = nil
  utils.logger.debug "Progress renderer cleaned up"
end

return M
