<p align="center">
  <img src="https://brands.home-assistant.io/_/homeassistant/logo.png" width="100" alt="Home Assistant Logo" />
</p>

<h1 align="center">ha.nvim</h1>

<p align="center">
  <strong>A comprehensive Home Assistant integration for Neovim</strong>
</p>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#installation">Installation</a> •
  <a href="#configuration">Configuration</a> •
  <a href="#commands">Commands</a> •
  <a href="#pickers">Pickers</a> •
  <a href="#keymaps">Keymaps</a> •
  <a href="#completion">Completion</a> •
  <a href="#diagnostics">Diagnostics</a> •
  <a href="#lsp">LSP</a>
</p>

---

**ha.nvim** brings the power of Home Assistant directly into your Neovim editor. Edit your HA configuration files with real-time entity completion, inline diagnostics, interactive pickers, and a live WebSocket connection to your Home Assistant instance.

## Features

- **Real-time Completion** — Entity IDs, services, domains, integrations, and MDI icons via [blink.cmp](https://github.com/saghen/blink.cmp)
- **Interactive Pickers** — Browse entities, services, integrations, and areas using [snacks.nvim](https://github.com/folke/snacks.nvim) pickers with live preview, filtering, and multi-select insertion
- **Inline Diagnostics** — Validates entity IDs and service calls against your live registry
- **Entity Hover** — Press `K` on any entity ID to see its current state, attributes, area, and device info
- **LSP Integration** — Optional Home Assistant Language Server with Mason auto-install
- **WebSocket API** — Live connection via `websocat` for real-time state and registry updates
- **Service Calls** — Call HA services directly from Neovim
- **Template Rendering** — Render Jinja2 templates and see results in a dedicated output channel
- **Statusline** — Connection status indicator for lualine
- **Workspace Detection** — Auto-activates when editing HA config files

## Requirements

- **Neovim** ≥ 0.10 (0.11+ recommended for native LSP)
- **[websocat](https://github.com/vi/websocat)** — WebSocket CLI client (required for API communication)
- **[plenary.nvim](https://github.com/nvim-lua/plenary.nvim)** — HTTP requests
- **[blink.cmp](https://github.com/saghen/blink.cmp)** — Completion engine
- **[snacks.nvim](https://github.com/folke/snacks.nvim)** — Picker UI

### Optional

- **[mason.nvim](https://github.com/williamboman/mason.nvim)** — Auto-install HA Language Server
- **[lualine.nvim](https://github.com/nvim-lualine/lualine.nvim)** — Statusline integration
- **[which-key.nvim](https://github.com/folke/which-key.nvim)** — Keymap discovery
- **Node.js** — Required if using the HA Language Server

## Installation

### With [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "szsolt/ha.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "saghen/blink.cmp",
    "folke/snacks.nvim",
  },
  ft = { "yaml", "home-assistant" },
  cmd = { "Ha" },
  event = "VeryLazy",
  opts = {
    -- See Configuration section below
  },
  config = function(_, opts)
    require("ha").setup(opts)
  end,
}
```

### With [AstroNvim](https://astronvim.com/)

Copy [`examples/astronvim.lua`](examples/astronvim.lua) to your AstroNvim plugins directory (e.g., `lua/plugins/home-assistant.lua`). This includes keymaps, statusline, completion sources, and which-key integration out of the box.

### Authentication

Before using the plugin, you need to set up authentication with your Home Assistant instance:

1. Run `:Ha auth setup`
2. Enter your Home Assistant URL (e.g., `http://homeassistant.local:8123`)
3. Enter a [Long-Lived Access Token](https://www.home-assistant.io/docs/authentication/#your-account-profile) from your HA profile

Credentials are encrypted and stored in `stdpath('data')/ha_credentials`.

> **Tip:** If you have the [VS Code Home Assistant](https://marketplace.visualstudio.com/items?itemName=keesschollaart.vscode-home-assistant) extension configured, credentials will be auto-migrated on first launch.

## Configuration

```lua
require("ha").setup({
  -- Logging: "trace", "debug", "info", "warn", "error", "fatal"
  log_level = "info",

  -- Language Server Protocol
  lsp = {
    enabled = false,          -- Disable by default, toggle with <localleader>hL
    auto_setup = true,        -- Auto-setup when enabled in HA workspaces
    server_path = nil,        -- Auto-detected; set to override
    dynamic = {
      enabled = true,         -- Enable dynamic installation via Mason
      auto_install = true,    -- Auto-install if server not found
    },
    settings = {
      ["vscode-home-assistant"] = {
        ignoreCertificates = false,
      },
    },
  },

  -- Authentication
  auth = {
    auto_migrate = true,      -- Auto-migrate from VS Code settings
    storage_file = "ha_credentials",
  },

  -- UI
  ui = {
    statusline = { enabled = true },
    notifications = { enabled = true, timeout = 5000 },
    progress = {
      enabled = true,
      spinner_type = "braille", -- "braille", "wheel", "ascii", "none"
    },
    picker = {
      layout = { preset = "default" },
    },
  },

  -- Completion (blink.cmp sources)
  completion = {
    enabled = true,
    sources = {
      ha_entities = { enabled = true, priority = 100 },
      ha_services = { enabled = true, priority = 90 },
      ha_domains = { enabled = true, priority = 110 },
      ha_mdi_icons = { enabled = true, priority = 80 },
    },
  },

  -- Diagnostics
  diagnostics = {
    enabled = true,
    on_change = true,         -- Validate on text change (debounced)
    debounce_ms = 1000,
    validate_entities = true, -- Validate entity_id references
    validate_services = true, -- Validate service calls
    severity = "warn",
  },

  -- Commands
  commands = {
    prefix = "ha",
    create_user_commands = true,
  },

  -- API
  api = {
    timeout = 10000,
    retry_count = 3,
    retry_delay = 1000,
  },

  -- Workspace detection
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
})
```

## Commands

All commands are available under the `:Ha` prefix.

| Command | Description |
|---------|-------------|
| `:Ha` | Show command picker |
| `:Ha auth setup` | Interactive credential setup |
| `:Ha auth test` | Test connection and authentication |
| `:Ha auth show` | Show current auth details (token obscured) |
| `:Ha auth clear` | Clear stored credentials |
| `:Ha entities` | Open entity picker (auto-detects entity under cursor) |
| `:Ha entities <id>` | Open entity picker focused on specific entity |
| `:Ha services` | Open service picker |
| `:Ha integrations` | Open integration browser |
| `:Ha template` | Render Jinja2 template (current line or visual selection) |
| `:Ha template help` | Show template syntax help |
| `:Ha reload list` | Show reload options picker |
| `:Ha reload automations` | Reload automations |
| `:Ha reload scripts` | Reload scripts |
| `:Ha reload scenes` | Reload scenes |
| `:Ha reload all` | Reload all configuration |
| `:Ha restart` | Restart Home Assistant |
| `:Ha status` | Show connection status |
| `:Ha log` | Show HA error log |
| `:Ha open` | Open Home Assistant in browser |
| `:Ha diagnostics run` | Run diagnostics on current buffer |
| `:Ha diagnostics clear` | Clear diagnostics |
| `:Ha diagnostics refresh` | Refresh diagnostics for all buffers |
| `:Ha diagnostics stats` | Show diagnostics statistics |
| `:Ha lsp toggle` | Toggle HA Language Server on/off |
| `:Ha lsp start` | Start HA Language Server |
| `:Ha lsp stop` | Stop HA Language Server |
| `:Ha lsp restart` | Restart HA Language Server |
| `:Ha lsp status` | Show LSP status |

## Pickers

Pickers are powered by [snacks.nvim](https://github.com/folke/snacks.nvim) and provide fuzzy search, live preview, and multi-select.

### Entity Picker

Open with `:Ha entities` or `<localleader>he`.

The entity picker shows all entities from your Home Assistant instance with:

- **Fuzzy search** by entity ID or friendly name
- **Live preview** with state, attributes, device info, and timeline
- **Domain filtering** — Press `<C-d>` to filter by domain (e.g., `light`, `sensor`)
- **Area filtering** — Press `<C-l>` to filter by area/room
- **Platform filtering** — Press `<C-p>` to filter by platform (e.g., MQTT, Z-Wave)
- **Device class filtering** — Press `<C-u>` to filter by device class
- **Toggle unavailable** — Press `<C-h>` to show/hide unavailable entities
- **Reset filters** — Press `<C-r>` to clear all filters
- **Insert into buffer** — Press `<C-s>` to insert selected entity ID(s) at cursor
- **Auto-detection** — If your cursor is on an entity ID, the picker will focus it

### Service Picker

Open with `:Ha services` or `<localleader>hS`.

- **Fuzzy search** by `domain.service` name
- **Live preview** with description, fields, types, defaults, examples, and target info
- **Insert into buffer** — Press `<C-s>` to insert selected service name(s) at cursor

### Integration Picker

Open with `:Ha integrations` or `<localleader>hi`.

- Browse all installed integrations
- Preview with manifest details, documentation links, and entity counts

### Reload Picker

Open with `:Ha reload list`.

- Quick access to reload automations, scripts, scenes, groups, and more
- Supports reloading all or individual domains

### Common Picker Keybindings

| Key | Action |
|-----|--------|
| `<CR>` | Confirm selection |
| `<Esc>` | Close picker |
| `<C-s>` | Insert selected item(s) into buffer at cursor |
| `<Tab>` | Toggle selection (multi-select) |
| `<C-d>` | Filter by domain (entity picker only) |
| `<C-l>` | Filter by area (entity picker only) |
| `<C-p>` | Filter by platform (entity picker only) |
| `<C-u>` | Filter by device class (entity picker only) |
| `<C-h>` | Toggle unavailable entities (entity picker only) |
| `<C-r>` | Reset filters (entity picker only) |

## Keymaps

Keymaps use the `<localleader>h` prefix. With `localleader` set to `,`, the keymaps are:

| Keymap | Action |
|--------|--------|
| `<localleader>h` | Show Home Assistant menu (which-key) |
| `<localleader>ha` | Setup authentication |
| `<localleader>ht` | Render template |
| `<localleader>hT` | Template help |
| `<localleader>he` | Entity picker |
| `<localleader>hS` | Service picker |
| `<localleader>hi` | Integration picker |
| `<localleader>hr` | Reload services |
| `<localleader>hR` | Restart Home Assistant |
| `<localleader>hs` | Show status |
| `<localleader>hl` | Show error log |
| `<localleader>ho` | Open in browser |
| `<localleader>hd` | Run diagnostics |
| `<localleader>hD` | Clear diagnostics |
| `<localleader>hL` | Toggle HA LSP |
| `K` | Hover entity info (falls back to LSP hover) |

## Completion

Completion is provided through [blink.cmp](https://github.com/saghen/blink.cmp) with the following sources:

### Entity Completion (`ha_entities`)
Triggers after typing a domain prefix (e.g., `light.`, `sensor.`). Shows entity IDs with friendly names and states from the live registry.

### Service Completion (`ha_services`)
Completes `domain.service` names with descriptions.

### Domain Completion (`ha_domains`)
Completes domain names extracted dynamically from your entity registry.

### Integration Completion (`ha_integrations`)
Completes integration domain names.

### MDI Icon Completion (`ha_mdi_icons`)
Triggers after `mdi:` prefix for Material Design Icons.

### blink.cmp Configuration

Add the sources to your blink.cmp configuration:

```lua
{
  "saghen/blink.cmp",
  opts = function(_, opts)
    vim.list_extend(opts.sources.default, {
      "ha_domains", "ha_entities", "ha_services",
      "ha_integrations", "ha_mdi_icons",
    })

    opts.sources.providers.ha_entities = {
      name = "Home Assistant Entities",
      module = "ha.completion.entities",
      score_offset = 100,
    }

    opts.sources.providers.ha_services = {
      name = "Home Assistant Services",
      module = "ha.completion.services",
      score_offset = 90,
    }

    opts.sources.providers.ha_domains = {
      name = "Home Assistant Domains",
      module = "ha.completion.domains",
      score_offset = 110,
    }

    opts.sources.providers.ha_mdi_icons = {
      name = "Home Assistant MDI Icons",
      module = "ha.completion.mdi",
      score_offset = 80,
    }

    opts.sources.providers.ha_integrations = {
      name = "Home Assistant Integrations",
      module = "ha.completion.integrations",
      score_offset = 85,
    }
  end,
}
```

## Diagnostics

ha.nvim validates your YAML files against the live Home Assistant registry:

- **Entity validation** — Warns when an `entity_id` reference doesn't exist in the registry
- **Service validation** — Warns when a `service` call references an unknown domain
- **Numeric values ignored** — Float values like `0.5` are not mistaken for entity IDs

Diagnostics run automatically on:
- Buffer enter (`BufEnter`)
- File save (`BufWritePost`)
- Text changes (`TextChanged`, `TextChangedI`) — debounced (configurable)

Use `:Ha diagnostics run` to trigger manually, or `:Ha diagnostics clear` to dismiss.

## LSP

ha.nvim integrates with the [Home Assistant Language Server](https://github.com/keesschollaart81/vscode-home-assistant) for schema validation, hover documentation, and completion.

### Setup

The LSP is **disabled by default**. Toggle it with `<localleader>hL` or `:Ha lsp toggle`.

When enabled, the server is auto-detected from:
1. Configured `lsp.server_path`
2. Mason installation (`home-assistant-language-server`)
3. Legacy locations

### Mason Auto-Install

ha.nvim bundles a Mason registry for the Home Assistant Language Server. This pulls [vscode-home-assistant](https://github.com/keesschollaart81/vscode-home-assistant) from GitHub and builds it locally.

**Requirements:**
- **Node.js** — Required for building and running the language server
- **npm** — Comes with Node.js

Add the registry to your Mason configuration:

```lua
{
  "williamboman/mason.nvim",
  opts = {
    registries = {
      "lua:ha.mason-registry",  -- Bundled with ha.nvim
      "github:mason-org/mason-registry",
    },
  },
}
```

Then enable auto-install in ha.nvim:

```lua
lsp = {
  enabled = true,
  dynamic = {
    enabled = true,
    auto_install = true,
  },
}
```

## Entity Hover

Press `K` with your cursor on an entity ID to see a floating window with:

- Friendly name and current state
- Unit of measurement
- Area and device information
- Platform
- All attributes
- Last changed timestamp

If the cursor is not on an entity ID, `K` falls back to standard LSP hover.

## Registry System

ha.nvim maintains an in-memory registry that mirrors your Home Assistant instance:

- **Areas** — All defined areas/rooms
- **Devices** — All registered devices with manufacturer, model info
- **Entities** — All entities enriched with device names, area resolution, and current state
- **Integrations** — All installed integrations

The registry is populated via WebSocket on first use and kept up-to-date with real-time subscriptions for state changes and registry updates.

## Statusline

Add the HA connection status to your statusline. With lualine:

```lua
{
  "nvim-lualine/lualine.nvim",
  opts = function(_, opts)
    table.insert(opts.sections.lualine_x, {
      function()
        return require("ha.ui.status").get_status_text()
      end,
      cond = function()
        return require("ha.utils").workspace.is_in_ha_environment()
      end,
    })
  end,
}
```

## Health Check

Run `:checkhealth ha` to verify:
- Plugin initialization
- Workspace detection
- Authentication status
- LSP client status
- Connection status
- Registry system
- Diagnostics system
- Dependencies

## Troubleshooting

### No completion items showing

1. Ensure you're in a Home Assistant workspace (check with `:Ha status`)
2. Verify authentication with `:Ha auth test`
3. Check that blink.cmp sources are registered
4. Entity completion triggers after a domain prefix (e.g., type `light.`)

### Connection issues

1. Ensure `websocat` is installed and in your PATH
2. Verify your HA URL is accessible
3. Check your access token is valid
4. Run `:checkhealth ha` for diagnostics

### Diagnostics false positives

- Float values (e.g., `0.5`) are automatically ignored
- If you see false warnings, check that your registry is initialized with `:Ha status`
- Use `:Ha diagnostics clear` to dismiss

## License

MIT License. See [LICENSE](LICENSE) for details.

## Contributing

Contributions are welcome! Please read the [Contributing Guide](CONTRIBUTING.md) before submitting a PR.

## Acknowledgments

- [Home Assistant](https://www.home-assistant.io/) — The amazing home automation platform
- [vscode-home-assistant](https://github.com/keesschollaart81/vscode-home-assistant) — Language server and inspiration
- [snacks.nvim](https://github.com/folke/snacks.nvim) — Beautiful picker UI
- [blink.cmp](https://github.com/saghen/blink.cmp) — Fast completion engine
