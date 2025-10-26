import { CompletionItem, CompletionItemKind, InsertTextFormat, MarkupKind } from 'vscode-languageserver/node';
import { ElementContext, shouldPrioritizeAttribute } from '../utils/element-context';
import { findEnclosingForLoop } from '../utils/for-loop-parser';
import { inferAssignType } from '../utils/type-inference';
import { ComponentsRegistry } from '../components-registry';
import { ControllersRegistry } from '../controllers-registry';
import { SchemaRegistry } from '../schema-registry';

/**
 * Phoenix attributes that trigger handle_event/3 callbacks on the server
 * These should be prioritized when the LiveView module has handle_event definitions
 */
const EVENT_TRIGGERING_ATTRIBUTES = [
  'phx-click',
  'phx-submit',
  'phx-change',
  'phx-blur',
  'phx-focus',
  'phx-keydown',
  'phx-keyup',
  'phx-window-keydown',
  'phx-window-keyup',
  'phx-window-blur',
  'phx-window-focus',
  'phx-capture-click',
  'phx-click-away',
  'phx-viewport-top',
  'phx-viewport-bottom',
];

// Phoenix LiveView specific attributes
const phoenixAttributes = [
  // Event Bindings
  {
    label: 'phx-click',
    detail: 'Trigger an event on click',
    documentation: `Binds a click event to send a message to the LiveView server.

**Example:**
\`\`\`heex
<button phx-click="delete" phx-value-id={@item.id}>Delete</button>
<div phx-click="toggle_menu">Menu</div>
\`\`\`

**Common Use Cases:**
- Button click handlers
- Interactive UI elements (cards, dropdowns, modals)
- Triggering server-side actions

**Modifiers:**
- Use with \`phx-target\` to scope to specific component
- Use with \`phx-value-*\` to send additional data
- Use with \`phx-throttle\` or \`phx-debounce\` to control frequency

**See Also:** phx-capture-click, phx-click-away, phx-target, phx-value-

[📖 HexDocs](https://hexdocs.pm/phoenix_live_view/bindings.html#click-events)`,
    insertText: 'phx-click="${1:event_name}"',
  },
  {
    label: 'phx-change',
    detail: 'Trigger an event on form input change',
    documentation: `Binds a change event for form inputs. Triggers on every keystroke or value change.

**Example:**
\`\`\`heex
<form phx-change="validate">
  <input type="text" name="user[email]" />
</form>
<input type="text" phx-change="search" phx-debounce="300" />
\`\`\`

**Common Use Cases:**
- Live form validation
- Search-as-you-type functionality
- Real-time input feedback
- Dynamic form updates

**Best Practices:**
- Use \`phx-debounce\` to avoid excessive server requests
- Combine with form validation on the server
- Consider using \`phx-submit\` for final form submission

**See Also:** phx-submit, phx-debounce, phx-blur

[📖 HexDocs](https://hexdocs.pm/phoenix_live_view/form-bindings.html#change-events)`,
    insertText: 'phx-change="${1:event_name}"',
  },
  {
    label: 'phx-submit',
    detail: 'Trigger an event on form submit',
    documentation: `Binds a submit event for forms. Automatically prevents default form submission.

**Example:**
\`\`\`heex
<form phx-submit="save">
  <input type="text" name="user[name]" />
  <button type="submit">Save</button>
</form>
\`\`\`

**Common Use Cases:**
- Form submission handling
- Data creation/updates
- Multi-step form wizards

**How it Works:**
- Prevents default browser form submission
- Serializes form data and sends to server
- Triggers \`handle_event/3\` callback on server

**See Also:** phx-change, phx-trigger-action, phx-disable-with

[📖 HexDocs](https://hexdocs.pm/phoenix_live_view/form-bindings.html#submit-events)`,
    insertText: 'phx-submit="${1:event_name}"',
  },
  {
    label: 'phx-blur',
    detail: 'Trigger an event when element loses focus',
    documentation: `Binds a blur event triggered when an element loses focus.

**Example:**
\`\`\`heex
<input type="text" phx-blur="validate_field" name="email" />
<textarea phx-blur="save_draft"></textarea>
\`\`\`

**Common Use Cases:**
- Field-level validation after user input
- Auto-saving form drafts
- Tracking user interaction patterns
- Hiding inline edit modes

**See Also:** phx-focus, phx-change, phx-window-blur

[📖 HexDocs](https://hexdocs.pm/phoenix_live_view/bindings.html#focus-events)`,
    insertText: 'phx-blur="${1:event_name}"',
  },
  {
    label: 'phx-focus',
    detail: 'Trigger an event when element gains focus',
    documentation: `Binds a focus event triggered when an element gains focus.

**Example:**
\`\`\`heex
<input type="text" phx-focus="load_suggestions" />
<div phx-focus="highlight_section" tabindex="0"></div>
\`\`\`

**Common Use Cases:**
- Loading autocomplete suggestions
- Tracking active form field
- Showing contextual help
- Analytics and user behavior tracking

**See Also:** phx-blur, phx-window-focus, JS.focus()

[📖 HexDocs](https://hexdocs.pm/phoenix_live_view/bindings.html#focus-events)`,
    insertText: 'phx-focus="${1:event_name}"',
  },
  {
    label: 'phx-keydown',
    detail: 'Trigger an event on keydown',
    documentation: `Binds a keydown event for keyboard interactions. Fires when key is pressed down.

**Example:**
\`\`\`heex
<input phx-keydown="search" phx-key="Enter" />
<div phx-keydown="move" phx-key="ArrowUp" tabindex="0"></div>
\`\`\`

**Common Use Cases:**
- Keyboard shortcuts
- Form submission on Enter key
- Navigation controls (arrow keys)
- Game controls

**Best Practices:**
- Use \`phx-key\` to filter specific keys
- Consider \`phx-window-keydown\` for global shortcuts
- Use \`phx-keyup\` for key release detection

**See Also:** phx-keyup, phx-key, phx-window-keydown

[📖 HexDocs](https://hexdocs.pm/phoenix_live_view/bindings.html#key-events)`,
    insertText: 'phx-keydown="${1:event_name}"',
  },
  {
    label: 'phx-keyup',
    detail: 'Trigger an event on keyup',
    documentation: `Binds a keyup event for keyboard interactions. Fires when key is released.

**Example:**
\`\`\`heex
<input type="text" phx-keyup="search" phx-debounce="300" />
<textarea phx-keyup="count_chars"></textarea>
\`\`\`

**Common Use Cases:**
- Live search with debouncing
- Character counting
- Text input validation
- Detecting key release in games

**Difference from phx-keydown:**
- \`phx-keydown\`: Fires when key pressed (repeats if held)
- \`phx-keyup\`: Fires when key released (no repeat)

**See Also:** phx-keydown, phx-key, phx-window-keyup

[📖 HexDocs](https://hexdocs.pm/phoenix_live_view/bindings.html#key-events)`,
    insertText: 'phx-keyup="${1:event_name}"',
  },
  {
    label: 'phx-window-keydown',
    detail: 'Trigger an event on window keydown',
    documentation: `Binds a keydown event at the window level (global keyboard shortcut).

**Example:**
\`\`\`heex
<div phx-window-keydown="close_modal" phx-key="Escape">Modal</div>
<div phx-window-keydown="save" phx-key="s" phx-meta="ctrlKey">Editor</div>
\`\`\`

**Common Use Cases:**
- Global keyboard shortcuts (Ctrl+S, Cmd+K, etc.)
- Modal close on Escape key
- Application-wide navigation
- Accessibility keyboard controls

**Difference from phx-keydown:**
- \`phx-window-keydown\`: Works anywhere in the window
- \`phx-keydown\`: Only when specific element has focus

**See Also:** phx-window-keyup, phx-key, phx-keydown

[📖 HexDocs](https://hexdocs.pm/phoenix_live_view/bindings.html#window-events)`,
    insertText: 'phx-window-keydown="${1:event_name}"',
  },
  {
    label: 'phx-window-keyup',
    detail: 'Trigger an event on window keyup',
    documentation: `Binds a keyup event at the window level (global key release detection).

**Example:**
\`\`\`heex
<div phx-window-keyup="stop_action" phx-key="Space">Game</div>
\`\`\`

**Common Use Cases:**
- Game controls (key release detection)
- Global hotkey systems
- Accessibility features

**See Also:** phx-window-keydown, phx-key, phx-keyup

[📖 HexDocs](https://hexdocs.pm/phoenix_live_view/bindings.html#window-events)`,
    insertText: 'phx-window-keyup="${1:event_name}"',
  },
  {
    label: 'phx-window-focus',
    detail: 'Trigger an event on window focus',
    documentation: `Binds a focus event triggered when the browser window/tab gains focus.

**Example:**
\`\`\`heex
<div phx-window-focus="refresh_data">Dashboard</div>
\`\`\`

**Common Use Cases:**
- Refreshing data when user returns to tab
- Resuming real-time updates
- Tracking user engagement
- Resuming timers or animations

**See Also:** phx-window-blur, phx-focus

[📖 HexDocs](https://hexdocs.pm/phoenix_live_view/bindings.html#window-events)`,
    insertText: 'phx-window-focus="${1:event_name}"',
  },
  {
    label: 'phx-window-blur',
    detail: 'Trigger an event on window blur',
    documentation: `Binds a blur event triggered when the browser window/tab loses focus.

**Example:**
\`\`\`heex
<div phx-window-blur="pause_updates">Chat</div>
\`\`\`

**Common Use Cases:**
- Pausing real-time updates to save resources
- Auto-saving work before user leaves
- Tracking user away time
- Stopping animations or timers

**See Also:** phx-window-focus, phx-blur

[📖 HexDocs](https://hexdocs.pm/phoenix_live_view/bindings.html#window-events)`,
    insertText: 'phx-window-blur="${1:event_name}"',
  },
  {
    label: 'phx-key',
    detail: 'Filter key events by key name',
    documentation: `Filters key events to only trigger on specific keys. Must be used with phx-keydown or phx-keyup.

**Example:**
\`\`\`heex
<input phx-keydown="submit" phx-key="Enter" />
<div phx-window-keydown="close" phx-key="Escape">Modal</div>
<form phx-keydown="navigate" phx-key="ArrowDown">
\`\`\`

**Common Keys:**
- Enter, Escape, Space, Tab
- ArrowUp, ArrowDown, ArrowLeft, ArrowRight
- Backspace, Delete
- Any letter: "a", "b", "c", etc.
- Modifiers: ctrlKey, shiftKey, altKey, metaKey (use \`phx-meta\`)

**See Also:** phx-keydown, phx-keyup, phx-window-keydown

[📖 HexDocs](https://hexdocs.pm/phoenix_live_view/bindings.html#key-events)`,
    insertText: 'phx-key="${1|Enter,Escape,Space,ArrowUp,ArrowDown,ArrowLeft,ArrowRight,Tab|}"',
  },

  // Target & Rate Limiting
  {
    label: 'phx-target',
    detail: 'Specify the event target',
    documentation: `Specifies which LiveView or component should handle the event.

**Example:**
\`\`\`heex
<!-- Send to parent LiveView -->
<button phx-click="delete" phx-target="#parent">Delete</button>

<!-- Send to self (LiveComponent) -->
<button phx-click="update" phx-target={@myself}>Update</button>

<!-- Send to specific component by ID -->
<button phx-click="refresh" phx-target="#user-list">Refresh</button>
\`\`\`

**Common Values:**
- \`@myself\` - Send to current LiveComponent
- CSS selector - Send to specific component/LiveView

**Why Use It:**
- Scope events to specific components
- Prevent parent LiveView from handling child events
- Enable component-level encapsulation

**See Also:** LiveComponent documentation

[📖 HexDocs](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveComponent.html)`,
    insertText: 'phx-target="${1:@myself}"',
  },
  {
    label: 'phx-throttle',
    detail: 'Throttle event frequency',
    documentation: `Throttles how often events are sent to the server (in milliseconds).

**Example:**
\`\`\`heex
<div phx-click="track_mouse" phx-throttle="100">...</div>
<input phx-keyup="search" phx-throttle="500" />
\`\`\`

**How it Works:**
- Ensures event fires at most once per time window
- First event fires immediately, then waits for throttle period
- Good for high-frequency events (scroll, mousemove)

**Throttle vs Debounce:**
- **Throttle**: Fires at regular intervals during activity
- **Debounce**: Waits for activity to stop before firing

**Common Values:**
- 100ms - Very responsive (mousemove, scroll)
- 250ms - Balanced (moderate interactions)
- 500-1000ms - Conservative (expensive operations)

**See Also:** phx-debounce

[📖 HexDocs](https://hexdocs.pm/phoenix_live_view/bindings.html#rate-limiting)`,
    insertText: 'phx-throttle="${1|100,250,500,1000|}"',
  },
  {
    label: 'phx-debounce',
    detail: 'Debounce event frequency',
    documentation: `Debounces events to wait until user stops typing/interacting before firing.

**Example:**
\`\`\`heex
<input phx-keyup="search" phx-debounce="300" />
<input phx-change="validate" phx-debounce="blur" />
\`\`\`

**How it Works:**
- Waits for specified time of inactivity before firing
- Each new event resets the timer
- Perfect for search-as-you-type

**Special Value: "blur"**
- Waits until input loses focus before firing
- Great for validation without annoying users

**Throttle vs Debounce:**
- **Throttle**: Fires at regular intervals during activity
- **Debounce**: Waits for activity to stop before firing

**Common Values:**
- 300ms - Search inputs (good balance)
- 500ms - Form validation
- "blur" - Validation on field exit

**See Also:** phx-throttle, phx-blur

[📖 HexDocs](https://hexdocs.pm/phoenix_live_view/bindings.html#rate-limiting)`,
    insertText: 'phx-debounce="${1|blur,100,250,500,1000|}"',
  },

  // Value Bindings
  {
    label: 'phx-value-',
    detail: 'Send custom value with event',
    documentation: `Adds custom value parameters to the event payload. The key after \`phx-value-\` becomes a parameter.

**Example:**
\`\`\`heex
<button phx-click="delete" phx-value-id={@item.id}>Delete</button>
<button phx-click="update" phx-value-status="approved" phx-value-user-id={@user.id}>
  Approve
</button>
\`\`\`

**Server-side Handler:**
\`\`\`elixir
def handle_event("delete", %{"id" => id}, socket) do
  # id is from phx-value-id
end

def handle_event("update", %{"status" => status, "user-id" => user_id}, socket) do
  # Multiple values received
end
\`\`\`

**Common Patterns:**
- \`phx-value-id\` - Entity ID for CRUD operations
- \`phx-value-action\` - Action type/variant
- \`phx-value-index\` - Array/list index

**Note:** Hyphens in attribute names become hyphens in params (not underscores)

**See Also:** phx-click, phx-target

[📖 HexDocs](https://hexdocs.pm/phoenix_live_view/bindings.html#click-events)`,
    insertText: 'phx-value-${1:key}="${2:value}"',
  },

  // Common phx-value-* patterns
  {
    label: 'phx-value-id',
    detail: 'Send ID value with event (most common)',
    documentation: `Sends an ID parameter with the event. Most common pattern for CRUD operations.

**Example:**
\`\`\`heex
<button phx-click="delete" phx-value-id={@item.id}>Delete</button>
<button phx-click="edit" phx-value-id={@user.id}>Edit User</button>
\`\`\`

**Server-side:**
\`\`\`elixir
def handle_event("delete", %{"id" => id}, socket) do
  MyApp.delete_item(id)
  {:noreply, socket}
end
\`\`\`

**Use Cases:**
- Deleting records
- Editing/updating entities
- Selecting items
- Navigation to detail pages

**See Also:** phx-value-action, phx-value-index`,
    insertText: 'phx-value-id={${1:@item.id}}',
  },

  {
    label: 'phx-value-action',
    detail: 'Send action type with event',
    documentation: `Sends an action parameter to handle different action types in the same event handler.

**Example:**
\`\`\`heex
<button phx-click="update-status" phx-value-action="approve" phx-value-id={@request.id}>
  Approve
</button>
<button phx-click="update-status" phx-value-action="reject" phx-value-id={@request.id}>
  Reject
</button>
\`\`\`

**Server-side:**
\`\`\`elixir
def handle_event("update-status", %{"action" => action, "id" => id}, socket) do
  case action do
    "approve" -> MyApp.approve_request(id)
    "reject" -> MyApp.reject_request(id)
  end
  {:noreply, socket}
end
\`\`\`

**Use Cases:**
- Approval workflows
- Multi-action buttons
- Status updates
- Action variants

**See Also:** phx-value-id, phx-value-status`,
    insertText: 'phx-value-action="${1:action-name}"',
  },

  {
    label: 'phx-value-index',
    detail: 'Send list index with event',
    documentation: `Sends the index position for list operations.

**Example:**
\`\`\`heex
<div :for={{item, index} <- Enum.with_index(@items)} :key={item.id}>
  <button phx-click="reorder" phx-value-index={index} phx-value-id={item.id}>
    ↑ Move Up
  </button>
  {item.name}
</div>
\`\`\`

**Server-side:**
\`\`\`elixir
def handle_event("reorder", %{"index" => index_str, "id" => id}, socket) do
  index = String.to_integer(index_str)
  items = reorder_items(socket.assigns.items, index)
  {:noreply, assign(socket, items: items)}
end
\`\`\`

**Use Cases:**
- Reordering lists
- Array manipulation
- Position-based operations
- Drag-and-drop

**See Also:** phx-value-id, :for with Enum.with_index`,
    insertText: 'phx-value-index={${1:index}}',
  },

  {
    label: 'phx-value-name',
    detail: 'Send name/label with event',
    documentation: `Sends a name or label parameter with the event.

**Example:**
\`\`\`heex
<button phx-click="select-option" phx-value-name="subscription" phx-value-id={@plan.id}>
  Choose Plan
</button>
<button phx-click="filter" phx-value-name="category" phx-value-value={@category.slug}>
  Filter
</button>
\`\`\`

**Server-side:**
\`\`\`elixir
def handle_event("select-option", %{"name" => name, "id" => id}, socket) do
  # Use both name and id
  {:noreply, assign(socket, selected: {name, id})}
end
\`\`\`

**Use Cases:**
- Filter parameters
- Option selection
- Named actions
- Label-based operations

**See Also:** phx-value-id, phx-value-value`,
    insertText: 'phx-value-name="${1:name}"',
  },

  {
    label: 'phx-value-value',
    detail: 'Send value parameter with event',
    documentation: `Sends a value parameter with the event (for filter values, selections, etc).

**Example:**
\`\`\`heex
<button phx-click="filter" phx-value-name="status" phx-value-value="active">
  Active Only
</button>
<button phx-click="set-option" phx-value-name="theme" phx-value-value="dark">
  Dark Mode
</button>
\`\`\`

**Server-side:**
\`\`\`elixir
def handle_event("filter", %{"name" => name, "value" => value}, socket) do
  filters = Map.put(socket.assigns.filters, name, value)
  {:noreply, assign(socket, filters: filters)}
end
\`\`\`

**Use Cases:**
- Filter selections
- Setting configuration values
- Dynamic parameters
- Key-value pairs

**See Also:** phx-value-name, phx-value-id`,
    insertText: 'phx-value-value="${1:value}"',
  },

  {
    label: 'phx-value-status',
    detail: 'Send status/state with event',
    documentation: `Sends a status or state parameter with the event.

**Example:**
\`\`\`heex
<button phx-click="update-order" phx-value-status="shipped" phx-value-id={@order.id}>
  Mark as Shipped
</button>
<button phx-click="toggle" phx-value-status="active" phx-value-id={@item.id}>
  Activate
</button>
\`\`\`

**Server-side:**
\`\`\`elixir
def handle_event("update-order", %{"status" => status, "id" => id}, socket) do
  order = Orders.get_order!(id)
  Orders.update_order(order, %{status: status})
  {:noreply, socket}
end
\`\`\`

**Common Use Cases:**
- Workflow state changes (pending, approved, rejected)
- Status toggles (active, inactive, archived)
- Order processing (processing, shipped, delivered)
- Approval flows (draft, pending, published)

**See Also:** phx-value-action, phx-value-id`,
    insertText: 'phx-value-status="${1:status}"',
  },

  {
    label: 'phx-value-slug',
    detail: 'Send URL slug with event',
    documentation: `Sends a URL-friendly slug parameter with the event.

**Example:**
\`\`\`heex
<button phx-click="navigate" phx-value-slug={@post.slug}>
  View Post
</button>
<a phx-click="filter-category" phx-value-slug={@category.slug}>
  {@category.name}
</a>
\`\`\`

**Server-side:**
\`\`\`elixir
def handle_event("navigate", %{"slug" => slug}, socket) do
  {:noreply, push_navigate(socket, to: ~p"/posts/\#{slug}")}
end

def handle_event("filter-category", %{"slug" => slug}, socket) do
  {:noreply, assign(socket, category_filter: slug)}
end
\`\`\`

**Common Use Cases:**
- Navigating to detail pages
- Filtering by URL-friendly identifiers
- Category/tag selection
- SEO-friendly routing

**See Also:** phx-value-id, phx-value-name`,
    insertText: 'phx-value-slug={${1:@item.slug}}',
  },

  {
    label: 'phx-value-key',
    detail: 'Send key/identifier with event',
    documentation: `Sends a key or identifier parameter with the event (useful for maps, settings, etc).

**Example:**
\`\`\`heex
<button :for={{key, value} <- @settings} phx-click="update-setting" phx-value-key={key}>
  {key}: {value}
</button>
<div :for={{key, item} <- @map} phx-click="select" phx-value-key={key} phx-value-id={item.id}>
  {item.name}
</div>
\`\`\`

**Server-side:**
\`\`\`elixir
def handle_event("update-setting", %{"key" => key}, socket) do
  {:noreply, assign(socket, active_setting: key)}
end

def handle_event("select", %{"key" => key, "id" => id}, socket) do
  {:noreply, assign(socket, selected: %{key: key, id: id})}
end
\`\`\`

**Common Use Cases:**
- Map key selection
- Setting/configuration keys
- Dynamic property names
- Enum/lookup keys

**See Also:** phx-value-index, phx-value-name, phx-value-id`,
    insertText: 'phx-value-key={${1:key}}',
  },

  {
    label: 'phx-value-type',
    detail: 'Send type/category with event',
    documentation: `Sends a type or category parameter with the event.

**Example:**
\`\`\`heex
<button phx-click="filter" phx-value-type="user">Users</button>
<button phx-click="filter" phx-value-type="admin">Admins</button>
<button phx-click="create" phx-value-type="post" phx-value-id={@author.id}>
  New Post
</button>
\`\`\`

**Server-side:**
\`\`\`elixir
def handle_event("filter", %{"type" => type}, socket) do
  {:noreply, assign(socket, filter_type: type)}
end

def handle_event("create", %{"type" => type, "id" => id}, socket) do
  case type do
    "post" -> create_post(id)
    "comment" -> create_comment(id)
  end
  {:noreply, socket}
end
\`\`\`

**Common Use Cases:**
- Content type filtering
- Entity type selection
- Polymorphic actions
- Category-based operations

**See Also:** phx-value-action, phx-value-name`,
    insertText: 'phx-value-type="${1:type}"',
  },

  // DOM Operations
  {
    label: 'phx-update',
    detail: 'Control how content is updated',
    documentation: `Controls how LiveView updates this element's DOM content.

**Example:**
\`\`\`heex
<ul id="messages" phx-update="append">
  <%= for msg <- @messages do %>
    <li id={"msg-\#{msg.id}"}><%= msg.text %></li>
  <% end %>
</ul>

<div phx-update="ignore">
  <!-- Never updated by LiveView -->
  <script>initThirdPartyWidget()</script>
</div>
\`\`\`

**Update Strategies:**
- \`replace\` (default) - Replace entire container contents
- \`append\` - Add new items to the end
- \`prepend\` - Add new items to the beginning
- \`ignore\` - Never update (preserve client-side changes)

**Common Use Cases:**
- \`append\`: Chat messages, infinite scroll lists
- \`prepend\`: New notifications at top
- \`ignore\`: Third-party widgets, client-side libraries

**Important:** Each child must have a unique \`id\` attribute when using append/prepend

**See Also:** phx-remove

[📖 HexDocs](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html#module-dom-patching-and-temporary-assigns)`,
    insertText: 'phx-update="${1|replace,append,prepend,ignore|}"',
  },
  {
    label: 'phx-remove',
    detail: 'Remove element on update',
    documentation: `Marks an element for removal on the next DOM patch. Useful for animations.

**Example:**
\`\`\`heex
<div id="flash" phx-remove={@flash_hidden}>
  Flash message!
</div>

<!-- With JS transition -->
<div phx-remove={JS.hide(transition: "fade-out")}>
  Fading out...
</div>
\`\`\`

**How it Works:**
- Element is marked for removal when attribute present
- Can be combined with JS commands for smooth transitions
- Element removed after transitions complete

**Common Use Cases:**
- Flash message dismissal
- Notification removal with animation
- Temporary UI element cleanup

**See Also:** phx-update, JS.hide()

[📖 HexDocs](https://hexdocs.pm/phoenix_live_view/js-interop.html#removing-elements)`,
    insertText: 'phx-remove',
  },
  {
    label: 'phx-mounted',
    detail: 'Execute JS commands when element mounted',
    documentation: `Executes Phoenix.LiveView.JS commands when the element is added to the DOM.

**Example:**
\`\`\`heex
<div id="modal" phx-mounted={JS.show(to: "#modal", transition: "fade-in")}>
  Modal content
</div>

<div phx-mounted={JS.focus(to: "#first-input")}>
  <input id="first-input" />
</div>
\`\`\`

**Common Use Cases:**
- Auto-focus inputs when form appears
- Animate element entrance
- Initialize client-side state
- Scroll to newly added content

**Difference from phx-hook:**
- \`phx-mounted\`: One-time JS commands
- \`phx-hook\`: Persistent JavaScript lifecycle hooks

**See Also:** JS.show(), JS.focus(), phx-hook

[📖 HexDocs](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.JS.html)`,
    insertText: 'phx-mounted="${1:JS.show()}"',
  },

  // Hooks
  {
    label: 'phx-hook',
    detail: 'Attach a client-side hook',
    documentation: `Attaches a JavaScript hook for advanced client-side interactivity.

**Example:**
\`\`\`heex
<div id="map" phx-hook="Map" data-lat={@lat} data-lng={@lng}></div>
<canvas id="chart" phx-hook="Chart" phx-update="ignore"></canvas>
\`\`\`

**JavaScript Hook:**
\`\`\`javascript
let Hooks = {};
Hooks.Map = {
  mounted() {
    this.map = initMap(this.el);
  },
  updated() {
    this.map.setCenter(this.el.dataset.lat, this.el.dataset.lng);
  },
  destroyed() {
    this.map.destroy();
  }
};

let liveSocket = new LiveSocket("/live", Socket, {hooks: Hooks});
\`\`\`

**Lifecycle Callbacks:**
- \`mounted()\` - Called when element added to DOM
- \`updated()\` - Called when element updated
- \`destroyed()\` - Called before element removed
- \`disconnected()\` - Called when LiveView disconnects
- \`reconnected()\` - Called when LiveView reconnects

**Common Use Cases:**
- Third-party library integration (maps, charts, editors)
- Custom DOM manipulations
- Client-side state management
- WebRTC, WebSockets, or other connections

**Important:** Element must have a unique \`id\` attribute

**See Also:** phx-update="ignore", phx-mounted

[📖 HexDocs](https://hexdocs.pm/phoenix_live_view/js-interop.html#client-hooks)`,
    insertText: 'phx-hook="${1:HookName}"',
  },

  // Feedback
  {
    label: 'phx-disable-with',
    detail: 'Show text while processing',
    documentation: `Replaces button/input text during form submission to show loading state.

**Example:**
\`\`\`heex
<button phx-disable-with="Saving...">Save</button>
<button type="submit" phx-disable-with="Processing payment...">
  Pay Now
</button>
\`\`\`

**How it Works:**
- Replaces button text when form submitted
- Button is disabled during submission
- Original text restored when response received

**Common Use Cases:**
- Form submit buttons
- Payment processing buttons
- Preventing double-clicks
- User feedback during async operations

**See Also:** phx-submit

[📖 HexDocs](https://hexdocs.pm/phoenix_live_view/form-bindings.html#phx-disable-with)`,
    insertText: 'phx-disable-with="${1:Processing...}"',
  },
  {
    label: 'phx-feedback-for',
    detail: 'Associate feedback with input',
    documentation: `Associates error feedback elements with form inputs for better UX timing.

**Example:**
\`\`\`heex
<input type="text" name="user[email]" id="user_email" />
<p class="error" phx-feedback-for="user[email]">
  <%= @errors[:email] %>
</p>
\`\`\`

**How it Works:**
- Error message hidden until user interacts with field
- Shows errors after blur or form submission
- Prevents showing errors on page load
- Works with Phoenix.HTML.Form helpers

**Common Use Cases:**
- Form validation errors
- Field-level error messages
- Inline validation feedback

**Why Use It:**
- Better UX: Don't show errors before user tries to input
- Shows errors at the right time (after blur/submit)
- Prevents "angry red form" on page load

**See Also:** phx-change, phx-blur, phx-submit

[📖 HexDocs](https://hexdocs.pm/phoenix_live_view/form-bindings.html#phx-feedback-for)`,
    insertText: 'phx-feedback-for="${1:input_name}"',
  },

  // Viewport
  {
    label: 'phx-viewport-top',
    detail: 'Trigger event when scrolled to top',
    documentation: `Triggers event when element enters the top of the viewport (scroll detection).

**Example:**
\`\`\`heex
<div id="top-sentinel" phx-viewport-top="load-more-top" phx-throttle="500">
  Loading...
</div>
\`\`\`

**Common Use Cases:**
- Infinite scroll (load older messages/posts)
- Lazy loading above current view
- Scroll position tracking
- Bidirectional pagination

**Best Practices:**
- Use small sentinel elements (e.g., loading spinners)
- Combine with \`phx-throttle\` to avoid excessive requests
- Use with \`phx-update="prepend"\` for top-loading lists

**See Also:** phx-viewport-bottom, phx-throttle, phx-update

[📖 HexDocs](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html#module-scroll-events)`,
    insertText: 'phx-viewport-top="${1:event_name}"',
  },
  {
    label: 'phx-viewport-bottom',
    detail: 'Trigger event when scrolled to bottom',
    documentation: `Triggers event when element enters the bottom of the viewport (scroll detection).

**Example:**
\`\`\`heex
<ul id="messages" phx-update="append">
  <%= for msg <- @messages do %>
    <li><%= msg.text %></li>
  <% end %>
</ul>
<div id="bottom-sentinel" phx-viewport-bottom="load-more" phx-throttle="500">
  Loading...
</div>
\`\`\`

**Common Use Cases:**
- Infinite scroll (Twitter/Facebook-style feed)
- Lazy loading below current view
- Chat message pagination
- "Load more" automation

**Server-side Handler:**
\`\`\`elixir
def handle_event("load-more", _, socket) do
  {:noreply, load_next_page(socket)}
end
\`\`\`

**Best Practices:**
- Use small sentinel elements at list end
- Combine with \`phx-throttle\` to avoid excessive requests
- Use with \`phx-update="append"\` for bottom-loading lists

**See Also:** phx-viewport-top, phx-throttle, phx-update

[📖 HexDocs](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html#module-scroll-events)`,
    insertText: 'phx-viewport-bottom="${1:event_name}"',
  },

  // Connection State
  {
    label: 'phx-page-loading',
    detail: 'Show element during page load',
    documentation: `Controls element visibility during page transitions (LiveView navigation).

**Example:**
\`\`\`heex
<div id="loader" class="phx-page-loading">
  <div class="spinner">Loading...</div>
</div>
\`\`\`

**CSS:**
\`\`\`css
.phx-page-loading { display: none; }
.phx-page-loading.phx-page-loading-show { display: block; }
\`\`\`

**How it Works:**
- Element hidden by default
- \`.phx-page-loading-show\` class added during navigation
- Automatically removed when new page loads

**Common Use Cases:**
- Top-bar loading indicators
- Full-page loading spinners
- Progress bars during navigation

**See Also:** phx-connected, phx-disconnected

[📖 HexDocs](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html#module-loading-states-and-errors)`,
    insertText: 'phx-page-loading',
  },
  {
    label: 'phx-connected',
    detail: 'CSS class when connected',
    documentation: `CSS class applied when LiveView is connected to the server.

**Example:**
\`\`\`heex
<div class="connection-status">
  <span phx-connected="connected">🟢 Connected</span>
</div>
\`\`\`

**CSS:**
\`\`\`css
[phx-connected] { display: none; }
[phx-connected].connected { display: inline; }
\`\`\`

**How it Works:**
- Specified class added when LiveView connection established
- Class removed when connection lost
- Useful for showing connection status to users

**Common Use Cases:**
- Connection status indicators
- Showing "online" badges
- Enabling features only when connected

**See Also:** phx-disconnected, phx-page-loading

[📖 HexDocs](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html#module-loading-states-and-errors)`,
    insertText: 'phx-connected="${1:connected}"',
  },
  {
    label: 'phx-disconnected',
    detail: 'CSS class when disconnected',
    documentation: `CSS class applied when LiveView is disconnected from the server.

**Example:**
\`\`\`heex
<div class="connection-status">
  <span phx-disconnected="disconnected">
    🔴 Connection lost. Retrying...
  </span>
</div>
\`\`\`

**CSS:**
\`\`\`css
[phx-disconnected] { display: none; }
[phx-disconnected].disconnected {
  display: block;
  color: red;
}
\`\`\`

**How it Works:**
- Specified class added when LiveView connection lost
- Class removed when connection re-established
- LiveView automatically attempts to reconnect

**Common Use Cases:**
- "Connection lost" warnings
- Offline mode indicators
- Disabling interactive features during disconnect

**See Also:** phx-connected, phx-page-loading

[📖 HexDocs](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html#module-loading-states-and-errors)`,
    insertText: 'phx-disconnected="${1:disconnected}"',
  },

  // Links and Navigation
  {
    label: 'phx-link',
    detail: 'Create a LiveView patch link',
    documentation: `Creates a link that patches the current LiveView (deprecated - use navigate/patch attributes instead).

**Deprecated:** Use \`navigate\` or \`patch\` attributes on \`<.link>\` component instead.

**Modern Alternative:**
\`\`\`heex
<.link navigate={~p"/users"}>All Users</.link>
<.link patch={~p"/users/\#{@user.id}"}>View User</.link>
\`\`\`

**Old Usage (Deprecated):**
\`\`\`heex
<a href="/users" phx-link="patch">All Users</a>
\`\`\`

**See Also:** Phoenix.Component.link/1

[📖 HexDocs](https://hexdocs.pm/phoenix_live_view/Phoenix.Component.html#link/1)`,
    insertText: 'phx-link="${1:patch}"',
  },
  {
    label: 'phx-click-away',
    detail: 'Trigger event on click outside',
    documentation: `Triggers event when user clicks outside the element boundaries.

**Example:**
\`\`\`heex
<div id="dropdown" phx-click-away="close_dropdown" class={@dropdown_open && "open"}>
  <button phx-click="toggle_dropdown">Menu</button>
  <ul class="dropdown-menu">
    <li>Item 1</li>
    <li>Item 2</li>
  </ul>
</div>
\`\`\`

**How it Works:**
- Listens for clicks anywhere on the page
- Fires event when click occurs outside element
- Does NOT fire when clicking inside element

**Common Use Cases:**
- Closing dropdowns when clicking outside
- Dismissing modals/popovers
- Hiding context menus
- Auto-closing search suggestions

**Best Practices:**
- Combine with local state to show/hide UI
- Use on parent element containing the whole widget

**See Also:** phx-click, phx-window-keydown (for Escape key)

[📖 HexDocs](https://hexdocs.pm/phoenix_live_view/bindings.html#click-away-events)`,
    insertText: 'phx-click-away="${1:event_name}"',
  },
  {
    label: 'phx-capture-click',
    detail: 'Capture click event during capture phase',
    documentation: `Binds click event using event capturing (propagates inwards from parent to target).

**Example:**
\`\`\`heex
<div phx-capture-click="track_clicks">
  <button>Child Button</button>
  <!-- phx-capture-click fires before button's phx-click -->
</div>
\`\`\`

**Event Propagation:**
1. **Capture Phase** (outer → inner): \`phx-capture-click\` fires here
2. **Target Phase**: Element's own click handler
3. **Bubble Phase** (inner → outer): \`phx-click\` fires here

**Common Use Cases:**
- Intercept clicks before children handle them
- Analytics tracking
- Preventing default actions
- Custom event routing

**Difference from phx-click:**
- \`phx-capture-click\`: Fires top-down (parent first)
- \`phx-click\`: Fires bottom-up (child first)

**See Also:** phx-click, phx-click-away

[📖 HexDocs](https://hexdocs.pm/phoenix_live_view/bindings.html#click-events)`,
    insertText: 'phx-capture-click="${1:event_name}"',
  },

  // Upload & Forms
  {
    label: 'phx-drop-target',
    detail: 'File drop target for uploads',
    documentation: `Marks element as a drop target for drag-and-drop file uploads.

**Example:**
\`\`\`heex
<div phx-drop-target={@uploads.avatar.ref} class="drop-zone">
  Drop files here or click to upload
</div>

<form phx-submit="save" phx-change="validate">
  <input type="file" name="avatar" phx-drop-target={@uploads.avatar.ref} />
</form>
\`\`\`

**Server-side Setup:**
\`\`\`elixir
def mount(_params, _session, socket) do
  {:ok, allow_upload(socket, :avatar, accept: ~w(.jpg .png), max_entries: 1)}
end
\`\`\`

**How it Works:**
- User drags files over element with \`phx-drop-target\`
- Element receives \`phx-drop-active\` class while dragging
- Files automatically added to upload when dropped
- Upload ref connects drop zone to specific upload

**Common Use Cases:**
- Drag-and-drop file uploads
- Image upload zones
- Document/attachment uploads

**See Also:** allow_upload/3, phx-submit

[📖 HexDocs](https://hexdocs.pm/phoenix_live_view/uploads.html)`,
    insertText: 'phx-drop-target="${1:@uploads.${2:name}.ref}"',
  },
  {
    label: 'phx-trigger-action',
    detail: 'Trigger form submit on DOM patch',
    documentation: `Triggers a standard HTTP form submit on the next DOM patch (for redirects after validation).

**Example:**
\`\`\`heex
<form phx-submit="save" phx-trigger-action={@trigger_action} action="/posts">
  <input type="text" name="post[title]" />
  <button type="submit">Save</button>
</form>
\`\`\`

**Server-side Handler:**
\`\`\`elixir
def handle_event("save", %{"post" => post_params}, socket) do
  case Posts.create_post(post_params) do
    {:ok, post} ->
      {:noreply, socket |> put_flash(:info, "Post created") |> assign(trigger_action: true)}
    {:error, changeset} ->
      {:noreply, assign(socket, changeset: changeset)}
  end
end
\`\`\`

**How it Works:**
- When \`@trigger_action\` becomes truthy, form submits via HTTP
- Used to trigger redirects after LiveView validation passes
- Allows standard form submission with all benefits of LiveView validation

**Common Use Cases:**
- OAuth/external authentication flows
- File downloads after validation
- Redirects to external URLs
- Standard form submission after LiveView validation

**See Also:** phx-submit, phx-change

[📖 HexDocs](https://hexdocs.pm/phoenix_live_view/form-bindings.html#phx-trigger-action)`,
    insertText: 'phx-trigger-action',
  },
  {
    label: 'phx-auto-recover',
    detail: 'Auto-recover form on reconnect',
    documentation: `Enables automatic form recovery when LiveView reconnects after disconnect.

**Example:**
\`\`\`heex
<form phx-submit="save" phx-auto-recover="recover_form">
  <input type="text" name="post[title]" value={@changeset[:title]} />
  <textarea name="post[body]"><%= @changeset[:body] %></textarea>
  <button type="submit">Save</button>
</form>
\`\`\`

**Server-side Handler:**
\`\`\`elixir
def handle_event("recover_form", %{"post" => post_params}, socket) do
  changeset = Post.changeset(%Post{}, post_params)
  {:noreply, assign(socket, changeset: changeset)}
end
\`\`\`

**How it Works:**
- Form data cached client-side during editing
- When LiveView reconnects, cached data sent to server
- Server can restore form state from cached data
- Prevents data loss during temporary disconnects

**Common Use Cases:**
- Long-form content editing
- Important forms where data loss is critical
- Offline-first applications

**See Also:** phx-change, phx-connected, phx-disconnected

[📖 HexDocs](https://hexdocs.pm/phoenix_live_view/form-bindings.html#phx-auto-recover)`,
    insertText: 'phx-auto-recover="${1:recover_event}"',
  },

  // Track Static
  {
    label: 'phx-track-static',
    detail: 'Track static asset changes',
    documentation: `Tracks static asset changes and triggers full page reload when assets update.

**Example:**
\`\`\`heex
<link rel="stylesheet" href="/assets/app.css" phx-track-static />
<script src="/assets/app.js" phx-track-static></script>
\`\`\`

**How it Works:**
- LiveView tracks static asset versions
- When asset changes (during deployment), page automatically reloads
- Ensures users always have latest CSS/JS
- Prevents stale client-side code issues

**Common Use Cases:**
- Production deployments
- Development with asset changes
- Ensuring CSS/JS in sync with server code

**Where to Use:**
- \`<link>\` tags for CSS
- \`<script>\` tags for JavaScript
- Other static assets that affect LiveView behavior

**Important:** Already added by default in Phoenix 1.7+ templates

[📖 HexDocs](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html#module-static-assets)`,
    insertText: 'phx-track-static',
  },
];

