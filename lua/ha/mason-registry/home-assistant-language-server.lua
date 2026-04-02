-- Home Assistant Language Server - simplified to use npm scripts correctly

return {
  name = "home-assistant-language-server",
  description = "Home Assistant Language Server for YAML configuration files with entity completion, validation, and documentation.",
  categories = { "LSP" },
  homepage = "https://github.com/keesschollaart81/vscode-home-assistant",
  languages = { "YAML" },
  licenses = { "MIT" },

  source = {
    id = "pkg:github/keesschollaart81/vscode-home-assistant@master",
    build = {
      run = "npm install && npm run schema && npm run compile",
      -- env = {
      --   NODE_ENV = "production",
      -- },
    },
  },

  bin = {
    ["home-assistant-language-server"] = "out/server/server.js",
  },
}
