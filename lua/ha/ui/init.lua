-- ha.nvim UI components
local M = {}

local config = require "ha.config"

-- UI state
local _state = {
  output_channels = {},
}

-- Global flag to ensure quit handler is only set up once
_G._ha_quit_handler_setup = false

---Setup UI components
function M.setup()
  -- Setup status line if enabled
  if config.get_value("ui.statusline.enabled", true) then require("ha.ui.status").setup() end

  -- Setup picker
  require("ha.ui.picker").setup()
end

---Cleanup UI components
function M.cleanup()
  require("ha.ui.status").cleanup()

  -- Close output channels
  for _, channel in pairs(_state.output_channels) do
    if channel and vim.api.nvim_buf_is_valid(channel.bufnr) then
      vim.api.nvim_buf_delete(channel.bufnr, { force = true })
    end
  end
  _state.output_channels = {}
end

---Show help in a floating window
---@param lines table Help lines
function M.show_help(lines) M._show_in_float("Home Assistant Help", lines, { width = 80, height = 25 }) end

---Show info message
---@param lines table Info lines
function M.show_info(lines)
  local content = table.concat(lines, "\n")
  vim.notify(content, vim.log.levels.INFO)
end

---Show error log
---@param content string Error log content
function M.show_error_log(content)
  local channel = M._get_or_create_channel "Home Assistant Error Log"
  M._write_to_channel(channel, content)
  M._show_channel(channel)
end



---Show content in floating window
---@param title string Window title
---@param lines table Content lines
---@param opts? table Window options
function M._show_in_float(title, lines, opts)
  opts = opts or {}
  local width = opts.width or math.min(120, vim.o.columns - 10)
  local height = opts.height or math.min(30, vim.o.lines - 10)

  -- Create buffer
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].filetype = opts.filetype or "text"

  -- Calculate window position
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  -- Create window
  local win_opts = {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = title,
    title_pos = "center",
  }

  local winnr = vim.api.nvim_open_win(bufnr, true, win_opts)

  -- Set keymaps for closing
  local keymaps = { "q", "<Esc>", "<C-c>" }
  for _, key in ipairs(keymaps) do
    vim.api.nvim_buf_set_keymap(bufnr, "n", key, "<cmd>close<cr>", { silent = true })
  end
end

---Get or create output channel
---@param name string Channel name
---@return table Channel object
function M._get_or_create_channel(name)
  if _state.output_channels[name] then
    local channel = _state.output_channels[name]
    if vim.api.nvim_buf_is_valid(channel.bufnr) then return channel end
  end

  -- Create new channel (scratch buffer)
  local bufnr = vim.api.nvim_create_buf(false, true)  -- nofile=false, scratch=true
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "hide"  -- Hide when not displayed
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = true
  vim.bo[bufnr].buflisted = false  -- Don't show in buffer list
  vim.api.nvim_buf_set_name(bufnr, name)

  local channel = {
    name = name,
    bufnr = bufnr,
  }

  _state.output_channels[name] = channel
  return channel
end

