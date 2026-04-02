# ha.nvim Architecture

This document describes the internal architecture of ha.nvim for developers working on the codebase. For user-facing documentation, see [README.md](README.md).

## Directory Structure

```
lua/ha/
├── init.lua                  # Plugin lifecycle, health check
├── api/
│   └── init.lua              # WebSocket (websocat) + REST API
├── auth/
│   └── init.lua              # Encrypted credential storage, VS Code migration
├── commands/
│   └── init.lua              # :Ha command tree, dispatch, all command handlers
├── completion/
│   ├── init.lua              # Completion source registration
│   ├── domains.lua           # Domain completion (from registry)
│   ├── entities.lua          # Entity ID completion (domain-aware)
│   ├── integrations.lua      # Integration domain completion
│   ├── mdi.lua               # MDI icon completion (mdi: prefix)
│   └── services.lua          # Service completion (domain.service)
├── config/
│   └── init.lua              # Default config, deep merge, dot-notation access
├── diagnostics/
│   └── init.lua              # Inline validation of entity_ids and services
├── lsp/
│   ├── init.lua              # HA Language Server setup, hover, toggle
│   └── handlers.lua          # Custom LSP notification handlers
├── ui/
│   ├── init.lua              # Output channels, floating windows
│   ├── formatting.lua        # Value formatting for previews and docs
│   ├── progress_renderer.lua # Spinner animation for async operations
│   ├── status.lua            # Statusline component (lualine)
│   ├── picker.lua            # Legacy picker (deprecated, kept for compat)
│   └── picker/
│       ├── init.lua          # Picker module re-exports
│       ├── core.lua          # Shared picker config, preview, format helpers
│       ├── actions.lua       # Reusable insertion action (C-s), extractors
│       ├── area.lua          # Area picker
│       ├── entity.lua        # Entity picker (filtering, auto-detect)
│       ├── integration.lua   # Integration picker
│       ├── reload.lua        # Reload options picker
│       └── service.lua       # Service picker (field docs, targets)
└── utils/
    ├── init.lua              # Re-exports, debounce helper
    ├── cache.lua             # Generic TTL cache
    ├── logger.lua            # Leveled logging to file
    ├── progress.lua          # Request progress tracking
    ├── registry.lua          # Entity/device/area/integration registry
    └── workspace.lua         # HA workspace detection heuristics
```

## Core Concepts

### Startup Sequence

`init.lua:setup()` orchestrates initialization:

1. Config merge (user opts → defaults)
2. Logger init
3. Workspace detection
4. Auth credential loading (with optional VS Code migration)
5. UI setup (statusline, output channels)
6. Completion source registration
7. Command tree registration (`:Ha` prefix)
8. Diagnostics autocommand setup
9. LSP setup (if enabled)

### WebSocket Connection (`api/`)

The API module manages the entire WebSocket lifecycle:

- **Process management** — spawns `websocat` as a child process via `vim.loop`
- **Auth handshake** — `auth_required → auth(token) → auth_ok`
- **Message correlation** — each request gets a unique `id`; responses are matched back via callbacks
- **Queue** — messages sent before connection is ready are queued and flushed after auth
- **Subscriptions** — event subscriptions (`subscribe_events`, `subscribe_trigger`) return subscription IDs for cleanup
- **Reconnection** — not currently automatic; user must reconnect via commands

### Registry (`utils/registry.lua`)

The registry is the central data store. Everything that shows HA data reads from it.

**Initialization:**
1. Fetches area, device, entity registries and state list in parallel
2. Enriches each entity with `device_name`, resolved `area_id`, current `state` and `attributes`
3. Subscribes to WebSocket events for real-time updates

**Consumers:**
- `completion/` — entity IDs, domains, services
- `ui/picker/` — all picker data
- `diagnostics/` — validation of entity_ids and services
- `lsp/` — entity hover

**Key design decisions:**
- Entities are indexed by `entity_id` for O(1) lookup
- Device/area resolution is done eagerly at init, not per-query
- The `get_entity()` function returns enriched data (state + registry + device + area)

### Command System (`commands/`)

Commands use a tree structure for hierarchical dispatch:

```
commands_tree.children = {
  auth = { children = { setup, test, clear, show } },
  entities = { callback = ... },
  services = { callback = ... },
  diagnostics = { children = { run, clear, refresh, stats } },
  lsp = { children = { toggle, stop, start, restart, status } },
  ...
}
```

