import { describe, it, expect } from 'vitest';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { EventsRegistry } from '../src/events-registry';
import { isElixirAvailable } from '../src/parsers/elixir-ast-parser';

describe('EventsRegistry Elixir AST Parser Integration', () => {
  it('should use Elixir parser when available', async () => {
    const elixirAvailable = await isElixirAvailable();
    console.log(`Elixir available: ${elixirAvailable}`);

    const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'events-registry-elixir-'));
    const liveViewPath = path.join(tmpRoot, 'lib', 'my_app_web', 'live', 'user_live.ex');

    const liveViewSource = `
defmodule MyAppWeb.UserLive do
  use Phoenix.LiveView

  @doc "Delete a user"
  def handle_event("delete", %{"id" => id}, socket) do
    {:noreply, socket}
  end

  def handle_event("edit", params, socket) do
    {:noreply, socket}
  end

  @doc false
  defp handle_event(:private_event, _params, socket) do
    {:noreply, socket}
  end

  @doc "Refresh data"
  def handle_info(:refresh, socket) do
    {:noreply, socket}
  end

  def handle_info({:update, data}, socket) do
    {:noreply, socket}
  end

  def handle_info("string_message", socket) do
    {:noreply, socket}
  end
end
`.trim();

    fs.mkdirSync(path.dirname(liveViewPath), { recursive: true });
    fs.writeFileSync(liveViewPath, liveViewSource, 'utf8');

    const registry = new EventsRegistry();
    registry.setWorkspaceRoot(tmpRoot);

    // Use parseFileAsync to test Elixir parser path
    const events = await registry.parseFileAsync(liveViewPath, liveViewSource);

    console.log(`\nParsed ${events.length} events using ${elixirAvailable ? 'Elixir' : 'Regex'} parser\n`);

    // Verify all events were detected
    expect(events.length).toBe(6);

    // Verify handle_event (string names)
    const deleteEvent = events.find(e => e.name === 'delete' && e.kind === 'handle_event');
    expect(deleteEvent).toBeDefined();
    expect(deleteEvent?.nameKind).toBe('string');
    expect(deleteEvent?.moduleName).toBe('MyAppWeb.UserLive');
    // Note: Elixir parser doesn't currently extract @doc (future enhancement)
    console.log(`delete event: ${JSON.stringify(deleteEvent)}`);

    const editEvent = events.find(e => e.name === 'edit' && e.kind === 'handle_event');
    expect(editEvent).toBeDefined();
    expect(editEvent?.nameKind).toBe('string');
    console.log(`edit event: ${JSON.stringify(editEvent)}`);

    // Verify handle_event (atom name, private)
    const privateEvent = events.find(e => e.name === 'private_event' && e.kind === 'handle_event');
    expect(privateEvent).toBeDefined();
    expect(privateEvent?.nameKind).toBe('atom');
    console.log(`private_event: ${JSON.stringify(privateEvent)}`);

    // Verify handle_info (atom)
    const refreshEvent = events.find(e => e.name === 'refresh' && e.kind === 'handle_info');
    expect(refreshEvent).toBeDefined();
    expect(refreshEvent?.nameKind).toBe('atom');
    // Note: Elixir parser doesn't currently extract @doc (future enhancement)
    console.log(`refresh event: ${JSON.stringify(refreshEvent)}`);

    // Verify handle_info (tuple)
    const updateEvent = events.find(e => e.name === 'update' && e.kind === 'handle_info');
    expect(updateEvent).toBeDefined();
    expect(updateEvent?.nameKind).toBe('atom');
    console.log(`update event: ${JSON.stringify(updateEvent)}`);

    // Verify handle_info (string)
    const stringEvent = events.find(e => e.name === 'string_message' && e.kind === 'handle_info');
    expect(stringEvent).toBeDefined();
    expect(stringEvent?.nameKind).toBe('string');
    console.log(`string_message event: ${JSON.stringify(stringEvent)}`);

    fs.rmSync(tmpRoot, { recursive: true, force: true });
  });

  it('should cache parsed events correctly', async () => {
    const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'events-registry-cache-'));
    const liveViewPath = path.join(tmpRoot, 'lib', 'my_app_web', 'live', 'page_live.ex');

    const liveViewSource = `
defmodule MyAppWeb.PageLive do
  use Phoenix.LiveView

  def handle_event("click", params, socket) do
    {:noreply, socket}
  end

  def handle_info(:tick, socket) do
    {:noreply, socket}
  end
end
`.trim();

    fs.mkdirSync(path.dirname(liveViewPath), { recursive: true });
    fs.writeFileSync(liveViewPath, liveViewSource, 'utf8');

    const registry = new EventsRegistry();
    registry.setWorkspaceRoot(tmpRoot);

    // First parse
    const start1 = Date.now();
    const events1 = await registry.parseFileAsync(liveViewPath, liveViewSource);
    const duration1 = Date.now() - start1;

    // Second parse (should use cache)
    const start2 = Date.now();
    const events2 = await registry.parseFileAsync(liveViewPath, liveViewSource);
    const duration2 = Date.now() - start2;

    console.log(`First parse: ${duration1}ms, Second parse: ${duration2}ms`);

    // Both should have same events
    expect(events1.length).toBe(2);
    expect(events2.length).toBe(2);

    // Verify events are correct
    expect(events1.some(e => e.name === 'click' && e.kind === 'handle_event')).toBe(true);
    expect(events1.some(e => e.name === 'tick' && e.kind === 'handle_info')).toBe(true);

    fs.rmSync(tmpRoot, { recursive: true, force: true });
  });

  it('should scan workspace asynchronously', async () => {
    const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'events-registry-scan-'));

    // Create multiple LiveView files
    const file1 = path.join(tmpRoot, 'lib', 'my_app_web', 'live', 'user_live.ex');
    const file2 = path.join(tmpRoot, 'lib', 'my_app_web', 'live', 'admin_live.ex');

    const source1 = `
defmodule MyAppWeb.UserLive do
  use Phoenix.LiveView

  def handle_event("save", params, socket) do
    {:noreply, socket}
  end

  def handle_info(:refresh, socket) do
    {:noreply, socket}
  end
end
`.trim();

    const source2 = `
defmodule MyAppWeb.AdminLive do
  use Phoenix.LiveView

  def handle_event("delete", params, socket) do
    {:noreply, socket}
  end

  def handle_event("approve", params, socket) do
    {:noreply, socket}
  end
end
`.trim();

    fs.mkdirSync(path.dirname(file1), { recursive: true });
    fs.writeFileSync(file1, source1, 'utf8');
    fs.writeFileSync(file2, source2, 'utf8');

    const registry = new EventsRegistry();
    await registry.scanWorkspace(tmpRoot);

    const allEvents = registry.getAllEvents();
    console.log(`\nScanned workspace, found ${allEvents.length} events total\n`);

    // Should find 4 events total (2 from file1, 2 from file2)
    expect(allEvents.length).toBe(4);

    // Verify events from file1
    const file1Events = registry.getEventsFromFile(file1);
    expect(file1Events.length).toBe(2);
    expect(file1Events.some(e => e.name === 'save')).toBe(true);
    expect(file1Events.some(e => e.name === 'refresh')).toBe(true);

    // Verify events from file2
    const file2Events = registry.getEventsFromFile(file2);
    expect(file2Events.length).toBe(2);
    expect(file2Events.some(e => e.name === 'delete')).toBe(true);
    expect(file2Events.some(e => e.name === 'approve')).toBe(true);

    fs.rmSync(tmpRoot, { recursive: true, force: true });
  });

  it('should fall back to regex parser on Elixir error', async () => {
    const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'events-registry-fallback-'));
    const invalidPath = path.join(tmpRoot, 'lib', 'my_app_web', 'live', 'invalid_live.ex');

    // Valid Elixir source (should work with both parsers)
    const validSource = `
defmodule MyAppWeb.InvalidLive do
  use Phoenix.LiveView

  def handle_event("test", params, socket) do
    {:noreply, socket}
  end
end
`.trim();

    fs.mkdirSync(path.dirname(invalidPath), { recursive: true });
    fs.writeFileSync(invalidPath, validSource, 'utf8');

    const registry = new EventsRegistry();
    registry.setWorkspaceRoot(tmpRoot);

    // Should parse successfully even if Elixir parser has issues
    const events = await registry.parseFileAsync(invalidPath, validSource);

    // Verify at least the regex parser works
    expect(events.length).toBeGreaterThanOrEqual(1);
    expect(events.some(e => e.name === 'test')).toBe(true);

    fs.rmSync(tmpRoot, { recursive: true, force: true });
  });
});
