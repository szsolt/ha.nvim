-- ha.nvim configuration management
local M = {}

-- Default configuration
local defaults = {
  -- Logging configuration
  log_level = "info", -- trace, debug, info, warn, error, fatal

  -- Language Server Protocol settings
  lsp = {
    enabled = true,
    auto_setup = true, -- Auto-setup LSP in HA workspaces
    server_path = nil, -- Path to HA language server (auto-detected if nil)
    -- Dynamic installation settings
    dynamic = {
      enabled = true, -- Enable dynamic installation via Mason
      auto_install = true, -- Auto-install if server not found
      repository = "https://github.com/keesschollaart81/vscode-home-assistant.git",
      version = "main", -- Branch, tag, or commit to use
    },
    settings = {
      ["vscode-home-assistant"] = {
        ignoreCertificates = false,
      },
    },
  },

  -- Authentication settings
  auth = {
    auto_migrate = true, -- Auto-migrate from VS Code settings
    storage_file = "ha_credentials", -- File name in stdpath('data')
  },

  -- UI settings
  ui = {
    statusline = {
      enabled = true,
      position = "right", -- left, right
      priority = 100,
    },
    notifications = {
      enabled = true,
      timeout = 5000, -- ms
    },
    progress = {
      enabled = true,
      spinner_type = "braille", -- braille, wheel, ascii, none
      animation_speed = 100, -- milliseconds between frames
    },
    picker = {
      -- snacks.picker settings
      layout = {
        preset = "default",
      },
    },
  },

  -- Completion settings
  completion = {
    enabled = true,
    -- Blink.cmp source settings
    sources = {
      ha_entities = {
        enabled = true,
        priority = 100,
      },
      ha_services = {
        enabled = true,
        priority = 90,
      },
    },
  },

  -- Command settings
  commands = {
    prefix = "ha", -- Command prefix
    create_user_commands = true, -- Create :Ha... user commands
  },

  -- Home Assistant API settings
  api = {
    timeout = 10000, -- Request timeout in ms
    retry_count = 3,
    retry_delay = 1000, -- ms
  },

  -- Workspace detection settings
  workspace = {
    auto_detect = true,
    indicators = {
      "configuration.yaml",
      ".storage",
      "home-assistant_v2.db",
      "automations.yaml",
      "scripts.yaml",
      "scenes.yaml",
    },
  },

  -- Diagnostics settings
  diagnostics = {
    enabled = true, -- Enable HA diagnostics
    on_change = true, -- Run diagnostics on text change (debounced)
    debounce_ms = 1000, -- Debounce delay for text change diagnostics
    validate_entities = true, -- Validate entity_id references
    validate_services = true, -- Validate service calls
    severity = "warn", -- Default severity: "error", "warn", "info", "hint"
  },
}

-- Current configuration
local _config = {}

---Setup configuration with user options
---@param opts table User configuration options
function M.setup(opts) _config = vim.tbl_deep_extend("force", defaults, opts or {}) end

---Get current configuration
---@return table Current configuration
function M.get() return _config end

---Get specific configuration value
---@param key string Dot-separated key path
---@param default? any Default value if not found
---@return any Value at key path or default
function M.get_value(key, default)
  local keys = vim.split(key, ".", { plain = true })
  local value = _config

  for _, k in ipairs(keys) do
    if type(value) ~= "table" or value[k] == nil then return default end
    value = value[k]
  end

  return value
end

return M
