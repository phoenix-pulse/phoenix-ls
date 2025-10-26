import { describe, it, expect } from 'vitest';
import { TextDocument } from 'vscode-languageserver-textdocument';
import { ComponentsRegistry } from '../src/components-registry';
import { validateComponentUsage } from '../src/validators/component-diagnostics';

// Test component with slot attributes
const listComponent = `
defmodule MyAppWeb.CoreComponents do
  use Phoenix.Component

  attr :id, :string, default: ""
  attr :class, :string, default: ""

  slot :item, required: true do
    attr :title, :string, required: true
    attr :description, :string
  end

  def list(assigns) do
    ~H"""
    <div id={@id} class={@class}>
      <dl>
        <div :for={item <- @item}>
          <dt>{item.title}</dt>
          <dd>{render_slot(item)}</dd>
        </div>
      </dl>
    </div>
    """
  end
end
`;

// Test component for nesting
const parentComponent = `
defmodule MyAppWeb.Components.Parent do
  use Phoenix.Component

  slot :parent_slot, required: true

  def parent(assigns) do
    ~H"""
    <div>
      <%= render_slot(@parent_slot) %>
    </div>
    """
  end
end
`;

const childComponent = `
defmodule MyAppWeb.Components.Child do
  use Phoenix.Component

  slot :child_slot

  def child(assigns) do
    ~H"""
    <span>
      <%= render_slot(@child_slot) %>
    </span>
    """
  end
end
`;

describe('GitHub Issue #1 & #2 Fixes', () => {
  it('validates slot attributes (Issue #1b)', () => {
    const registry = new ComponentsRegistry();
    registry.setWorkspaceRoot('/workspace');
    registry.updateFile('/workspace/lib/my_app_web/core_components.ex', listComponent);

    const templatePath = '/workspace/lib/my_app_web/templates/test.html.heex';

    // Test 1: Missing required slot attribute
    const docMissingAttr = TextDocument.create(
      `file://${templatePath}`,
      'phoenix-heex',
      1,
      `
<.list>
  <:item>Content</:item>
</.list>
      `
    );

    const diagnostics1 = validateComponentUsage(docMissingAttr, registry, templatePath);
    const slotAttrError = diagnostics1.find(d => d.code === 'slot-missing-attribute');
    expect(slotAttrError).toBeDefined();
    expect(slotAttrError?.message).toContain('missing required attribute "title"');

    // Test 2: Valid slot attributes
    const docValidAttrs = TextDocument.create(
      `file://${templatePath}`,
      'phoenix-heex',
      2,
      `
<.list>
  <:item title="Test" description="Desc">Content</:item>
</.list>
      `
    );

    const diagnostics2 = validateComponentUsage(docValidAttrs, registry, templatePath);
    const slotAttrErrors2 = diagnostics2.filter(d => d.code === 'slot-missing-attribute');
    expect(slotAttrErrors2).toHaveLength(0);

    // Test 3: Unknown slot attribute
    const docUnknownAttr = TextDocument.create(
      `file://${templatePath}`,
      'phoenix-heex',
      3,
      `
<.list>
  <:item title="Test" invalid="foo">Content</:item>
</.list>
      `
    );

    const diagnostics3 = validateComponentUsage(docUnknownAttr, registry, templatePath);
    const unknownAttrWarning = diagnostics3.find(d => d.code === 'slot-unknown-attribute');
    expect(unknownAttrWarning).toBeDefined();
    expect(unknownAttrWarning?.message).toContain('Unknown attribute "invalid"');
  });

  it('does not validate nested component slots against parent (Issue #1a)', () => {
    const registry = new ComponentsRegistry();
    registry.setWorkspaceRoot('/workspace');
    registry.updateFile('/workspace/lib/my_app_web/components/parent.ex', parentComponent);
    registry.updateFile('/workspace/lib/my_app_web/components/child.ex', childComponent);

    const templatePath = '/workspace/lib/my_app_web/templates/test.html.heex';
    const document = TextDocument.create(
      `file://${templatePath}`,
      'phoenix-heex',
      1,
      `
<.parent>
  <:parent_slot>
    <.child>
      <:child_slot>Nested content</:child_slot>
    </.child>
  </:parent_slot>
</.parent>
      `
    );

    const diagnostics = validateComponentUsage(document, registry, templatePath);

    // Should NOT have error about parent missing child_slot
    const badSlotError = diagnostics.find(d =>
      d.message.includes('parent') && d.message.includes('child_slot')
    );
    expect(badSlotError).toBeUndefined();

    // Should have no unknown slot errors
    const unknownSlotErrors = diagnostics.filter(d => d.code === 'component-unknown-slot');
    expect(unknownSlotErrors).toHaveLength(0);
  });

  it('allows arbitrary assigns on live_component (Issue #2)', () => {
    const registry = new ComponentsRegistry();
    registry.setWorkspaceRoot('/workspace');

    const templatePath = '/workspace/lib/my_app_web/templates/test.html.heex';

    // Test 1: Missing required attributes
    const docMissing = TextDocument.create(
      `file://${templatePath}`,
      'phoenix-heex',
      1,
      `
<.live_component custom_prop={@value} />
      `
    );

    const diagnostics1 = validateComponentUsage(docMissing, registry, templatePath);
    const moduleError = diagnostics1.find(d => d.code === 'live-component-missing-module');
    const idError = diagnostics1.find(d => d.code === 'live-component-missing-id');
    expect(moduleError).toBeDefined();
    expect(idError).toBeDefined();

    // Test 2: Valid live_component with arbitrary assigns
    const docValid = TextDocument.create(
      `file://${templatePath}`,
      'phoenix-heex',
      2,
      `
<.live_component module={MyModule} id="test" custom_prop={@value} another_prop="foo" />
      `
    );

    const diagnostics2 = validateComponentUsage(docValid, registry, templatePath);

    // Should NOT have unknown attribute warnings for custom_prop or another_prop
    const unknownAttrErrors = diagnostics2.filter(d => d.code === 'component-unknown-attribute');
    expect(unknownAttrErrors).toHaveLength(0);

    // Should NOT have any errors
    expect(diagnostics2).toHaveLength(0);
  });
});
