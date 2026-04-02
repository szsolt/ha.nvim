-- AstroNvim configuration for ha.nvim
-- Copy this file to your AstroNvim plugins directory (e.g., lua/plugins/home-assistant.lua)

---@type LazySpec
return {
  -- Core Home Assistant plugin
  {
    "szsolt/ha.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "saghen/blink.cmp",
      "folke/snacks.nvim",
      {
        "samsze0/websocket.nvim",
        dependencies = { "samsze0/utils.nvim" },
      },
      -- Mason with HA registry - lazy.nvim merges opts automatically
      {
        "williamboman/mason.nvim",
        opts = {
          registries = {
            "lua:ha.mason-registry", -- HA Language Server (bundled with ha.nvim)
            "github:mason-org/mason-registry",
          },
        },
      },
    },
    ft = { "yaml", "home-assistant" },
    cmd = { "Ha" },
    event = "VeryLazy",
    opts = {
      log_level = "info",
      lsp = {
        enabled = false, -- Toggle with <localleader>hL
        auto_setup = true,
      },
      auth = {
        auto_migrate = true,
        storage_file = "ha_credentials",
      },
      ui = {
        statusline = { enabled = true },
        notifications = { enabled = true, timeout = 5000 },
      },
      completion = {
        enabled = true,
        sources = {
          ha_domains = { enabled = true, priority = 110 },
          ha_entities = { enabled = true, priority = 100 },
          ha_services = { enabled = true, priority = 90 },
          ha_mdi_icons = { enabled = true, priority = 80 },
        },
      },
    },
    config = function(_, opts) require("ha").setup(opts) end,
  },

  -- AstroCore integration for keymaps
  {
    "AstroNvim/astrocore",
    optional = true,
    ---@type AstroCoreOpts
    opts = {
      mappings = {
        n = {
          ["<localleader>h"] = { desc = "󰟢 Home Assistant" },
          ["<localleader>ha"] = { "<Cmd>Ha auth setup<CR>", desc = "Setup Authentication" },
          ["<localleader>ht"] = { "<Cmd>Ha template<CR>", desc = "Render Template" },
          ["<localleader>hr"] = { "<Cmd>Ha reload list<CR>", desc = "Reload Services" },
          ["<localleader>hR"] = { "<Cmd>Ha restart<CR>", desc = "Restart HA" },
          ["<localleader>ho"] = { "<Cmd>Ha open<CR>", desc = "Open in Browser" },
          ["<localleader>hs"] = { "<Cmd>Ha status<CR>", desc = "Show Status" },
          ["<localleader>hl"] = { "<Cmd>Ha log show<CR>", desc = "Show Error Log" },
          ["<localleader>he"] = { "<Cmd>Ha entities<CR>", desc = "Entity Picker" },
          ["<localleader>hS"] = { "<Cmd>Ha services<CR>", desc = "Service Picker" },
          ["<localleader>hi"] = { "<Cmd>Ha integrations<CR>", desc = "Integration Picker" },
          ["<localleader>hd"] = { "<Cmd>Ha diagnostics run<CR>", desc = "Run Diagnostics" },
          ["<localleader>hD"] = { "<Cmd>Ha diagnostics clear<CR>", desc = "Clear Diagnostics" },
          ["<localleader>hL"] = { "<Cmd>Ha lsp toggle<CR>", desc = "Toggle HA LSP" },
          ["K"] = {
            function()
              local utils = require "ha.utils"
              if not utils.workspace.is_in_ha_environment() then
                vim.lsp.buf.hover()
                return
              end
              local ok, commands = pcall(require, "ha.commands")
              if ok then
                local entity_id = commands.get_entity_under_cursor()
                if entity_id then
                  require("ha.lsp").show_entity_hover(entity_id)
                  return
                end
              end
              vim.lsp.buf.hover()
            end,
            desc = "Hover (HA entity or LSP)",
          },
        },
        v = {
          ["<localleader>ht"] = { "<Cmd>Ha template<CR>", desc = "Render Template" },
        },
      },
      autocmds = {
        home_assistant_filetype = {
          {
            event = { "BufRead", "BufNewFile" },
            pattern = {
              "configuration.yaml",
              "automations.yaml",
              "scripts.yaml",
              "scenes.yaml",
              "groups.yaml",
              "customize.yaml",
              "lovelace.yaml",
              "ui-lovelace.yaml",
              "secrets.yaml",
              "*/automations/*.yaml",
              "*/scripts/*.yaml",
              "*/scenes/*.yaml",
            },
            callback = function(args) vim.bo[args.buf].filetype = "home-assistant" end,
            desc = "Set Home Assistant filetype for HA config files",
          },
        },
      },
    },
  },

  -- Lualine statusline integration
  {
    "nvim-lualine/lualine.nvim",
    optional = true,
    opts = function(_, opts)
      local ha_status = {
        function()
          local ok, status = pcall(require, "ha.ui.status")
          if ok then return status.get_status_text() end
          return ""
        end,
        cond = function()
          local ok, utils = pcall(require, "ha.utils")
          if ok then return utils.workspace.is_in_ha_environment() end
          return false
        end,
      }
      if not opts.sections then opts.sections = {} end
      if not opts.sections.lualine_x then opts.sections.lualine_x = {} end
      table.insert(opts.sections.lualine_x, ha_status)
    end,
  },

  -- Blink completion integration
  {
    "saghen/blink.cmp",
    optional = true,
    opts = function(_, opts)
      if not opts.sources then opts.sources = {} end
      if not opts.sources.default then opts.sources.default = {} end
      if not opts.sources.providers then opts.sources.providers = {} end

      vim.list_extend(opts.sources.default, {
        "ha_domains", "ha_entities", "ha_services", "ha_integrations", "ha_mdi_icons"
      })

      opts.sources.providers.ha_domains = {
        name = "Home Assistant Domains",
        module = "ha.completion.domains",
        score_offset = 110,
      }
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
      opts.sources.providers.ha_integrations = {
        name = "Home Assistant Integrations",
        module = "ha.completion.integrations",
        score_offset = 85,
      }
      opts.sources.providers.ha_mdi_icons = {
        name = "Home Assistant MDI Icons",
        module = "ha.completion.mdi",
        score_offset = 80,
      }
      return opts
    end,
  },

  -- Which-key integration
  {
    "folke/which-key.nvim",
    optional = true,
    opts = function(_, opts)
      if not opts.spec then opts.spec = {} end
      opts.spec[#opts.spec + 1] = {
        { "<localleader>h", group = "󰟢 Home Assistant", mode = { "n", "v" } },
      }
    end,
  },
}
