import { describe, it, expect } from 'vitest';
import { TextDocument } from 'vscode-languageserver-textdocument';
import { RouterRegistry } from '../src/router-registry';
import { getRouteHelperCompletions } from '../src/completions/routes';

describe('route helper completions', () => {
  it('suggests route helpers with snippets and metadata', () => {
    const registry = new RouterRegistry();
    registry.setWorkspaceRoot('/workspace');

    const routerSource = `
defmodule MyAppWeb.Router do
  use Phoenix.Router

  scope "/", MyAppWeb do
    pipe_through :browser

    get "/users", MyAppWeb.UserController, :index
    get "/users/:id", MyAppWeb.UserController, :show
    post "/users", MyAppWeb.UserController, :create
  end

  scope "/admin", MyAppWeb, as: :admin do
    get "/reports", MyAppWeb.ReportController, :index
  end

  scope "/billing", MyAppWeb,
    pipe_through: [:browser],
    as: :billing do
    get "/invoices/:invoice_id", MyAppWeb.InvoiceController, :show
  end

  resources "/posts", MyAppWeb.PostController
end
`;

    registry.updateFile('/workspace/lib/my_app_web/router.ex', routerSource);

    const line = 'Routes.';
    const document = TextDocument.create(
      'file:///workspace/lib/my_app_web/live/example.ex',
      'elixir',
      1,
      line
    );

    const completions = getRouteHelperCompletions(
      document,
      { line: 0, character: line.length },
      line,
      registry
    );

    expect(completions).toBeTruthy();
    const helperLabels = completions!.map(item => item.label);
    expect(helperLabels).toContain('user_path');
    expect(helperLabels).toContain('user_url');
    expect(helperLabels).toContain('admin_report_path');
    expect(helperLabels).toContain('billing_invoice_path');
    expect(helperLabels).toContain('post_path');

    const userPathCompletion = completions!.find(item => item.label === 'user_path');
    expect(userPathCompletion).toBeTruthy();
    expect(userPathCompletion?.textEdit?.newText).toBe(
      'user_path(${1:conn_or_socket}, :${2|create,index,show|}, ${3:id})'
    );

    const postPathCompletion = completions!.find(item => item.label === 'post_path');
    expect(postPathCompletion?.textEdit?.newText).toBe(
      'post_path(${1:conn_or_socket}, :${2|index,new,create,show,edit,update,delete|}, ${3:id})'
    );

    const adminPathCompletion = completions!.find(item => item.label === 'admin_report_path');
    expect(adminPathCompletion?.textEdit?.newText).toBe(
      'admin_report_path(${1:conn_or_socket}, :${2:index})'
    );

    const billingPathCompletion = completions!.find(item => item.label === 'billing_invoice_path');
    expect(billingPathCompletion?.textEdit?.newText).toBe(
      'billing_invoice_path(${1:conn_or_socket}, :${2:show}, ${3:invoice_id})'
    );

    expect(userPathCompletion?.documentation).toBeTruthy();
    const userDoc = (userPathCompletion?.documentation as { value: string }).value;
    expect(userDoc).toContain('GET');
    expect(userDoc).toContain('/users/:id');
    expect(userDoc).toContain(':show');
  });
});
