import { describe, it, expect } from 'vitest';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { TextDocument } from 'vscode-languageserver-textdocument';
import { EventsRegistry } from '../src/events-registry';
import { TemplatesRegistry } from '../src/templates-registry';
import { validatePhoenixAttributes, getUnusedEventDiagnostics } from '../src/validators/phoenix-diagnostics';

async function createLiveViewModule(source: string, modulePath: string, eventsRegistry: EventsRegistry, templatesRegistry: TemplatesRegistry) {
  fs.mkdirSync(path.dirname(modulePath), { recursive: true });
  fs.writeFileSync(modulePath, source, 'utf8');
  await eventsRegistry.updateFile(modulePath, source);
}

function createTemplate(templatePath: string, content: string) {
  fs.mkdirSync(path.dirname(templatePath), { recursive: true });
  fs.writeFileSync(templatePath, content, 'utf8');
}

describe('LiveView event diagnostics', () => {
  it('reports unused handle_event definitions', async () => {
    const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'phoenix-events-unused-'));
    const modulePath = path.join(tmpRoot, 'lib', 'my_app_web', 'live', 'page_live.ex');
    const templatePath = path.join(tmpRoot, 'lib', 'my_app_web', 'live', 'page_live', 'index.html.heex');

    const moduleSource = `
defmodule MyAppWeb.PageLive do
  use Phoenix.LiveView

  embed_templates "page_live/*"

  @impl true
  def handle_event("save", params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("unused", params, socket) do
    {:noreply, socket}
  end
end
`.trim();

    const templateSource = `
<button phx-click="save">Save</button>
`.trim();

    const eventsRegistry = new EventsRegistry();
    const templatesRegistry = new TemplatesRegistry();
    eventsRegistry.setWorkspaceRoot(tmpRoot);
    templatesRegistry.setWorkspaceRoot(tmpRoot);

    await createLiveViewModule(moduleSource, modulePath, eventsRegistry, templatesRegistry);
    createTemplate(templatePath, templateSource);
    await templatesRegistry.updateFile(modulePath, moduleSource);

    // Prime attribute analysis for the template
    const templateDoc = TextDocument.create(`file://${templatePath}`, 'phoenix-heex', 1, templateSource);
    validatePhoenixAttributes(templateDoc, eventsRegistry, templatePath);

    const moduleDoc = TextDocument.create(`file://${modulePath}`, 'elixir', 1, moduleSource);
    const diagnostics = getUnusedEventDiagnostics(moduleDoc, eventsRegistry, templatesRegistry);

    expect(diagnostics.some(diag => diag.code === 'unused-event' && diag.message.includes('"unused"'))).toBe(true);
    expect(diagnostics.some(diag => diag.message.includes('"save"'))).toBe(false);

    fs.rmSync(tmpRoot, { recursive: true, force: true });
  });

  it('counts JS.push event invocations as usage', async () => {
    const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'phoenix-events-jspush-'));
    const modulePath = path.join(tmpRoot, 'lib', 'my_app_web', 'live', 'page_live.ex');
    const templatePath = path.join(tmpRoot, 'lib', 'my_app_web', 'live', 'page_live', 'index.html.heex');

    const moduleSource = `
defmodule MyAppWeb.PageLive do
  use Phoenix.LiveView

  embed_templates "page_live/*"

  def handle_event("toggle", params, socket) do
    {:noreply, socket}
  end
end
`.trim();

    const templateSource = `
<button phx-click={JS.push("toggle")}>Toggle</button>
`.trim();

    const eventsRegistry = new EventsRegistry();
    const templatesRegistry = new TemplatesRegistry();
    eventsRegistry.setWorkspaceRoot(tmpRoot);
    templatesRegistry.setWorkspaceRoot(tmpRoot);

    await createLiveViewModule(moduleSource, modulePath, eventsRegistry, templatesRegistry);
    createTemplate(templatePath, templateSource);
    await templatesRegistry.updateFile(modulePath, moduleSource);

    const templateDoc = TextDocument.create(`file://${templatePath}`, 'phoenix-heex', 1, templateSource);
    validatePhoenixAttributes(templateDoc, eventsRegistry, templatePath);

    const moduleDoc = TextDocument.create(`file://${modulePath}`, 'elixir', 1, moduleSource);
    const diagnostics = getUnusedEventDiagnostics(moduleDoc, eventsRegistry, templatesRegistry);

    expect(diagnostics.some(diag => diag.code === 'unused-event')).toBe(false);

    fs.rmSync(tmpRoot, { recursive: true, force: true });
  });
});
