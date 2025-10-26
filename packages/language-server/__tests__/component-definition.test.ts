import { describe, it, expect } from 'vitest';
import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';
import { ComponentsRegistry } from '../src/components-registry';

describe('component definition resolution', () => {
  it('resolves cross-file component definitions with normalized paths', () => {
    const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'phoenix-pulse-components-'));
    const componentsRegistry = new ComponentsRegistry();
    componentsRegistry.setWorkspaceRoot(tmpRoot);

    const componentsDir = path.join(tmpRoot, 'lib', 'my_app_web', 'components');
    fs.mkdirSync(componentsDir, { recursive: true });

    const componentPath = path.join(componentsDir, 'badge.ex');
    const componentSource = `
defmodule MyAppWeb.BadgeComponents do
  use Phoenix.Component

  attr :status, :string

  def badge(assigns) do
    ~H"""
    <span>{@status}</span>
    """
  end
end
`;
    fs.writeFileSync(componentPath, componentSource, 'utf8');
    componentsRegistry.updateFile(componentPath, componentSource);

    const templatePath = path.join(tmpRoot, 'lib', 'my_app_web', 'controllers', 'page_html', 'index.html.heex');
    fs.mkdirSync(path.dirname(templatePath), { recursive: true });
    fs.writeFileSync(templatePath, '<.badge status="ok" />', 'utf8');

    const resolved = componentsRegistry.resolveComponent(templatePath, 'badge');
    expect(resolved).toBeTruthy();
    expect(resolved?.moduleName).toBe('MyAppWeb.BadgeComponents');
    expect(resolved?.filePath).toBe(path.normalize(path.resolve(componentPath)));

    fs.rmSync(tmpRoot, { recursive: true, force: true });
  });
});
