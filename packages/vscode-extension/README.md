<p align="center">
  <img src="https://raw.githubusercontent.com/phoenix-pulse/phoenix-ls/main/packages/vscode-extension/images/logo.png" alt="Phoenix Pulse Logo" width="200"/>
</p>

<h1 align="center">Phoenix Pulse</h1>

<p align="center">
  <strong>The complete IDE companion for Phoenix LiveView development</strong>
</p>

<p align="center">
  <a href="#%EF%B8%8F-recommended-settings">Recommended Settings</a> •
  <a href="#-phoenix-pulse-project-explorer">Project Explorer</a> •
  <a href="#-features">Features</a> •
  <a href="#-installation">Installation</a> •
  <a href="#-requirements">Requirements</a> •
  <a href="#-troubleshooting">Troubleshooting</a>
</p>

---

Phoenix Pulse provides intelligent IntelliSense, validation, and navigation for Phoenix 1.6+ and 1.7+ applications. Work faster with smart completions for components, templates, routes, and assigns—all powered by deep understanding of your Phoenix project structure.

**Powered by the Elixir-native Phoenix LS server** for source-aware analysis, indexing, completions, diagnostics, navigation, explorer data, and ERD payloads.

---

## ⚙️ Recommended Settings

For the best experience with Phoenix Pulse, add these settings to your VS Code `settings.json`:

```json
{
    // Disable word-based suggestions to prevent pollution
    "editor.wordBasedSuggestions": "off",

    // Allow snippets in quick suggestions
    "editor.suggest.snippetsPreventQuickSuggestions": false,

    // Instant completions (no delay)
    "editor.quickSuggestionsDelay": 0,

    // Better completion ordering
    "editor.suggest.localityBonus": true,

    // Exclude build directories from search
    "search.exclude": {
        "**/.elixir_ls": true,
        "**/.lexical": true,
        "**/deps": true,
        "**/_build": true
    }
}
```

> **Note:** These settings are **recommended** but not required. Phoenix Pulse works without them, but the experience is noticeably better with them.

---

## ☰ Phoenix Pulse Project Explorer

Phoenix Pulse provides a comprehensive **Project Explorer** in the VS Code sidebar that gives you instant visibility into your entire Phoenix application structure. Click the Phoenix Pulse icon in the Activity Bar to access it.

### Features

#### 📊 Statistics Overview
Get a bird's-eye view of your Phoenix project with real-time metrics:
- **Overview** - Total counts: components, routes, schemas, templates, LiveView modules
- **Route Breakdown** - Routes grouped by HTTP verb (GET, POST, PUT, DELETE, etc.)
- **Component Metrics** - Components categorized by complexity
- **Top Schemas** - Top 5 schemas by total fields and associations

#### 🗂️ Schemas
Browse all your Ecto schemas with field and association counts:
- **Expand schema** → View all fields (with types) and associations
- **Click field/association** → Jump to schema definition
- **Right-click** → Copy schema name, module name, table name, or file path

#### 🧩 Components
Explore all function components grouped by file:
- **Expand component file** → See all components in that file
- **Component info** → Shows attribute and slot counts
- **Expand component** → View all attributes and slots with types
- **Click component** → Jump to component definition
- **Right-click** → Copy component name, module name, tag (`<.component>`), or file path

#### 🛣️ Routes
Navigate your Phoenix router with grouped routes:
- **Routes grouped by controller** for better organization
- **Route info** → Shows HTTP verb, path, and action
- **Click route** → Jump to route definition in router
- **Right-click** → Copy route name, path, or file path

#### 📄 Templates
View all templates (file-based and embedded):
- **Expand template file** → See all templates in that file
- **Template info** → Shows format (HTML, JSON, etc.)
- **Click template** → Jump to template file or function definition
- **Right-click** → Copy template name or file path

#### ⚡ LiveView
Complete visibility into your LiveView architecture:
- **LiveView modules grouped by name**
- **Expand module** → See all lifecycle functions organized by type
- **Function count badge** - Shows total functions in each module
- **Click function** → Jump directly to function definition

