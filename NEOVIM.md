# Phoenix Pulse for Neovim

**Intelligent IDE tooling for Phoenix LiveView development in Neovim**

This is the complete Neovim plugin for Phoenix Pulse, providing all LSP features plus custom UI components including Project Explorer and ERD Diagram viewer.

---

## 📋 Requirements

- **Neovim**: 0.8.0 or higher (tested on 0.9 and 0.10)
- **Node.js**: 16+ (for Language Server)
- **Phoenix**: 1.6+ or 1.7+ project
- **nvim-lspconfig**: Required plugin
- **nvim-web-devicons**: Optional (recommended for icons)

---

## 📦 Installation

### Using lazy.nvim (Recommended)

```lua
{
  "phoenix-pulse/phoenix-ls",
  dir = "packages/nvim-plugin",
  build = "./install-lsp.sh",  -- Installs LSP from npm
  dependencies = {
    "neovim/nvim-lspconfig",
    "nvim-tree/nvim-web-devicons",  -- Optional but recommended
  },
  ft = { "elixir", "heex", "eelixir" },
  config = function()
    require("phoenix-pulse").setup()
  end,
}
```

### Using packer.nvim

```lua
use {
  "phoenix-pulse/phoenix-ls",
  run = "cd packages/nvim-plugin && ./install-lsp.sh",
  requires = {
    "neovim/nvim-lspconfig",
    "nvim-tree/nvim-web-devicons",
  },
  config = function()
    require("phoenix-pulse").setup()
  end,
}
```

### Using vim-plug

```vim
Plug 'neovim/nvim-lspconfig'
Plug 'nvim-tree/nvim-web-devicons'
Plug 'phoenix-pulse/phoenix-ls', {'do': 'cd packages/nvim-plugin && ./install-lsp.sh'}
```

Then in your `init.lua`:
```lua
require("phoenix-pulse").setup()
```

### Manual Installation

```bash
# Clone the repository
git clone https://github.com/phoenix-pulse/phoenix-ls ~/.config/nvim/pack/plugins/start/phoenix-ls

# Install LSP server
cd ~/.config/nvim/pack/plugins/start/phoenix-ls/packages/nvim-plugin
./install-lsp.sh
```

---

## ⚙️ Configuration

### Basic Setup

```lua
require("phoenix-pulse").setup()
```

### Advanced Configuration

```lua
require("phoenix-pulse").setup({
  -- Explorer mode: "float" (popup window) or "split" (sidebar)
  explorer_mode = "float",

  -- Auto-open ERD in browser
  auto_open_erd = true,

  -- Custom keybindings (set to false to disable)
  keybindings = {
    toggle_explorer = "<leader>pp",  -- Toggle Project Explorer
    show_erd = "<leader>pe",          -- Show ERD diagram
    refresh = "<leader>pr",           -- Refresh registries
  },

  -- Custom LSP server path (auto-detected if nil)
  lsp_server_path = nil,

  -- Float window configuration (if explorer_mode = "float")
  float_config = {
    width = 80,
    height = 30,
    border = "rounded",  -- "single", "double", "rounded", "solid", "shadow"
  },

  -- Split window configuration (if explorer_mode = "split")
  split_config = {
    width = 40,
    position = "left",  -- "left" or "right"
  },
})
```

---

## 🎯 Features

### LSP Features (Automatic)

Once installed, Phoenix Pulse provides:

#### Component Intelligence
- Type `<.` to see component completions
- Attribute completions with type information
- Slot completions (`<:slot_name>`)
- Go-to-definition with `gd` on component names
- Hover documentation with `K`

#### Schema-Aware Completions
- Type `@` in templates to see assigns
- Drill down: `@user.email`, `@post.author.name`
- Works in both `.heex` files and `~H` sigils

#### Route Completions
- Route helper completions
- Verified route path completions (`~p"/users"`)
- Go-to-definition on routes

#### Event Completions
- Event completions in `phx-click=""` attributes
- Shows available `handle_event` functions
- Go-to-definition on event handlers

### Project Explorer

Toggle with `<leader>pp` (or custom keybinding):

**Float Mode (Default):**
- Opens centered popup window
- Press `q` or `<Esc>` to close
- Keyboard navigation with `j/k`

**Split Mode:**
- Opens sidebar (left or right)
- Persistent window
- Resize with standard Neovim commands

**Explorer Sections:**
- 📊 **Statistics** - Project overview with counts
- 🗂️ **Schemas** - Expandable schemas with fields/associations
- 🧩 **Components** - Expandable components with attributes/slots
- 🛣️ **Routes** - Routes grouped by controller
- 📄 **Templates** - File and embedded templates
- ⚡ **LiveView** - LiveView modules with lifecycle functions

**Navigation:**
- `<CR>` - Expand/collapse or go to definition
- `o` - Go to definition in current window
- `t` - Go to definition in new tab
- `s` - Go to definition in horizontal split
- `v` - Go to definition in vertical split
- `q` or `<Esc>` - Close explorer (float mode)
- `/` - Search/filter items
- `r` - Refresh explorer

**Copy Actions:**
- `yn` - Copy name
- `ym` - Copy module name
- `yf` - Copy file path
- `yc` - Copy component tag
- `yr` - Copy route path
- `yt` - Copy table name (schemas)

### ERD Diagram Viewer

