# Contributing to ha.nvim

Thank you for your interest in contributing! This guide covers what you need to get started.

## Getting Started

1. Fork the repository
2. Clone your fork locally
3. Create a branch (`feat/…`, `fix/…`, or `docs/…`)
4. Make your changes
5. Submit a pull request

## Development Setup

1. Clone and point your plugin manager to the local copy:

```lua
-- lazy.nvim
{
  "ha.nvim",
  dir = "/path/to/ha.nvim",
}
```

2. Set `log_level = "debug"` for verbose output.

3. You need a running Home Assistant instance and a Long-Lived Access Token for testing. Run `:Ha auth setup` to configure.

4. Run `:checkhealth ha` to verify everything works.

## Project Structure

See [ARCHITECTURE.md](ARCHITECTURE.md) for a full breakdown.

The key directories are:

- `lua/ha/api/` — WebSocket and REST communication
- `lua/ha/auth/` — Credential management
- `lua/ha/commands/` — `:Ha` command tree
- `lua/ha/completion/` — blink.cmp completion sources
- `lua/ha/config/` — Default configuration and merging
- `lua/ha/diagnostics/` — Inline YAML validation
- `lua/ha/lsp/` — Language Server integration
- `lua/ha/ui/` — Pickers, statusline, progress, formatting
- `lua/ha/utils/` — Logger, registry, workspace detection, cache

When adding a feature, look at an existing module of the same type first. The patterns are consistent across the codebase.

## Code Style

- **2-space indentation**, `local` for all declarations
- **LuaDoc annotations** on all public functions (`---@param`, `---@return`)
- **Module pattern**: `local M = {} … return M`
- **Naming**: `snake_case` for files and functions, `UPPER_SNAKE_CASE` for constants, `_` prefix for private functions
- **Error handling**: `pcall` for external calls, `vim.notify` for user-facing messages, `utils.logger` for debug output
- **Early returns** over deep nesting

## Making Changes

### Bug Fixes

- Identify the root cause, not just the symptom
- Prefer minimal fixes — a single-line change is better than a refactor
- Describe the bug and the fix clearly in your PR

### New Features

- Check existing modules for patterns before writing from scratch
- Add a command in `commands/init.lua` if the feature is user-facing
- Add a keymap entry if appropriate
- Update the health check if the feature has dependencies
- Update README.md and lua/ha/doc/ha.txt

## Testing

There is no automated test suite yet — this is a great area to contribute!

For now, manually verify:

1. `:checkhealth ha` passes
2. Existing features still work (completion, pickers, diagnostics, hover)
3. Your change works in both HA workspace and non-HA workspace contexts

## Commit Messages

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add device picker with area grouping
fix: prevent infinite loop in entity picker filter reset
docs: update README with diagnostics section
refactor: extract shared formatting utilities
```

## Pull Requests

- **One concern per PR** — don't mix bug fixes with new features
- **Describe what and why** in the PR description
- **Include screenshots** for UI changes (pickers, hover, statusline)
- **Note breaking changes** explicitly

## Reporting Issues

When filing a bug report, include:

- Neovim version (`:version`)
- Output of `:checkhealth ha`
- Steps to reproduce
- Expected vs actual behavior
- Relevant log output (`log_level = "debug"`)

## Code of Conduct

This project follows the [Contributor Covenant](https://www.contributor-covenant.org/version/2/1/code_of_conduct/). Be kind and constructive.