#### 🔍 Search & Filter
- **Search icon** in toolbar → Filter all sections by name, path, or action
- **Multi-word search** → Find items matching multiple terms
- **Clear icon** → Reset filter and show all items
- **Auto-expand** → Matching categories expand automatically

#### 📋 Copy Actions
Right-click any item to copy useful information to clipboard:
- **Copy Name** - The item's name
- **Copy Module Name** - Full module path
- **Copy File Path** - Absolute path to the file
- **Copy Component Tag** - Ready-to-use component tag
- **Copy Route Path** - Route path
- **Copy Table Name** - Database table name for schemas

#### 📊 ERD Diagram
- **Graph icon** in toolbar → View Entity-Relationship diagram of your schemas
- Interactive Mermaid diagram showing all schema relationships
- Visual representation of associations and fields

---

## ✨ Features

### 🧩 Component Intelligence

**Smart Completions**
- Type `<.` to see all available function components
- Autocomplete component attributes with type information and documentation
- Slot completions (`<:slot_name>`) with attribute suggestions
- Special attribute completions (`:for`, `:if`, `:let`, `:key`)

**Real-Time Validation**
- ❌ Missing required attributes
- ⚠️ Unknown attributes (respects `attr :rest, :global`)
- ⚠️ Invalid attribute values (validates against `values: [...]` constraints)
- ❌ Missing required slots with nested slot support
- ❌ Component not imported in HTML module

**Navigation & Documentation**
- **F12 / Ctrl+Click** on component name → Jump to definition
- **Hover** over components → See full documentation, attributes, slots, and usage examples
- Works with nested components and function clauses

**Example:**
```heex
<.input
  field={@form[:email]}
  type="email"
  label="Email Address"
  required
/>
<!-- All attributes validated, autocompleted, and documented -->
```

---

### 📄 Template Features (Phoenix 1.7+)

**Template Completions**
- Type `render(conn, :` in controllers to see available templates
- Shows both file-based (`.heex`) and embedded function templates
- Template suggestions include location and type information

**Template Validation**
- ❌ Template not found in HTML module
- Suggests creating template file or embedded function
- Validates template name conventions

**Navigation**
- **F12 / Ctrl+Click** on `:template_name` → Jump to template file or function definition
- **Hover** → See template type, file location, and parent module
- Supports both Phoenix 1.6 (`:view`) and 1.7+ (`:html`) patterns

---

### 🛣️ Route Intelligence

**Comprehensive Router Support**
- ✅ All HTTP verbs (`get`, `post`, `put`, `patch`, `delete`, `options`, `head`, `match`)
- ✅ Phoenix 1.7 verified routes (`~p"/users/#{user.id}"`)
- ✅ Nested resources with proper path generation
- ✅ Singleton resources (`singleton: true`)
- ✅ Custom parameter names (`param: "slug"`)
- ✅ Live routes and forward routes
- ✅ Resource action filtering (`only:`, `except:`)
- ✅ Pipeline tracking and scope management

**Smart Completions**
- Route helper completions with parameter hints
- Action completions filtered by resource options
- Verified route path completions
- Navigation component route validation

**Navigation & Documentation**
- **F12 / Ctrl+Click** on route helpers or verified routes → Jump to router definition
- **Hover** → See HTTP verb, full path, parameters, controller/LiveView, and pipeline

---

### 📦 Controller-Aware Assigns

**Schema-Aware Completions**
- Type `@` in templates to see assigns passed from controller `render()` calls
- Drill down into Ecto schemas: `@user.email`, `@post.author.name`
- Works in both `.heex` templates and `~H` sigils in `.ex` files
- Detects `has_many` associations and suggests `:for` loop patterns

**Ecto Schema Integration**
- Automatically discovers all Ecto schema fields and associations
- Shows field types in completion documentation
- Resolves `belongs_to`, `has_one`, `has_many`, and `many_to_many` associations
- Handles schema aliases across module namespaces

