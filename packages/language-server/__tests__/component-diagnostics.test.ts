import { describe, it, expect } from 'vitest';
import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';
import { TextDocument } from 'vscode-languageserver-textdocument';
import { ComponentsRegistry } from '../src/components-registry';
import { validateComponentUsage } from '../src/validators/component-diagnostics';
import { validateNavigationComponents, validateJsPushUsage } from '../src/validators/navigation-diagnostics';
import { SchemaRegistry } from '../src/schema-registry';
import { getFormFieldCompletions } from '../src/completions/form-fields';
import { RouterRegistry } from '../src/router-registry';
import { getVerifiedRouteCompletions } from '../src/completions/routes';
import { getHandleInfoEventCompletions } from '../src/completions/events';
import { EventsRegistry } from '../src/events-registry';

const badgeComponent = `
defmodule MyAppWeb.Components.Badge do
  use Phoenix.Component

  attr :status, :string, required: true
  attr :class, :string
  slot :title, required: true
  slot :inner_block, required: true

  def badge(assigns) do
    ~H"""
    <div class={@class}>
      <span><%= @status %></span>
      <div><%= render_slot(@title) %></div>
      <div><%= render_slot(@inner_block) %></div>
    </div>
    """
  end
end
`;

const multiClauseInputComponent = `
defmodule MyAppWeb.Components.MultiInput do
  use Phoenix.Component

  attr :prompt, :string, default: nil
  attr :type, :string, default: "text"

  def input(%{normalize: true} = assigns) do
    assigns
    |> Map.put(:normalize, false)
    |> input()
  end

  def input(assigns) do
    ~H"""
    <div>
      <select>
        <option :if={@prompt} value="">{@prompt}</option>
      </select>
    </div>
    """
  end
end
`;

