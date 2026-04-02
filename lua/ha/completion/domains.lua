-- Home Assistant Domain completion source for blink.cmp
-- Provides domain completion when typing 2-3+ characters

local utils = require "ha.utils"
local auth = require "ha.auth"
local registry = require "ha.utils.registry"

local M = {}

---Create new source instance
function M.new() return setmetatable({}, { __index = M }) end

---Check if this source should be enabled
function M:enabled() 
  local has_creds = auth.has_credentials()
  local is_ha_file = utils.workspace.is_ha_file()
  local should_trigger = self:_should_trigger_domain_completion()
  local enabled = has_creds and is_ha_file and should_trigger
  
  utils.logger.debug("Domain completion enabled check - has_creds: " .. tostring(has_creds) .. ", is_ha_file: " .. tostring(is_ha_file) .. ", should_trigger: " .. tostring(should_trigger) .. ", enabled: " .. tostring(enabled))
  
  return enabled
end

---Get completion items
function M:get_completions(context, callback)
  utils.logger.debug("=== Domain completion get_completions called ===")
  utils.logger.debug("Context: " .. vim.inspect(context))
  
  if not self:enabled() then
    utils.logger.debug("Domain completion not enabled")
    callback { items = {} }
    return
  end

  -- Debug logging
  utils.logger.debug("Domain completion enabled, proceeding...")

  -- Check if we should trigger domain completion  
  local current_word = self:_get_current_word(context)
  utils.logger.debug("Current word: " .. tostring(current_word))
  
  if not current_word or #current_word < 2 then  -- Reduced to 2 characters
    utils.logger.debug("Word too short or missing: " .. tostring(current_word) .. " (length: " .. (current_word and #current_word or 0) .. ")")
    callback { items = {} }
    return
  end

  -- Get available domains from registry
  local domains = registry.get_available_domains()
  utils.logger.debug("Available domains: " .. vim.inspect(domains))
  
  local items = {}

  for _, domain in ipairs(domains) do
    -- Check if domain matches the typed prefix
    if domain:lower():sub(1, #current_word) == current_word:lower() then
      local item = {
        label = domain,
        kind = require("blink.cmp.types").CompletionItemKind.Module,
        detail = "Home Assistant domain",
        documentation = {
          kind = "markdown", 
          value = self:_get_domain_documentation(domain),
        },
        insertText = domain,
        filterText = domain,
        sortText = domain,
        data = {
          source = "ha_domains",
          domain = domain,
        },
      }
      table.insert(items, item)
      utils.logger.debug("Added domain completion: " .. domain)
    end
  end

  utils.logger.debug("Domain completion items: " .. #items)
  callback { items = items }
end

---Resolve completion item
function M:resolve(item, callback) callback(item) end

---Get trigger characters
function M:get_trigger_characters() return {} end

---Get the current word being typed
---@param context table|nil Completion context from blink.cmp
---@return string|nil Current word prefix
function M:_get_current_word(context)
  local line, col
  
  if context and context.line and context.cursor then
    -- Use context from blink.cmp
    line = context.line
    col = context.cursor[2] 
    utils.logger.debug("Using blink context - line: '" .. line .. "', cursor: " .. vim.inspect(context.cursor))
  else
    -- Fallback to API calls
    line = vim.api.nvim_get_current_line()
    col = vim.api.nvim_win_get_cursor(0)[2]
    utils.logger.debug("Using API fallback - line: '" .. line .. "', col: " .. col)
  end
  
  local text_before_cursor = line:sub(1, col)
  
  -- Extract word being typed (alphanumeric and underscore)
  local current_word = text_before_cursor:match("([%w_]+)$")
  utils.logger.debug("Extracted word: '" .. tostring(current_word) .. "' from text: '" .. text_before_cursor .. "'")
  return current_word
end

---Get documentation for a domain
---@param domain string Domain name
---@return string Formatted documentation
function M:_get_domain_documentation(domain)
  -- Get entity count for this domain
  local entities = registry.get_all_entities()
  local domain_entities = 0
  local sample_entities = {}
  
  for _, entity in ipairs(entities) do
    local entity_domain = entity.entity_id:match("^([^%.]+)%.")
    if entity_domain == domain then
      domain_entities = domain_entities + 1
      if #sample_entities < 3 then
        table.insert(sample_entities, entity.entity_id)
      end
    end
  end

  local docs = {}
  table.insert(docs, "**Domain:** `" .. domain .. "`")
  table.insert(docs, "**Entities:** " .. domain_entities .. " entities")
  
  if #sample_entities > 0 then
    table.insert(docs, "**Examples:** `" .. table.concat(sample_entities, "`, `") .. "`")
  end

  return table.concat(docs, "\n")
end

---Check if we should trigger domain completion based on context
---@return boolean True if domain completion should be triggered
function M:_should_trigger_domain_completion()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2]
  local text_before_cursor = line:sub(1, col)
  
  -- Extract current word being typed
  local current_word = text_before_cursor:match("([%w_]+)$")
  
  utils.logger.debug("Domain trigger check - line: '" .. line .. "', text_before: '" .. text_before_cursor .. "', word: '" .. tostring(current_word) .. "'")
  
  -- Trigger if we have 2+ characters that could be a domain
  if current_word and #current_word >= 2 then
    -- Quick check - does this look like it could be a domain?
    -- Most HA domains are alphabetic with optional underscores
    if current_word:match("^[%w_]+$") then
      utils.logger.debug("Domain completion should trigger for word: " .. current_word)
      return true
    end
  end
  
  utils.logger.debug("Domain completion should NOT trigger")
  return false
end

return M