**Example:**
```heex
<!-- Type @ to see controller assigns -->
<h1><%= @user.name %></h1>
<p>Email: <%= @user.email %></p>
<!-- All fields autocompleted from User schema -->
```

---

### ⚡ Phoenix Attributes & Events

**Phoenix LiveView Attributes**
- All 29 `phx-*` attributes with rich documentation
- Context-aware: `phx-click`, `phx-submit` only shown when events exist
- Hover documentation includes usage examples and HexDocs links

**Event Completions**
- Inside `phx-click=""` → Shows available `handle_event` functions
- Distinguishes between primary (same file) and secondary (LiveView) events
- Supports both string and atom event names
- Validates event name exists in LiveView module

**JS Command Support**
- `JS.push`, `JS.navigate`, `JS.patch`, `JS.show`, `JS.hide`, etc.
- Pipe chain completions
- Parameter suggestions for each command

---

### 🔄 Smart :for Loop Validation

**Context-Aware Key Requirements**
- Regular `:for` loops require `:key` attribute
- Stream iterations (`:for={{id, item} <- @streams.items}`) skip `:key` requirement
- Warns if `:key` added to stream (unnecessary, uses DOM `id`)

**:for Loop Variable Completions**
- Type inference for loop variables: `<div :for={user <- @users}>{user.█}</div>`
- Shows Ecto schema fields for loop variables
- Supports nested field access: `user.organization.name`
- Handles tuple destructuring: `{id, item} <- @streams.items`

---

### 🔍 Go-to-Definition (F12)

**Supported Navigation:**
- ✅ Component names (`<.button>`)
- ✅ Nested components (`<.icon>` inside `<.banner>`)
- ✅ Slot names (`<:actions>`, `<:header>`)
- ✅ Template atoms (`:home` in `render(conn, :home)`)
- ✅ Route helpers (`Routes.user_path`)
- ✅ Verified routes (`~p"/users"`)

**Fast & Cached:**
- First navigation: ~500ms (parses file)
- Subsequent: ~1-2ms (uses cache)
- Content-based caching for instant repeat lookups

---

### 💡 Hover Information

**Rich Documentation for:**
- ✅ Components (all attributes, slots, documentation blocks)
- ✅ Component attributes (type, required status, default value, allowed values)
- ✅ Phoenix attributes (`phx-*` with examples and links)
- ✅ Templates (type, file location, module info)
- ✅ Routes (HTTP verb, full path, parameters, controller, pipeline)
- ✅ Events (`handle_event` function signature and location)
- ✅ JS commands (all `JS.*` functions with parameters)
- ✅ Schema associations (shows target schema and available fields)

---

## 📦 Installation

### From VS Code Marketplace (Recommended)

1. Open VS Code
2. Press `Ctrl+Shift+X` (or `Cmd+Shift+X` on Mac)
3. Search for **"Phoenix Pulse"**
4. Click **Install**

### Via Command Line

```bash
code --install-extension onsever.phoenix-pulse
```

---

## 📋 Requirements

### Minimum Requirements

- **VS Code**: 1.75.0 or higher
- **Phoenix**: 1.6+ or 1.7+ project
- **Phoenix LS executable**: bundled with release builds, or configured with `phoenixPulse.serverPath`

### Recommended

- **Elixir/Mix**: 1.17+ when building the local Phoenix LS executable from source
- **Phoenix**: 1.7+ (for verified routes and `:html` modules)

### Supported File Types

- `.ex` - Elixir source files
- `.exs` - Elixir script files
- `.heex` - HEEx template files
- `~H` sigils - Embedded HEEx in `.ex` files

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
| Nested Resources | ✅ | ✅ |
| Singleton Resources | ✅ | ✅ |

---

## ⚙️ Configuration

Phoenix Pulse includes configurable settings. Access them via:
- `Ctrl+,` (or `Cmd+,` on Mac) → Search "Phoenix Pulse"
- Or edit `settings.json` directly

### Available Settings