The `dispatch()` function walks the tree based on `:Ha arg1 arg2 ...` arguments. Tab completion is generated from the tree structure.

### Completion (`completion/`)

Each source implements the blink.cmp interface:
- `new()` — constructor
- `enabled()` — context check (HA workspace? registry ready?)
- `get_completions(context, callback)` — async item generation

Entity completion is domain-aware: typing `light.` only shows light entities. All sources use registry data directly (no separate cache).

### Picker System (`ui/picker/`)

Pickers are built on snacks.nvim. The `core.lua` module provides shared helpers:
- `create_preview_function()` — wraps a generator into snacks preview format
- `create_format_function()` — standardized item display with availability dimming
- `create_confirm_function()` — extracts data from selection and invokes callback

The `actions.lua` module provides the `<C-s>` insertion action, reusable across all picker types. Each picker defines its own items, preview generator, and filter keybindings.

**Entity picker specifics:**
- Filters: domain, area, platform, device class, availability
- Auto-detects entity under cursor and focuses it
- If target entity is filtered out: resets filters → retries with unavailable shown → gives up gracefully (no infinite loop)

### Diagnostics (`diagnostics/`)

Uses `vim.diagnostic` with a dedicated namespace (`ha_diagnostics`).

**Validation pipeline:**
1. Extract entity refs and service refs from buffer lines via regex patterns
2. Skip comments, numeric values (e.g., `0.5`), and system domains
3. Validate each ref against the live registry
4. Deduplicate by `line:col:message` key
5. Set diagnostics via `vim.diagnostic.set()`

Runs on `BufEnter`, `BufWritePost`, and optionally on text change (debounced).

### LSP (`lsp/`)

Integrates the Home Assistant Language Server (VS Code extension's server).

- **Disabled by default** — toggled via `:Ha lsp toggle` or `<localleader>hL`
- **Server detection** — configured path → Mason → legacy locations
- **Auth forwarding** — sends credentials via `workspace/didChangeConfiguration`
- **Entity hover** — `show_entity_hover()` renders entity state/attributes in a floating window; used by the `K` keymap override

### Formatting (`ui/formatting.lua`)

Shared formatting used by pickers, hover, and completion docs:
- `format_value_for_docs()` — recursively formats Lua values (tables, arrays, key-value pairs) into markdown, with truncation
- `format_value_for_services()` — same but without truncation (service field docs need full content)
- `format_selector_type()` — converts HA service field selectors into human-readable type descriptions
- `generate_entity_preview()` — full entity preview for picker sidebar

## Data Flow

```
User Action (command / completion trigger / keymap)
        │
        ▼
  commands/init.lua  ─────────────────────┐
        │                                  │
        ▼                                  ▼
  api/init.lua (WebSocket/REST)      ui/picker/ (interactive)
        │                                  │
        ▼                                  │
  Home Assistant Instance                  │
        │                                  │
        ▼                                  │
  utils/registry.lua  ◄───────────────────┘
  (enriched entity/device/area data)
        │
        ├──► completion/  (blink.cmp items)
        ├──► diagnostics/ (validation)
        ├──► lsp/         (entity hover)
        └──► ui/picker/   (picker items + preview)
```

## Key Patterns

### Error Handling
- `pcall` for all external/optional module loads
- `vim.notify` for user-facing messages
- `utils.logger` for debug/trace output (written to log file)
- Never silently swallow errors

### Lazy Loading
- Registry is lazy-loaded via `utils/init.lua` to avoid circular dependencies
- LSP module only activates when explicitly enabled
- Completion sources check `enabled()` before doing any work

### Deduplication
- Diagnostics use a `seen` table keyed by `line:col:message`
- Registry updates replace existing entries by ID rather than appending

## Future Work

### High Priority
- **Entity state actions in picker** — toggle lights, set values directly from picker
- **Automation/script execution** — `:Ha run automation.<id>`, picker trigger action
- **Device picker** — browse entities grouped by device

### Medium Priority
- **Entity history** — `:Ha history <entity_id>` with timeline view
- **Dashboard/Lovelace support** — card type completion, schema validation
- **Secrets management** — `!secret` reference completion and validation
- **Smart service field completion** — domain-aware entity suggestions for target fields
- **Automated test suite** — plenary test harness or busted

### Low Priority
- **Blueprint support** — input completion and schema validation
- **Event subscription UI** — live event stream viewer
- **Config entry management** — view/reload integration config entries
- **Offline mode** — cache last-known registry, graceful degradation
