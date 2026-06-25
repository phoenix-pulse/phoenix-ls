# Phoenix Pulse

**Intelligent IDE tooling for Phoenix LiveView development** - Available for VS Code and Neovim

This is the `phoenix-ls` monorepo containing the Phoenix Pulse Language Server and editor extensions.

## 📦 Packages

### [`@phoenix-pulse/language-server`](./packages/language-server/)
The core Language Server Protocol (LSP) server providing intelligent features for Phoenix LiveView development.

- 🧩 Component completions with attributes and slots
- 📊 Schema completions with association drill-down
- 🛣️ Route completions for verified routes
- ⚡ Event completions for LiveView events
- 🔍 Diagnostics for invalid attributes and values
- 📖 Hover documentation
- 🎯 Go-to-definition support

**Published to npm:** `@phoenix-pulse/language-server`

### [VS Code Extension](./packages/vscode-extension/)
Full-featured VS Code extension for Phoenix LiveView development.

- All LSP features
- 📦 Project Explorer (TreeView)
- 📊 ERD Diagram viewer
- 🎨 Syntax highlighting for HEEx templates

**Install from:** [VS Code Marketplace](https://marketplace.visualstudio.com/items?itemName=onsever.phoenix-pulse)

### [Neovim Plugin](./packages/nvim-plugin/)
Complete Neovim plugin using the same LSP server as VS Code.

- All LSP features
- 📦 Project Explorer (Float/Split)
- 📊 ERD Diagram viewer
- 🔍 Search/filter functionality
- 📋 Context-aware copy commands

**Install:** See [NEOVIM.md](./NEOVIM.md) for complete installation guide

---

## 🚀 Installation

### VS Code

**From Marketplace (Recommended):**
1. Open VS Code
2. Press `Ctrl+Shift+X` (or `Cmd+Shift+X` on Mac)
3. Search for **"Phoenix Pulse"**
4. Click **Install**

**Or via command line:**
```bash
code --install-extension onsever.phoenix-pulse
```

**Manual Installation (.vsix):**
```bash
# Download .vsix from releases
code --install-extension phoenix-pulse-1.3.0.vsix
```

### Neovim

**Using lazy.nvim:**
```lua
{
  "phoenix-pulse/phoenix-ls",
  dir = "packages/nvim-plugin",
  build = "./install-lsp.sh",  -- Builds or verifies the Phoenix LS executable
  dependencies = { "neovim/nvim-lspconfig" },
  ft = { "elixir", "heex", "eelixir" },
  config = function()
    require("phoenix-pulse").setup()
  end,
}
```

**Using packer.nvim:**
```lua
use {
  "phoenix-pulse/phoenix-ls",
  run = "cd packages/nvim-plugin && ./install-lsp.sh",
  config = function()
    require("phoenix-pulse").setup()
  end,
}
```

**Using vim-plug:**
```vim
Plug 'phoenix-pulse/phoenix-ls', {'do': 'cd packages/nvim-plugin && ./install-lsp.sh'}
```

See [NEOVIM.md](./NEOVIM.md) for complete installation and configuration details.

---

## 📋 Requirements

- **VS Code**: 1.75.0 or higher
- **Neovim**: 0.8.0 or higher (for Neovim users)
- **Phoenix**: 1.6+ or 1.7+ project
- **Node.js**: 16+ (for workspace development tooling)
- **Elixir/Mix**: 1.17+ when building the local Phoenix LS executable from source

---

## 🚀 Quick Start

### For Developers

**Clone and Setup:**
```bash
git clone https://github.com/phoenix-pulse/phoenix-ls
cd phoenix-ls
npm install              # Installs all workspace packages
npm run compile          # Builds language-server + vscode-extension
```

**Development Commands:**
```bash
# Compile everything
npm run compile

# Compile specific package
npm run compile:lsp
npm run compile:vscode

# Watch mode (auto-recompile on changes)
npm run watch:lsp
npm run watch:vscode

# Run tests
npm test

# Clean build artifacts
npm run clean
```

**Test VS Code Extension:**
```bash
cd packages/vscode-extension
npm run compile
npm run package         # Creates .vsix file
code --install-extension phoenix-pulse-*.vsix
```

**Test Neovim Plugin:**
```bash
# Install or update the Phoenix LS executable for Neovim
cd packages/nvim-plugin
./install-lsp.sh  # or: npm run update-lsp

# Add to your Neovim config (pointing to local directory)
{
  dir = "~/phoenix-ls/packages/nvim-plugin",
  config = function()
    require("phoenix-pulse").setup()
  end,
}
```

---

## 📖 Documentation

- [NEOVIM.md](./NEOVIM.md) - Complete Neovim plugin documentation
- [CONTRIBUTING.md](./CONTRIBUTING.md) - Contribution guidelines
- **VS Code Extension:** Full documentation on [VS Code Marketplace](https://marketplace.visualstudio.com/items?itemName=onsever.phoenix-pulse)

---

## 🏗️ Repository Structure

```
phoenix-ls/
├── packages/
│   ├── language-server/          # @phoenix-pulse/language-server
│   │   ├── src/                   # TypeScript source
│   │   ├── dist/                  # Compiled output
│   │   ├── elixir-parser/         # Elixir AST parsers
│   │   └── package.json
│   │
│   ├── vscode-extension/          # VS Code extension
│   │   ├── src/                   # Extension source
│   │   ├── syntaxes/              # HEEx grammar
│   │   ├── images/                # Icons
│   │   └── package.json
│   │
│   └── nvim-plugin/               # Neovim plugin
│       ├── lua/phoenix-pulse/     # Lua modules
│       ├── plugin/                # Plugin entry point
│       ├── doc/                   # Vim help docs
│       └── install-lsp.sh         # LSP installer script
│
├── package.json                   # Root workspace config
├── README.md                      # This file
├── NEOVIM.md                      # Neovim documentation
├── CONTRIBUTING.md                # Contribution guidelines
└── LICENSE                        # MIT License
```

---

## 🔄 Workflow

### Updating the Language Server

```bash
# 1. Make changes to language-server
cd packages/language-server
# ... edit src/ files ...
npm run compile

# 2. Test in VS Code
cd ../vscode-extension
npm run compile
code .  # Press F5 to launch Extension Development Host

# 3. Test in Neovim
cd ../nvim-plugin
./install-lsp.sh
nvim /path/to/phoenix/project
```

### Publishing

**Language Server to npm:**
```bash
cd packages/language-server
npm version patch  # or minor, major
npm run compile
npm publish
```

**VS Code Extension to Marketplace:**
```bash
cd packages/vscode-extension
npm version patch
npm run package
npm run publish
```

**Neovim Plugin:**
```bash
# Users install via plugin manager from GitHub
# No separate publishing needed
git tag nvim-v0.X.X
git push --tags
```

---

## 🤝 Contributing

We welcome contributions! See [CONTRIBUTING.md](./CONTRIBUTING.md) for guidelines.

**Areas to contribute:**
- 🐛 Bug fixes
- ✨ New features
- 📖 Documentation improvements
- 🧪 Tests

---

## 📊 Status

| Package | Version | Status |
|---------|---------|--------|
| Language Server | 1.0.0 | ✅ Published to npm |
| VS Code Extension | 1.3.0 | ✅ Ready to publish |
| Neovim Plugin | 1.0.0 | ✅ Stable |

---

## 📝 License

MIT - See [LICENSE](./LICENSE)

---

## 🙏 Credits

Created by [Onurcan Sever](https://github.com/onsever)

Special thanks to all contributors and the Phoenix/Elixir community!

---

## 🔗 Links

- **GitHub:** https://github.com/phoenix-pulse/phoenix-ls
- **Organization:** https://github.com/phoenix-pulse
- **VS Code Marketplace:** https://marketplace.visualstudio.com/items?itemName=onsever.phoenix-pulse
- **Issues:** https://github.com/phoenix-pulse/phoenix-ls/issues
- **npm:** https://www.npmjs.com/package/@phoenix-pulse/language-server
