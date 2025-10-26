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

describe('controller-driven assign completions', () => {
  it('surfaces controller assigns and schema-aware fields in templates', async () => {
    const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'phoenix-lsp-controller-'));

    const controllersDir = path.join(tmpRoot, 'lib', 'my_app_web', 'controllers');
    const userHtmlDir = path.join(controllersDir, 'user_html');
    const schemaDir = path.join(tmpRoot, 'lib', 'my_app', 'accounts');

    fs.mkdirSync(userHtmlDir, { recursive: true });
    fs.mkdirSync(schemaDir, { recursive: true });

    const userHtmlModulePath = path.join(controllersDir, 'user_html.ex');
    const userHtmlModuleSource = `defmodule MyAppWeb.UserHTML do
  use MyAppWeb, :html

  embed_templates "user_html/*"
end
`;
    fs.writeFileSync(userHtmlModulePath, userHtmlModuleSource, 'utf8');

    const templatePath = path.join(userHtmlDir, 'index.html.heex');
    const templateSource = `<div>
  @
  @user.
</div>`;
    fs.writeFileSync(templatePath, templateSource, 'utf8');

    const controllerPath = path.join(controllersDir, 'user_controller.ex');
    const controllerSource = `defmodule MyAppWeb.UserController do
  use MyAppWeb, :controller

  def index(conn, _params) do
    user = %{}
    render(conn, :index, user: user, page_title: "Users")
  end
end
`;
    fs.writeFileSync(controllerPath, controllerSource, 'utf8');

    const schemaPath = path.join(schemaDir, 'user.ex');
    const schemaSource = `defmodule MyApp.Accounts.User do
  use Ecto.Schema

  schema "users" do
    field :email, :string
    field :username, :string
  end
end
`;
    fs.writeFileSync(schemaPath, schemaSource, 'utf8');

    const templatesRegistry = new TemplatesRegistry();
    const controllersRegistry = new ControllersRegistry(templatesRegistry);
    const schemaRegistry = new SchemaRegistry();
    const componentsRegistry = new ComponentsRegistry();

    templatesRegistry.setWorkspaceRoot(tmpRoot);
    controllersRegistry.setWorkspaceRoot(tmpRoot);
    schemaRegistry.setWorkspaceRoot(tmpRoot);
    componentsRegistry.setWorkspaceRoot(tmpRoot);

    templatesRegistry.updateFile(userHtmlModulePath, userHtmlModuleSource);
    await controllersRegistry.updateFile(controllerPath, controllerSource);
    schemaRegistry.updateFile(schemaPath, schemaSource);

    const document = TextDocument.create(`file://${templatePath}`, 'phoenix-heex', 1, templateSource);
    const text = document.getText();

    const baseOffset = document.offsetAt({ line: 1, character: 3 });
    const baseLinePrefix = text.slice(Math.max(0, baseOffset - 100), baseOffset);
    const baseCompletions = getAssignCompletions(
      componentsRegistry,
      schemaRegistry,
      controllersRegistry,
      templatePath,
      baseOffset,
      text,
      baseLinePrefix
    );

    expect(baseCompletions.some(item => item.label === 'user')).toBe(true);
    expect(baseCompletions.some(item => item.label === 'page_title')).toBe(true);

    const nestedOffset = document.offsetAt({ line: 2, character: 8 });
    const nestedLinePrefix = text.slice(Math.max(0, nestedOffset - 100), nestedOffset);
    const nestedCompletions = getAssignCompletions(
      componentsRegistry,
      schemaRegistry,
      controllersRegistry,
      templatePath,
      nestedOffset,
      text,
      nestedLinePrefix
    );

    expect(nestedCompletions.some(item => item.label === 'email')).toBe(true);

    fs.rmSync(tmpRoot, { recursive: true, force: true });
  });
});