/**
 * Get Phoenix attribute completions with context-aware and event-aware priority sorting
 *
 * @param context - Optional element context for prioritizing relevant attributes
 * @param hasEvents - Whether the LiveView module has handle_event/3 callbacks
 * @returns Array of CompletionItems with context-aware and event-aware sorting
 *
 * @example
 * // Inside <form> tag - form-specific attrs (phx-submit, phx-change) appear first
 * getPhoenixCompletions('form')
 *
 * // Inside <input> tag - focusable attrs (phx-blur, phx-focus) appear first
 * getPhoenixCompletions('input')
 *
 * // LiveView with events - event-triggering attrs appear first with ⚡ emoji
 * getPhoenixCompletions('generic', true)
 */
/**
 * Get documentation for a specific Phoenix attribute
 * Used for hover documentation
 *
 * @param attributeName - The Phoenix attribute name (e.g., 'phx-click', 'phx-value-id')
 * @returns The markdown documentation string, or null if attribute not found
 */
export function getPhoenixAttributeDocumentation(attributeName: string): string | null {
  // Handle phx-value-* pattern
  const attrKey = attributeName.startsWith('phx-value-') ? 'phx-value-' : attributeName;

  const attr = phoenixAttributes.find(a => a.label === attrKey);
  return attr ? attr.documentation : null;
}

