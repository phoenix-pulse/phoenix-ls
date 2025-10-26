import { CompletionItem, CompletionItemKind, InsertTextFormat, MarkupKind } from 'vscode-languageserver/node';

/**
 * Phoenix.LiveView.JS command completions
 * These commands provide client-side JavaScript utilities for LiveView
 * Based on: https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.JS.html
 */

export interface JSCommand {
  label: string;
  detail: string;
  documentation: string;
  insertText: string;
  isChainable: boolean; // Can be used in a pipe chain
}

const jsCommands: JSCommand[] = [
  // Visibility Commands
  {
    label: 'JS.show',
    detail: 'Show element(s) with optional transitions',
    documentation: `Shows element(s) selected by CSS selector with optional transition effects.

**Example:**
\`\`\`heex
<button phx-click={JS.show("#modal")}>Open Modal</button>
<button phx-click={JS.show("#alert", transition: "fade-in", time: 300)}>
  Show Alert
</button>
\`\`\`

**Options:**
- \`transition\` - CSS class for transition effect
- \`time\` - Duration in milliseconds (default: 200)
- \`display\` - CSS display value (default: "block")
- \`to\` - CSS selector (required)

**Common Use Cases:**
- Opening modals and dialogs
- Revealing hidden content
- Showing notifications and alerts
- Expanding accordion sections

**Chainable:**
\`\`\`elixir
JS.show("#modal")
|> JS.focus("#modal input")
|> JS.transition("#backdrop", "fade-in")
\`\`\`

**See Also:** JS.hide, JS.toggle, phx-mounted

[📖 HexDocs](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.JS.html#show/1)`,
    insertText: 'JS.show("${1:#selector}"${2:, transition: "${3:fade-in}", time: ${4:300}})',
    isChainable: true,
  },
  {
    label: 'JS.hide',
    detail: 'Hide element(s) with optional transitions',
    documentation: `Hides element(s) selected by CSS selector with optional transition effects.

**Example:**
\`\`\`heex
<button phx-click={JS.hide("#modal")}>Close Modal</button>
<button phx-click={JS.hide("#dropdown", transition: "fade-out", time: 200)}>
  Close Menu
</button>
\`\`\`

**Options:**
- \`transition\` - CSS class for transition effect
- \`time\` - Duration in milliseconds (default: 200)
- \`to\` - CSS selector (required)

**Common Use Cases:**
- Closing modals and dialogs
- Hiding notifications after timeout
- Collapsing expandable sections
- Dismissing dropdowns and tooltips

**With Transitions:**
\`\`\`css
.fade-out {
  animation: fadeOut 200ms ease-out;
}

@keyframes fadeOut {
  from { opacity: 1; }
  to { opacity: 0; }
}
\`\`\`

**Chainable:**
\`\`\`elixir
JS.hide("#modal", transition: "fade-out")
|> JS.hide("#backdrop", transition: "fade-out")
\`\`\`

**See Also:** JS.show, JS.toggle, phx-remove

[📖 HexDocs](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.JS.html#hide/1)`,
    insertText: 'JS.hide("${1:#selector}"${2:, transition: "${3:fade-out}", time: ${4:300}})',
    isChainable: true,
  },
  {
    label: 'JS.toggle',
    detail: 'Toggle element visibility',
    documentation: `Toggles visibility of element(s) selected by CSS selector.

**Example:**
\`\`\`heex
<button phx-click={JS.toggle("#dropdown")}>Toggle Menu</button>
<button phx-click={JS.toggle("#panel", in: "slide-in", out: "slide-out", time: 300)}>
  Toggle Panel
</button>
\`\`\`

**Options:**
- \`in\` - CSS class for showing transition
- \`out\` - CSS class for hiding transition
- \`time\` - Duration in milliseconds (default: 200)
- \`display\` - CSS display value when shown (default: "block")
- \`to\` - CSS selector (required)

**Common Use Cases:**
- Dropdown menus
- Collapsible sidebars
- Accordion sections
- Mobile navigation menus

**How it Works:**
- If element is hidden → Shows it with \`in\` transition
- If element is visible → Hides it with \`out\` transition

**Complete Example:**
\`\`\`heex
<div class="sidebar-toggle">
  <button phx-click={JS.toggle("#sidebar",
    in: "slide-in-left",
    out: "slide-out-left",
    time: 250
  )}>
    Menu
  </button>
</div>
\`\`\`

**See Also:** JS.show, JS.hide, JS.toggle_class

[📖 HexDocs](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.JS.html#toggle/1)`,
    insertText: 'JS.toggle("${1:#selector}"${2:, in: "${3:fade-in}", out: "${4:fade-out}", time: ${5:300}})',
    isChainable: true,
  },

  // Class Manipulation
  {
    label: 'JS.add_class',
    detail: 'Add CSS class(es) to element(s)',
    documentation: `Adds one or more CSS classes to element(s).

**Example:**
\`\`\`heex
<button phx-click={JS.add_class("#button", "active")}>Activate</button>
<button phx-click={JS.add_class(".card", "highlight pulse")}>
  Highlight Cards
</button>
\`\`\`

**Options:**
- \`to\` - CSS selector (required)
- \`transition\` - CSS class for transition effect
- \`time\` - Duration in milliseconds (default: 200)

**Common Use Cases:**
- Adding active/selected state to buttons
- Highlighting elements on interaction
- Applying animation classes
- Theme switching (dark mode, high contrast)

**Multiple Classes:**
\`\`\`elixir
JS.add_class("#card", "shadow-lg border-blue-500")
\`\`\`

**With Transition:**
\`\`\`elixir
JS.add_class("#alert", "visible", transition: "fade-in", time: 300)
\`\`\`

**Chainable:**
\`\`\`elixir
JS.add_class("#nav", "active")
|> JS.remove_class("#prev-nav", "active")
\`\`\`

**See Also:** JS.remove_class, JS.toggle_class

[📖 HexDocs](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.JS.html#add_class/1)`,
    insertText: 'JS.add_class("${1:#selector}", "${2:class-name}"${3:, transition: "${4:transition}", time: ${5:300}})',
    isChainable: true,
  },
  {
    label: 'JS.remove_class',
    detail: 'Remove CSS class(es) from element(s)',
    documentation: `Removes one or more CSS classes from element(s).

**Example:**
\`\`\`heex
<button phx-click={JS.remove_class("#button", "active")}>
  Deactivate
</button>
<button phx-click={JS.remove_class(".card", "highlight pulse")}>
  Remove Highlight
</button>
\`\`\`

**Options:**
- \`to\` - CSS selector (required)
- \`transition\` - CSS class for transition effect
- \`time\` - Duration in milliseconds (default: 200)

**Common Use Cases:**
- Removing active/selected state
- Dismissing highlights or badges
- Clearing error states
- Resetting UI after interaction

**Multiple Classes:**
\`\`\`elixir
JS.remove_class("#form", "was-validated has-error")
\`\`\`

**Chainable Example:**
\`\`\`elixir
JS.remove_class(".tab", "active")
|> JS.add_class("#tab-\#{id}", "active")
|> JS.show("#panel-\#{id}")
\`\`\`

**See Also:** JS.add_class, JS.toggle_class

[📖 HexDocs](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.JS.html#remove_class/1)`,
    insertText: 'JS.remove_class("${1:#selector}", "${2:class-name}"${3:, transition: "${4:transition}", time: ${5:300}})',
    isChainable: true,
  },
  {
    label: 'JS.toggle_class',
    detail: 'Toggle CSS class(es) on element(s)',
    documentation: `Toggles one or more CSS classes on element(s).

**Example:**
\`\`\`heex
<button phx-click={JS.toggle_class("#menu", "open")}>
  Toggle Menu
</button>
<button phx-click={JS.toggle_class("body", "dark-mode")}>
  Toggle Theme
</button>
\`\`\`

**Options:**
- \`to\` - CSS selector (required)
- \`transition\` - CSS class for transition effect
- \`time\` - Duration in milliseconds (default: 200)

**Common Use Cases:**
- Toggling navigation menus (open/closed)
- Dark mode switching
- Expanding/collapsing sections
- Button pressed states

**How it Works:**
- If class exists → Removes it
- If class doesn't exist → Adds it

**Complete Example:**
\`\`\`heex
<button
  phx-click={JS.toggle_class("#sidebar", "w-64", to: "#sidebar")}
  class="sidebar-toggle"
>
  <svg class="icon">...</svg>
</button>
\`\`\`

**Chainable:**
\`\`\`elixir
JS.toggle_class("#icon", "rotate-180")
|> JS.toggle("#panel", in: "slide-down", out: "slide-up")
\`\`\`

**See Also:** JS.add_class, JS.remove_class, JS.toggle

[📖 HexDocs](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.JS.html#toggle_class/1)`,
    insertText: 'JS.toggle_class("${1:#selector}", "${2:class-name}"${3:, transition: "${4:transition}", time: ${5:300}})',
    isChainable: true,
  },

  // Attribute Manipulation
  {
    label: 'JS.set_attribute',
    detail: 'Set attribute on element(s)',
    documentation: `Sets an attribute value on element(s).

**Example:**
\`\`\`heex
<button phx-click={JS.set_attribute("#input", {"disabled", "disabled"})}>
  Disable Input
</button>
<button phx-click={JS.set_attribute(".tab", {"aria-selected", "true"})}>
  Select Tab
</button>
\`\`\`

**Options:**
- \`to\` - CSS selector (required)

**Common Use Cases:**
- Setting ARIA attributes for accessibility
- Enabling/disabling form inputs
- Setting data attributes
- Updating custom attributes

**Multiple Attributes:**
\`\`\`elixir
JS.set_attribute("#input", {"disabled", "disabled"})
|> JS.set_attribute("#input", {"aria-busy", "true"})
\`\`\`

**Accessibility Example:**
\`\`\`elixir
JS.set_attribute("#panel", {"aria-expanded", "true"})
|> JS.set_attribute("#trigger", {"aria-pressed", "true"})
\`\`\`

**See Also:** JS.remove_attribute

[📖 HexDocs](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.JS.html#set_attribute/1)`,
    insertText: 'JS.set_attribute("${1:#selector}", {"${2:attribute}", "${3:value}"})',
    isChainable: true,
  },
  {
    label: 'JS.remove_attribute',
    detail: 'Remove attribute from element(s)',
    documentation: `Removes an attribute from element(s).

**Example:**
\`\`\`heex
<button phx-click={JS.remove_attribute("#input", "disabled")}>
  Enable Input
</button>
<button phx-click={JS.remove_attribute(".tab", "aria-selected")}>
  Deselect Tab
</button>
\`\`\`

**Options:**
- \`to\` - CSS selector (required)

**Common Use Cases:**
- Re-enabling form inputs
- Clearing ARIA states
- Removing data attributes
- Resetting custom attributes

**Example with Form:**
\`\`\`elixir
JS.remove_attribute("#submit-btn", "disabled")
|> JS.remove_attribute("#form", "aria-busy")
\`\`\`

**See Also:** JS.set_attribute

[📖 HexDocs](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.JS.html#remove_attribute/1)`,
    insertText: 'JS.remove_attribute("${1:#selector}", "${2:attribute}")',
    isChainable: true,
  },

  // Transition
  {
    label: 'JS.transition',
    detail: 'Apply CSS transition to element(s)',
    documentation: `Applies a CSS transition to element(s).

**Example:**
\`\`\`heex
<button phx-click={JS.transition("#card", "fade-in-scale")}>
  Animate Card
</button>
<button phx-click={JS.transition(".item", "slide-in", time: 500)}>
  Slide In
</button>
\`\`\`

**Options:**
- \`to\` - CSS selector (required)
- \`time\` - Duration in milliseconds (default: 200)

**CSS Setup:**
\`\`\`css
.fade-in-scale {
  animation: fadeInScale 300ms ease-out;
}

@keyframes fadeInScale {
  from {
    opacity: 0;
    transform: scale(0.95);
  }
  to {
    opacity: 1;
    transform: scale(1);
  }
}
\`\`\`

**Common Use Cases:**
- Entry/exit animations
- Attention grabbers (pulse, shake)
- Page transitions
- Loading states

**Chainable:**
\`\`\`elixir
JS.show("#modal")
|> JS.transition("#modal", "zoom-in", time: 250)
|> JS.focus("#modal input")
\`\`\`

**See Also:** JS.show, JS.hide, JS.add_class

[📖 HexDocs](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.JS.html#transition/1)`,
    insertText: 'JS.transition("${1:#selector}", "${2:transition-class}"${3:, time: ${4:300}})',
    isChainable: true,
  },

  // Focus
  {
    label: 'JS.focus',
    detail: 'Focus element',
    documentation: `Sets focus to the first element matching the selector.

**Example:**
\`\`\`heex
<button phx-click={JS.show("#modal") |> JS.focus("#search-input")}>
  Open Search
</button>
<button phx-click={JS.focus("#modal input[type='text']")}>
  Focus Input
</button>
\`\`\`

**Options:**
- \`to\` - CSS selector (required)

**Common Use Cases:**
- Auto-focusing search inputs when modal opens
- Setting focus after form submission
- Improving accessibility (keyboard navigation)
- Focusing first error field in forms

**Accessibility Best Practice:**
\`\`\`elixir
JS.show("#modal")
|> JS.focus("#modal [role='dialog']")
|> JS.set_attribute("#modal", {"aria-hidden", "false"})
\`\`\`

**With Form Validation:**
\`\`\`elixir
# Focus first invalid field
JS.focus("#form .is-invalid:first")
\`\`\`

**Chainable:**
\`\`\`elixir
JS.show("#search-modal")
|> JS.transition("#search-modal", "fade-in")
|> JS.focus("#search-input")
\`\`\`

**See Also:** JS.focus_first, phx-focus

[📖 HexDocs](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.JS.html#focus/1)`,
    insertText: 'JS.focus("${1:#selector}")',
    isChainable: true,
  },
  {
    label: 'JS.focus_first',
    detail: 'Focus first focusable element',
    documentation: `Sets focus to the first focusable element within the selector.

**Example:**
\`\`\`heex
<button phx-click={JS.show("#form") |> JS.focus_first("#form")}>
  Open Form
</button>
<button phx-click={JS.focus_first("#modal")}>
  Focus Modal
</button>
\`\`\`

**Options:**
- \`to\` - CSS selector (required)

**How it Works:**
- Searches for the first focusable element within container
- Focusable elements: input, button, select, textarea, a[href], [tabindex]
- Useful when you don't know exact input ID

**Common Use Cases:**
- Auto-focusing first field in forms
- Focusing first interactive element in modals
- Improving keyboard navigation
- Accessibility enhancements

**Example with Modal:**
\`\`\`elixir
JS.show("#dialog")
|> JS.focus_first("#dialog")
|> JS.set_attribute("#dialog", {"aria-hidden", "false"})
\`\`\`

**Difference from JS.focus:**
- \`JS.focus\`: Requires exact selector
- \`JS.focus_first\`: Finds first focusable child automatically

**See Also:** JS.focus

[📖 HexDocs](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.JS.html#focus_first/1)`,
    insertText: 'JS.focus_first("${1:#selector}")',
    isChainable: true,
  },

  // Server Communication
  {
    label: 'JS.push',
    detail: 'Push event to server',
    documentation: `Pushes an event to the server (triggers \`handle_event/3\` callback).

**Example:**
\`\`\`heex
<button phx-click={JS.push("save")}>Save</button>
<button phx-click={JS.push("update", value: %{id: @item.id})}>
  Update
</button>
<button phx-click={JS.push("delete", target: @myself)}>
  Delete
</button>
\`\`\`

**Options:**
- \`value\` - Map of values to send to server
- \`target\` - Component target (default: current LiveView)
- \`loading\` - Element selector to disable during request
- \`page_loading\` - Show page loading state (boolean)

**Server-side Handler:**
\`\`\`elixir
def handle_event("save", %{"id" => id}, socket) do
  # Handle the event
  {:noreply, socket}
end
\`\`\`

**Common Use Cases:**
- Client-initiated server actions
- Saving without form submission
- Triggering background jobs
- Multi-step workflows

**With Loading State:**
\`\`\`elixir
JS.push("process", loading: "#submit-btn")
\`\`\`

**Chainable:**
\`\`\`elixir
JS.push("save")
|> JS.hide("#modal")
|> JS.navigate("/dashboard")
\`\`\`

**See Also:** phx-click, handle_event/3

[📖 HexDocs](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.JS.html#push/1)`,
    insertText: 'JS.push("${1:event-name}"${2:, value: %{${3:key}: ${4:value}\\}})',
    isChainable: true,
  },

  // Navigation
  {
    label: 'JS.navigate',
    detail: 'Navigate to URL (full page load)',
    documentation: `Navigates to a URL with a full page reload.

**Example:**
\`\`\`heex
<button phx-click={JS.navigate("/users")}>View Users</button>
<button phx-click={JS.navigate(~p"/posts/\#{@post.id}")}>
  View Post
</button>
\`\`\`

**When to Use:**
- Navigating to different LiveView
- Going to static pages
- External URLs
- When you want full page reload

**Difference from JS.patch:**
- \`JS.navigate\`: Full page reload (LiveView mount/1 called)
- \`JS.patch\`: Same LiveView, handle_params/3 called

**With Confirmation:**
\`\`\`elixir
JS.push("confirm_navigate")
|> JS.navigate("/logout")
\`\`\`

**See Also:** JS.patch, <.link navigate={...}>

[📖 HexDocs](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.JS.html#navigate/1)`,
    insertText: 'JS.navigate("${1:/path}")',
    isChainable: true,
  },
  {
    label: 'JS.patch',
    detail: 'Patch LiveView (no page reload)',
    documentation: `Patches the current LiveView without a full page reload.

**Example:**
\`\`\`heex
<button phx-click={JS.patch("/users?page=2")}>Next Page</button>
<button phx-click={JS.patch(~p"/posts/\#{@post.id}/edit")}>
  Edit
</button>
\`\`\`

**When to Use:**
- Updating URL params (pagination, filters)
- Switching tabs or views in same LiveView
- Maintaining LiveView state
- SEO-friendly navigation

**How it Works:**
- URL changes in browser
- \`handle_params/3\` callback triggered
- State preserved (assigns, components)
- No full page reload

**Example with Tabs:**
\`\`\`elixir
JS.patch(~p"/profile?tab=settings")
|> JS.add_class("#settings-tab", "active")
|> JS.remove_class(".tab", "active", to: "#settings-tab")
\`\`\`

**Difference from JS.navigate:**
- \`JS.patch\`: Same LiveView, handle_params/3 called
- \`JS.navigate\`: Full page reload, mount/1 called

**See Also:** JS.navigate, handle_params/3, <.link patch={...}>

[📖 HexDocs](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.JS.html#patch/1)`,
    insertText: 'JS.patch("${1:/path}")',
    isChainable: true,
  },

  // DOM Events
  {
    label: 'JS.dispatch',
    detail: 'Dispatch custom DOM event',
    documentation: `Dispatches a custom DOM event from element(s).

**Example:**
\`\`\`heex
<button phx-click={JS.dispatch("click", to: "#hidden-button")}>
  Trigger Click
</button>
<button phx-click={JS.dispatch("custom:event", to: "#container",
  detail: %{id: @item.id})}>
  Dispatch Custom
</button>
\`\`\`

**Options:**
- \`to\` - Target selector (required)
- \`detail\` - Event detail data (map)
- \`bubbles\` - Allow event to bubble (default: true)

**Common Use Cases:**
- Triggering third-party library events
- Communicating with phx-hooks
- Simulating user interactions
- Custom event systems

**With phx-hook:**
\`\`\`javascript
// In hook
this.handleEvent("custom:event", ({detail}) => {
  console.log("Received:", detail.id);
});
\`\`\`

\`\`\`heex
<div id="chart" phx-hook="Chart"></div>
<button phx-click={JS.dispatch("chart:update", to: "#chart",
  detail: %{data: @chart_data})}>
  Update Chart
</button>
\`\`\`

**Chainable:**
\`\`\`elixir
JS.dispatch("submit", to: "#form")
|> JS.push("track_submit")
\`\`\`

**See Also:** phx-hook, JS.exec

[📖 HexDocs](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.JS.html#dispatch/1)`,
    insertText: 'JS.dispatch("${1:event-name}", to: "${2:#selector}"${3:, detail: %{${4:key}: ${5:value}\\}})',
    isChainable: true,
  },

  // Exec (Advanced)
  {
    label: 'JS.exec',
    detail: 'Execute custom JavaScript',
    documentation: `Executes custom JavaScript code on element(s).

**Example:**
\`\`\`heex
<button phx-click={JS.exec("console.log", to: "#element")}>
  Log Element
</button>
\`\`\`

**Options:**
- \`to\` - CSS selector (required)

**⚠️ Warning:**
Use sparingly. Prefer built-in JS commands when possible:
- Use \`JS.show/hide\` instead of \`exec("style.display")\`
- Use \`JS.add_class\` instead of \`exec("classList.add")\`
- Use \`JS.dispatch\` for custom events

**Valid Use Cases:**
- Calling third-party library methods
- Complex DOM manipulations not covered by built-in commands
- Temporary workarounds

**Example with Third-Party Library:**
\`\`\`heex
<button phx-click={JS.exec("scrollIntoView", to: "#target")}>
  Scroll To Target
</button>
\`\`\`

**Note:** The \`to\` option specifies which element(s) to call the function on. The element becomes \`this\` in the JavaScript context.

**See Also:** JS.dispatch, phx-hook

[📖 HexDocs](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.JS.html#exec/1)`,
    insertText: 'JS.exec("${1:js-function}", to: "${2:#selector}")',
    isChainable: true,
  },
];

