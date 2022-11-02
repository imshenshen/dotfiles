local present, masonlspconfig = pcall(require, "mason-lspconfig")

if not present then
  return
end

local utils = require "core.utils"

local M = {}

M.on_attach = function(client, bufnr)
  client.server_capabilities.documentFormattingProvider = false
  client.server_capabilities.documentRangeFormattingProvider = false

  utils.load_mappings("lspconfig", { buffer = bufnr })

  if client.server_capabilities.signatureHelpProvider then
    require("nvchad_ui.signature").setup(client)
  end
end

M.capabilities = vim.lsp.protocol.make_client_capabilities()

M.capabilities.textDocument.completion.completionItem = {
  documentationFormat = { "markdown", "plaintext" },
  snippetSupport = true,
  preselectSupport = true,
  insertReplaceSupport = true,
  labelDetailsSupport = true,
  deprecatedSupport = true,
  commitCharactersSupport = true,
  tagSupport = { valueSet = { 1 } },
  resolveSupport = {
    properties = {
      "documentation",
      "detail",
      "additionalTextEdits",
    },
  },
}

masonlspconfig.setup({
  ensure_installed = {
    "sumneko_lua",
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
})

masonlspconfig.setup_handlers {
  function (server_name) -- default handler (optional)
    require("lspconfig")[server_name].setup {
      on_attach = M.on_attach,
      capabilities = M.capabilities
    }
  end,
  ["sumneko_lua"] = function ()

    require("lspconfig").sumneko_lua.setup {
      on_attach = M.on_attach,
      capabilities = M.capabilities,

      settings = {
        Lua = {
          diagnostics = {
            globals = { "vim" },
          },
          workspace = {
            library = {
              [vim.fn.expand "$VIMRUNTIME/lua"] = true,
              [vim.fn.expand "$VIMRUNTIME/lua/vim/lsp"] = true,
            },
            maxPreload = 100000,
            preloadFileSize = 10000,
          },
        },
      },
    }
  end

}
