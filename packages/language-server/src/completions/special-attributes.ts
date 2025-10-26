import { CompletionItem, CompletionItemKind, InsertTextFormat, MarkupKind, TextEdit, Range, Position } from 'vscode-languageserver/node';
import { TextDocument } from 'vscode-languageserver-textdocument';

/**
 * Phoenix LiveView special template attributes
 * Introduced in LiveView 0.18
 *
 * These provide syntactic sugar for common template patterns:
 * - :for - Loop comprehensions (replaces <%= for ... do %>)
 * - :if - Conditional rendering (replaces <%= if ... do %>)
 * - :let - Yield values from components/slots back to caller
 * - :key - Efficient diffing for :for loops
 */
const specialAttributes = [
  {
    label: ':for',
    detail: 'Loop comprehension',
    documentation: `Provides shorthand syntax for iterating over collections directly on HTML elements and components.

**Basic Loop:**
\`\`\`heex
<div :for={item <- @items}>
  {item.name}
</div>
\`\`\`

**With Pattern Matching:**
\`\`\`heex
<tr :for={{id, user} <- @users}>
  <td>{id}</td>
  <td>{user.name}</td>
</tr>
\`\`\`

**With Index (using Enum.with_index):**
\`\`\`heex
<li :for={{item, index} <- Enum.with_index(@items)} :key={item.id}>
  {index + 1}. {item.name}
</li>
\`\`\`

**With Guards:**
\`\`\`heex
<div :for={user <- @users, user.active}>
  {user.name}
</div>
\`\`\`

**Common Use Cases:**
- Rendering lists of items (tables, cards, lists)
- Iterating over collections with complex markup
- Building navigation menus from data
- Displaying search results or filtered data

**Best Practices:**
- **Always use with :key** - Provide unique \`:key\` attribute for efficient DOM diffing
- Prefer \`:for\` over \`<%= for ... do %>\` - Cleaner syntax and better tooling support
- Use pattern matching to destructure complex data structures
- Combine with \`:if\` for conditional rendering within loops

**See Also:** :key, :if, Enum.with_index/1

[📖 HexDocs](https://hexdocs.pm/phoenix_live_view/Phoenix.Component.html#module-the-for-attribute)`,
    insertText: ':for={${1:item} <- ${2:@items}}',
    sortText: '!0001',
  },
  {
    label: ':if',
    detail: 'Conditional rendering',
    documentation: `Provides shorthand syntax for conditionally rendering elements and components.

**Basic Conditional:**
\`\`\`heex
<div :if={@show_alert} class="alert">
  Important message!
</div>
\`\`\`

**With Negation:**
\`\`\`heex
<p :if={!@loading}>
  Content loaded successfully
</p>
\`\`\`

**With Complex Conditions:**
\`\`\`heex
<button :if={@user && @user.admin?}>
  Admin Panel
</button>
\`\`\`

**Pattern Matching:**
\`\`\`heex
<div :if={@status == :success} class="success">
  Operation completed!
</div>
<div :if={@status == :error} class="error">
  Something went wrong
</div>
\`\`\`

**Common Use Cases:**
- Showing/hiding elements based on state
- Conditional rendering of alerts and notifications
- Feature flags and permissions
- Loading states and error messages
- Displaying content for specific user roles

**Best Practices:**
- **No else clause** - Use separate \`:if\` attributes with inverted conditions for else behavior
- Prefer \`:if\` over \`<%= if ... do %>\` - Cleaner syntax and better performance
- Combine with other attributes like \`:for\` for complex rendering logic
- Use for entire components: \`<.modal :if={@show_modal}>\`

**Performance Note:**
Elements with \`:if={false}\` are completely removed from the DOM (not just hidden with CSS).

**See Also:** :for, Phoenix.Component.show/1, Phoenix.Component.hide/1

[📖 HexDocs](https://hexdocs.pm/phoenix_live_view/Phoenix.Component.html#module-the-if-attribute)`,
    insertText: ':if={${1:@condition}}',
    sortText: '!0002',
  },
  {
    label: ':let',
    detail: 'Yield value from component/slot',
    documentation: `Captures values yielded by components and slots back to the caller.

**With Form Components:**
\`\`\`heex
<.form :let={f} for={@changeset} phx-submit="save">
  <.input field={f[:email]} type="email" label="Email" />
  <.input field={f[:password]} type="password" label="Password" />
  <button type="submit">Save</button>
</.form>
\`\`\`

**With Async Assigns:**
\`\`\`heex
<.async_result :let={user} assign={@user}>
  <:loading>Loading user...</:loading>
  <:failed :let={reason}>Error: {reason}</:failed>
  <div>Welcome, {user.name}!</div>
</.async_result>
\`\`\`

**With Slots:**
\`\`\`heex
<.table :let={row} rows={@users}>
  <:col :let={user} label="Name">{user.name}</:col>
  <:col :let={user} label="Email">{user.email}</:col>
</.table>
\`\`\`

**With Custom Components:**
\`\`\`heex
<.modal :let={modal_id} id="confirm-delete">
  <p>Are you sure?</p>
  <button phx-click={JS.hide("#\#{modal_id}")}>Cancel</button>
  <button phx-click="delete">Confirm</button>
</.modal>
\`\`\`

**Common Use Cases:**
- Accessing form field helpers (Phoenix.Component.form/1)
- Working with table row data in custom table components
- Capturing async operation results
- Getting component-generated IDs or state
- Destructuring slot attributes

**How It Works:**
Components use \`render_slot/2\` to yield values:
\`\`\`elixir
# In component definition:
render_slot(@inner_block, %{user: user, index: index})
\`\`\`

**Pattern Matching:**
\`\`\`heex
<.data_provider :let={{user, metadata}}>
  {user.name} - {metadata.timestamp}
</.data_provider>
\`\`\`

**See Also:** Phoenix.Component.render_slot/2, Phoenix.Component.form/1, slots

[📖 HexDocs](https://hexdocs.pm/phoenix_live_view/Phoenix.Component.html#module-the-let-attribute)`,
    insertText: ':let={${1:var}}',
    sortText: '!0003',
  },
  {
    label: ':key',
    detail: 'Efficient diffing for :for loops',
    documentation: `Specifies a unique identifier for items in \`:for\` loops to optimize DOM diffing and preserve element state.

**Why Use :key?**
Without \`:key\`, LiveView uses array index for diffing. When items are reordered, added, or removed, this causes unnecessary DOM mutations and lost element state (focus, scroll position, etc.).

**Basic Usage:**
\`\`\`heex
<div :for={user <- @users} :key={user.id}>
  {user.name}
</div>
\`\`\`

**With Pattern Matching:**
\`\`\`heex
<tr :for={{id, product} <- @products} :key={id}>
  <td>{product.name}</td>
  <td>\${product.price}</td>
</tr>
\`\`\`

**With Composite Keys:**
\`\`\`heex
<li :for={item <- @items} :key={"\#{item.category}_\#{item.id}"}>
  {item.category}: {item.name}
</li>
\`\`\`

**Preserving Input State:**
\`\`\`heex
<div :for={field <- @fields} :key={field.id}>
  <input type="text" name={field.name} value={field.value} />
</div>
\`\`\`
Without \`:key\`, reordering fields would lose user input!

**Performance Impact:**
- **Without :key**: Reordering 1000 items = 1000 DOM updates
- **With :key**: Reordering 1000 items = minimal DOM moves

**Common Use Cases:**
- Lists where items can be reordered (drag-and-drop, sorting)
- Dynamically added/removed items (todo lists, forms)
- Paginated or filtered data
- Real-time updates (chat messages, notifications)

**Best Practices:**
- **Always use :key with :for** - Default index-based diffing is rarely optimal
- Use stable, unique identifiers (database IDs, UUIDs)
- Avoid using array index as key (defeats the purpose)
- For temporary items without IDs, use \`Ecto.UUID.generate()\`

**See Also:** :for, Phoenix.LiveView.stream/3 (for large lists)

[📖 HexDocs](https://hexdocs.pm/phoenix_live_view/Phoenix.Component.html#module-the-for-attribute)`,
    insertText: ':key={${1:item.id}}',
    sortText: '!0004',
  },
];

