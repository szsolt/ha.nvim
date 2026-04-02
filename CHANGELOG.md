# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - Unreleased

### Added

- **WebSocket API** — Real-time connection to Home Assistant via `websocat`
- **Authentication** — Encrypted credential storage with VS Code migration
- **Completion sources** — Entity, service, domain, integration, and MDI icon completion via blink.cmp
- **Entity picker** — Interactive picker with domain, area, platform, and device class filtering
- **Service picker** — Browse services with field documentation and type info
- **Integration picker** — Browse installed integrations
- **Reload picker** — Quick access to reload automations, scripts, scenes, etc.
- **Inline diagnostics** — Validates entity IDs and service calls against live registry
- **Entity hover** — Press `K` on entity IDs to see state, attributes, area, and device info
- **LSP integration** — Optional Home Assistant Language Server with Mason auto-install
- **Template rendering** — Render Jinja2 templates with output channel
- **Registry system** — In-memory cache with real-time WebSocket updates
- **Statusline** — Connection status indicator for lualine
- **Workspace detection** — Auto-activates for HA configuration directories
- **Keymaps** — Full keymap set under `<localleader>h` prefix
- **Health check** — `:checkhealth ha` for diagnostics
- **Commands** — Comprehensive `:Ha` command tree with tab completion
- **Buffer insertion** — `<C-s>` in any picker to insert selected items at cursor