View Entity-Relationship diagrams with `<leader>pe`:

- Shows all schemas and their relationships
- Displays associations (`belongs_to`, `has_many`, etc.)
- Interactive Mermaid diagram
- Opens in default browser
- Auto-generated HTML file

---

## 🎮 Commands

All commands are available via `:PhoenixPulse` prefix:

```vim
:PhoenixPulseExplorer      " Toggle Project Explorer
:PhoenixPulseERD           " Show ERD diagram
:PhoenixPulseRefresh       " Refresh language server registries
```

---

## 🔧 Customization

### Custom Keybindings

Disable default keybindings and set your own:

```lua
require("phoenix-pulse").setup({
  keybindings = false,  -- Disable defaults
})

-- Set custom keybindings
vim.keymap.set("n", "<leader>fe", ":PhoenixPulseExplorer<CR>", { desc = "Phoenix Explorer" })
vim.keymap.set("n", "<leader>fd", ":PhoenixPulseERD<CR>", { desc = "Phoenix ERD" })
vim.keymap.set("n", "<leader>fr", ":PhoenixPulseRefresh<CR>", { desc = "Phoenix Refresh" })
```

### Float Window Appearance

```lua
require("phoenix-pulse").setup({
  explorer_mode = "float",
  float_config = {
    width = 100,           -- Width in columns
    height = 40,           -- Height in rows
    border = "double",     -- Border style
    title = " Phoenix ",  -- Custom title
    title_pos = "center",  -- "left", "center", "right"
  },
})
```

### Split Window Configuration

```lua
require("phoenix-pulse").setup({
  explorer_mode = "split",
  split_config = {
    width = 50,          -- Width in columns
    position = "right",  -- "left" or "right"
  },
})
```

---

## 🐛 Troubleshooting

### LSP not starting

**Check LSP server exists:**
```bash
ls packages/nvim-plugin/node_modules/@phoenix-pulse/language-server/dist/server.js
```

**If missing, reinstall:**
```bash
cd packages/nvim-plugin
./install-lsp.sh
```

**Check LSP logs:**
```vim
:lua vim.print(vim.lsp.get_active_clients())
:lua vim.lsp.set_log_level("debug")
:edit ~/.local/state/nvim/lsp.log
```

### Completions not working

**Verify file type:**
```vim
:set filetype?
" Should show: filetype=elixir or filetype=heex
```

**Check Phoenix project detected:**
```vim
:messages
" Look for: "[PhoenixPulse] Phoenix project detected"
```

**Ensure mix.exs exists:**
```bash
ls mix.exs
```

### Explorer not opening

**Check for errors:**
```vim
:messages
```

**Verify plugin loaded:**
```vim
:lua print(require("phoenix-pulse"))
```

**Try manual command:**
```vim
:PhoenixPulseExplorer
```

### Icons not showing

**Install nvim-web-devicons:**
```lua
-- Add to your plugin manager
"nvim-tree/nvim-web-devicons"
```

**Install a Nerd Font:**
- Download from https://www.nerdfonts.com/
- Recommended: JetBrainsMono Nerd Font, FiraCode Nerd Font
- Configure your terminal to use the font

### Performance issues

**Lower parser concurrency:**
Set environment variable:
```bash
export PHOENIX_PULSE_PARSER_CONCURRENCY=5
```

**Check Elixir installed:**
```bash
elixir --version
```

Without Elixir, falls back to regex parser (slower).

---

## 📖 Help Documentation

After installation, access built-in Vim help:

```vim
:help phoenix-pulse
:help phoenix-pulse-intro
:help phoenix-pulse-installation
:help phoenix-pulse-config
:help phoenix-pulse-commands
:help phoenix-pulse-features
:help phoenix-pulse-troubleshooting
```

---

## 🎯 Supported Phoenix Versions

| Feature | Phoenix 1.6 | Phoenix 1.7+ |
|---------|-------------|--------------|
| Function Components | ✅ | ✅ |
| Component Attributes & Slots | ✅ | ✅ |
| Templates (`:view` modules) | ✅ | ✅ |
| Templates (`:html` modules) | - | ✅ |
| Verified Routes (`~p`) | - | ✅ |
| Route Helpers | ✅ | ✅ |
| LiveView Events | ✅ | ✅ |
| Ecto Schemas | ✅ | ✅ |
| Controller Assigns | ✅ | ✅ |

---

## 🤝 Contributing

See the main [CONTRIBUTING.md](./CONTRIBUTING.md) for development guidelines.

**Development Setup:**
```bash
git clone https://github.com/phoenix-pulse/phoenix-ls
cd phoenix-ls
npm install
npm run compile
```

**Test Plugin Locally:**
```lua
{
  dir = "~/phoenix-ls/packages/nvim-plugin",
  config = function()
    require("phoenix-pulse").setup()
  end,
}
```

---

## 📝 License

MIT License - See [LICENSE](./LICENSE) for details.

---

## 🔗 Links

- **GitHub Repository:** https://github.com/phoenix-pulse/phoenix-ls
- **Organization:** https://github.com/phoenix-pulse
- **npm Package:** https://www.npmjs.com/package/@phoenix-pulse/language-server
- **Issues:** https://github.com/phoenix-pulse/phoenix-ls/issues

---

Built with ❤️ for the Phoenix community by [Onurcan Sever](https://github.com/onsever)