/**
 * Get completions for Phoenix LiveView special template attributes
 * These attributes work on both regular HTML elements and Phoenix components
 *
 * Handles the case where user has already typed ':' to avoid double colon (::if)
 *
 * @param document - The text document
 * @param position - The current cursor position
 * @param linePrefix - The text before the cursor on the current line
 */
export function getSpecialAttributeCompletions(
  document?: TextDocument,
  position?: Position,
  linePrefix?: string
): CompletionItem[] {
  const replacementRange =
    document && position ? findSpecialAttributeReplacementRange(document, position) : null;
  const typedSegment =
    replacementRange && document
      ? document.getText({
          start: replacementRange.start,
          end: replacementRange.end,
        })
      : '';

  return specialAttributes.map((attr, index) => {
    const item: CompletionItem = {
      label: attr.label, // Keep :for in label for display
      kind: CompletionItemKind.Property,
      detail: attr.detail,
      documentation: {
        kind: MarkupKind.Markdown,
        value: attr.documentation,
      },
      insertTextFormat: InsertTextFormat.Snippet,
      sortText: `!65${index.toString().padStart(2, '0')}`, // After Phoenix attrs (!6xxx), before HTML (!7xxx)
      filterText: typedSegment || attr.label,
    };

    if (replacementRange) {
      item.textEdit = TextEdit.replace(replacementRange, attr.insertText);
    } else {
      item.insertText = attr.insertText;
    }

    return item;
  });
}

function findSpecialAttributeReplacementRange(document: TextDocument, position: Position): Range | null {
  const text = document.getText();
  const offset = document.offsetAt(position);

  let i = offset - 1;
  while (i >= 0) {
    const ch = text[i];

    if (ch === ':') {
      return {
        start: document.positionAt(i),
        end: position,
      };
    }

    if (!/[a-zA-Z]/.test(ch)) {
      break;
    }

    i--;
  }

  return null;
}


/**
 * Check if we're in a context where special attributes should be suggested
 * Special attributes can be used on any HTML element or Phoenix component
 */
export function shouldShowSpecialAttributes(linePrefix: string): boolean {
  // Check if we're inside an opening tag (HTML or component)
  // Pattern: <tagname or <.component_name followed by whitespace and possibly other attributes
  const inHtmlTag = /<[a-zA-Z][a-zA-Z0-9]*\s+[^>]*$/.test(linePrefix);
  const inComponentTag = /<\.[a-z_][a-z0-9_]*\s+[^>]*$/.test(linePrefix);

  return inHtmlTag || inComponentTag;
}