export function getPhoenixCompletions(
  context?: ElementContext,
  hasEvents?: boolean
): CompletionItem[] {
  return phoenixAttributes.map((attr, index) => {
    // Determine sort priority based on:
    // 1. Context-specific (form/input) - existing logic
    // 2. Event-triggering when LiveView has events - NEW
    const isPrioritized =
      (context && shouldPrioritizeAttribute(attr.label, context)) ||
      (hasEvents && EVENT_TRIGGERING_ATTRIBUTES.includes(attr.label));

    // Prioritized attributes get '!0' prefix, others get '!6' prefix
    const priorityPrefix = isPrioritized ? '!0' : '!6';
    const sortText = `${priorityPrefix}${index.toString().padStart(3, '0')}`;

    // Add ⚡ emoji to event-triggering attrs when LiveView has events
    const isEventTriggering = EVENT_TRIGGERING_ATTRIBUTES.includes(attr.label);
    const detail = hasEvents && isEventTriggering
      ? `⚡ ${attr.detail}`
      : attr.detail;

    return {
      label: attr.label,
      kind: CompletionItemKind.Keyword,
      detail,
      documentation: {
        kind: MarkupKind.Markdown,
        value: attr.documentation,
      },
      insertText: attr.insertText,
      insertTextFormat: InsertTextFormat.Snippet,
      sortText,
    };
  });
}

