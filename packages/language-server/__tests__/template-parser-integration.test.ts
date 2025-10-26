import { describe, it, expect } from 'vitest';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { TemplatesRegistry } from '../src/templates-registry';
import { isElixirAvailable } from '../src/parsers/elixir-ast-parser';

describe('TemplatesRegistry Elixir AST Parser Integration', () => {
  it('should use Elixir parser when available', async () => {
    const elixirAvailable = await isElixirAvailable();
    console.log(`Elixir available: ${elixirAvailable}`);

    const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'template-registry-elixir-'));
    const htmlModulePath = path.join(tmpRoot, 'lib', 'my_app_web', 'controllers', 'page_html.ex');

    // Create HTML module with various template types
    const htmlModuleSource = `
defmodule MyAppWeb.PageHTML do
  use MyAppWeb, :html

  embed_templates "page_html/*"

  def home(assigns) do
    ~H"""
    <h1>Welcome</h1>
    """
  end

  def about(assigns) do
    ~H"""
    <h1>About</h1>
    """
  end

  # Private function - should be skipped
  defp _helper(assigns) do
    ~H"<span>Helper</span>"
  end
end
`.trim();

    fs.mkdirSync(path.dirname(htmlModulePath), { recursive: true });
    fs.writeFileSync(htmlModulePath, htmlModuleSource, 'utf8');

    const registry = new TemplatesRegistry();
    registry.setWorkspaceRoot(tmpRoot);

    // Update file with Elixir parser
    await registry.updateFile(htmlModulePath, htmlModuleSource);

    const templates = registry.getTemplatesForModule('MyAppWeb.PageHTML');
    console.log(`\\nFound ${templates.length} templates for MyAppWeb.PageHTML`);

    // Should find function templates (home, about)
    expect(templates.length).toBeGreaterThanOrEqual(2);

    const homeTemplate = templates.find(t => t.name === 'home');
    expect(homeTemplate).toBeDefined();
    expect(homeTemplate?.format).toBe('html');
    expect(homeTemplate?.moduleName).toBe('MyAppWeb.PageHTML');

    const aboutTemplate = templates.find(t => t.name === 'about');
    expect(aboutTemplate).toBeDefined();

    // Should NOT find private function
    const helperTemplate = templates.find(t => t.name === '_helper');
    expect(helperTemplate).toBeUndefined();

    fs.rmSync(tmpRoot, { recursive: true, force: true });
  });

  it('should parse View modules correctly', async () => {
    const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'template-registry-view-'));
    const viewModulePath = path.join(tmpRoot, 'lib', 'my_app_web', 'views', 'user_view.ex');

    const viewModuleSource = `
defmodule MyAppWeb.UserView do
  use MyAppWeb, :view
end
`.trim();

    fs.mkdirSync(path.dirname(viewModulePath), { recursive: true });
    fs.writeFileSync(viewModulePath, viewModuleSource, 'utf8');

    const registry = new TemplatesRegistry();
    registry.setWorkspaceRoot(tmpRoot);

    await registry.updateFile(viewModulePath, viewModuleSource);

    // View modules are detected (even if no templates exist)
    const templates = registry.getTemplatesForModule('MyAppWeb.UserView');
    console.log(`Found ${templates.length} templates for UserView`);

    fs.rmSync(tmpRoot, { recursive: true, force: true });
  });

  it('should scan workspace asynchronously', async () => {
    const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'template-registry-scan-'));

    // Create multiple HTML modules
    const pageHtmlPath = path.join(tmpRoot, 'lib', 'my_app_web', 'controllers', 'page_html.ex');
    const userHtmlPath = path.join(tmpRoot, 'lib', 'my_app_web', 'controllers', 'user_html.ex');

    const pageHtmlSource = `
defmodule MyAppWeb.PageHTML do
  use MyAppWeb, :html

  def home(assigns) do
    ~H"<h1>Home</h1>"
  end
end
`.trim();

    const userHtmlSource = `
defmodule MyAppWeb.UserHTML do
  use MyAppWeb, :html

  def index(assigns) do
    ~H"<h1>Users</h1>"
  end

  def show(assigns) do
    ~H"<h1>User Details</h1>"
  end
end
`.trim();

    fs.mkdirSync(path.dirname(pageHtmlPath), { recursive: true });
    fs.writeFileSync(pageHtmlPath, pageHtmlSource, 'utf8');
    fs.writeFileSync(userHtmlPath, userHtmlSource, 'utf8');

    const registry = new TemplatesRegistry();
    await registry.scanWorkspace(tmpRoot);

    const allTemplates = registry.getAllTemplates();
    console.log(`\\nScanned workspace, found ${allTemplates.length} templates total`);
    console.log('Templates:', allTemplates.map(t => `${t.moduleName}:${t.name}`).join(', '));

    const pageTemplates = registry.getTemplatesForModule('MyAppWeb.PageHTML');
    console.log(`PageHTML templates: ${pageTemplates.length} - ${pageTemplates.map(t => t.name).join(', ')}`);

    const userTemplates = registry.getTemplatesForModule('MyAppWeb.UserHTML');
    console.log(`UserHTML templates: ${userTemplates.length} - ${userTemplates.map(t => t.name).join(', ')}\\n`);

    // Should find templates from both modules
    expect(pageTemplates.length).toBe(1); // home
    expect(userTemplates.length).toBe(2); // index, show
    expect(allTemplates.length).toBe(3); // home, index, show

    fs.rmSync(tmpRoot, { recursive: true, force: true });
  });

  it('should fall back to regex parser on Elixir error', async () => {
    const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'template-registry-fallback-'));
    const htmlModulePath = path.join(tmpRoot, 'lib', 'my_app_web', 'controllers', 'test_html.ex');

    // Valid HTML module source
    const validSource = `
defmodule MyAppWeb.TestHTML do
  use MyAppWeb, :html

  def test(assigns) do
    ~H"<p>Test</p>"
  end
end
`.trim();

    fs.mkdirSync(path.dirname(htmlModulePath), { recursive: true });
    fs.writeFileSync(htmlModulePath, validSource, 'utf8');

    const registry = new TemplatesRegistry();
    registry.setWorkspaceRoot(tmpRoot);

    // Should parse successfully even if Elixir parser has issues
    await registry.updateFile(htmlModulePath, validSource);

    const templates = registry.getTemplatesForModule('MyAppWeb.TestHTML');
    expect(templates.length).toBeGreaterThanOrEqual(1);

    fs.rmSync(tmpRoot, { recursive: true, force: true });
  });
});
