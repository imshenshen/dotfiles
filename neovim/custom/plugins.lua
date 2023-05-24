local cmp = require "cmp"
local on_attach = require("plugins.configs.lspconfig").on_attach
local capabilities = require("plugins.configs.lspconfig").capabilities


local plugins = {
  { "github/copilot.vim" , lazy = false },
  {
    "hrsh7th/nvim-cmp",
    opts = {
      mapping = {
        -- https://github.com/hrsh7th/nvim-cmp/wiki/Example-mappings#intellij-like-mapping
        ["<Tab>"] = cmp.mapping(function(fallback)
          if cmp.visible() then
            local entry = cmp.get_selected_entry()
            if not entry then
              cmp.select_next_item({ behavior = cmp.SelectBehavior.Select })
            else
              cmp.confirm()
            end
          elseif require("luasnip").expand_or_jumpable() then
            vim.fn.feedkeys(vim.api.nvim_replace_termcodes("<Plug>luasnip-expand-or-jump", true, true, true), "")
          else
            fallback()
          end
        end, {
            "i",
            "s",
          }),

      }
    }
  },
  -- lsp configs
  {
    "neovim/nvim-lspconfig",
    dependencies = {
      "williamboman/mason-lspconfig.nvim"
    }
  },
  {
    "williamboman/mason-lspconfig.nvim",
    cmd = { "LspInstall", "LspUninstall" },
    dependencies = {
      "williamboman/mason.nvim"
    },
    opts = {
      -- use lspconfig name : https://github.com/williamboman/mason-lspconfig.nvim/blob/main/doc/server-mapping.md
      ensure_installed = {
        "html",
        "jsonls",
        "eslint",
        "rust_analyzer",
        "svelte",
        "tsserver",
        "vuels",
        "dockerls",
        "jdtls",
        "gopls"
      },
      handlers = {
        function (server_name) -- default handler (optional)
          require("lspconfig")[server_name].setup {
            on_attach = on_attach,
            capabilities = capabilities
          }
        end
      }
    }
  }
}

return plugins