/**
 * Get context-aware phx-value-* completions based on :for loop context
 * When inside a :for loop, suggests phx-value-* attributes based on the loop variable's schema fields
 *
 * Example:
 * <div :for={product <- @products}>
 *   <button phx-click="select" phx-value-█>  <!-- suggests: phx-value-id, phx-value-slug, etc. -->
 * </div>
 */
export function getContextAwarePhxValueCompletions(
  text: string,
  offset: number,
  linePrefix: string,
  filePath: string,
  componentsRegistry: ComponentsRegistry,
  controllersRegistry: ControllersRegistry,
  schemaRegistry: SchemaRegistry
): CompletionItem[] {
  const completions: CompletionItem[] = [];

  // Only trigger when typing 'phx-value-' or 'phx-value-X'
  const phxValuePattern = /phx-value-([a-z_]*)?$/;
  if (!phxValuePattern.test(linePrefix)) {
    return completions;
  }

  // Detect if we're inside a :for loop
  const forLoop = findEnclosingForLoop(text, offset);
  if (!forLoop || !forLoop.variable) {
    return completions;
  }

  const loopVar = forLoop.variable;

  // Infer the type of the loop variable using the same logic as assigns.ts
  const baseType = inferAssignType(
    componentsRegistry,
    controllersRegistry,
    schemaRegistry,
    filePath,
    loopVar.baseAssign,
    offset,
    text
  );

  if (!baseType) {
    return completions;
  }

  // Determine the target type for the loop variable
  let targetType: string | null = null;

  if (loopVar.path.length === 0) {
    // Direct list access: product <- @products
    targetType = baseType;
  } else {
    // Field access: image <- @product.images
    const baseSchema = schemaRegistry.getSchema(baseType);
    if (!baseSchema) {
      return completions;
    }

    const loopField = baseSchema.fields.find(f => f.name === loopVar.path[0]);
    if (!loopField || !loopField.elixirType) {
      return completions;
    }

    targetType = schemaRegistry.resolveTypeName(loopField.elixirType, baseSchema.moduleName);
    if (!targetType) {
      return completions;
    }
  }

  // Get fields from the target schema
  const targetSchema = schemaRegistry.getSchema(targetType);
  if (!targetSchema) {
    return completions;
  }

  // Generate phx-value-* completions for relevant fields
  // Prioritize common field names that are typically used with events
  const relevantFieldNames = ['id', 'slug', 'status', 'type', 'name', 'key', 'action', 'role'];

  targetSchema.fields.forEach((field, index) => {
    // Skip associations and embedded schemas for phx-value (only use simple types)
    if (field.elixirType) {
      return;
    }

    // Determine if this is a high-priority field
    const isRelevant = relevantFieldNames.includes(field.name);
    const sortPrefix = isRelevant ? '!05' : '!06'; // Between event attrs (!0) and general Phoenix attrs (!6)

    // Build helpful documentation
    const fieldTypeDisplay = `:${field.type}`;
    let doc = `Send **${field.name}** from loop variable **${loopVar.name}** with the event.\n\n`;
    doc += `**Field Type:** ${fieldTypeDisplay}\n\n`;
    doc += `**Example:**\n\`\`\`heex\n`;
    doc += `<div :for={${loopVar.name} <- ${loopVar.source}}>\n`;
    doc += `  <button phx-click="select" phx-value-${field.name}={${loopVar.name}.${field.name}}>\n`;
    doc += `    Select\n`;
    doc += `  </button>\n`;
    doc += `</div>\n\`\`\`\n\n`;
    doc += `**Server-side:**\n\`\`\`elixir\n`;
    doc += `def handle_event("select", %{"${field.name}" => ${field.name}}, socket) do\n`;
    doc += `  # Use ${field.name}\n`;
    doc += `  {:noreply, socket}\n`;
    doc += `end\n\`\`\``;

    completions.push({
      label: `phx-value-${field.name}`,
      kind: CompletionItemKind.Property,
      detail: `From ${loopVar.name}: ${fieldTypeDisplay}`,
      documentation: {
        kind: MarkupKind.Markdown,
        value: doc,
      },
      insertText: `phx-value-${field.name}={${loopVar.name}.${field.name}}`,
      insertTextFormat: InsertTextFormat.PlainText,
      sortText: `${sortPrefix}${index.toString().padStart(3, '0')}`,
    });
  });

  return completions;
}