---Write content to channel
---@param channel table Channel object
---@param content string Content to write
function M._write_to_channel(channel, content)
  local lines = vim.split(content, "\n")
  vim.bo[channel.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(channel.bufnr, -1, -1, false, lines)
  vim.bo[channel.bufnr].modifiable = false
end

---Clear channel content
---@param channel table Channel object
function M._clear_channel(channel)
  vim.bo[channel.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(channel.bufnr, 0, -1, false, {})
  vim.bo[channel.bufnr].modifiable = false
end

---Show channel in a window
---@param channel table Channel object
function M._show_channel(channel)
  -- Find existing window or create new one
  local winnr = nil
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == channel.bufnr then
      winnr = win
      break
    end
  end

  if not winnr then
    -- Save current window before creating split
    local current_win = vim.api.nvim_get_current_win()
    
    -- Create new window
    vim.cmd "botright split"
    winnr = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(winnr, channel.bufnr)
    vim.api.nvim_win_set_height(winnr, math.min(15, math.floor(vim.o.lines / 3)))
    
    -- Set up buffer-local keymaps for the channel
    M._setup_channel_keymaps(channel.bufnr)
    
    -- Return focus to original window immediately
    vim.api.nvim_set_current_win(current_win)
  end

  -- Set window options and ensure normal mode
  vim.wo[winnr].wrap = true

  -- Go to end of buffer but DON'T focus the window - stay in current window
  -- This allows continuous template editing without window switching
  vim.api.nvim_win_call(winnr, function()
    vim.cmd "normal! G"
  end)
  -- Cursor stays in original window for seamless workflow
end

---Setup channel-specific keymaps
---@param bufnr number Buffer number
function M._setup_channel_keymaps(bufnr)
  -- Close channel with 'q'
  vim.keymap.set('n', 'q', function()
    local wins = vim.api.nvim_list_wins()
    for _, win in ipairs(wins) do
      if vim.api.nvim_win_get_buf(win) == bufnr then
        vim.api.nvim_win_close(win, false)
        break
      end
    end
  end, { buffer = bufnr, desc = "Close HA channel" })
  
  -- Set buffer options
  vim.bo[bufnr].filetype = "ha-output"
  vim.bo[bufnr].readonly = true
  vim.bo[bufnr].modifiable = false
end

-- Set up a one-time autocommand to handle HA channel buffers on quit
if not _G._ha_quit_handler_setup then
  _G._ha_quit_handler_setup = true
  vim.api.nvim_create_autocmd("QuitPre", {
    callback = function()
      -- Close all HA channel windows before quitting
      for _, channel in pairs(_state.output_channels) do
        if vim.api.nvim_buf_is_valid(channel.bufnr) then
          local wins = vim.api.nvim_list_wins()
          for _, win in ipairs(wins) do
            if vim.api.nvim_win_get_buf(win) == channel.bufnr then
              vim.api.nvim_win_close(win, true)  -- Force close
            end
          end
        end
      end
    end,
  })
end

---Toggle template result channel
---@param channel_name string Channel name to toggle
function M.toggle_channel(channel_name)
  channel_name = channel_name or "Home Assistant Template Renderer"
  
  -- Check if channel window is currently visible
  local channel = _state.output_channels[channel_name]
  if not channel or not vim.api.nvim_buf_is_valid(channel.bufnr) then
    vim.notify("No " .. channel_name .. " to toggle", vim.log.levels.WARN)
    return
  end
  
  local winnr = nil
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == channel.bufnr then
      winnr = win
      break
    end
  end
  
  if winnr then
    -- Channel is visible, close it
    vim.api.nvim_win_close(winnr, false)
  else
    -- Channel is hidden, show it
    M._show_channel(channel)
  end
end

---Show template result with toggle support
---@param success boolean Whether the render was successful
---@param data table Template render data
function M.show_template_result(success, data)
  local channel = M._get_or_create_channel("Home Assistant Template Renderer")
  
  -- Add timestamp and formatting
  local timestamp = os.date("[%H:%M:%S]")
  local separator = string.rep("-", 50)
  
  M._write_to_channel(channel, separator)
  M._write_to_channel(channel, timestamp .. " Rendering template:")
  M._write_to_channel(channel, data.template or "Unknown template")
  M._write_to_channel(channel, "")
  
  if success then
    M._write_to_channel(channel, "Result:")
    M._write_to_channel(channel, data.result or "No result")
  else
    M._write_to_channel(channel, "Error:")
    local error_msg = data.error or "Unknown error"
    
    -- Extract just the meaningful part from HTTP errors
    if error_msg:match("HTTP error: %d+") then
      -- Try to extract just the detailed message after the HTTP status
      local detailed_msg = error_msg:match("\n(.+)")
      if detailed_msg then
        error_msg = detailed_msg
      end
    end
    
    M._write_to_channel(channel, error_msg)
  end
  
  M._write_to_channel(channel, "")
  M._show_channel(channel)
end

-- Export submodules
M.status = require "ha.ui.status"
M.picker = require "ha.ui.picker"
M.progress_renderer = require "ha.ui.progress_renderer"

return M
