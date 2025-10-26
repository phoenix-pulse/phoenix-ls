import { describe, it, expect } from 'vitest';
import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';
import { TextDocument } from 'vscode-languageserver-textdocument';
import { ComponentsRegistry } from '../src/components-registry';
import { SchemaRegistry } from '../src/schema-registry';
import { TemplatesRegistry } from '../src/templates-registry';
import { ControllersRegistry } from '../src/controllers-registry';
import { getAssignCompletions } from '../src/completions/assigns';

describe('Phase 2: Advanced Assign Completions', () => {
  it('supports 2-level nested field completion (@user.organization.name)', async () => {
    const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'phoenix-lsp-phase2-'));

    const controllersDir = path.join(tmpRoot, 'lib', 'my_app_web', 'controllers');
    const userHtmlDir = path.join(controllersDir, 'user_html');
    const schemaDir = path.join(tmpRoot, 'lib', 'my_app', 'accounts');

    fs.mkdirSync(userHtmlDir, { recursive: true });
    fs.mkdirSync(schemaDir, { recursive: true });

    // Create User schema with organization association
    const userSchemaPath = path.join(schemaDir, 'user.ex');
    const userSchemaSource = `defmodule MyApp.Accounts.User do
  use Ecto.Schema

  schema "users" do
    field :email, :string
    field :username, :string
    belongs_to :organization, MyApp.Accounts.Organization
    timestamps()
  end
end
`;
    fs.writeFileSync(userSchemaPath, userSchemaSource, 'utf8');

    // Create Organization schema
    const orgSchemaPath = path.join(schemaDir, 'organization.ex');
    const orgSchemaSource = `defmodule MyApp.Accounts.Organization do
  use Ecto.Schema

  schema "organizations" do
    field :name, :string
    field :slug, :string
    field :active, :boolean
    timestamps()
  end
end
`;
    fs.writeFileSync(orgSchemaPath, orgSchemaSource, 'utf8');

    // Create controller with typed assigns
    const controllerPath = path.join(controllersDir, 'user_controller.ex');
    const controllerSource = `defmodule MyAppWeb.UserController do
  use MyAppWeb, :controller

  def show(conn, %{"id" => id}) do
    user = MyApp.Accounts.get_user!(id)
    render(conn, :show, user: user)
  end
end
`;
    fs.writeFileSync(controllerPath, controllerSource, 'utf8');

    // Create template module
    const userHtmlModulePath = path.join(controllersDir, 'user_html.ex');
    const userHtmlModuleSource = `defmodule MyAppWeb.UserHTML do
  use MyAppWeb, :html

  embed_templates "user_html/*"
end
`;
    fs.writeFileSync(userHtmlModulePath, userHtmlModuleSource, 'utf8');

    // Create template with 2-level nesting
    const templatePath = path.join(userHtmlDir, 'show.html.heex');
    const templateSource = `<div>
  <h1>@user.</h1>
  <p>@user.organization.</p>
</div>`;
    fs.writeFileSync(templatePath, templateSource, 'utf8');

    // Initialize registries
    const templatesRegistry = new TemplatesRegistry();
    const controllersRegistry = new ControllersRegistry(templatesRegistry);
    const schemaRegistry = new SchemaRegistry();
    const componentsRegistry = new ComponentsRegistry();

    templatesRegistry.setWorkspaceRoot(tmpRoot);
    controllersRegistry.setWorkspaceRoot(tmpRoot);
    schemaRegistry.setWorkspaceRoot(tmpRoot);
    componentsRegistry.setWorkspaceRoot(tmpRoot);

    // Update registries
    await templatesRegistry.updateFile(userHtmlModulePath, userHtmlModuleSource);
    await schemaRegistry.updateFile(userSchemaPath, userSchemaSource);
    await schemaRegistry.updateFile(orgSchemaPath, orgSchemaSource);
    await controllersRegistry.updateFile(controllerPath, controllerSource);

    const document = TextDocument.create(`file://${templatePath}`, 'phoenix-heex', 1, templateSource);
    const text = document.getText();


    // Test 1: First level - @user. should show User fields
    const level1Offset = document.offsetAt({ line: 1, character: 12 }); // After @user. (position 12, not 13)
    const level1Line = text.split('\n')[1]; // Get line 1 (0-indexed)
    const level1LinePrefix = level1Line.substring(0, 12); // Characters 0-12 on that line

    const level1Completions = getAssignCompletions(
      componentsRegistry,
      schemaRegistry,
      controllersRegistry,
      templatePath,
      level1Offset,
      text,
      level1LinePrefix
    );

    expect(level1Completions.some(item => item.label === 'email')).toBe(true);
    expect(level1Completions.some(item => item.label === 'username')).toBe(true);
    expect(level1Completions.some(item => item.label === 'organization')).toBe(true);
    expect(level1Completions.some(item => item.label === 'id')).toBe(true); // Auto-added
    expect(level1Completions.some(item => item.label === 'inserted_at')).toBe(true); // From timestamps()
    expect(level1Completions.some(item => item.label === 'updated_at')).toBe(true);

    // Test 2: Second level - @user.organization. should show Organization fields
    const level2Offset = document.offsetAt({ line: 2, character: 24 }); // After @user.organization. (position 24)
    const level2Line = text.split('\n')[2]; // Get line 2 (0-indexed)
    const level2LinePrefix = level2Line.substring(0, 24); // Characters 0-24 on that line
    const level2Completions = getAssignCompletions(
      componentsRegistry,
      schemaRegistry,
      controllersRegistry,
      templatePath,
      level2Offset,
      text,
      level2LinePrefix
    );

    expect(level2Completions.some(item => item.label === 'name')).toBe(true);
    expect(level2Completions.some(item => item.label === 'slug')).toBe(true);
    expect(level2Completions.some(item => item.label === 'active')).toBe(true);
    expect(level2Completions.some(item => item.label === 'id')).toBe(true);
    expect(level2Completions.some(item => item.label === 'inserted_at')).toBe(true);
    expect(level2Completions.some(item => item.label === 'updated_at')).toBe(true);

    fs.rmSync(tmpRoot, { recursive: true, force: true });
  });

  it('finds all schemas in workspace (no over-filtering)', () => {
    const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'phoenix-lsp-schemas-'));

    const catalogDir = path.join(tmpRoot, 'lib', 'my_app', 'catalog');
    const accountsDir = path.join(tmpRoot, 'lib', 'my_app', 'accounts');
    const analyticsDir = path.join(tmpRoot, 'lib', 'my_app', 'analytics');
    const messagesDir = path.join(tmpRoot, 'lib', 'my_app', 'messages');

    fs.mkdirSync(catalogDir, { recursive: true });
    fs.mkdirSync(accountsDir, { recursive: true });
    fs.mkdirSync(analyticsDir, { recursive: true });
    fs.mkdirSync(messagesDir, { recursive: true });

    const schemas = [
      { dir: accountsDir, file: 'admin_user.ex', module: 'MyApp.Accounts.AdminUser', table: 'admin_users' },
      { dir: catalogDir, file: 'product.ex', module: 'MyApp.Catalog.Product', table: 'products' },
      { dir: catalogDir, file: 'product_image.ex', module: 'MyApp.Catalog.ProductImage', table: 'product_images' },
      { dir: analyticsDir, file: 'event.ex', module: 'MyApp.Analytics.Event', table: 'events' },
      { dir: messagesDir, file: 'contact_message.ex', module: 'MyApp.Messages.ContactMessage', table: 'contact_messages' },
      { dir: catalogDir, file: 'review.ex', module: 'MyApp.Catalog.Review', table: 'reviews' },
    ];

    schemas.forEach(({ dir, file, module, table }) => {
      const schemaPath = path.join(dir, file);
      const schemaSource = `defmodule ${module} do
  use Ecto.Schema

  schema "${table}" do
    field :name, :string
    timestamps()
  end
end
`;
      fs.writeFileSync(schemaPath, schemaSource, 'utf8');
    });

    const schemaRegistry = new SchemaRegistry();
    schemaRegistry.setWorkspaceRoot(tmpRoot);

    // Scan all schemas
    schemas.forEach(({ dir, file, module, table }) => {
      const schemaPath = path.join(dir, file);
      const content = fs.readFileSync(schemaPath, 'utf8');
      schemaRegistry.updateFile(schemaPath, content);
    });

    const allSchemas = schemaRegistry.getAllSchemas();

    // Verify all 6 schemas were found
    expect(allSchemas.length).toBe(6);
    expect(allSchemas.some(s => s.moduleName === 'MyApp.Accounts.AdminUser')).toBe(true);
    expect(allSchemas.some(s => s.moduleName === 'MyApp.Catalog.Product')).toBe(true);
    expect(allSchemas.some(s => s.moduleName === 'MyApp.Catalog.ProductImage')).toBe(true);
    expect(allSchemas.some(s => s.moduleName === 'MyApp.Analytics.Event')).toBe(true);
    expect(allSchemas.some(s => s.moduleName === 'MyApp.Messages.ContactMessage')).toBe(true);
    expect(allSchemas.some(s => s.moduleName === 'MyApp.Catalog.Review')).toBe(true);

    fs.rmSync(tmpRoot, { recursive: true, force: true });
  });

  it.skip('handles type inference fallback (FeaturedProduct -> Product)', async () => {
    const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'phoenix-lsp-fallback-'));

    const controllersDir = path.join(tmpRoot, 'lib', 'my_app_web', 'controllers');
    const pageHtmlDir = path.join(controllersDir, 'page_html');
    const catalogDir = path.join(tmpRoot, 'lib', 'my_app', 'catalog');

    fs.mkdirSync(pageHtmlDir, { recursive: true });
    fs.mkdirSync(catalogDir, { recursive: true });

    // Create Product schema (note: no FeaturedProduct schema)
    const productSchemaPath = path.join(catalogDir, 'product.ex');
    const productSchemaSource = `defmodule MyApp.Catalog.Product do
  use Ecto.Schema

  schema "products" do
    field :name, :string
    field :price, :decimal
    field :featured, :boolean
    timestamps()
  end
end
`;
    fs.writeFileSync(productSchemaPath, productSchemaSource, 'utf8');

    // Create controller that calls list_featured_products
    const controllerPath = path.join(controllersDir, 'page_controller.ex');
    const controllerSource = `defmodule MyAppWeb.PageController do
  use MyAppWeb, :controller

  def home(conn, _params) do
    featured_products = MyApp.Catalog.list_featured_products(6)
    render(conn, :home, featured_products: featured_products)
  end
end
`;
    fs.writeFileSync(controllerPath, controllerSource, 'utf8');

    // Create template module
    const pageHtmlModulePath = path.join(controllersDir, 'page_html.ex');
    const pageHtmlModuleSource = `defmodule MyAppWeb.PageHTML do
  use MyAppWeb, :html

  embed_templates "page_html/*"
end
`;
    fs.writeFileSync(pageHtmlModulePath, pageHtmlModuleSource, 'utf8');

    // Create template
    const templatePath = path.join(pageHtmlDir, 'home.html.heex');
    const templateSource = `<div>
  @featured_products.
</div>`;
    fs.writeFileSync(templatePath, templateSource, 'utf8');

    // Initialize registries
    const templatesRegistry = new TemplatesRegistry();
    const controllersRegistry = new ControllersRegistry(templatesRegistry);
    const schemaRegistry = new SchemaRegistry();
    const componentsRegistry = new ComponentsRegistry();

    templatesRegistry.setWorkspaceRoot(tmpRoot);
    controllersRegistry.setWorkspaceRoot(tmpRoot);
    schemaRegistry.setWorkspaceRoot(tmpRoot);
    componentsRegistry.setWorkspaceRoot(tmpRoot);

    // Update registries
    await templatesRegistry.updateFile(pageHtmlModulePath, pageHtmlModuleSource);
    await schemaRegistry.updateFile(productSchemaPath, productSchemaSource);
    await controllersRegistry.updateFile(controllerPath, controllerSource);

    const document = TextDocument.create(`file://${templatePath}`, 'phoenix-heex', 1, templateSource);
    const text = document.getText();

    // Test: @featured_products. should show Product fields despite name mismatch
    const offset = document.offsetAt({ line: 1, character: 22 }); // After @featured_products.
    const linePrefix = text.slice(Math.max(0, offset - 100), offset);
    const completions = getAssignCompletions(
      componentsRegistry,
      schemaRegistry,
      controllersRegistry,
      templatePath,
      offset,
      text,
      linePrefix
    );

    // Should find Product schema via fallback logic
    // Type inference: list_featured_products -> [%FeaturedProduct{}]
    // Fallback: FeaturedProduct -> Product (only schema in Catalog context)
    expect(completions.some(item => item.label === 'name')).toBe(true);
    expect(completions.some(item => item.label === 'price')).toBe(true);
    expect(completions.some(item => item.label === 'featured')).toBe(true);

    fs.rmSync(tmpRoot, { recursive: true, force: true });
  });

  it('handles rapid registry updates without race conditions', () => {
    const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'phoenix-lsp-race-'));

    const schemaDir = path.join(tmpRoot, 'lib', 'my_app', 'accounts');
    fs.mkdirSync(schemaDir, { recursive: true });

    const userSchemaPath = path.join(schemaDir, 'user.ex');
    const schemaRegistry = new SchemaRegistry();
    schemaRegistry.setWorkspaceRoot(tmpRoot);

    // Simulate rapid typing: update schema 20 times rapidly
    for (let i = 0; i < 20; i++) {
      const schemaSource = `defmodule MyApp.Accounts.User do
  use Ecto.Schema

  schema "users" do
    field :email, :string
    field :username, :string
    field :iteration_${i}, :integer
    timestamps()
  end
end
`;
      schemaRegistry.updateFile(userSchemaPath, schemaSource);

      // Immediately check if schema is available (should never be missing)
      const schema = schemaRegistry.getSchema('MyApp.Accounts.User');
      expect(schema).not.toBeNull();
      expect(schema?.fields.length).toBeGreaterThan(0);
    }

    fs.rmSync(tmpRoot, { recursive: true, force: true });
  });

  it('auto-adds id and timestamps fields to schemas', () => {
    const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'phoenix-lsp-auto-fields-'));

    const schemaDir = path.join(tmpRoot, 'lib', 'my_app', 'accounts');
    fs.mkdirSync(schemaDir, { recursive: true });

    const userSchemaPath = path.join(schemaDir, 'user.ex');
    const userSchemaSource = `defmodule MyApp.Accounts.User do
  use Ecto.Schema

  schema "users" do
    field :email, :string
    timestamps()
  end
end
`;
    fs.writeFileSync(userSchemaPath, userSchemaSource, 'utf8');

    const schemaRegistry = new SchemaRegistry();
    schemaRegistry.setWorkspaceRoot(tmpRoot);
    schemaRegistry.updateFile(userSchemaPath, userSchemaSource);

    const schema = schemaRegistry.getSchema('MyApp.Accounts.User');

    // Verify auto-added fields
    expect(schema?.fields.some(f => f.name === 'id')).toBe(true); // Auto-added
    expect(schema?.fields.some(f => f.name === 'email')).toBe(true); // Declared
    expect(schema?.fields.some(f => f.name === 'inserted_at')).toBe(true); // From timestamps()
    expect(schema?.fields.some(f => f.name === 'updated_at')).toBe(true); // From timestamps()

    fs.rmSync(tmpRoot, { recursive: true, force: true });
  });
});