/**
 * Get JS command completions for use in phx-* attribute values
 */
export function getJSCommandCompletions(): CompletionItem[] {
  return jsCommands.map((cmd, index) => ({
    label: cmd.label,
    kind: CompletionItemKind.Function,
    detail: cmd.detail,
    documentation: {
      kind: MarkupKind.Markdown,
      value: cmd.documentation,
    },
    insertText: cmd.insertText,
    insertTextFormat: InsertTextFormat.Snippet,
    sortText: `!1${index.toString().padStart(3, '0')}`, // Priority after event names but before HTML attrs
  }));
}

/**
 * Get chainable JS command completions (for use after pipe |>)
 */
export function getChainableJSCompletions(): CompletionItem[] {
  return jsCommands
    .filter((cmd) => cmd.isChainable)
    .map((cmd, index) => {
      // Remove "JS." prefix for chained calls
      const label = cmd.label.replace('JS.', '');
      return {
        label,
        kind: CompletionItemKind.Function,
        detail: cmd.detail,
        documentation: {
          kind: MarkupKind.Markdown,
          value: cmd.documentation + '\n\n**Chainable:** This command can be used with the `|>` operator.',
        },
        insertText: cmd.insertText.replace('JS.', ''),
        insertTextFormat: InsertTextFormat.Snippet,
        sortText: `!0${index.toString().padStart(3, '0')}`, // High priority in pipe context
      };
    });
}

/**
 * Check if the context suggests JS command usage
 */
export function isJSCommandContext(linePrefix: string): boolean {
  // Look for patterns like:
  // phx-click={JS.
  // phx-click="JS.
  // |>
  return (
    /phx-[a-z-]+\s*=\s*["{]\s*JS\./.test(linePrefix) ||
    /\|\>\s*$/.test(linePrefix)
  );
}

/**
 * Check if we're in a pipe chain context
 */
export function isPipeChainContext(linePrefix: string): boolean {
  return /\|\>\s*$/.test(linePrefix);
}