```json
{
  // Custom Phoenix LS Elixir executable path (auto-detected if empty)
  "phoenixPulse.serverPath": "",

  // Prefer source-only indexing without loading project code
  "phoenixPulse.sourceOnlyMode": true,

  // Server log level
  "phoenixPulse.logLevel": "info",

  // Enable project indexing
  "phoenixPulse.indexing.enabled": true
}
```

---

## 🐛 Troubleshooting

### Completions not working?

**Check 1: Phoenix Project Detection**
- Ensure `mix.exs` exists in workspace root
- Phoenix dependency should be in `deps`
- Check "Phoenix Pulse" output channel for "✅ Phoenix project detected!"

**Check 2: File Types**
- HEEx templates must use `.heex` extension
- Elixir files must use `.ex` or `.exs`
- Components must be in `*_web/components/` directory

**Check 3: Reload VS Code**
```
Ctrl+Shift+P → "Developer: Reload Window"
```

### Template features not working?

**Phoenix 1.7+ (`:html` modules)**
- HTML module must use: `use YourAppWeb, :html`
- Controller name must match convention: `PageController` → `PageHTML`
- Templates in `page_html/` directory or embedded functions

**Phoenix 1.6 (`:view` modules)**
- View module must use: `use YourAppWeb, :view`
- Controller name must match: `PageController` → `PageView`
- Templates in `templates/page/` directory

### Routes not showing?

**Check Router Location**
- Router file must match pattern: `*_web/router.ex`
- Standard location: `lib/my_app_web/router.ex`

**Check Router Syntax**
- Ensure `router.ex` compiles without errors
- Run `mix compile` to check for syntax errors

### Performance issues?

**Enable Debug Logging**
```json
{
  "phoenixPulse.logLevel": "debug",
  "phoenixPulse.sourceOnlyMode": true,
  "phoenixPulse.indexing.enabled": true
}
```

Check the "Phoenix Pulse" output channel for indexing, degraded-mode, and startup messages.

**Solutions:**
1. Check the configured executable: `"phoenixPulse.serverPath"`
2. Confirm the bundled executable runs: `packages/vscode-extension/server/phoenix_ls --help`
3. Rebuild local release artifacts with `npm run package:vscode`

### Still having issues?

1. **Check GitHub Issues**: https://github.com/phoenix-pulse/phoenix-ls/issues
2. **Open New Issue**: Include:
   - VS Code version
   - Phoenix version
   - Extension version
   - Logs from "Phoenix Pulse" output channel
   - Sample code that reproduces the issue

---

## 🤝 Contributing

We welcome contributions! See the [monorepo repository](https://github.com/phoenix-pulse/phoenix-ls) for contribution guidelines.

**Development Setup:**
```bash
git clone https://github.com/phoenix-pulse/phoenix-ls
cd phoenix-ls
npm install
npm run compile
```

See [CONTRIBUTING.md](https://github.com/phoenix-pulse/phoenix-ls/blob/main/CONTRIBUTING.md) for detailed development documentation.

---

## 📄 License

MIT License - See [LICENSE](https://github.com/phoenix-pulse/phoenix-ls/blob/main/LICENSE) for details.

---

## 💖 Credits

Built with ❤️ for the Phoenix community by [Onurcan Sever](https://github.com/onsever).

Inspired by the amazing Phoenix framework, LiveView, and the developers pushing Elixir web development forward.

**Special Thanks:**
- Phoenix Framework team for creating an incredible web framework
- Elixir community for continuous inspiration
- All contributors and users who provided feedback

---

<p align="center">
  <strong>Enjoy the pulse! 💥</strong>
</p>

<p align="center">
  <a href="https://github.com/phoenix-pulse/phoenix-ls">GitHub</a> •
  <a href="https://github.com/phoenix-pulse/phoenix-ls/issues">Issues</a> •
  <a href="https://marketplace.visualstudio.com/items?itemName=onsever.phoenix-pulse">VS Code Marketplace</a>
</p>