describe('component diagnostics & completions', () => {
  it('reports missing attributes, unknown attributes, and missing slots', () => {
    const registry = new ComponentsRegistry();
    registry.setWorkspaceRoot('/workspace');
    registry.updateFile('/workspace/lib/my_app_web/components/badge.ex', badgeComponent);

    const templatePath = '/workspace/lib/my_app_web/components/example.html.heex';
    const document = TextDocument.create(
      `file://${templatePath}`,
      'phoenix-heex',
      1,
      `
<.badge class="bg" >
  <:title>Title</:title>
  Body content
</.badge>

<.badge status="ok" invalid_attr="oops">
  <:title>Heading</:title>
  Body content
</.badge>

<.badge status="ok">
  Body content
</.badge>
`
    );

    const diagnostics = validateComponentUsage(document, registry, templatePath);
    expect(diagnostics.some(d => d.code === 'component-missing-attribute')).toBe(true);
    expect(diagnostics.some(d => d.code === 'component-unknown-attribute')).toBe(true);
    expect(diagnostics.some(d => d.code === 'component-missing-slot')).toBe(true);
  });

  it('warns on unknown slot usage', () => {
    const registry = new ComponentsRegistry();
    registry.setWorkspaceRoot('/workspace');
    registry.updateFile('/workspace/lib/my_app_web/components/badge.ex', badgeComponent);

    const templatePath = '/workspace/lib/my_app_web/components/example.html.heex';
    const document = TextDocument.create(
      `file://${templatePath}`,
      'phoenix-heex',
      1,
      `
<.badge status="ok">
  <:unknown>Oops</:unknown>
</.badge>
`
    );

    const diagnostics = validateComponentUsage(document, registry, templatePath);
    expect(diagnostics.some(d => d.code === 'component-unknown-slot')).toBe(true);
  });

  it('allows attributes declared before multi-clause components', () => {
    const registry = new ComponentsRegistry();
    registry.setWorkspaceRoot('/workspace');
    registry.updateFile('/workspace/lib/my_app_web/components/multi_input.ex', multiClauseInputComponent);

    const templatePath = '/workspace/lib/my_app_web/components/example.html.heex';
    const document = TextDocument.create(
      `file://${templatePath}`,
      'phoenix-heex',
      1,
      `<.input prompt="Choose one" />`
    );

    const diagnostics = validateComponentUsage(document, registry, templatePath);
    expect(diagnostics.some(d => d.code === 'component-unknown-attribute')).toBe(false);
  });

  it('does not require imports for builtin Phoenix components', () => {
    const registry = new ComponentsRegistry();
    registry.setWorkspaceRoot('/workspace');

    const templatePath = '/workspace/lib/my_app_web/components/example.html.heex';
    const document = TextDocument.create(
      `file://${templatePath}`,
      'phoenix-heex',
      1,
      `<.link navigate="/teams">Teams</.link>`
    );

    const diagnostics = validateComponentUsage(document, registry, templatePath);
    expect(diagnostics.some(d => d.code === 'component-not-imported')).toBe(false);
  });

  it('respects use MyAppWeb, :html imports for CoreComponents', () => {
    const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'phoenix-lsp-test-'));
    const componentsDir = path.join(tmpRoot, 'lib', 'my_app_web', 'components');
    fs.mkdirSync(componentsDir, { recursive: true });

    const coreComponentsPath = path.join(componentsDir, 'core_components.ex');
    const coreComponentSource = `
defmodule MyAppWeb.CoreComponents do
  use Phoenix.Component

  attr :label, :string, required: true

  def button(assigns) do
    ~H"""
    <button><%= @label %></button>
    """
  end
end
`;
    fs.writeFileSync(coreComponentsPath, coreComponentSource, 'utf8');

    const htmlModulePath = path.join(tmpRoot, 'lib', 'my_app_web', 'components.ex');
    fs.writeFileSync(htmlModulePath, `defmodule MyAppWeb.Components do\n  use MyAppWeb, :html\nend\n`, 'utf8');

    const registry = new ComponentsRegistry();
    registry.setWorkspaceRoot(tmpRoot);
    registry.updateFile(coreComponentsPath, coreComponentSource);

    const templatePath = path.join(tmpRoot, 'lib', 'my_app_web', 'components', 'example.html.heex');
    fs.mkdirSync(path.dirname(templatePath), { recursive: true });
    const template = `<.button label="Save" />`;
    const document = TextDocument.create(`file://${templatePath}`, 'phoenix-heex', 1, template);

    const diagnostics = validateComponentUsage(document, registry, templatePath);
    expect(diagnostics.some(d => d.code === 'component-not-imported')).toBe(false);

    fs.rmSync(tmpRoot, { recursive: true, force: true });
  });

  it('requires module and id when invoking live_component', () => {
    const registry = new ComponentsRegistry();
    registry.setWorkspaceRoot('/workspace');

    const templatePath = '/workspace/lib/my_app_web/components/example.html.heex';
    const document = TextDocument.create(
      `file://${templatePath}`,
      'phoenix-heex',
      1,
      `<.live_component id="modal" />`
    );

    const navigationDiagnostics = validateNavigationComponents(document, registry, templatePath);
    expect(navigationDiagnostics.some(d => d.code === 'live-component-missing-module')).toBe(true);
  });

  it('warns when JS.push is missing an event name', () => {
    const registry = new ComponentsRegistry();
    registry.setWorkspaceRoot('/workspace');

    const templatePath = '/workspace/lib/my_app_web/components/example.html.heex';
    const document = TextDocument.create(
      `file://${templatePath}`,
      'phoenix-heex',
      1,
      `<button phx-click={JS.push()}></button>`
    );

    const diagnostics = validateJsPushUsage(document, document.getText());
    expect(diagnostics.some(d => d.code === 'js-push-missing-event')).toBe(true);
  });

  it('suggests schema fields for form bindings', () => {
    const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'phoenix-lsp-form-test-'));
    const schemaRegistry = new SchemaRegistry();
    schemaRegistry.setWorkspaceRoot(tmpRoot);

    const schemaPath = path.join(tmpRoot, 'lib', 'my_app', 'accounts', 'user.ex');
    fs.mkdirSync(path.dirname(schemaPath), { recursive: true });
    const schemaSource = `
defmodule MyApp.Accounts.User do
  use Ecto.Schema

  schema "users" do
    field :email, :string
    field :username, :string
  end
end
`;
    schemaRegistry.updateFile(schemaPath, schemaSource);

    const registry = new ComponentsRegistry();
    registry.setWorkspaceRoot(tmpRoot);

    const templatePath = path.join(tmpRoot, 'lib', 'my_app_web', 'components', 'example.html.heex');
    fs.mkdirSync(path.dirname(templatePath), { recursive: true });
    const template = `<.form :let={f} for={@user}>
  <.input field={f[:}
</.form>`;
    const document = TextDocument.create(`file://${templatePath}`, 'phoenix-heex', 1, template);
    const text = document.getText();
    const offset = document.offsetAt({ line: 1, character: '  <.input field={f[:'.length });
    const linePrefix = text.slice(Math.max(0, offset - 100), offset);

    const completions = getFormFieldCompletions(
      document,
      text,
      offset,
      linePrefix,
      schemaRegistry,
      registry,
      templatePath
    );

    expect(completions?.some(item => item.label === 'email')).toBe(true);
    expect(completions?.some(item => item.label === 'username')).toBe(true);

    fs.rmSync(tmpRoot, { recursive: true, force: true });
  });

  it('suggests schema fields for inputs_for nested bindings', () => {
    const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'phoenix-lsp-inputs-for-test-'));
    const schemaRegistry = new SchemaRegistry();
    schemaRegistry.setWorkspaceRoot(tmpRoot);

    const accountsDir = path.join(tmpRoot, 'lib', 'my_app', 'accounts');
    fs.mkdirSync(accountsDir, { recursive: true });

    const userSchemaPath = path.join(accountsDir, 'user.ex');
    const userSchemaSource = `
defmodule MyApp.Accounts.User do
  use Ecto.Schema

  schema "users" do
    field :email, :string
    has_many :addresses, MyApp.Accounts.Address
  end
end
`;
    fs.writeFileSync(userSchemaPath, userSchemaSource, 'utf8');
    schemaRegistry.updateFile(userSchemaPath, userSchemaSource);

    const addressSchemaPath = path.join(accountsDir, 'address.ex');
    const addressSchemaSource = `
defmodule MyApp.Accounts.Address do
  use Ecto.Schema

  schema "addresses" do
    field :street, :string
    field :city, :string
    field :postal_code, :string
  end
end
`;
    fs.writeFileSync(addressSchemaPath, addressSchemaSource, 'utf8');
    schemaRegistry.updateFile(addressSchemaPath, addressSchemaSource);

    const registry = new ComponentsRegistry();
    registry.setWorkspaceRoot(tmpRoot);

    const templatePath = path.join(tmpRoot, 'lib', 'my_app_web', 'components', 'example.html.heex');
    fs.mkdirSync(path.dirname(templatePath), { recursive: true });
    const template = `<.form :let={f} for={@user}>
  <.inputs_for :let={address_form} field={f[:addresses]}>
    <.input field={address_form[:}
  </.inputs_for>
</.form>`;
    const document = TextDocument.create(`file://${templatePath}`, 'phoenix-heex', 1, template);
    const text = document.getText();
    const offset = document.offsetAt({ line: 2, character: '    <.input field={address_form[:'.length });
    const linePrefix = text.slice(Math.max(0, offset - 100), offset);

    const completions = getFormFieldCompletions(
      document,
      text,
      offset,
      linePrefix,
      schemaRegistry,
      registry,
      templatePath
    );

    expect(completions?.some(item => item.label === 'street')).toBe(true);
    expect(completions?.some(item => item.label === 'city')).toBe(true);
    expect(completions?.some(item => item.label === 'postal_code')).toBe(true);
    expect(completions?.some(item => item.label === 'email')).toBeFalsy();

    fs.rmSync(tmpRoot, { recursive: true, force: true });
  });

  it('suggests routes for VerifiedRoutes navigation', () => {
    const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'phoenix-lsp-routes-test-'));
    const routerRegistry = new RouterRegistry();
    routerRegistry.setWorkspaceRoot(tmpRoot);

    const routerPath = path.join(tmpRoot, 'lib', 'my_app_web', 'router.ex');
    fs.mkdirSync(path.dirname(routerPath), { recursive: true });
    const routerSource = `
defmodule MyAppWeb.Router do
  use Phoenix.Router

  scope "/" do
    pipe_through :browser
    get "/dashboard", DashboardController, :index
  end
end
`;
    routerRegistry.updateFile(routerPath, routerSource);

    const templatePath = path.join(tmpRoot, 'lib', 'my_app_web', 'components', 'example.html.heex');
    fs.mkdirSync(path.dirname(templatePath), { recursive: true });
    const template = `<.link navigate={~p"/"}>Dashboard</.link>`;
    const document = TextDocument.create(`file://${templatePath}`, 'phoenix-heex', 1, template);
    const text = document.getText();
    const position = { line: 0, character: `<.link navigate={~p"/`.length };
    const offset = document.offsetAt(position);
    const linePrefix = text.slice(Math.max(0, offset - 100), offset);

    const completions = getVerifiedRouteCompletions(
      document,
      position,
      linePrefix,
      routerRegistry
    );

    expect(completions?.some(item => item.label === '/dashboard')).toBe(true);

    fs.rmSync(tmpRoot, { recursive: true, force: true });
  });

  it('suggests handle_info events when sending messages', async () => {
    const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'phoenix-lsp-info-test-'));
    const eventsRegistry = new EventsRegistry();
    eventsRegistry.setWorkspaceRoot(tmpRoot);

    const livePath = path.join(tmpRoot, 'lib', 'my_app_web', 'live', 'demo_live.ex');
    fs.mkdirSync(path.dirname(livePath), { recursive: true });
    const liveSource = `
defmodule MyAppWeb.DemoLive do
  use Phoenix.LiveView

  def handle_info(:tick, socket) do
    {:noreply, socket}
  end

  def trigger(socket) do
    send(self(), :
  end
end
`;
    await eventsRegistry.updateFile(livePath, liveSource);

    const document = TextDocument.create(`file://${livePath}`, 'elixir', 1, liveSource);
    const text = document.getText();
    const sendIndex = text.indexOf('send(self(), :') + 'send(self(), :'.length;
    const position = document.positionAt(sendIndex);
    const linePrefix = text.slice(Math.max(0, sendIndex - 100), sendIndex);

    const completions = getHandleInfoEventCompletions(linePrefix, position, livePath, eventsRegistry);
    expect(completions?.some(item => item.label === ':tick')).toBe(true);

    fs.rmSync(tmpRoot, { recursive: true, force: true });
  });
});
